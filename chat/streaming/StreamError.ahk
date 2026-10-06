; ----------------------------------------------------
; StreamError.ahk — Streaming error + cancellation
;
; Handles API errors (JSON error extraction) and user
; cancellation (partial response save + estimated tokens).
; Also: handleCancelStream (moved from ChatRequestBuilder.ahk).
; ----------------------------------------------------

_extractErrorMsg(rawOutput) {
    try {
        parsed := jsongo.Parse(rawOutput)
        if Type(parsed) = "Array" && parsed.Length > 0 && parsed[1].Has("error") && parsed[1]["error"].Has("message")
            return parsed[1]["error"]["message"]
        if IsObject(parsed) {
            if parsed.Has("detail") && parsed["detail"] != "" {
                detail := parsed["detail"]
                if !IsObject(detail)
                    return String(detail)
                if detail.Has("message") && detail["message"] != ""
                    return String(detail["message"])
            }
            if parsed.Has("message") && parsed["message"] != ""
                return String(parsed["message"])
            if parsed.Has("error") {
                err := parsed["error"]
                if IsObject(err) && err.Has("message") && err["message"] != ""
                    return String(err["message"])
                if !IsObject(err) && err != ""
                    return String(err)
            }
            if parsed.Has("response") && IsObject(parsed["response"]) {
                response := parsed["response"]
                if response.Has("error") && IsObject(response["error"]) && response["error"].Has("message") && response["error"]["message"] != ""
                    return String(response["error"]["message"])
            }
        }
    } catch Error as e {
        debugLog("_extractErrorMsg parse error: " e.Message, "ErrorHandler")
    }
    return ""
}

_extractErrorCode(rawOutput) {
    try {
        parsed := jsongo.Parse(rawOutput)
        if Type(parsed) = "Array" && parsed.Length > 0
            parsed := parsed[1]
        if !IsObject(parsed)
            return ""
        if parsed.Has("error") && IsObject(parsed["error"]) && parsed["error"].Has("code")
            return String(parsed["error"]["code"])
        if parsed.Has("response") && IsObject(parsed["response"]) {
            response := parsed["response"]
            if response.Has("error") && IsObject(response["error"]) && response["error"].Has("code")
                return String(response["error"]["code"])
        }
    } catch {
    }
    return ""
}

