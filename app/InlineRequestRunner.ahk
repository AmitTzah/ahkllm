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
    ; Returns object with request, JSON, and file paths.
    static _BuildAndWriteRequest(commandName, fullAPIModelName, singleAPIModelName, captured, isFIM, systemMessage, temperature, maxTokens, stop, stream, thinking, thinkingLevel, uniqueID) {
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
        requestFile := A_Temp "\" RegExReplace("chatHistoryJSONRequest_" commandName "_" singleAPIModelName "_" uniqueID ".json", sanitizeRe, "")
        curlFile := A_Temp "\" RegExReplace("cURLCommand_" commandName "_" singleAPIModelName "_" uniqueID ".txt", sanitizeRe, "")
        outputFile := A_Temp "\" RegExReplace("cURLOutput_" commandName "_" singleAPIModelName "_" uniqueID ".json", sanitizeRe, "")
        errorFile := A_Temp "\" RegExReplace("cURLError_" commandName "_" singleAPIModelName "_" uniqueID ".txt", sanitizeRe, "")

        FileOpen(requestFile, "w", "UTF-8-RAW").Write(chatHistoryJSONRequest)
        if isFIM {
            cURLCommand := llmClient.buildFIMcURLCommand(requestFile, outputFile)
        } else {
            cURLCommand := llmClient.buildcURLCommand(requestFile, outputFile)
        }
        FileOpen(curlFile, "w", "UTF-8-RAW").Write(cURLCommand)

        return {
            requestJSON: chatHistoryJSONRequest,
            requestFile: requestFile,
            curlFile: curlFile,
            outputFile: outputFile,
            errorFile: errorFile
        }
    }

    ; Execute cURL synchronously and parse the response.
    ; Returns { success: true/false, response: parsedResponse, rawJSON: rawResponseText }
    static _ExecuteCurlAndParse(files, isFIM) {
        requestStartTime := A_TickCount
        cURLCommand := FileOpen(files.curlFile, "r", "UTF-8-RAW").Read()
        Run(cURLCommand, , "Hide", &cURLPID)
        while ProcessExist(cURLPID)
            Sleep 250

        responseFromLLM := ""
        JSONResponseFromLLM := ""
        if FileExist(files.outputFile) {
            JSONResponseFromLLM := FileOpen(files.outputFile, "r", "UTF-8-RAW").Read()
            try {
                if isFIM
                    responseFromLLM := llmClient.extractFIMResponse(jsongo.Parse(JSONResponseFromLLM))
                else
                    responseFromLLM := llmClient.extractJSONResponse(jsongo.Parse(JSONResponseFromLLM))
            } catch Error as e {
                debugLog("Failed to parse LLM response: " e.Message, "InlineRequestRunner")
            }
        }

        return {
            success: IsObject(responseFromLLM) && responseFromLLM.HasProp("response"),
            response: responseFromLLM,
            rawJSON: JSONResponseFromLLM,
            latencyMs: A_TickCount - requestStartTime
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
            endpoint: isFIM ? FIMEndpoint : APIEndpoint,
            pasteMode: pasteMode,
            request: files.requestJSON,
            response: result.rawJSON,
            status: "success",
            latencyMs: result.latencyMs
        })
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
}
