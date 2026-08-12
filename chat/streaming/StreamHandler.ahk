; ----------------------------------------------------
; StreamHandler.ahk — Streaming orchestration
;
; Core polling, SSE reading, finalization, state cleanup.
; Completion/error handling delegated to StreamCompletion.ahk
; and StreamError.ahk.
; ----------------------------------------------------

#Include StreamCompletion.ahk
#Include StreamError.ahk

sendStreamingRequest(&chatHistoryJSONRequest, initialRequest := false) {
    debugLog("[STREAM] Started — thread=" activeThreadId)
    try {

    requestStartTime := A_TickCount

    if FileExist(requestParams["cURLOutputFile"]) {
        FileDelete(requestParams["cURLOutputFile"])
    }
    if FileExist(requestParams["cURLErrorFile"]) {
        FileDelete(requestParams["cURLErrorFile"])
    }

    providerInfo := ProviderResolver.Resolve(requestParams["singleAPIModelName"])
    ; Bug #112: never launch a URL-less cURL command - surface a friendly
    ; "No endpoint configured" error (same helper as the chat request path).
    if !providerInfo.endpoint {
        _ShowEndpointError(providerInfo)
        return
    }
    cURLCommand := CurlBuilder.BuildStream(providerInfo, requestParams["chatHistoryJSONRequestFile"], requestParams["cURLOutputFile"], requestParams["cURLErrorFile"])
    FileOpen(requestParams["cURLCommandFile"], "w", "UTF-8-RAW").Write(cURLCommand)

    Run(cURLCommand, , "Hide", &cURLPID)
    cURLState("set", cURLPID)

    requestParams["_streamOutputFile"]       := requestParams["cURLOutputFile"]
    requestParams["_streamLastPos"]          := 0
    requestParams["_streamContent"]          := ""
    requestParams["_streamReasoning"]        := ""
    sanitizedModel := ModelParser.Sanitize(requestParams["singleAPIModelName"])
    requestParams["_streamModelName"]        := sanitizedModel

    ; Use assistant name as display title when active
    if requestParams.Has("activeAssistantId") && requestParams["activeAssistantId"] {
        asst := AssistantRepo.GetFromSettings(requestParams["activeAssistantId"])
        displayName := asst && asst.name ? asst.name : sanitizedModel
    } else {
        displayName := sanitizedModel
    }
    requestParams["_streamDisplayName"] := displayName

    requestParams["_streamFirstTokenTime"]   := 0
    requestParams["_streamUsage"]            := {}
    requestParams["_streamProviderKey"]      := providerInfo.providerKey
    requestParams["_streamRawSseChunks"]     := ""
    requestParams["_streamRawLastResponse"]  := ""
    ; Bug #178: a `data:` JSON line split across poll boundaries is buffered
    ; here (as the incomplete trailing fragment) until the next poll completes
    ; it - the old code parsed each chunk in isolation, so the partial JSON
    ; crashed the poll (jsongo.Parse returns a String) and the remainder
    ; (no `data: ` prefix) was silently lost.
    requestParams["_streamPendingLine"]      := ""
    requestParams["_streamPollCount"]        := 0
    requestParams["_streamRequestStartTime"] := requestStartTime
    requestParams["_streamChatHistoryJSONRequest"] := chatHistoryJSONRequest
    requestParams["_streamPID"]              := cURLPID
    requestParams["_streamCancelled"]        := false
    ; Bug #159: capture the thread that SENT this request. The completion and
    ; cancel handlers must persist into THIS thread even if the user navigates
    ; (switch thread / New Chat / branch) or deletes the thread mid-stream -
    ; reading the global activeThreadId at completion time wrote the response
    ; into whatever thread happened to be active then.
    requestParams["_streamThreadId"]         := activeThreadId
    ; Bug #197: also capture the LAST message of the request path at send
    ; time. _persistStreamResponse used to re-read the active path at
    ; completion, so switching BRANCHES within the same thread mid-stream
    ; attached the response to the newly-active branch's leaf. The request's
    ; own parent is fixed at send time. A root retry has no parent (bug #147).
    requestParams["_streamParentId"]         := ""
    if !(requestParams.Has("pendingRetryIsRoot") && requestParams["pendingRetryIsRoot"]) {
        sendPath := ChatDB.Msg_GetActivePath(activeThreadId)
        if sendPath.Length
            requestParams["_streamParentId"] := sendPath[sendPath.Length].id
    }
    ; Bug #206: capture the request's log metadata at send time too - the
    ; completion/error/cancel loggers must describe the request that was sent,
    ; not whatever thread became active before the request finished.
    requestParams["_streamLogWindowTitle"]   := requestParams["windowTitle"]
    requestParams["_streamLogProviderName"]  := requestParams["providerName"]
    requestParams["_streamLogModel"]         := requestParams["singleAPIModelName"]
    requestParams["_streamLogPasteMode"]     := requestParams["pasteMode"]

    ; Post display title to UI immediately for bubble author during streaming
    postWebMessage("streamModelName", displayName)

    SetTimer(_pollStreamTimer, 100)
    } catch Error as e {
        debugLog("sendStreamingRequest error: " e.Message)
        postWebMessage("setChatButtonsEnabled", true)
        startLoadingCursor(false)
        postWebMessage("showError", { message: "Request failed: " e.Message })
    }
}

_pollStreamTimer() {
    try {
        pid := requestParams["_streamPID"]
        if !ProcessExist(pid) {
            SetTimer(, 0)
            _finalizeStreaming()
            return
        }
        _readStreamChunkFromParams()
        requestParams["_streamPollCount"]++
    } catch Error as e {
        debugLog("_pollStreamTimer error: " e.Message)
        SetTimer(, 0)
        _finalizeStreaming()
    }
}

_readStreamChunkFromParams() {
    state := _StreamStateFromParams()
    _readAndProcessStream(state, true)
    _ParamsFromStreamState(state)
}

; Build a stream state Map from requestParams.
_StreamStateFromParams() {
    return {
        outputFile: requestParams["_streamOutputFile"],
        lastPos: requestParams["_streamLastPos"],
        content: requestParams["_streamContent"],
        reasoning: requestParams["_streamReasoning"],
        modelName: requestParams["_streamModelName"],
        firstTokenTime: requestParams["_streamFirstTokenTime"],
        usage: requestParams["_streamUsage"],
        providerKey: requestParams["_streamProviderKey"],
        rawSseChunks: requestParams["_streamRawSseChunks"],
        rawLastResponse: requestParams["_streamRawLastResponse"],
        pendingLine: requestParams["_streamPendingLine"]
    }
}

; Write stream state back into requestParams.
_ParamsFromStreamState(state) {
    requestParams["_streamLastPos"] := state.lastPos
    requestParams["_streamContent"] := state.content
    requestParams["_streamReasoning"] := state.reasoning
    requestParams["_streamModelName"] := state.modelName
    requestParams["_streamFirstTokenTime"] := state.firstTokenTime
    requestParams["_streamUsage"] := state.usage
    requestParams["_streamRawSseChunks"] := state.rawSseChunks
    requestParams["_streamRawLastResponse"] := state.rawLastResponse
    requestParams["_streamPendingLine"] := state.pendingLine
}

_readFileChunk(state) {
    if !FileExist(state.outputFile)
        return ""
    ; Bug #160: read the cURL output as RAW BYTES and only advance the byte
    ; cursor past COMPLETE UTF-8 characters. A poll boundary that splits a
    ; multibyte character leaves its leading bytes unconsumed (lastPos stays
    ; before them), so the next poll re-reads them together with the rest and
    ; decodes the character correctly - never U+FFFD (the old UTF-8-RAW
    ; byte-seek decoded each chunk alone and mangled the persisted content).
    file := FileOpen(state.outputFile, "r")
    if !file
        return ""
    file.Pos := state.lastPos
    avail := file.Length - state.lastPos
    if avail <= 0 {
        file.Close()
        return ""
    }
    newBuf := Buffer(avail)
    file.RawRead(newBuf, avail)
    file.Close()

    complete := _UTF8CompletePrefixLen(newBuf, avail)
    state.lastPos += complete
    return complete > 0 ? StrGet(newBuf, complete, "UTF-8") : ""
}

; Number of leading bytes that form COMPLETE UTF-8 characters (the trailing
; bytes of an incomplete multibyte sequence are excluded so they stay pending).
_UTF8CompletePrefixLen(buf, len) {
    if len = 0
        return 0
    ; Scan back from the end to the last LEADING byte (continuation bytes have
    ; the 10xxxxxx pattern).
    i := len
    while i > 1 && (NumGet(buf, i - 1, "UChar") & 0xC0) = 0x80
        i--
    b := NumGet(buf, i - 1, "UChar")
    if (b & 0x80) = 0
        charLen := 1
    else if (b & 0xE0) = 0xC0
        charLen := 2
    else if (b & 0xF0) = 0xE0
        charLen := 3
    else if (b & 0xF8) = 0xF0
        charLen := 4
    else
        return len  ; corrupt leading byte - let the decoder replace it once
    return i + charLen - 1 <= len ? len : i - 1
}

_readAndProcessStream(state, doPostMessage := false) {
    newContent := _readFileChunk(state)
    if !newContent
        return

    ; Bug #178: an incomplete JSON fragment held from the previous poll is the
    ; head of this chunk's first line - prepend it so a `data:` line split
    ; across poll boundaries re-forms and its payload survives in full.
    pending := state.HasOwnProp("pendingLine") ? state.pendingLine : ""
    lines := StrSplit(pending . newContent, "`n", "`r")
    ; The chunk's LAST piece may itself be an incomplete line (no trailing
    ; newline yet) - hold it for the next poll unless it is a complete JSON
    ; event that can be processed right away.
    lastIdx := lines.Length
    tail := lines[lastIdx]
    holdTail := tail != "" && !_IsCompleteJsonEvent(tail)
    if holdTail {
        state.pendingLine := tail
        lines.RemoveAt(lastIdx)
    } else {
        state.pendingLine := ""
    }

    for line in lines {
        if (line = "")
            continue

        if InStr(line, "data: ")
            state.rawSseChunks .= line "`n"

        if InStr(line, "data: {") {
            jsonStart := InStr(line, "{")
            state.rawLastResponse := SubStr(line, jsonStart)
        }

        chunk := SSEParser.ParseLine(line)
        _processChunk(state, chunk, doPostMessage)
    }
}