_handleStreamError() {
    try {
    streamThreadId := requestParams.Has("_streamThreadId") ? requestParams["_streamThreadId"] : activeThreadId
    _RestoreFailedRetryLeaf()
    errorFile := requestParams["cURLErrorFile"]
    stderrText := ""
    if FileExist(errorFile) {
        stderrText := Trim(FileOpen(errorFile, "r", "UTF-8-RAW").Read())
        debugLog("[STREAM] Error — stderr: " stderrText)
    }

    rawOutput := ""
    errMsg := requestParams.Has("_streamErrorMessage") ? requestParams["_streamErrorMessage"] : ""
    errCode := requestParams.Has("_streamErrorCode") ? requestParams["_streamErrorCode"] : ""

    if FileExist(requestParams["_streamOutputFile"]) {
        rawOutput := FileOpen(requestParams["_streamOutputFile"], "r", "UTF-8-RAW").Read()
        debugLog("[STREAM] Error — output: " SubStr(rawOutput, 1, 500))
        ; A mid-stream SSE error message lives in the last data event.
        ; `data:` JSON event (tracked by the stream reader as
        ; _streamRawLastResponse) - the output FILE holds multiple SSE events,
        ; so jsongo.Parse on the whole file fails and the provider message
        ; would be lost. Try the last event first, then the whole file (the
        ; non-streaming JSON error bodies still parse as a whole).
        lastEvent := requestParams.Has("_streamRawLastResponse") ? requestParams["_streamRawLastResponse"] : ""
        if lastEvent && !errMsg
            errMsg := _extractErrorMsg(lastEvent)
        if lastEvent && !errCode
            errCode := _extractErrorCode(lastEvent)
        if !errMsg
            errMsg := _extractErrorMsg(rawOutput)
        if !errCode
            errCode := _extractErrorCode(rawOutput)
    }

    ; Surface the failure and re-enable the UI regardless of whether the
    ; output file exists. A connection failure (refused/DNS) makes cURL exit
    ; before it ever creates the output file — the stderr capture then holds
    ; the only diagnostic, so error handling cannot depend on the output file.
    if !errMsg && stderrText
        errMsg := stderrText
    if !errMsg {
        if requestParams.Has("_streamTransport") && requestParams["_streamTransport"] = "chatgpt-responses"
            errMsg := "ChatGPT returned no text or image-generation request. Try again or choose another model."
        else
            errMsg := "Request failed. Check your API key and try again."
    }
    debugLog("[STREAM] Failure detail: " errMsg)
    if errCode = "subscription_sharing_usage_limit_exceeded"
        _PostChatError(errMsg, streamThreadId, "Manage usage", "https://chatgpt.com/#settings/Usage")
    else
        _PostChatError(errMsg, streamThreadId)
    diagnosticResponse := rawOutput ? rawOutput : jsongo.Stringify(Map("error", Map("message", errMsg ? errMsg : "Unknown error")))
    diagnosticStream := _FindStreamByKey(_currentStreamKey)
    if IsObject(diagnosticStream) {
        diagnosticEntry := {request: "", response: jsongo.Stringify(Map("error", Map("message", errMsg, "code", errCode)))}
        ApplicationStreamDiagnostics.Attach(diagnosticEntry, diagnosticStream)
        diagnosticResponse := diagnosticEntry.response
    }
    ; Diagnostics have been read into memory; remove the request files before
    ; any later logging/UI work can return control to another request.
    deleteTempFiles()
    ; The finishing stream is still registered here, so exclude it while
    ; checking all other streams, search loops, and non-stream requests.
    currentStream := _FindStreamByKey(_currentStreamKey)
    _MaybeEnableThreadComposer(streamThreadId, "", currentStream)

    responseTimeMs := requestParams["_streamRequestStartTime"] > 0
        ? A_TickCount - requestParams["_streamRequestStartTime"]
        : 0
    logEntry := {
        timestamp: FormatTime(, "yyyy-MM-dd HH:mm:ss"),
        commandName: _streamLogWindowTitle(),
        provider: _streamLogProviderName(),
        model: _streamLogModel(),
        isFIM: false,
        endpoint: _getProviderEndpoint(),
        pasteMode: _streamLogPasteMode(),
        request: requestParams.Has("_streamWireRequestJSON") ? requestParams["_streamWireRequestJSON"] : requestParams.Has("_streamChatHistoryJSONRequest") ? requestParams["_streamChatHistoryJSONRequest"] : "{}",
        response: diagnosticResponse,
        status: "error",
        responseTimeMs: responseTimeMs
    }
    if ThreadLockService.ShouldRedactContent(streamThreadId) {
        logEntry.request := "<hidden: locked chat>"
        logEntry.response := "<hidden: locked chat>"
    }
    ApiLogger.LogRequest(logEntry)

    } catch Error as e {
        debugLog("_handleStreamError crashed: " e.Message "`n" e.Stack, "ErrorHandler")
        errorThreadId := IsSet(streamThreadId) ? streamThreadId : activeThreadId
        _PostChatError("Request failed: " e.Message, errorThreadId)
        currentStream := _FindStreamByKey(_currentStreamKey)
        _MaybeEnableThreadComposer(errorThreadId, "", currentStream)
        deleteTempFiles()
    }
}

; Persist a partial streamed response (user cancel or mid-stream error) into
; the thread that SENT the request, using the parent/retry metadata captured
; at send time, using the same ownership rules as the completion path.
; Returns the dbMsg payload for the streamCancelled post ("" when there is
; nothing to persist or no thread). Shared by _handleStreamCancelled and the
; mid-stream error path.
_persistPartialStreamContent() {
    ; A partial control envelope is not assistant prose and must never be
    ; adopted into a connected chat when a request is stopped or fails.
    if ApplicationChat.UsesTextProtocol(requestParams.Get("_streamThreadId", ""))
        requestParams["_streamContent"] := ""
    content := requestParams.Has("_streamContent") ? requestParams["_streamContent"] : ""
    reasoning := requestParams.Has("_streamReasoning") ? requestParams["_streamReasoning"] : ""
    if !content && !reasoning
        return ""
    streamThreadId := requestParams.Has("_streamThreadId") ? requestParams["_streamThreadId"] : activeThreadId
    if !streamThreadId
        return ""
    path := ChatDB.Msg_GetActivePath(streamThreadId)
    ; Mirror completion-path root-retry handling.
    ; A root-assistant retry has no parent, so insert the cancelled partial as a
    ; SIBLING with parent_id NULL - never as a child of the original root.
    isRootRetry := requestParams.Has("pendingRetryIsRoot") && requestParams["pendingRetryIsRoot"]
    if isRootRetry
        requestParams.Delete("pendingRetryIsRoot")
    parentId := requestParams.Has("_streamParentId") ? requestParams["_streamParentId"] : ""
    if !isRootRetry && !parentId && path.Length
        parentId := path[path.Length].id
    retrySiblingGroup := requestParams.Has("pendingRetrySiblingGroup") ? requestParams["pendingRetrySiblingGroup"] : ""
    retrySiblingGroup := _ValidatedRetrySiblingGroup(streamThreadId, parentId, retrySiblingGroup)
    retrySiblingIdx := retrySiblingGroup ? MessageRepo.GetMaxSiblingIndex(retrySiblingGroup) + 1 : 0
    if retrySiblingGroup
        requestParams.Delete("pendingRetrySiblingGroup")
    ChatDB.Msg_Insert({
        thread_id: streamThreadId, role: "assistant",
        content: content,
        model: requestParams.Has("_streamModelName") && requestParams["_streamModelName"] ? requestParams["_streamModelName"] : requestParams["singleAPIModelName"],
        provider: requestParams.Has("_streamProviderKey") ? requestParams["_streamProviderKey"] : "",
        parent_id: parentId, sibling_group: retrySiblingGroup, sibling_index: retrySiblingIdx,
        reasoning: reasoning,
        ; Cancelled streams have no usage report, so persist them as local rows.
        ; local_copy skips the chat_usage upsert + cumulative recompute.
        local_copy: true,
        token_count: 0,
        thinking_tokens: 0,
        cached_tokens: 0,
        response_time_ms: 0
    })
    _maybeGenerateTitle(path, streamThreadId)
    postThreadStats(streamThreadId)
    ; Cancelled/error partials also change sidebar model/order metadata.
    ; Keep the sidebar in sync on the partial path
    ; too (mirrors _handleStreamComplete).
    _postThreadListRefresh()
    streamPath := ChatDB.Msg_GetActivePath(streamThreadId)
    if !streamPath.Length
        return ""
    return buildStructuredMessagesFromPath([streamPath[streamPath.Length]])[1]
}

