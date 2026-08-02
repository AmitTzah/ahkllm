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
        commandName: requestParams["windowTitle"],
        provider: requestParams["providerName"],
        model: requestParams["singleAPIModelName"],
        isFIM: false,
        endpoint: _getProviderEndpoint(),
        pasteMode: requestParams["pasteMode"],
        request: requestParams.Has("_streamChatHistoryJSONRequest") ? requestParams["_streamChatHistoryJSONRequest"] : "{}",
        response: rawOutput ? rawOutput : '{"error": {"message": "' (errMsg ? errMsg : "Unknown error") '"}}',
        status: "error",
        responseTimeMs: responseTimeMs
    })

    } catch Error as e {
        debugLog("_handleStreamError crashed: " e.Message "`n" e.Stack, "ErrorHandler")
        postWebMessage("showError", { message: "Request failed: " e.Message })
        postWebMessage("setChatButtonsEnabled", true)
        startLoadingCursor(false)
    }
}

_handleStreamCancelled() {
    try {
    contentLen := StrLen(requestParams.Has("_streamContent") ? requestParams["_streamContent"] : "")
    debugLog("[STREAM] Cancelled — partial=" contentLen "chars")
    cURLState("close")

    _logCancelledRequest()

    if activeThreadId && (requestParams["_streamContent"] != "" || requestParams["_streamReasoning"] != "") {
        path := ChatDB.Msg_GetActivePath(activeThreadId)
        parentId := path.Length ? path[path.Length].id : ""
        retrySiblingGroup := requestParams.Has("pendingRetrySiblingGroup") ? requestParams["pendingRetrySiblingGroup"] : ""
        retrySiblingIdx := retrySiblingGroup ? MessageRepo.GetMaxSiblingIndex(retrySiblingGroup) + 1 : 0
        if retrySiblingGroup
            requestParams.Delete("pendingRetrySiblingGroup")
        ChatDB.Msg_Insert({
            thread_id: activeThreadId, role: "assistant",
            content: requestParams["_streamContent"],
            model: requestParams["_streamModelName"] ? requestParams["_streamModelName"] : requestParams["singleAPIModelName"],
            parent_id: parentId, sibling_group: retrySiblingGroup, sibling_index: retrySiblingIdx,
            reasoning: requestParams["_streamReasoning"],
            token_count: 0,
            thinking_tokens: 0,
            cached_tokens: 0,
            response_time_ms: 0
        })
        _maybeGenerateTitle(path)
        postThreadStats(activeThreadId)
        dbMsgData := buildStructuredMessagesFromPath([ChatDB.Msg_GetActivePath(activeThreadId)[ChatDB.Msg_GetActivePath(activeThreadId).Length]])[1]
        postWebMessage("streamCancelled", { dbMsg: dbMsgData })
    } else {
        postWebMessage("streamCancelled", true)
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
        model_full: requestParams["singleAPIModelName"]
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
        commandName: requestParams["windowTitle"],
        provider: requestParams["providerName"],
        model: requestParams["singleAPIModelName"],
        isFIM: false,
        endpoint: _getProviderEndpoint(),
        pasteMode: requestParams["pasteMode"],
        request: requestParams["_streamChatHistoryJSONRequest"],
        response: jsongo.Stringify(logEntry),
        status: "cancelled",
        responseTimeMs: responseTimeMs
    })
}
