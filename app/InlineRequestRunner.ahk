; ----------------------------------------------------
; InlineRequestRunner — Non-chat LLM request execution
;
; Builds cURL command, runs it, parses response, pastes
; result (replace/append), logs API call, cleans up.
; Extracted from RequestProcessor.ahk.
; ----------------------------------------------------

class InlineRequestRunner {

    static Run(commandName, fullAPIModelName, providerName, singleAPIModelName, captured, isFIM, systemMessage, pasteMode, temperature, maxTokens, stop, stream, thinking, thinkingLevel := "") {
        uniqueID := A_TickCount

        ; Build the JSON request
        if isFIM {
            chatHistoryJSONRequest := llmClient.createFIMRequest(fullAPIModelName, captured.prefix, captured.suffix,
                temperature, maxTokens, stop)
        } else {
            chatHistoryJSONRequest := llmClient.createJSONRequest(fullAPIModelName, systemMessage, captured.userMessage,
                temperature, maxTokens, stop, stream, thinking, thinkingLevel)
        }

        ; Generate sanitized filenames
        sanitizeRe := "[\/\\:*?`"<>|]"
        chatHistoryJSONRequestFile := A_Temp "\" RegExReplace("chatHistoryJSONRequest_" commandName "_" singleAPIModelName "_" uniqueID ".json", sanitizeRe, "")
        cURLCommandFile := A_Temp "\" RegExReplace("cURLCommand_" commandName "_" singleAPIModelName "_" uniqueID ".txt", sanitizeRe, "")
        cURLOutputFile := A_Temp "\" RegExReplace("cURLOutput_" commandName "_" singleAPIModelName "_" uniqueID ".json", sanitizeRe, "")
        cURLErrorFile := A_Temp "\" RegExReplace("cURLError_" commandName "_" singleAPIModelName "_" uniqueID ".txt", sanitizeRe, "")

        FileOpen(chatHistoryJSONRequestFile, "w", "UTF-8-RAW").Write(chatHistoryJSONRequest)
        if isFIM {
            cURLCommand := llmClient.buildFIMcURLCommand(chatHistoryJSONRequestFile, cURLOutputFile)
        } else {
            cURLCommand := llmClient.buildcURLCommand(chatHistoryJSONRequestFile, cURLOutputFile)
        }
        FileOpen(cURLCommandFile, "w", "UTF-8-RAW").Write(cURLCommand)

        ; Track active model for tooltip
        getActiveModels()[uniqueID] := {
            commandName: commandName,
            name: singleAPIModelName,
            provider: llmClient,
            JSONFile: chatHistoryJSONRequestFile,
            cURLFile: cURLCommandFile,
            outputFile: cURLOutputFile,
            errorFile: cURLErrorFile,
            isLoading: true
        }
        updateLoadingUI("Update")

        ; Execute cURL and wait
        requestStartTime := A_TickCount
        cURLCommand := FileOpen(cURLCommandFile, "r", "UTF-8-RAW").Read()
        Run(cURLCommand, , "Hide", &cURLPID)
        while ProcessExist(cURLPID)
            Sleep 250

        ; Parse response
        responseFromLLM := ""
        JSONResponseFromLLM := ""
        if FileExist(cURLOutputFile) {
            JSONResponseFromLLM := FileOpen(cURLOutputFile, "r", "UTF-8-RAW").Read()
            try {
                if isFIM
                    responseFromLLM := llmClient.extractFIMResponse(jsongo.Parse(JSONResponseFromLLM))
                else
                    responseFromLLM := llmClient.extractJSONResponse(jsongo.Parse(JSONResponseFromLLM))
            }
        }

        ; Paste result
        if IsObject(responseFromLLM) && responseFromLLM.HasProp("response") {
            latencyMs := A_TickCount - requestStartTime
            A_Clipboard := responseFromLLM.response
            if pasteMode = "append" {
                Send("{Right}")
                Sleep 50
            }
            Send("^v")
            Sleep 50
            if pasteMode = "append" {
                Send("{Left}{Right}")
            }
            ApiLogger.LogRequest({
                timestamp: FormatTime(, "yyyy-MM-dd HH:mm:ss"),
                commandName: commandName,
                provider: providerName,
                model: singleAPIModelName,
                isFIM: isFIM,
                endpoint: isFIM ? FIMEndpoint : APIEndpoint,
                pasteMode: pasteMode,
                request: chatHistoryJSONRequest,
                response: JSONResponseFromLLM,
                status: "success",
                latencyMs: latencyMs
            })
        }

        ; Cleanup
        getActiveModels()[uniqueID].isLoading := false
        updateLoadingUI("Update")
        getActiveModels().Delete(uniqueID)
        FileDelete(chatHistoryJSONRequestFile)
        FileDelete(cURLCommandFile)
        safeDelete(cURLOutputFile)
        safeDelete(cURLErrorFile)
    }
}
