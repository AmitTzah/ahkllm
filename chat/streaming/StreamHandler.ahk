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
    cURLCommand := CurlBuilder.BuildStream(providerInfo, requestParams["chatHistoryJSONRequestFile"], requestParams["cURLOutputFile"], requestParams["cURLErrorFile"])
    FileOpen(requestParams["cURLCommandFile"], "w", "UTF-8-RAW").Write(cURLCommand)

    Run(cURLCommand, , "Hide", &cURLPID)
    cURLState("set", cURLPID)

    requestParams["_streamOutputFile"]       := requestParams["cURLOutputFile"]
    requestParams["_streamLastPos"]          := 0
    requestParams["_streamContent"]          := ""
    requestParams["_streamReasoning"]        := ""
    requestParams["_streamModelName"]        := ""
    requestParams["_streamFirstTokenTime"]   := 0
    requestParams["_streamUsage"]            := {}
    requestParams["_streamProviderKey"]      := providerInfo.providerKey
    requestParams["_streamRawSseChunks"]     := ""
    requestParams["_streamRawLastResponse"]  := ""
    requestParams["_streamPollCount"]        := 0
    requestParams["_streamRequestStartTime"] := requestStartTime
    requestParams["_streamChatHistoryJSONRequest"] := chatHistoryJSONRequest
    requestParams["_streamPID"]              := cURLPID
    requestParams["_streamCancelled"]        := false

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
        rawLastResponse: requestParams["_streamRawLastResponse"]
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
}

_readFileChunk(state) {
    if !FileExist(state.outputFile)
        return ""
    file := FileOpen(state.outputFile, "r", "UTF-8-RAW")
    if !file
        return ""
    file.Pos := state.lastPos
    newContent := file.Read()
    state.lastPos := file.Pos
    file.Close()
    return newContent
}

_readAndProcessStream(state, doPostMessage := false) {
    newContent := _readFileChunk(state)
    if !newContent
        return

    for line in StrSplit(newContent, "`n", "`r") {
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
            if chunk.HasOwnProp("usage") && chunk.usage.HasOwnProp("totalTokens") && chunk.usage.totalTokens > 0
                state.usage := chunk.usage

        case "reasoning":
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
            if chunk.HasOwnProp("usage") && chunk.usage.HasOwnProp("totalTokens") && chunk.usage.totalTokens > 0
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

        if (requestParams["_streamContent"] = "" && requestParams["_streamReasoning"] = "") {
            _handleStreamError()
            _cleanupStreamState()
            return
        }

        wasCancelled := requestParams.Has("_streamCancelled") && requestParams["_streamCancelled"]

        if wasCancelled {
            _handleStreamCancelled()
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
    requestParams.Delete("_streamOutputFile")
    requestParams.Delete("_streamLastPos")
    requestParams.Delete("_streamContent")
    requestParams.Delete("_streamReasoning")
    requestParams.Delete("_streamModelName")
    requestParams.Delete("_streamFirstTokenTime")
    requestParams.Delete("_streamUsage")
    requestParams.Delete("_streamProviderKey")
    requestParams.Delete("_streamRawSseChunks")
    requestParams.Delete("_streamRawLastResponse")
    requestParams.Delete("_streamPollCount")
    requestParams.Delete("_streamRequestStartTime")
    requestParams.Delete("_streamChatHistoryJSONRequest")
    requestParams.Delete("_streamPID")
    requestParams.Delete("_streamCancelled")
}

readStreamChunk(streamState) {
    _readAndProcessStream(streamState, false)
}
