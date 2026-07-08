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

    providerInfo := LLMClient.ResolveProvider(requestParams["singleAPIModelName"])
    cURLCommand := LLMClient.BuildStreamcURLCommand(providerInfo, requestParams["chatHistoryJSONRequestFile"], requestParams["cURLOutputFile"], requestParams["cURLErrorFile"])
    FileOpen(requestParams["cURLCommandFile"], "w", "UTF-8-RAW").Write(cURLCommand)

    Run(cURLCommand, , "Hide", &cURLPID)
    manageState("cURL", "set", cURLPID)
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
    outputFile := requestParams["_streamOutputFile"]
    if !FileExist(outputFile)
        return

    file := FileOpen(outputFile, "r", "UTF-8-RAW")
    if !file
        return

    file.Pos := requestParams["_streamLastPos"]
    newContent := file.Read()
    requestParams["_streamLastPos"] := file.Pos
    file.Close()

    if !newContent
        return

    for line in StrSplit(newContent, "`n", "`r") {
        if (line = "")
            continue

        if requestParams["_streamProviderKey"] = "google" && InStr(line, "data: ") {
            requestParams["_streamRawSseChunks"] .= line "`n"
        }

        if InStr(line, "data: {") {
            jsonStart := InStr(line, "{")
            requestParams["_streamRawLastResponse"] := SubStr(line, jsonStart)
        }

        chunk := SSEParser.ParseLine(line)

        switch chunk.type {
            case "content":
                if (requestParams["_streamFirstTokenTime"] = 0)
                    requestParams["_streamFirstTokenTime"] := A_TickCount
                requestParams["_streamContent"] .= chunk.content
                postWebMessage("streamContent", chunk.content)
                if chunk.HasOwnProp("model") && chunk.model
                    requestParams["_streamModelName"] := StrReplace(SubStr(chunk.model, InStr(chunk.model, "/") + 1), ":", "-")
                if chunk.HasOwnProp("usage") && chunk.usage.HasOwnProp("totalTokens") && chunk.usage.totalTokens > 0
                    requestParams["_streamUsage"] := chunk.usage

            case "reasoning":
                requestParams["_streamReasoning"] .= chunk.content
                collapseFlag := false
                if requestParams["_streamReasoning"] = chunk.content {
                    if providers.Has(requestParams["_streamProviderKey"]) {
                        p := providers[requestParams["_streamProviderKey"]]
                        if p.HasOwnProp("collapseThinking")
                            collapseFlag := p.collapseThinking
                    }
                }
                postWebMessage("streamReasoning", { content: chunk.content, collapsed: collapseFlag })

            case "finish":
                if chunk.HasOwnProp("model") && chunk.model
                    requestParams["_streamModelName"] := StrReplace(SubStr(chunk.model, InStr(chunk.model, "/") + 1), ":", "-")
                if chunk.HasOwnProp("usage") && chunk.usage.HasOwnProp("totalTokens") && chunk.usage.totalTokens > 0
                    requestParams["_streamUsage"] := chunk.usage

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
    if FileExist(requestParams["_streamOutputFile"]) {
        rawOutput := FileOpen(requestParams["_streamOutputFile"], "r", "UTF-8-RAW").Read()
        debugLog("cURL output (error): " SubStr(rawOutput, 1, 500))
        try {
            parsedError := jsongo.Parse(rawOutput)
            if parsedError.Has("error") && parsedError["error"].Has("message") {
                errMsg := parsedError["error"]["message"]
                postWebMessage("showError", { message: errMsg })
            }
        }
    }
    if !FileExist(requestParams["_streamOutputFile"]) || !FileOpen(requestParams["_streamOutputFile"], "r").Read() {
        postWebMessage("showError", { message: "Request failed. Check your API key and try again." })
    }
}

_handleStreamCancelled() {
    debugLog("User cancelled streaming request")
    manageState("cURL", "close")

    if activeThreadId && (requestParams["_streamContent"] != "" || requestParams["_streamReasoning"] != "") {
        path := ChatDB.Msg_GetActivePath(activeThreadId)
        parentId := path.Length ? path[path.Length].id : ""
        ChatDB.Msg_Insert({
            thread_id: activeThreadId, role: "assistant",
            content: requestParams["_streamContent"],
            model: requestParams["_streamModelName"] ? requestParams["_streamModelName"] : requestParams["singleAPIModelName"],
            parent_id: parentId, sibling_group: "", sibling_index: 0,
            reasoning: requestParams["_streamReasoning"],
            prompt_tokens: requestParams["_streamUsage"].HasOwnProp("promptTokens") ? requestParams["_streamUsage"].promptTokens : 0,
            completion_tokens: requestParams["_streamUsage"].HasOwnProp("completionTokens") ? requestParams["_streamUsage"].completionTokens : 0,
            total_tokens: requestParams["_streamUsage"].HasOwnProp("totalTokens") ? requestParams["_streamUsage"].totalTokens : 0,
            cached_tokens: requestParams["_streamUsage"].HasOwnProp("cachedTokens") ? requestParams["_streamUsage"].cachedTokens : 0
        })
        _maybeGenerateTitle(path)
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
        manageState("cURL", "set", 0)

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
    if !FileExist(streamState.outputFile)
        return

    file := FileOpen(streamState.outputFile, "r", "UTF-8-RAW")
    if !file
        return

    file.Pos := streamState.lastPos
    newContent := file.Read()
    streamState.lastPos := file.Pos
    file.Close()

    if !newContent
        return

    for line in StrSplit(newContent, "`n", "`r") {
        if (line = "")
            continue

        if streamState.providerKey = "google" && InStr(line, "data: ")
            streamState.rawSseChunks .= line "`n"

        if InStr(line, "data: {") {
            jsonStart := InStr(line, "{")
            streamState.rawLastResponse := SubStr(line, jsonStart)
        }

        chunk := SSEParser.ParseLine(line)

        switch chunk.type {
            case "content":
                if (streamState.firstTokenTime = 0)
                    streamState.firstTokenTime := A_TickCount
                streamState.content .= chunk.content
                if chunk.HasOwnProp("model") && chunk.model
                    streamState.modelName := StrReplace(SubStr(chunk.model, InStr(chunk.model, "/") + 1), ":", "-")
                if chunk.HasOwnProp("usage") && chunk.usage.HasOwnProp("totalTokens") && chunk.usage.totalTokens > 0
                    streamState.usage := chunk.usage

            case "reasoning":
                streamState.reasoning .= chunk.content
                collapseFlag := false
                if streamState.reasoning = chunk.content {
                    if providers.Has(streamState.providerKey) {
                        p := providers[streamState.providerKey]
                        if p.HasOwnProp("collapseThinking")
                            collapseFlag := p.collapseThinking
                    }
                }

            case "finish":
                if chunk.HasOwnProp("model") && chunk.model
                    streamState.modelName := StrReplace(SubStr(chunk.model, InStr(chunk.model, "/") + 1), ":", "-")
                if chunk.HasOwnProp("usage") && chunk.usage.HasOwnProp("totalTokens") && chunk.usage.totalTokens > 0
                    streamState.usage := chunk.usage

            case "done":
        }
    }
}

saveStreamResponse(content, modelName, &chatHistoryJSONRequest, requestStartTime, firstTokenTime, usage := {}, reasoning := "", rawLastResponse := "", providerKey := "", rawSseChunks := "") {
    if !content && !reasoning
        return

    requestBeforeAppend := chatHistoryJSONRequest
    router.appendToChatHistory("assistant", content, &chatHistoryJSONRequest, requestParams["chatHistoryJSONRequestFile"])

    if activeThreadId {
        path := ChatDB.Msg_GetActivePath(activeThreadId)
        parentId := path.Length ? path[path.Length].id : ""
        retrySiblingGroup := requestParams.Has("pendingRetrySiblingGroup") ? requestParams["pendingRetrySiblingGroup"] : ""
        retrySiblingIdx := 0
        if retrySiblingGroup {
            sibTable := ChatDB.db.Exec("SELECT MAX(sibling_index) as max_idx FROM messages WHERE sibling_group='" retrySiblingGroup "';")
            retrySiblingIdx := sibTable.count ? Integer(sibTable[1, "max_idx"]) + 1 : 0
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

    logEntry := {
        choices: [{ message: { content: content }, finish_reason: "stop" }],
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
        commandName: requestParams["responseWindowTitle"], provider: requestParams["providerName"],
        model: requestParams["singleAPIModelName"], isFIM: false, endpoint: APIEndpoint,
        pasteMode: requestParams["pasteMode"], request: requestBeforeAppend, response: fullResponse,
        status: "success", latencyMs: latencyMs
    })
}
