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
            } catch Error as e {
                debugLog("Failed to parse LLM response: " e.Message, "InlineRequestRunner")
            }
        }

        ; Paste result
        if IsObject(responseFromLLM) && responseFromLLM.HasProp("response") {
            latencyMs := A_TickCount - requestStartTime
            responseText := responseFromLLM.response

            ; Try UIA paste for FIM (avoids clipboard; works for simple ValuePattern controls).
            ; Non-FIM uses ^v to preserve undo history (ValuePattern.SetValue doesn't
            ; create undo points in complex editors like VS Code).
            pastedViaUIA := false
            if isFIM {
                try {
                    el := UIA.GetFocusedElement()
                    if el.IsValuePatternAvailable && !el.ValueIsReadOnly {
                        if pasteMode = "replace"
                            el.Value := captured.prefix . responseText . captured.suffix
                        else
                            el.Value := captured.prefix . responseText
                        pastedViaUIA := true
                    }
                }
            }

            if !pastedViaUIA {
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
}
