; ----------------------------------------------------
; Streaming request handler
; Polls the SSE output file, parses lines, posts to WebView
; ----------------------------------------------------

sendStreamingRequest(&chatHistoryJSONRequest, initialRequest := false) {
    debugLog("sendStreamingRequest entered. initialRequest=" initialRequest)

    ; Record start time for latency tracking
    requestStartTime := A_TickCount

    ; Delete old output and error files so stale data can't mask a cURL failure on subsequent requests
    if FileExist(requestParams["cURLOutputFile"]) {
        FileDelete(requestParams["cURLOutputFile"])
    }
    if FileExist(requestParams["cURLErrorFile"]) {
        FileDelete(requestParams["cURLErrorFile"])
    }

    ; Rebuild cURL command fresh each request (not from stale file)
    cURLCommand := router.buildStreamcURLCommand(requestParams["chatHistoryJSONRequestFile"], requestParams["cURLOutputFile"], requestParams["cURLErrorFile"])
    FileOpen(requestParams["cURLCommandFile"], "w", "UTF-8-RAW").Write(cURLCommand)

    Run(cURLCommand, , "Hide", &cURLPID)
    manageState("cURL", "set", cURLPID)
    debugLog("Streaming cURL PID: " cURLPID)

    ; Initialize streaming state
    streamState := {
        outputFile: requestParams["cURLOutputFile"],
        lastPos: 0,
        content: "",
        reasoning: "",
        modelName: "",
        firstTokenTime: 0,
        usage: {}
    }

    ; Poll the output file incrementally
    pollCount := 0
    while (ProcessExist(cURLPID)) {
        readStreamChunk(streamState)
        pollCount++
        Sleep 100
    }
    debugLog("Streaming while loop exited. Poll iterations=" pollCount)

    ; Process any remaining data after process exits
    readStreamChunk(streamState)
    debugLog("After final readStreamChunk. Total content length=" StrLen(streamState.content) " reasoning length=" StrLen(streamState.reasoning))

    ; Check stderr file for cURL errors if no content was produced
    if (streamState.content = "" && streamState.reasoning = "") {
        errorFile := requestParams["cURLErrorFile"]
        if FileExist(errorFile) {
            errorContent := FileOpen(errorFile, "r", "UTF-8-RAW").Read()
            debugLog("cURL stderr: " Trim(errorContent))
        }
        ; Also check the output file for API-level error responses
        if FileExist(streamState.outputFile) {
            rawOutput := FileOpen(streamState.outputFile, "r", "UTF-8-RAW").Read()
            debugLog("cURL output (error): " SubStr(rawOutput, 1, 300))
        }
    }

    ; If user cancelled, clean up but keep window alive (persistent ChatWindow)
    if !manageState("cURL", "get") {
        debugLog("User cancelled streaming request")
        manageState("cURL", "close")
        deleteTempFiles()
        startLoadingCursor(false)
        postWebMessage("setChatButtonsEnabled", true)
        return
    }

    cURLPID := 0
    manageState("cURL", "set", cURLPID)

    ; Save full response to chat history and log
    saveStreamResponse(streamState.content, streamState.modelName, &chatHistoryJSONRequest, requestStartTime, streamState.firstTokenTime, streamState.usage, streamState.reasoning)

    ; Build DB message data to sync back to WebView (id, siblingInfo, reasoning)
    dbMsgData := ""
    if activeThreadId {
        path := ChatDB.Msg_GetActivePath(activeThreadId)
        if path.Length {
            dbMsgData := buildStructuredMessagesFromPath([path[path.Length]])[1]
        }
    }

    ; Finalize: tell WebView streaming is done, include DB message data for id sync
    postWebMessage("streamDone", { model: streamState.modelName ? streamState.modelName : requestParams["singleAPIModelName"], dbMsg: dbMsgData })
    debugLog("Streaming complete. streamDone posted.")

    ; Post token usage to WebView (streaming)
    if streamState.usage.HasProp("totalTokens") && streamState.usage.totalTokens > 0 {
        effectiveModel := streamState.modelName ? streamState.modelName : requestParams["singleAPIModelName"]
        costs := LLMClient.ComputeTokenCosts(effectiveModel, streamState.usage)
        tokenUsage := {
            promptTokens:     streamState.usage.promptTokens,
            completionTokens: streamState.usage.completionTokens,
            totalTokens:      streamState.usage.totalTokens,
            cachedTokens:     streamState.usage.HasProp("cachedTokens") ? streamState.usage.cachedTokens : 0,
            contextWindow:    costs.contextWindow,
            inputCost:        costs.inputCost,
            outputCost:       costs.outputCost,
            totalCost:        costs.totalCost
        }
        postWebMessage("updateTokenUsage", tokenUsage)
    }

    ; Enable chat input
    postWebMessage("setChatButtonsEnabled", true)
    startLoadingCursor(false)
}

