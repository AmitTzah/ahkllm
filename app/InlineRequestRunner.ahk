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

        files := InlineRequestRunner._BuildAndWriteRequest(commandName, fullAPIModelName, singleAPIModelName, captured, isFIM, systemMessage, temperature, maxTokens, stop, stream, thinking, thinkingLevel, uniqueID)

        ; Track active model for tooltip
        getActiveModels()[uniqueID] := {
            commandName: commandName,
            name: singleAPIModelName,
            provider: llmClient,
            JSONFile: files.requestFile,
            cURLFile: files.curlFile,
            outputFile: files.outputFile,
            errorFile: files.errorFile,
            isLoading: true
        }
        updateLoadingUI("Update")

        ; Execute cURL and parse response
        result := InlineRequestRunner._ExecuteCurlAndParse(files, isFIM)

        ; Paste result if successful
        if result.success {
            InlineRequestRunner._PasteAndLogResponse(result, captured, isFIM, pasteMode, commandName, providerName, singleAPIModelName, files)
        }

        ; Cleanup
        getActiveModels()[uniqueID].isLoading := false
        updateLoadingUI("Update")
        getActiveModels().Delete(uniqueID)
        InlineRequestRunner._CleanupTempFiles(files)
    }

    ; Build the JSON request and write it + cURL command to temp files.
    ; Uses static CurlBuilder methods (no more llmClient instance passthroughs).
    ; Returns object with request, JSON, and file paths.
    static _BuildAndWriteRequest(commandName, fullAPIModelName, singleAPIModelName, captured, isFIM, systemMessage, temperature, maxTokens, stop, stream, thinking, thinkingLevel, uniqueID) {
        ; Build the JSON request
        if isFIM {
            chatHistoryJSONRequest := llmClient.createFIMRequest(fullAPIModelName, captured.prefix, captured.suffix,
                temperature, maxTokens, stop)
        } else {
            chatHistoryJSONRequest := LLMRequestBuilder.createJSONRequest(fullAPIModelName, systemMessage, captured.userMessage,
                temperature, maxTokens, stop, stream, thinking, thinkingLevel)
        }

        ; Resolve provider info for CurlBuilder
        providerInfo := ProviderResolver.Resolve(fullAPIModelName)

        ; Generate sanitized filenames
        sanitizeRe := "[\/\\:*?`"<>|]"
        requestFile := A_Temp "\" RegExReplace("chatHistoryJSONRequest_" commandName "_" singleAPIModelName "_" uniqueID ".json", sanitizeRe, "")
        curlFile := A_Temp "\" RegExReplace("cURLCommand_" commandName "_" singleAPIModelName "_" uniqueID ".txt", sanitizeRe, "")
        outputFile := A_Temp "\" RegExReplace("cURLOutput_" commandName "_" singleAPIModelName "_" uniqueID ".json", sanitizeRe, "")
        errorFile := A_Temp "\" RegExReplace("cURLError_" commandName "_" singleAPIModelName "_" uniqueID ".txt", sanitizeRe, "")

        FileOpen(requestFile, "w", "UTF-8-RAW").Write(chatHistoryJSONRequest)
        if isFIM {
            cURLCommand := CurlBuilder.BuildFIM(providerInfo, requestFile, outputFile)
        } else {
            cURLCommand := CurlBuilder.Build(providerInfo, requestFile, outputFile)
        }
        FileOpen(curlFile, "w", "UTF-8-RAW").Write(cURLCommand)

        return {
            requestJSON: chatHistoryJSONRequest,
            requestFile: requestFile,
            curlFile: curlFile,
            outputFile: outputFile,
            errorFile: errorFile,
            endpoint: providerInfo.endpoint
        }
    }

    ; Execute cURL synchronously and parse the response.
    ; Uses ResponseParser directly (no more llmClient passthroughs).
    ; Returns { success: true/false, response: parsedResponse, rawJSON: rawResponseText }
    static _ExecuteCurlAndParse(files, isFIM) {
        requestStartTime := A_TickCount
        cURLCommand := FileOpen(files.curlFile, "r", "UTF-8-RAW").Read()
        JSONResponseFromLLM := CurlExecutor.Run(cURLCommand, files.outputFile)

        responseFromLLM := ""
        if JSONResponseFromLLM != "" {
            try {
                if isFIM
                    responseFromLLM := ResponseParser.ParseFIMResponse(jsongo.Parse(JSONResponseFromLLM))
                else
                    responseFromLLM := ResponseParser.ParseChatResponse(jsongo.Parse(JSONResponseFromLLM))
            } catch Error as e {
                debugLog("Failed to parse LLM response: " e.Message, "InlineRequestRunner")
            }
        }

        return {
            success: IsObject(responseFromLLM) && responseFromLLM.HasProp("response"),
            response: responseFromLLM,
            rawJSON: JSONResponseFromLLM,
            responseTimeMs: A_TickCount - requestStartTime
        }
    }

    ; Paste the response and log it to the API logger.
    static _PasteAndLogResponse(result, captured, isFIM, pasteMode, commandName, providerName, singleAPIModelName, files) {
        responseText := TextCapture.NormalizeLineEndings(result.response.response, false)
        
        ; Paste via clipboard (^v).  UIA ValuePattern.SetValue wouldn't
        ; preserve undo history in editors like VS Code and Notepad.

        A_Clipboard := responseText
        if pasteMode = "append" {
            if captured.HasOwnProp("needsDeselect") && captured.needsDeselect {
                Send("{Right}")
                Sleep 50
            }
        }
        Send("^v")
        Sleep 50
        if pasteMode = "append" {
            Send("{Left}{Right}")
        }
        ; Highlight inserted text so the user can immediately see what was added
        if isFIM {
            Sleep 100  ; let the target app finish processing the paste
            InlineRequestRunner.HighlightInsertedText(responseText)
        }
        ApiLogger.LogRequest({
            timestamp: FormatTime(, "yyyy-MM-dd HH:mm:ss"),
            commandName: commandName,
            provider: providerName,
            model: singleAPIModelName,
            isFIM: isFIM,
            endpoint: files.endpoint,
            pasteMode: pasteMode,
            request: files.requestJSON,
            response: result.rawJSON,
            status: "success",
            responseTimeMs: result.responseTimeMs
        })

        ; Track command usage for the dashboard (daily aggregation)
        usage := InlineRequestRunner._ExtractUsage(result, commandName)
        if IsSet(usage) {
            costs := CostCalculator.ComputeTokenCosts(singleAPIModelName, usage)
            debugLog("[API] Command '" commandName "' done — prompt=" usage.promptTokens " completion=" usage.completionTokens " model=" singleAPIModelName)
            debugLog("[USAGE] Command '" commandName "' — prompt=" usage.promptTokens " completion=" usage.completionTokens)
            debugLog("[COST] Command '" commandName "' — input=$" (costs.inputCost != "" ? costs.inputCost : "0") " cached=$" (costs.cachedInputCost != "" ? costs.cachedInputCost : "0") " output=$" (costs.outputCost != "" ? costs.outputCost : "0") " total=$" (costs.totalCost != "" ? costs.totalCost : "0"))
            ChatDB.CommandUsage_Upsert({
                date: FormatTime(, "yyyy-MM-dd"),
                model: singleAPIModelName,
                provider: providerName,
                command_name: commandName,
                prompt_tokens: usage.promptTokens,
                completion_tokens: usage.completionTokens,
                thinking_tokens: usage.HasOwnProp("thinkingTokens") ? usage.thinkingTokens : 0,
                cached_tokens: usage.cachedTokens,
                input_cost: costs.inputCost != "" ? costs.inputCost : 0,
                cached_input_cost: costs.cachedInputCost != "" ? costs.cachedInputCost : 0,
                output_cost: costs.outputCost != "" ? costs.outputCost : 0,
                total_cost: costs.totalCost != "" ? costs.totalCost : 0,
                response_time_ms: result.responseTimeMs
            })
        }
    }

    ; Remove temp files created during the request.
    static _CleanupTempFiles(files) {
        FileDelete(files.requestFile)
        FileDelete(files.curlFile)
        safeDelete(files.outputFile)
        safeDelete(files.errorFile)
    }

    ; ----------------------------------------------------
    ; HighlightInsertedText — select just-pasted FIM text
    ;
    ; After a FIM paste, the caret is at the end of the
    ; inserted text. Uses UIA TextPattern to select backwards
    ; by StrLen(responseText) characters — no keystrokes,
    ; no scroll, no line-count math.
    ; ----------------------------------------------------
    static HighlightInsertedText(responseText) {
        responseLen := StrLen(responseText)
        if responseLen = 0
            return

        try {
            el := UIA.GetFocusedElement()
            if !el.IsTextPatternAvailable
                return

            textPattern := el.TextPattern
            selRanges := textPattern.GetSelection()
            if !selRanges.Length
                return

            ; Cursor (degenerate range) is at end of pasted text.
            ; Move start back by responseLen characters, then select.
            selRange := selRanges[1]
            selRange.MoveEndpointByUnit(
                UIA.TextPatternRangeEndpoint.Start,
                UIA.TextUnit.Character,
                -responseLen
            )
            selRange.Select()
        } catch Error as e {
            debugLog("HighlightInsertedText UIA failed: " e.Message, "InlineRequestRunner")
        }
    }

    ; Extract usage from command response — handles both normal and FIM formats
    static _ExtractUsage(result, commandName) {
        if result.response.HasOwnProp("usage") {
            return result.response.usage
        }
        ; FIM responses don't include usage — parse from raw JSON
        try {
            rawParsed := jsongo.Parse(result.rawJSON)
            if !rawParsed.Has("usage") {
                return
            }
            rawUsage := rawParsed["usage"]
            pt := rawUsage.Has("prompt_tokens") ? Integer(rawUsage["prompt_tokens"]) : 0
            ct := rawUsage.Has("completion_tokens") ? Integer(rawUsage["completion_tokens"]) : 0
            tht := 0
            if rawUsage.Has("completion_tokens_details") {
                ctd := rawUsage["completion_tokens_details"]
                if ctd.Has("reasoning_tokens")
                    tht := Integer(ctd["reasoning_tokens"])
            }
            ckt := 0
            if rawUsage.Has("prompt_tokens_details") {
                ptd := rawUsage["prompt_tokens_details"]
                if ptd.Has("cached_tokens")
                    ckt := Integer(ptd["cached_tokens"])
            }
            tt := rawUsage.Has("total_tokens") ? Integer(rawUsage["total_tokens"]) : pt + ct
            return { promptTokens: pt, completionTokens: ct, thinkingTokens: tht, cachedTokens: ckt, totalTokens: tt }
        } catch Error as e {
            debugLog("Command FIM usage parse error: " e.Message, "ErrorHandler")
        }
        return
    }
}
