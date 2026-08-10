; ----------------------------------------------------
; StreamCompletion.ahk - Streaming completion handling
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
        userTokenCount := 0
        if activeThreadId {
            path := ChatDB.Msg_GetActivePath(activeThreadId)
            if path.Length {
                dbMsgData := buildStructuredMessagesFromPath([path[path.Length]])[1]
                ; Find last user message's backfilled token_count
                i := path.Length
                while i >= 1 {
                    if path[i].role = "user" {
                        userTokenCount := path[i].HasProp("token_count") ? path[i].token_count : 0
                        break
                    }
                    i--
                }
            }
        }

        postWebMessage("streamDone", { model: requestParams["_streamModelName"] ? requestParams["_streamModelName"] : requestParams["singleAPIModelName"], displayName: requestParams.Has("_streamDisplayName") ? requestParams["_streamDisplayName"] : "", dbMsg: dbMsgData, userTokenCount: userTokenCount })

        postThreadStats(activeThreadId)
        postWebMessage("setChatButtonsEnabled", true)
        startLoadingCursor(false)
        ; Bug #110: never leave the request/cURL temp files (which contain the
        ; Authorization Bearer token) on disk after a successful stream.
        deleteTempFiles()
    } catch Error as normErr {
        debugLog("Stream completion error: " normErr.Message "`nStack: " normErr.Stack)
        postWebMessage("showError", { message: "Request failed: " normErr.Message })
        deleteTempFiles()
    }
}

_maybeGenerateTitle(path) {
    if autoTitleGenerationEnabled && IsSet(titleGenModel) && titleGenModel && path.Length <= 2 {
        ; Bug #140: once a title request has been dispatched for this thread,
        ; never schedule another - a retry of the first exchange re-checks the
        ; same pre-insert path (length 1) with the title still "New Chat" and
        ; used to fire a duplicate API call.
        global _titleGenRequestedThreads
        if _titleGenRequestedThreads.Has(activeThreadId) {
            debugLog("[TITLEGEN] skip duplicate trigger thread=" activeThreadId)
            return
        }
        threadInfo := ChatDB.db.Query("SELECT title FROM chat_threads WHERE id=?;", activeThreadId)
        if threadInfo.count {
            currentTitle := threadInfo[1, "title"]
            debugLog("[TITLEGEN] trigger check thread=" activeThreadId " title='" currentTitle "'")
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

    if activeThreadId {
        responseTimeMs := A_TickCount - requestStartTime
        ttftMs := firstTokenTime > 0 ? firstTokenTime - requestStartTime : 0
        _persistStreamResponse(content, modelName, reasoning, usage, responseTimeMs, ttftMs)
    }

    _logStreamResponse(content, modelName, reasoning, usage, rawLastResponse, requestBeforeAppend, requestStartTime, firstTokenTime)
}

_persistStreamResponse(content, modelName, reasoning, usage, responseTimeMs := 0, ttftMs := 0) {
    path := ChatDB.Msg_GetActivePath(activeThreadId)
    ; Bug #147: a retry of a ROOT assistant (no parent) must insert the new
    ; response as a SIBLING with parent_id NULL - not as a CHILD of the
    ; original root (path[last] would be the original assistant itself).
    isRootRetry := requestParams.Has("pendingRetryIsRoot") && requestParams["pendingRetryIsRoot"]
    if isRootRetry
        requestParams.Delete("pendingRetryIsRoot")
    parentId := ""
    if !isRootRetry
        parentId := path.Length ? path[path.Length].id : ""
    retrySiblingGroup := requestParams.Has("pendingRetrySiblingGroup") ? requestParams["pendingRetrySiblingGroup"] : ""
    retrySiblingIdx := retrySiblingGroup ? MessageRepo.GetMaxSiblingIndex(retrySiblingGroup) + 1 : 0
    if retrySiblingGroup
        requestParams.Delete("pendingRetrySiblingGroup")

    completionTokens := usage.HasProp("completionTokens") ? usage.completionTokens : 0
    thinkingTokens := usage.HasProp("thinkingTokens") ? usage.thinkingTokens : 0
    promptTokens := usage.HasProp("promptTokens") ? usage.promptTokens : 0

    ChatDB.Msg_Insert({
        thread_id: activeThreadId, role: "assistant", content: content, model: modelName,
        parent_id: parentId, sibling_group: retrySiblingGroup, sibling_index: retrySiblingIdx,
        reasoning: reasoning,
        prompt_tokens: promptTokens,
        token_count: Max(0, completionTokens - thinkingTokens),
        thinking_tokens: thinkingTokens,
        cached_tokens: usage.HasProp("cachedTokens") ? usage.cachedTokens : 0,
        response_time_ms: responseTimeMs,
        ttft_ms: ttftMs
    })
    _maybeGenerateTitle(path)
}

_logStreamResponse(content, modelName, reasoning, usage, rawLastResponse, requestBeforeAppend, requestStartTime, firstTokenTime) {
    responseTimeMs := firstTokenTime > 0 ? firstTokenTime - requestStartTime : A_TickCount - requestStartTime

    pt := usage.HasProp("promptTokens") ? usage.promptTokens : 0
    ct := usage.HasProp("completionTokens") ? usage.completionTokens : 0
    tht := usage.HasProp("thinkingTokens") ? usage.thinkingTokens : 0
    ckt := usage.HasProp("cachedTokens") ? usage.cachedTokens : 0
    debugLog("[API] Chat done - prompt=" pt " completion=" ct " cached=" ckt " latency=" responseTimeMs "ms model=" modelName)
    debugLog("[USAGE] Chat - prompt=" pt " completion=" ct " cached=" ckt)
    costs := CostCalculator.ComputeTokenCosts(modelName, usage)
    if costs.totalCost != ""
        debugLog("[COST] Chat - input=$" costs.inputCost " cached=$" costs.cachedInputCost " output=$" costs.outputCost " total=$" costs.totalCost)

    ; Build response: real API data from last chunk, but with accumulated content
    responseStr := rawLastResponse
    if content && rawLastResponse {
        try {
            parsed := jsongo.Parse(rawLastResponse)
            if parsed.Has("choices") && parsed["choices"].Length > 0 {
                parsed["choices"][1]["delta"]["content"] := content
                if reasoning
                    parsed["choices"][1]["delta"]["reasoning_content"] := reasoning
                responseStr := jsongo.Stringify(parsed)
            }
        }
    }

    ApiLogger.LogRequest({
        timestamp: FormatTime(, "yyyy-MM-dd HH:mm:ss"),
        commandName: requestParams["windowTitle"], provider: requestParams["providerName"],
        model: requestParams["singleAPIModelName"], isFIM: false, endpoint: _getProviderEndpoint(),
        pasteMode: requestParams["pasteMode"], request: requestBeforeAppend,
        response: responseStr,
        status: "success", responseTimeMs: responseTimeMs
    })
}

