; ----------------------------------------------------
; StreamCompletion.ahk — Streaming completion handling
;
; Handles successful stream completion: response persistence,
; API logging, title generation trigger, provider lookup.
; ----------------------------------------------------

_handleStreamComplete() {
    try {
        cURLState("set", 0)

        chatHistoryCopy := requestParams["_streamChatHistoryJSONRequest"]
        saveStreamResponse(requestParams["_streamContent"], requestParams["_streamModelName"], &chatHistoryCopy, requestParams["_streamRequestStartTime"], requestParams["_streamFirstTokenTime"], requestParams["_streamUsage"], requestParams["_streamReasoning"], requestParams["_streamRawLastResponse"], requestParams["_streamProviderKey"], requestParams["_streamRawSseChunks"])

        dbMsgData := ""
        if activeThreadId {
            path := ChatDB.Msg_GetActivePath(activeThreadId)
            if path.Length
                dbMsgData := buildStructuredMessagesFromPath([path[path.Length]])[1]
        }

        postWebMessage("streamDone", { model: requestParams["_streamModelName"] ? requestParams["_streamModelName"] : requestParams["singleAPIModelName"], dbMsg: dbMsgData })

        postThreadStats(activeThreadId)
        postWebMessage("setChatButtonsEnabled", true)
        startLoadingCursor(false)
    } catch Error as normErr {
        debugLog("Stream completion error: " normErr.Message "`nStack: " normErr.Stack)
        postWebMessage("showError", { message: "Request failed: " normErr.Message })
    }
}

_maybeGenerateTitle(path) {
    if IsSet(titleGenModel) && titleGenModel && path.Length <= 2 {
        threadInfo := ChatDB.db.Exec("SELECT title FROM chat_threads WHERE id='" activeThreadId "';")
        if threadInfo.count {
            currentTitle := threadInfo[1, "title"]
            if currentTitle = "New Chat" || InStr(currentTitle, "(")
                SetTimer(generateThreadTitle.Bind(activeThreadId), -200)
        }
    }
}

_getProviderEndpoint() {
    providerKey := requestParams.Has("_streamProviderKey") ? requestParams["_streamProviderKey"] : "deepseek"
    if providers.Has(providerKey)
        return providers[providerKey].endpoint
    return APIEndpoint
}

saveStreamResponse(content, modelName, &chatHistoryJSONRequest, requestStartTime, firstTokenTime, usage := {}, reasoning := "", rawLastResponse := "", providerKey := "", rawSseChunks := "") {
    if !content && !reasoning
        return

    requestBeforeAppend := chatHistoryJSONRequest
    llmClient.appendToChatHistory("assistant", content, &chatHistoryJSONRequest, requestParams["chatHistoryJSONRequestFile"])

    if activeThreadId
        _persistStreamResponse(content, modelName, reasoning, usage)

    _logStreamResponse(content, modelName, reasoning, usage, rawLastResponse, requestBeforeAppend, requestStartTime, firstTokenTime)
}

_persistStreamResponse(content, modelName, reasoning, usage) {
    path := ChatDB.Msg_GetActivePath(activeThreadId)
    parentId := path.Length ? path[path.Length].id : ""
    retrySiblingGroup := requestParams.Has("pendingRetrySiblingGroup") ? requestParams["pendingRetrySiblingGroup"] : ""
    retrySiblingIdx := retrySiblingGroup ? MessageRepo.GetMaxSiblingIndex(retrySiblingGroup) + 1 : 0
    if retrySiblingGroup
        requestParams.Delete("pendingRetrySiblingGroup")

    ChatDB.Msg_Insert({
        thread_id: activeThreadId, role: "assistant", content: content, model: modelName,
        parent_id: parentId, sibling_group: retrySiblingGroup, sibling_index: retrySiblingIdx,
        reasoning: reasoning,
        prompt_tokens: usage.HasProp("promptTokens") ? usage.promptTokens : 0,
        completion_tokens: usage.HasProp("completionTokens") ? usage.completionTokens : 0,
        total_tokens: usage.HasProp("totalTokens") ? usage.totalTokens : 0,
        cached_tokens: usage.HasProp("cachedTokens") ? usage.cachedTokens : 0
    })
    _maybeGenerateTitle(path)
}

_logStreamResponse(content, modelName, reasoning, usage, rawLastResponse, requestBeforeAppend, requestStartTime, firstTokenTime) {
    finishReason := "stop"
    if rawLastResponse {
        try {
            parsedChunk := jsongo.Parse(rawLastResponse)
            if parsedChunk.Has("choices") && parsedChunk["choices"].Length > 0 {
                choice := parsedChunk["choices"][1]
                if choice.Has("finish_reason") && choice["finish_reason"]
                    finishReason := choice["finish_reason"]
            }
        }
    }
    logEntry := {
        choices: [{ message: { content: content }, finish_reason: finishReason }],
        model: modelName ? modelName : requestParams["singleAPIModelName"],
        model_full: requestParams["singleAPIModelName"]
    }
    if reasoning
        logEntry.choices[1].message.reasoning_content := reasoning
    if usage.HasProp("totalTokens") && usage.totalTokens > 0 {
        logEntry.usage := {
            prompt_tokens: usage.promptTokens, completion_tokens: usage.completionTokens,
            total_tokens: usage.totalTokens, prompt_cache_hit_tokens: usage.cachedTokens
        }
    }

    latencyMs := firstTokenTime > 0 ? firstTokenTime - requestStartTime : A_TickCount - requestStartTime

    ApiLogger.LogRequest({
        timestamp: FormatTime(, "yyyy-MM-dd HH:mm:ss"),
        commandName: requestParams["windowTitle"], provider: requestParams["providerName"],
        model: requestParams["singleAPIModelName"], isFIM: false, endpoint: _getProviderEndpoint(),
        pasteMode: requestParams["pasteMode"], request: requestBeforeAppend, response: jsongo.Stringify(logEntry),
        status: "success", latencyMs: latencyMs
    })
}
