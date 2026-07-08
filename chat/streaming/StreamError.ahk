; ----------------------------------------------------
; StreamError.ahk — Streaming error + cancellation
;
; Handles API errors (JSON error extraction) and user
; cancellation (partial response save + estimated tokens).
; ----------------------------------------------------

_extractErrorMsg(rawOutput) {
    try {
        parsed := jsongo.Parse(rawOutput)
        if Type(parsed) = "Array" && parsed.Length > 0 && parsed[1].Has("error") && parsed[1]["error"].Has("message")
            return parsed[1]["error"]["message"]
        if parsed.Has("error") && parsed["error"].Has("message")
            return parsed["error"]["message"]
    }
    return ""
}

_handleStreamError() {
    errorFile := requestParams["cURLErrorFile"]
    if FileExist(errorFile) {
        errorContent := FileOpen(errorFile, "r", "UTF-8-RAW").Read()
        debugLog("cURL stderr: " Trim(errorContent))
    }

    rawOutput := ""
    errMsg := ""

    if FileExist(requestParams["_streamOutputFile"]) {
        rawOutput := FileOpen(requestParams["_streamOutputFile"], "r", "UTF-8-RAW").Read()
        debugLog("cURL output (error): " SubStr(rawOutput, 1, 500))
        errMsg := _extractErrorMsg(rawOutput)
        if errMsg {
            postWebMessage("showError", { message: errMsg })
        } else {
            postWebMessage("showError", { message: "Request failed. Check your API key and try again." })
        }
    }

    if !errMsg && (!FileExist(requestParams["_streamOutputFile"]) || !FileOpen(requestParams["_streamOutputFile"], "r").Read()) {
        postWebMessage("showError", { message: "Request failed. Check your API key and try again." })
    }

    latencyMs := requestParams["_streamRequestStartTime"] > 0
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
        latencyMs: latencyMs
    })
}

_handleStreamCancelled() {
    debugLog("User cancelled streaming request")
    cURLState("close")

    completionChars := StrLen(requestParams["_streamContent"]) + StrLen(requestParams["_streamReasoning"])
    estPromptTokens := 0
    if activeThreadId {
        path := ChatDB.Msg_GetActivePath(activeThreadId)
        for msg in path {
            estPromptTokens += TokenEstimation.Estimate(msg.content)
            if msg.HasProp("reasoning") && msg.reasoning
                estPromptTokens += TokenEstimation.Estimate(msg.reasoning)
        }
    }
    estPromptTokens := Max(1, estPromptTokens)
    estCompletionTokens := Max(1, TokenEstimation.Estimate(requestParams["_streamContent"] . requestParams["_streamReasoning"]))

    _logCancelledRequest(estPromptTokens, estCompletionTokens)

    if activeThreadId && (requestParams["_streamContent"] != "" || requestParams["_streamReasoning"] != "") {
        path := ChatDB.Msg_GetActivePath(activeThreadId)
        parentId := path.Length ? path[path.Length].id : ""
        ChatDB.Msg_Insert({
            thread_id: activeThreadId, role: "assistant",
            content: requestParams["_streamContent"],
            model: requestParams["_streamModelName"] ? requestParams["_streamModelName"] : requestParams["singleAPIModelName"],
            parent_id: parentId, sibling_group: "", sibling_index: 0,
            reasoning: requestParams["_streamReasoning"],
            prompt_tokens: estPromptTokens,
            completion_tokens: estCompletionTokens,
            total_tokens: estPromptTokens + estCompletionTokens,
            cached_tokens: 0
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
}

_logCancelledRequest(estPromptTokens, estCompletionTokens) {
    latencyMs := requestParams["_streamFirstTokenTime"] > 0
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
        prompt_tokens: estPromptTokens,
        completion_tokens: estCompletionTokens,
        total_tokens: estPromptTokens + estCompletionTokens,
        prompt_cache_hit_tokens: 0,
        estimated: "true"
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
        latencyMs: latencyMs
    })
}