; A trailing chunk piece is only safe to process immediately when it is a
; complete JSON event (the old code consumed newline-less complete lines). An
; incomplete JSON fragment - whether `data:`-prefixed or a bare continuation -
; is held in state.pendingLine until the next poll completes it (bug #178).
_IsCompleteJsonEvent(line) {
    dataPos := InStr(line, "data: ")
    payload := dataPos ? SubStr(line, dataPos + 6) : line
    if payload = "[DONE]"
        return true
    if !InStr("{[", SubStr(payload, 1, 1))
        return true  ; plain text / empty - not a JSON fragment
    try {
        parsed := jsongo.Parse(payload)
    } catch {
        return false
    }
    ; jsongo.Parse returns an empty STRING for truncated JSON (it does not
    ; throw) - only a Map/Array result means the event is complete.
    return IsObject(parsed) && (Type(parsed) = "Map" || Type(parsed) = "Array")
}

; Apply a parsed SSE chunk to the stream state, posting to WebView if needed.
_processChunk(state, chunk, doPostMessage) {
    switch chunk.type {
        case "content":
            if (state.firstTokenTime = 0)
                state.firstTokenTime := A_TickCount
            state.content .= chunk.content
            if doPostMessage
                postWebMessage("streamContent", chunk.content)
            if chunk.HasOwnProp("model") && chunk.model
                state.modelName := ModelParser.Sanitize(chunk.model)
            if chunk.HasOwnProp("usage") && IsObject(chunk.usage) && chunk.usage.HasOwnProp("totalTokens") && chunk.usage.totalTokens > 0
                state.usage := chunk.usage

        case "reasoning":
            ; Bug #170: a reasoning-only stream never produces a "content"
            ; chunk, so the first-token timer must also stamp on reasoning -
            ; otherwise ttft_ms stays 0 (popover hides TTFT, dashboard
            ; averages 0ms, API-log latency falls back to the full duration).
            if (state.firstTokenTime = 0)
                state.firstTokenTime := A_TickCount
            state.reasoning .= chunk.content
            collapseFlag := false
            if state.reasoning = chunk.content {
                if providers.Has(state.providerKey) {
                    p := providers[state.providerKey]
                    if p.HasOwnProp("collapseThinking")
                        collapseFlag := p.collapseThinking
                }
            }
            if doPostMessage
                postWebMessage("streamReasoning", { content: chunk.content, collapsed: collapseFlag })

        case "finish":
            if chunk.HasOwnProp("model") && chunk.model
                state.modelName := ModelParser.Sanitize(chunk.model)
            if chunk.HasOwnProp("usage") && IsObject(chunk.usage) && chunk.usage.HasOwnProp("totalTokens") && chunk.usage.totalTokens > 0
                state.usage := chunk.usage

        case "done":
    }
}

_finalizeStreaming() {
    try {
        _readStreamChunkFromParams()
        contentLen := StrLen(requestParams["_streamContent"])
        reasoningLen := StrLen(requestParams["_streamReasoning"])
        debugLog("[STREAM] Done — content=" contentLen "chars reasoning=" reasoningLen "chars polls=" requestParams["_streamPollCount"])

        wasCancelled := requestParams.Has("_streamCancelled") && requestParams["_streamCancelled"]

        ; Bug #56: a user-initiated Stop before the first token must finalize
        ; as a clean cancellation - check the flag BEFORE the empty-content
        ; branch, which would otherwise look like a connection failure and show
        ; the misleading API-key banner.
        if wasCancelled {
            _handleStreamCancelled()
            ; Bug #98: every exit path must clean up the _stream* keys so a
            ; cancelled request can never leak stale stream state into the
            ; next send. The call is idempotent (_handleStreamCancelled also
            ; cleans up internally), but _finalizeStreaming must not rely on
            ; that transitive cleanup.
            _cleanupStreamState()
            return
        }

        if (requestParams["_streamContent"] = "" && requestParams["_streamReasoning"] = "") {
            _handleStreamError()
            _cleanupStreamState()
            return
        }

        _handleStreamComplete()
        _cleanupStreamState()
    } catch Error as e {
        debugLog("_finalizeStreaming error: " e.Message)
        postWebMessage("setChatButtonsEnabled", true)
        startLoadingCursor(false)
        postWebMessage("showError", { message: "Request failed: " e.Message })
        _cleanupStreamState()
    }
}

_cleanupStreamState() {
    ; Map.Delete throws "Item has no value" for a missing key, so guard every
    ; delete: cleanup must be idempotent (bug #98's contract) even when the
    ; request failed before all stream keys were written.
    if requestParams.Has("_streamOutputFile")
        requestParams.Delete("_streamOutputFile")
    if requestParams.Has("_streamLastPos")
        requestParams.Delete("_streamLastPos")
    if requestParams.Has("_streamContent")
        requestParams.Delete("_streamContent")
    if requestParams.Has("_streamReasoning")
        requestParams.Delete("_streamReasoning")
    if requestParams.Has("_streamModelName")
        requestParams.Delete("_streamModelName")
    if requestParams.Has("_streamDisplayName")
        requestParams.Delete("_streamDisplayName")
    if requestParams.Has("_streamFirstTokenTime")
        requestParams.Delete("_streamFirstTokenTime")
    if requestParams.Has("_streamUsage")
        requestParams.Delete("_streamUsage")
    if requestParams.Has("_streamProviderKey")
        requestParams.Delete("_streamProviderKey")
    if requestParams.Has("_streamRawSseChunks")
        requestParams.Delete("_streamRawSseChunks")
    if requestParams.Has("_streamRawLastResponse")
        requestParams.Delete("_streamRawLastResponse")
    if requestParams.Has("_streamPendingLine")
        requestParams.Delete("_streamPendingLine")
    if requestParams.Has("_streamPollCount")
        requestParams.Delete("_streamPollCount")
    if requestParams.Has("_streamRequestStartTime")
        requestParams.Delete("_streamRequestStartTime")
    if requestParams.Has("_streamChatHistoryJSONRequest")
        requestParams.Delete("_streamChatHistoryJSONRequest")
    if requestParams.Has("_streamPID")
        requestParams.Delete("_streamPID")
    if requestParams.Has("_streamCancelled")
        requestParams.Delete("_streamCancelled")
    if requestParams.Has("_streamThreadId")
        requestParams.Delete("_streamThreadId")
    if requestParams.Has("_streamParentId")
        requestParams.Delete("_streamParentId")
    if requestParams.Has("_streamLogWindowTitle")
        requestParams.Delete("_streamLogWindowTitle")
    if requestParams.Has("_streamLogProviderName")
        requestParams.Delete("_streamLogProviderName")
    if requestParams.Has("_streamLogModel")
        requestParams.Delete("_streamLogModel")
    if requestParams.Has("_streamLogPasteMode")
        requestParams.Delete("_streamLogPasteMode")
}

; Bug #206: the API-log/error/cancel loggers must describe the REQUEST that
; was sent, not the thread that happens to be active when it finished. The
; values are captured in sendStreamingRequest and fall back to current
; requestParams only for legacy/unit-test flows.
_streamLogWindowTitle() {
    return requestParams.Has("_streamLogWindowTitle") ? requestParams["_streamLogWindowTitle"] : requestParams["windowTitle"]
}
_streamLogProviderName() {
    return requestParams.Has("_streamLogProviderName") ? requestParams["_streamLogProviderName"] : requestParams["providerName"]
}
_streamLogModel() {
    return requestParams.Has("_streamLogModel") ? requestParams["_streamLogModel"] : requestParams["singleAPIModelName"]
}
_streamLogPasteMode() {
    return requestParams.Has("_streamLogPasteMode") ? requestParams["_streamLogPasteMode"] : requestParams["pasteMode"]
}
