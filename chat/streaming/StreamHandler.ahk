; ----------------------------------------------------
; Streaming request handler
; Polls the SSE output file, parses lines, posts to WebView
;
; Uses SetTimer-based polling so the main thread can process
; WebView2 COM callbacks (like cancelStream from Stop button)
; between poll ticks.
; ----------------------------------------------------

sendStreamingRequest(&chatHistoryJSONRequest, initialRequest := false) {
    debugLog("sendStreamingRequest entered. initialRequest=" initialRequest)
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
    debugLog("Streaming cURL PID: " cURLPID)

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
    state := {
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

    _readAndProcessStream(state, true)

    requestParams["_streamLastPos"] := state.lastPos
    requestParams["_streamContent"] := state.content
    requestParams["_streamReasoning"] := state.reasoning
    requestParams["_streamModelName"] := state.modelName
    requestParams["_streamFirstTokenTime"] := state.firstTokenTime
    requestParams["_streamUsage"] := state.usage
    requestParams["_streamRawSseChunks"] := state.rawSseChunks
    requestParams["_streamRawLastResponse"] := state.rawLastResponse
}

_readAndProcessStream(state, doPostMessage := false) {
    if !FileExist(state.outputFile)
        return

    file := FileOpen(state.outputFile, "r", "UTF-8-RAW")
    if !file
        return

    file.Pos := state.lastPos
    newContent := file.Read()
    state.lastPos := file.Pos
    file.Close()

    if !newContent
        return

    for line in StrSplit(newContent, "`n", "`r") {
        if (line = "")
            continue

        if state.providerKey = "google" && InStr(line, "data: ")
            state.rawSseChunks .= line "`n"

        if InStr(line, "data: {") {
            jsonStart := InStr(line, "{")
            state.rawLastResponse := SubStr(line, jsonStart)
        }

        chunk := SSEParser.ParseLine(line)

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
}

_finalizeStreaming() {
    try {
        pollCount := requestParams["_streamPollCount"]
        debugLog("Streaming while loop exited. Poll iterations=" pollCount)

        _readStreamChunkFromParams()
        debugLog("After final readStreamChunk. Total content length=" StrLen(requestParams["_streamContent"]) " reasoning length=" StrLen(requestParams["_streamReasoning"]))

        ; Check for empty response (API error, connectivity issue, etc.)
        if (requestParams["_streamContent"] = "" && requestParams["_streamReasoning"] = "") {
            _handleStreamError()
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
        try {
            parsed := jsongo.Parse(rawOutput)

            ; Extract error message from both formats:
            ;   Object:  {error: {message: "..."}}     — OpenAI, DeepSeek
            ;   Array:   [{error: {message: "..."}}]   — Google Gemini
            if Type(parsed) = "Array" && parsed.Length > 0 && parsed[1].Has("error") && parsed[1]["error"].Has("message") {
                errMsg := parsed[1]["error"]["message"]
            } else if parsed.Has("error") && parsed["error"].Has("message") {
                errMsg := parsed["error"]["message"]
            }

            if errMsg {
                postWebMessage("showError", { message: errMsg })
            }
        } catch Error as e {
            debugLog("Error parsing API error response: " e.Message)
            ; JSON parse failed — fall back to generic error so user still sees something
            postWebMessage("showError", { message: "Request failed. Check your API key and try again." })
        }
    }

    if !errMsg && (!FileExist(requestParams["_streamOutputFile"]) || !FileOpen(requestParams["_streamOutputFile"], "r").Read()) {
        errMsg := "Request failed. Check your API key and try again."
        postWebMessage("showError", { message: errMsg })
    }

    ; Log the failed request to API logs so users can inspect the error response
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

    ; Estimate token counts — real usage unavailable (only in final SSE chunk).
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
        postThreadStats(activeThreadId)  ; refresh token/cost bar in UI
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

; Trigger title generation if this is the first assistant response and title is still default.
; Extracted to eliminate duplication between cancellation and normal completion paths.
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

; Log a cancelled API call with estimated token counts.
; Character-based estimation (4 chars ≈ 1 token for English) works across
; all providers (DeepSeek, OpenAI, Gemini). The estimated: true flag
; distinguishes these from real API-reported usage.
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

saveStreamResponse(content, modelName, &chatHistoryJSONRequest, requestStartTime, firstTokenTime, usage := {}, reasoning := "", rawLastResponse := "", providerKey := "", rawSseChunks := "") {
    if !content && !reasoning
        return

    requestBeforeAppend := chatHistoryJSONRequest
    llmClient.appendToChatHistory("assistant", content, &chatHistoryJSONRequest, requestParams["chatHistoryJSONRequestFile"])

    if activeThreadId {
        path := ChatDB.Msg_GetActivePath(activeThreadId)
        parentId := path.Length ? path[path.Length].id : ""
        retrySiblingGroup := requestParams.Has("pendingRetrySiblingGroup") ? requestParams["pendingRetrySiblingGroup"] : ""
        retrySiblingIdx := retrySiblingGroup ? MessageRepo.GetMaxSiblingIndex(retrySiblingGroup) + 1 : 0
        if retrySiblingGroup {
            requestParams.Delete("pendingRetrySiblingGroup")
        }
        pt := usage.HasProp("promptTokens") ? usage.promptTokens : 0
        ct := usage.HasProp("completionTokens") ? usage.completionTokens : 0
        tt := usage.HasProp("totalTokens") ? usage.totalTokens : 0
        ckt := usage.HasProp("cachedTokens") ? usage.cachedTokens : 0

        ChatDB.Msg_Insert({
            thread_id: activeThreadId, role: "assistant", content: content, model: modelName,
            parent_id: parentId, sibling_group: retrySiblingGroup, sibling_index: retrySiblingIdx,
            reasoning: reasoning, prompt_tokens: pt, completion_tokens: ct, total_tokens: tt, cached_tokens: ckt
        })

        _maybeGenerateTitle(path)
    }

    ; Extract real finish_reason from the last SSE chunk (e.g., "stop", "length", "content_filter")
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
    fullResponse := jsongo.Stringify(logEntry)


    latencyMs := firstTokenTime > 0 ? firstTokenTime - requestStartTime : A_TickCount - requestStartTime

    ApiLogger.LogRequest({
        timestamp: FormatTime(, "yyyy-MM-dd HH:mm:ss"),
        commandName: requestParams["windowTitle"], provider: requestParams["providerName"],
        model: requestParams["singleAPIModelName"], isFIM: false, endpoint: _getProviderEndpoint(),
        pasteMode: requestParams["pasteMode"], request: requestBeforeAppend, response: fullResponse,
        status: "success", latencyMs: latencyMs
    })
}

; Resolve the actual provider endpoint for API log entries.
; Uses the stored provider key from the streaming session.
_getProviderEndpoint() {
    providerKey := requestParams.Has("_streamProviderKey") ? requestParams["_streamProviderKey"] : "deepseek"
    if providers.Has(providerKey)
        return providers[providerKey].endpoint
    return APIEndpoint
}
