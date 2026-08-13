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
        if parsed.Has("error") && parsed["error"].Has("message")
            return parsed["error"]["message"]
    } catch Error as e {
        debugLog("_extractErrorMsg parse error: " e.Message, "ErrorHandler")
    }
    return ""
}

_handleStreamError() {
    try {
    errorFile := requestParams["cURLErrorFile"]
    stderrText := ""
    if FileExist(errorFile) {
        stderrText := Trim(FileOpen(errorFile, "r", "UTF-8-RAW").Read())
        debugLog("[STREAM] Error — stderr: " stderrText)
    }

    rawOutput := ""
    errMsg := ""

    if FileExist(requestParams["_streamOutputFile"]) {
        rawOutput := FileOpen(requestParams["_streamOutputFile"], "r", "UTF-8-RAW").Read()
        debugLog("[STREAM] Error — output: " SubStr(rawOutput, 1, 500))
        ; Bug #219: a mid-stream SSE error event's message lives in the LAST
        ; `data:` JSON event (tracked by the stream reader as
        ; _streamRawLastResponse) - the output FILE holds multiple SSE events,
        ; so jsongo.Parse on the whole file fails and the provider message
        ; would be lost. Try the last event first, then the whole file (the
        ; non-streaming JSON error bodies still parse as a whole).
        lastEvent := requestParams.Has("_streamRawLastResponse") ? requestParams["_streamRawLastResponse"] : ""
        if lastEvent
            errMsg := _extractErrorMsg(lastEvent)
        if !errMsg
            errMsg := _extractErrorMsg(rawOutput)
    }

    ; Surface the failure and re-enable the UI regardless of whether the
    ; output file exists. A connection failure (refused/DNS) makes cURL exit
    ; before it ever creates the output file — the stderr capture then holds
    ; the only diagnostic. Previously the whole error/re-enable block was
    ; inside the FileExist(outputFile) branch, so such failures left the UI
    ; stuck in the Stop state with no error banner at all.
    if !errMsg && stderrText
        errMsg := stderrText
    if !errMsg
        errMsg := "Request failed. Check your API key and try again."
    postWebMessage("showError", { message: errMsg })
    postWebMessage("setChatButtonsEnabled", true)
    startLoadingCursor(false)

    responseTimeMs := requestParams["_streamRequestStartTime"] > 0
        ? A_TickCount - requestParams["_streamRequestStartTime"]
        : 0
    ApiLogger.LogRequest({
        timestamp: FormatTime(, "yyyy-MM-dd HH:mm:ss"),
        commandName: _streamLogWindowTitle(),
        provider: _streamLogProviderName(),
        model: _streamLogModel(),
        isFIM: false,
        endpoint: _getProviderEndpoint(),
        pasteMode: _streamLogPasteMode(),
        request: requestParams.Has("_streamChatHistoryJSONRequest") ? requestParams["_streamChatHistoryJSONRequest"] : "{}",
        response: rawOutput ? rawOutput : '{"error": {"message": "' (errMsg ? errMsg : "Unknown error") '"}}',
        status: "error",
        responseTimeMs: responseTimeMs
    })

    ; Bug #110: the error path must also delete the temp request/cURL files
    ; (they contain the Bearer token) once the diagnostics have been read.
    deleteTempFiles()

    } catch Error as e {
        debugLog("_handleStreamError crashed: " e.Message "`n" e.Stack, "ErrorHandler")
        postWebMessage("showError", { message: "Request failed: " e.Message })
        postWebMessage("setChatButtonsEnabled", true)
        startLoadingCursor(false)
        deleteTempFiles()
    }
}