_handleStreamCancelled() {
    try {
    if ApplicationChat.UsesTextProtocol(requestParams.Get("_streamThreadId", ""))
        requestParams["_streamContent"] := ""
    contentLen := StrLen(requestParams.Has("_streamContent") ? requestParams["_streamContent"] : "")
    debugLog("[STREAM] Cancelled — partial=" contentLen "chars")
    _CloseCurrentStreamPID()

    _logCancelledRequest()

    ; Persist cancellation into the thread that sent the request.
    ; The user may switch threads between send and Stop.
    streamThreadId := requestParams.Has("_streamThreadId") ? requestParams["_streamThreadId"] : activeThreadId
    dbMsgData := _persistPartialStreamContent()
    postWebMessage("streamCancelled", { dbMsg: dbMsgData, threadId: streamThreadId })

    _cleanupStreamState()
    deleteTempFiles()
    ; The finishing stream is still registered here, so exclude it while
    ; checking all other streams, search loops, and non-stream requests.
    currentStream := _FindStreamByKey(_currentStreamKey)
    _MaybeEnableThreadComposer(streamThreadId, "", currentStream)

    } catch Error as e {
        debugLog("_handleStreamCancelled crashed: " e.Message "`n" e.Stack, "ErrorHandler")
        _cleanupStreamState()
        deleteTempFiles()
        errorThreadId := IsSet(streamThreadId) ? streamThreadId : activeThreadId
        currentStream := _FindStreamByKey(_currentStreamKey)
        _MaybeEnableThreadComposer(errorThreadId, "", currentStream)
        _PostChatError("Cancellation error: " e.Message, errorThreadId)
    }
}

