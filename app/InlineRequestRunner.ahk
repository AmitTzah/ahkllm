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
            ; Highlight inserted text so the user can immediately see what was added
            if isFIM {
                Sleep 100  ; let the target app finish processing the paste
                InlineRequestRunner.HighlightInsertedText(responseFromLLM.response)
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
    ; inserted text. This selects backwards so the user can
    ; immediately see what was added.
    ; ----------------------------------------------------
    static HighlightInsertedText(responseText) {
        params := InlineRequestRunner._GetHighlightParams(responseText)
        lineCount := params.lineCount

        ; Brief sleep before sending selection keystrokes — the target app
        ; needs time to finish processing the paste before we can select.
        Sleep 60

        if (lineCount = 1) {
            Send("{Shift down}{Left " params.firstLineLen "}{Shift up}")
        } else {
            ; Select backwards from end to start. {Home 2} reaches column 0
            ; even in editors with smart-home behavior.
            Send("{Shift down}{Up " (lineCount - 1) "}{Home 2}{Shift up}")
        }
    }

    ; ----------------------------------------------------
    ; _GetHighlightParams — pure computation (no Send),
    ; testable without side effects.
    ;
    ; Returns { lineCount, firstLineLen }
    ; ----------------------------------------------------
    static _GetHighlightParams(responseText) {
        ; Normalize all line endings to LF (CRLF before bare CR — order matters)
        cleanText := StrReplace(StrReplace(responseText, "`r`n", "`n"), "`r", "`n")
        ; Strip trailing newline to avoid inflating lineCount with an empty last element
        cleanText := RTrim(cleanText, "`n")
        lines := StrSplit(cleanText, "`n")
        return { lineCount: lines.Length, firstLineLen: lines.Length > 0 ? StrLen(lines[1]) : 0 }
    }
}