; Persist a partial streamed response (user cancel or mid-stream error) into
; the thread that SENT the request, using the parent/retry metadata captured
; at send time (same semantics as the completion path - bugs #159/#197/#205).
; Returns the dbMsg payload for the streamCancelled post ("" when there is
; nothing to persist or no thread). Shared by _handleStreamCancelled and the
; bug #219 mid-stream error path.
_persistPartialStreamContent() {
    content := requestParams.Has("_streamContent") ? requestParams["_streamContent"] : ""
    reasoning := requestParams.Has("_streamReasoning") ? requestParams["_streamReasoning"] : ""
    if !content && !reasoning
        return ""
    streamThreadId := requestParams.Has("_streamThreadId") ? requestParams["_streamThreadId"] : activeThreadId
    if !streamThreadId
        return ""
    path := ChatDB.Msg_GetActivePath(streamThreadId)
    ; Bug #205: mirror the completion path's root-retry handling. A retried
    ; ROOT assistant (no parent) must insert the cancelled partial as a
    ; SIBLING with parent_id NULL - never as a child of the original root.
    isRootRetry := requestParams.Has("pendingRetryIsRoot") && requestParams["pendingRetryIsRoot"]
    if isRootRetry
        requestParams.Delete("pendingRetryIsRoot")
    parentId := requestParams.Has("_streamParentId") ? requestParams["_streamParentId"] : ""
    if !isRootRetry && !parentId && path.Length
        parentId := path[path.Length].id
    retrySiblingGroup := requestParams.Has("pendingRetrySiblingGroup") ? requestParams["pendingRetrySiblingGroup"] : ""
    retrySiblingIdx := retrySiblingGroup ? MessageRepo.GetMaxSiblingIndex(retrySiblingGroup) + 1 : 0
    if retrySiblingGroup
        requestParams.Delete("pendingRetrySiblingGroup")
    ChatDB.Msg_Insert({
        thread_id: streamThreadId, role: "assistant",
        content: content,
        model: requestParams.Has("_streamModelName") && requestParams["_streamModelName"] ? requestParams["_streamModelName"] : requestParams["singleAPIModelName"],
        parent_id: parentId, sibling_group: retrySiblingGroup, sibling_index: retrySiblingIdx,
        reasoning: reasoning,
        ; Bug #133: a cancelled stream never reported usage - LOCAL row:
        ; local_copy skips the chat_usage upsert + cumulative recompute.
        local_copy: true,
        token_count: 0,
        thinking_tokens: 0,
        cached_tokens: 0,
        response_time_ms: 0
    })
    _maybeGenerateTitle(path, streamThreadId)
    postThreadStats(streamThreadId)
    streamPath := ChatDB.Msg_GetActivePath(streamThreadId)
    if !streamPath.Length
        return ""
    return buildStructuredMessagesFromPath([streamPath[streamPath.Length]])[1]
}

_handleStreamCancelled() {
    try {
    contentLen := StrLen(requestParams.Has("_streamContent") ? requestParams["_streamContent"] : "")
    debugLog("[STREAM] Cancelled — partial=" contentLen "chars")
    cURLState("close")

    _logCancelledRequest()

    ; Bug #171: cancel must persist into the thread that SENT the request
    ; (captured at send time), not the currently-active thread - the user may
    ; have switched threads between send and Stop.
    streamThreadId := requestParams.Has("_streamThreadId") ? requestParams["_streamThreadId"] : activeThreadId
    if streamThreadId && (requestParams["_streamContent"] != "" || requestParams["_streamReasoning"] != "") {
        path := ChatDB.Msg_GetActivePath(streamThreadId)
        ; Bug #205: mirror the completion path's root-retry handling. A retried
        ; ROOT assistant (no parent) must insert the cancelled partial as a
        ; SIBLING with parent_id NULL - never as a child of the original root.
        isRootRetry := requestParams.Has("pendingRetryIsRoot") && requestParams["pendingRetryIsRoot"]
        if isRootRetry
            requestParams.Delete("pendingRetryIsRoot")
        parentId := requestParams.Has("_streamParentId") ? requestParams["_streamParentId"] : ""
        if !isRootRetry && !parentId && path.Length
            parentId := path[path.Length].id
        retrySiblingGroup := requestParams.Has("pendingRetrySiblingGroup") ? requestParams["pendingRetrySiblingGroup"] : ""
        retrySiblingIdx := retrySiblingGroup ? MessageRepo.GetMaxSiblingIndex(retrySiblingGroup) + 1 : 0
        if retrySiblingGroup
            requestParams.Delete("pendingRetrySiblingGroup")
        ChatDB.Msg_Insert({
            thread_id: streamThreadId, role: "assistant",
            content: requestParams["_streamContent"],
            model: requestParams["_streamModelName"] ? requestParams["_streamModelName"] : requestParams["singleAPIModelName"],
            parent_id: parentId, sibling_group: retrySiblingGroup, sibling_index: retrySiblingIdx,
            reasoning: requestParams["_streamReasoning"],
            ; Bug #133: a cancelled stream never reported usage - LOCAL row:
            ; local_copy skips the chat_usage upsert + cumulative recompute.
            local_copy: true,
            token_count: 0,
            thinking_tokens: 0,
            cached_tokens: 0,
            response_time_ms: 0
        })
        _maybeGenerateTitle(path, streamThreadId)
        postThreadStats(streamThreadId)
        streamPath := ChatDB.Msg_GetActivePath(streamThreadId)
        dbMsgData := buildStructuredMessagesFromPath([streamPath[streamPath.Length]])[1]
        postWebMessage("streamCancelled", { dbMsg: dbMsgData, threadId: streamThreadId })
    } else {
        postWebMessage("streamCancelled", { threadId: streamThreadId })
    }

    _cleanupStreamState()
    deleteTempFiles()
    startLoadingCursor(false)
    postWebMessage("setChatButtonsEnabled", true)

    } catch Error as e {
        debugLog("_handleStreamCancelled crashed: " e.Message "`n" e.Stack, "ErrorHandler")
        _cleanupStreamState()
        deleteTempFiles()
        startLoadingCursor(false)
        postWebMessage("setChatButtonsEnabled", true)
        postWebMessage("showError", { message: "Cancellation error: " e.Message })
    }
}

; Called by Dispatch.ahk (cancelStream action) when user clicks stop.
; Kills the cURL process and sets the cancelled flag — the streaming
; poll timer will detect the flag on its next tick and finalize.
handleCancelStream() {
    try {
    curlPID := cURLState("get")
    if curlPID && ProcessExist(curlPID) {
        cURLState("close")
    }
    requestParams["_streamCancelled"] := true
    postWebMessage("setChatButtonsEnabled", true)
    } catch Error as e {
        debugLog("handleCancelStream error: " e.Message "`n" e.Stack, "ErrorHandler")
        postWebMessage("setChatButtonsEnabled", true)
    }
}

_logCancelledRequest() {
    responseTimeMs := requestParams["_streamFirstTokenTime"] > 0
        ? requestParams["_streamFirstTokenTime"] - requestParams["_streamRequestStartTime"]
        : A_TickCount - requestParams["_streamRequestStartTime"]
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
    ApiLogger.LogRequest({
        timestamp: FormatTime(, "yyyy-MM-dd HH:mm:ss"),
        commandName: _streamLogWindowTitle(),
        provider: _streamLogProviderName(),
        model: _streamLogModel(),
        isFIM: false,
        endpoint: _getProviderEndpoint(),
        pasteMode: _streamLogPasteMode(),
        request: requestParams["_streamChatHistoryJSONRequest"],
        response: jsongo.Stringify(logEntry),
        status: "cancelled",
        responseTimeMs: responseTimeMs
    })
}