; Called by Dispatch.ahk (cancelStream action) when user clicks stop.
; Kills the cURL process and sets the cancelled flag — the streaming
; poll timer will detect the flag on its next tick and finalize.
handleCancelStream(threadId := "") {
    try {
    targetThreadId := threadId ? threadId : activeThreadId
    ; Web-search round in flight: the PID and cancellation flag belong to the
    ; originating request's loop state, so cancelling thread B cannot kill A.
    loopState := _FindToolLoopForThread(targetThreadId)
    if loopState {
        SearchTools.CancelProcess(loopState)
        ; The loop remains registered until its synchronous handler resumes;
        ; exclude it while checking whether another operation is active.
        _MaybeEnableThreadComposer(targetThreadId, loopState)
        return
    }
    initialRequest := _FindNonStreamRequestForThread(targetThreadId)
    if initialRequest {
        CodexCliTransport._Trace(initialRequest, "ahk.cancel.nonstream.enter")
        if initialRequest.HasOwnProp("transport") && initialRequest.transport = "codex-cli" {
            ; Codex owns its process handle inside _RunBatch. Keep the WebView2
            ; COM callback non-blocking: record intent here and let the transport
            ; loop terminate the process tree after CoWaitForMultipleHandles returns.
            initialRequest.cancelRequested := true
            initialRequest.cancelled := true
            CodexCliTransport._Trace(initialRequest, "ahk.cancel.nonstream.flagged")
            return
        }
        CodexCliTransport._Trace(initialRequest, "ahk.cancel.nonstream.kill.begin")
        SearchTools.CancelProcess(initialRequest)
        CodexCliTransport._Trace(initialRequest, "ahk.cancel.nonstream.kill.returned")
        _MaybeEnableThreadComposer(targetThreadId, "", "", initialRequest)
        return
    }
    ; Cancel the request associated with the current thread;
    ; concurrent command streams there is no single global cURL PID. Fall back
    ; to the most recent stream only when there is no visible thread (legacy
    ; flows); never cancel another thread's active request.
    stream := _FindLatestStreamForThread(targetThreadId)
    if !stream && !targetThreadId && _activeStreams.Length
        stream := _activeStreams[_activeStreams.Length]
    if !stream {
        _MaybeEnableThreadComposer(targetThreadId)
        return
    }
    _LoadStreamIntoParams(stream)
    ; Set the cancelled flag BEFORE killing the process tree. taskkill blocks,
    ; and if the poll finalizes after the PID dies but before the flag is set,
    ; the stream takes the COMPLETION path with a partial/zero-token response
    ; and would inflate cumulative counters.
    requestParams["_streamCancelled"] := true
    stream.cancelled := true
    pid := requestParams["_streamPID"]
    if pid && ProcessExist(pid) {
        ; The 2> redirection runs cURL inside cmd, so kill the whole tree -
        ; ProcessClose on the cmd wrapper can leave an orphaned cURL that
        ; keeps writing to the output file and delivers a late streamContent
        ; chunk AFTER the cancel finalizes the bubble (double-bubble).
        RunWait('taskkill /PID ' pid ' /T /F', , "Hide")
        if cURLState("get") = pid
            cURLState("set", 0)
    }
    ; Do not re-enable the composer here. Killing cURL only requests
    ; cancellation; the poll/finalize path still has to read any buffered
    ; SSE, persist the partial, and post streamCancelled. Re-enabling now
    ; clears the WebView stream state too early and lets a trailing reasoning
    ; delta open a second assistant bubble. _handleStreamCancelled re-enables
    ; the composer after streamCancelled has been posted.
    } catch Error as e {
        debugLog("handleCancelStream error: " e.Message "`n" e.Stack, "ErrorHandler")
        errorThreadId := IsSet(targetThreadId) ? targetThreadId : activeThreadId
        _MaybeEnableThreadComposer(errorThreadId)
    }
}

_logCancelledRequest() {
    streamThreadId := requestParams.Has("_streamThreadId") ? requestParams["_streamThreadId"] : activeThreadId
    responseTimeMs := requestParams["_streamRequestStartTime"] > 0
        ? A_TickCount - requestParams["_streamRequestStartTime"]
        : 0
    logEntry := {
        choices: [{ message: { content: requestParams["_streamContent"] }, finish_reason: "cancelled" }],
        model: requestParams["_streamModelName"] ? requestParams["_streamModelName"] : requestParams["singleAPIModelName"],
        model_full: _streamLogModel()
    }
    if requestParams["_streamReasoning"]
        logEntry.choices[1].message.reasoning_content := requestParams["_streamReasoning"]
    logEntry.usage := {
        prompt_tokens: 0,
        completion_tokens: 0,
        total_tokens: 0,
        prompt_cache_hit_tokens: 0
    }
    cancelLogEntry := {
        timestamp: FormatTime(, "yyyy-MM-dd HH:mm:ss"),
        commandName: _streamLogWindowTitle(),
        provider: _streamLogProviderName(),
        model: _streamLogModel(),
        isFIM: false,
        endpoint: _getProviderEndpoint(),
        pasteMode: _streamLogPasteMode(),
        request: requestParams.Has("_streamWireRequestJSON") ? requestParams["_streamWireRequestJSON"] : requestParams["_streamChatHistoryJSONRequest"],
        response: jsongo.Stringify(logEntry),
        status: "cancelled",
        responseTimeMs: responseTimeMs
    }
    cancelledStream := _FindStreamByKey(_currentStreamKey)
    if IsObject(cancelledStream) && cancelledStream.transport = "http"
        ApplicationStreamDiagnostics.Attach(cancelLogEntry, cancelledStream)
    if ThreadLockService.ShouldRedactContent(streamThreadId) {
        cancelLogEntry.request := "<hidden: locked chat>"
        cancelLogEntry.response := "<hidden: locked chat>"
    }
    ApiLogger.LogRequest(cancelLogEntry)
}