; Read and parse new content from the stream output file
readStreamChunk(streamState) {
    if !FileExist(streamState.outputFile) {
        return
    }

    file := FileOpen(streamState.outputFile, "r", "UTF-8-RAW")
    if !file {
        return
    }

    file.Pos := streamState.lastPos
    newContent := file.Read()
    streamState.lastPos := file.Pos
    file.Close()

    if !newContent {
        return
    }

    ; Parse each line for SSE data
    for line in StrSplit(newContent, "`n", "`r") {
        if (line = "")
            continue
        chunk := router.parseSSELine(line)

        switch chunk.type {
            case "content":
                if (streamState.firstTokenTime = 0) {
                    streamState.firstTokenTime := A_TickCount
                }
                streamState.content .= chunk.content
                postWebMessage("streamContent", chunk.content)

            case "reasoning":
                streamState.reasoning .= chunk.content
                postWebMessage("streamReasoning", chunk.content)

            case "finish":
                if chunk.HasProp("model") && chunk.model {
                    streamState.modelName := StrReplace(SubStr(chunk.model, InStr(chunk.model, "/") + 1), ":", "-")
                }
                ; Capture usage data from the final SSE chunk
                if chunk.HasProp("usage") && chunk.usage.HasProp("totalTokens") && chunk.usage.totalTokens > 0 {
                    streamState.usage := chunk.usage
                }

            case "done":
                ; No more data expected
        }
    }
}

; Save the accumulated streaming response to chat history
saveStreamResponse(content, modelName, &chatHistoryJSONRequest, requestStartTime, firstTokenTime, usage := {}, reasoning := "") {
    manageState("model", "add", modelName ? modelName : requestParams["singleAPIModelName"])

    ; Snapshot the request BEFORE appending the response
    requestBeforeAppend := chatHistoryJSONRequest

    ; Append assistant message to chat history
    router.appendToChatHistory("assistant", content, &chatHistoryJSONRequest, requestParams["chatHistoryJSONRequestFile"])
    manageChatHistoryJSON("set", chatHistoryJSONRequest)

    ; Persist assistant response in SQLite DB
    if activeThreadId {
        path := ChatDB.Msg_GetActivePath(activeThreadId)
        parentId := path.Length ? path[path.Length].id : ""
        ; Check for pending retry sibling_group
        retrySiblingGroup := requestParams.Has("pendingRetrySiblingGroup") ? requestParams["pendingRetrySiblingGroup"] : ""
        retrySiblingIdx := 0
        if retrySiblingGroup {
            sibTable := ChatDB.db.Exec("SELECT MAX(sibling_index) as max_idx FROM messages WHERE sibling_group='" retrySiblingGroup "';")
            retrySiblingIdx := sibTable.count ? Integer(sibTable[1, "max_idx"]) + 1 : 0
            requestParams.Delete("pendingRetrySiblingGroup")
        }
        ChatDB.Msg_Insert({
            thread_id: activeThreadId,
            role: "assistant",
            content: content,
            model: modelName,
            parent_id: parentId,
            sibling_group: retrySiblingGroup,
            sibling_index: retrySiblingIdx,
            reasoning: reasoning
        })
    }

    ; Reconstruct the full JSON response for logging
    ; Include usage data if available (captured from the SSE finish chunk)
    logEntry := {
        choices: [{ message: { content: content } }],
        model: modelName ? modelName : requestParams["singleAPIModelName"]
    }
    if usage.HasProp("totalTokens") && usage.totalTokens > 0 {
        logEntry.usage := {
            prompt_tokens:            usage.promptTokens,
            completion_tokens:        usage.completionTokens,
            total_tokens:             usage.totalTokens,
            prompt_cache_hit_tokens:  usage.cachedTokens
        }
    }
    fullResponse := jsongo.Stringify(logEntry)

    ; For streaming, latency = time to first token (TTFT)
    ; This is the most meaningful metric — how fast the model starts responding
    latencyMs := firstTokenTime > 0
        ? firstTokenTime - requestStartTime
        : A_TickCount - requestStartTime

    LLMClient.LogRequest({
        timestamp: FormatTime(, "yyyy-MM-dd HH:mm:ss"),
        promptName: requestParams["responseWindowTitle"],
        provider: requestParams["providerName"],
        model: requestParams["singleAPIModelName"],
        isFIM: false,
        endpoint: APIEndpoint,
        pasteMode: requestParams["pasteMode"],
        request: requestBeforeAppend,
        response: fullResponse,
        status: "success",
        latencyMs: latencyMs
    })
}
