; ----------------------------------------------------
; Connect to LLM API and process request
; ----------------------------------------------------

; ----------------------------------------------------
; Diagnostic logging helper (standalone for main script context)
; ----------------------------------------------------

debugLog(message) {
    timestamp := FormatTime(, "HH:mm:ss")
    FileAppend(timestamp " [RequestProcessor] " message "`n", A_Temp "\LLM_Debug_Log.txt")
}

processInitialRequest(commandName, menuText, systemMessage, APIModels, copyAsMarkdown, pasteMode, skipConfirmation, isFIM,
    customInputMessage := "", temperature := "", maxTokens := "", stop := "", stream := false, thinking := "") {
    debugLog("processInitialRequest: " commandName " stream=" stream " pasteMode=" pasteMode)

    ; ----------------------------------------------------
    ; STEP 1: Capture text (clipboard-based)
    ; ----------------------------------------------------
    clipboardBeforeCopy := A_Clipboard
    prefix := ""
    suffix := ""

    if isFIM {
        ; --- FIM text capture ---

        ; First, try to copy the selection
        A_Clipboard := ""
        Send("^c")

        selection := ""
        if !ClipWait(1) {
            ; Nothing selected — try Ctrl+Shift+Home to grab text before cursor
            A_Clipboard := ""
            Send("^+{Home}^c")
            if !ClipWait(1) {
                manageCursorAndToolTip("Reset")
                A_Clipboard := clipboardBeforeCopy
                MsgBox "No text found before cursor. Please select some text or place your cursor after text.", "FIM Continue", "IconX"
                return
            }
            ; Text-before-cursor grabbed — FIM Continue, no suffix
            prefix := A_Clipboard
            suffix := ""
        } else {
            ; Selection found
            selection := A_Clipboard

            if pasteMode = "replace" {
                ; FIM Fill: cut the gap (removes selection, cursor at gap position)
                A_Clipboard := ""
                Send("^x")
                if !ClipWait(1) {
                    manageCursorAndToolTip("Reset")
                    A_Clipboard := clipboardBeforeCopy
                    MsgBox "Could not cut the selected text.", "FIM Fill", "IconX"
                    return
                }
                ; The gap is now removed from the text. Extract everything before it.
                A_Clipboard := ""
                Send("^+{Home}^c")
                if !ClipWait(1) {
                    prefix := ""
                } else {
                    prefix := A_Clipboard
                }
                ; Move cursor back to gap position, then get everything after the gap.
                Send("{Right}")
                Sleep 50
                A_Clipboard := ""
                Send("+^{End}^c")
                if !ClipWait(1) {
                    suffix := ""
                } else {
                    suffix := A_Clipboard
                }
                ; Move cursor back to gap position for paste later.
                Send("{Left}")
            } else {
                ; FIM Continue with selection as prefix
                prefix := selection
                suffix := ""
            }
        }

        A_Clipboard := clipboardBeforeCopy

        ; For FIM, restrict to a single model since FIM doesn't support multi-model
        if InStr(APIModels, ",") {
            MsgBox "FIM does not support multiple models. Only the first model will be used.", "FIM Warning", "IconX"
        }

        ; Parse models (take only the first for FIM)
        APIModels := StrSplit(RegExReplace(APIModels, "\s+", ""), ",")
        APIModels := [APIModels[1]]
    } else {
        ; --- Chat text capture (with retry cascade) ---
        A_Clipboard := ""
        Critical("On")
        SendInput("^c")
        copied := ClipWait(0.5)
        if !copied {
            ; Retry with standard Send
            A_Clipboard := ""
            Send("^c")
            copied := ClipWait(1.5)
        }
        if !copied {
            ; Final fallback: Ctrl+Insert (works in terminals)
            A_Clipboard := ""
            Send("^{Insert}")
            copied := ClipWait(1)
        }
        Critical("Off")

        if !copied {
            if customInputMessage != "" {
                userMessage := customInputMessage
            } else {
                manageCursorAndToolTip("Reset")
                A_Clipboard := clipboardBeforeCopy
                MsgBox "The attempt to copy text onto the clipboard failed.", "No text copied", "IconX"
                return
            }
        } else if customInputMessage != "" {
            userMessage := customInputMessage "`n`n" A_Clipboard
        } else {
            userMessage := A_Clipboard
        }

        A_Clipboard := clipboardBeforeCopy

        ; Removes newlines, spaces, and splits by comma
        APIModels := StrSplit(RegExReplace(APIModels, "\s+", ""), ",")

        ; For pasteMode "replace" or "append", fall back to "chat" if multi-model
        if pasteMode = "replace" || pasteMode = "append" {
            pasteMode := (APIModels.Length > 1) ? "chat" : pasteMode
        }
    }

    ; ----------------------------------------------------
    ; STEP 2: Build request and spawn Response Windows
    ; ----------------------------------------------------
    for i, fullAPIModelName in APIModels {

        ; Parse provider/model format (e.g., "openai/gpt-4o") or direct model name
        if (slashPos := InStr(fullAPIModelName, "/")) {
            providerName := SubStr(fullAPIModelName, 1, slashPos - 1)
            singleAPIModelName := SubStr(fullAPIModelName, slashPos + 1)
        } else {
            providerName := "deepseek"  ; default fallback
            for prefix, mappedProvider in providerMap {
                if InStr(fullAPIModelName, prefix) {
                    providerName := mappedProvider
                    break
                }
            }
            singleAPIModelName := fullAPIModelName
        }

        uniqueID := A_TickCount

        ; Build the JSON request — FIM or chat, with optional temperature/maxTokens/stop/stream/thinking
        if isFIM {
            chatHistoryJSONRequest := router.createFIMRequest(fullAPIModelName, prefix, suffix,
                temperature, maxTokens, stop)
        } else {
            chatHistoryJSONRequest := router.createJSONRequest(fullAPIModelName, systemMessage, userMessage,
                temperature, maxTokens, stop, stream, thinking)
        }

        ; Generate sanitized filenames
        chatHistoryJSONRequestFile := A_Temp "\" RegExReplace("chatHistoryJSONRequest_" commandName "_" singleAPIModelName "_" uniqueID ".json",
            "[\/\\:*?`"<>|]", "")
        cURLCommandFile := A_Temp "\" RegExReplace("cURLCommand_" commandName "_" singleAPIModelName "_" uniqueID ".txt",
            "[\/\\:*?`"<>|]", "")
        cURLOutputFile := A_Temp "\" RegExReplace("cURLOutput_" commandName "_" singleAPIModelName "_" uniqueID ".json",
            "[\/\\:*?`"<>|]", "")
        cURLErrorFile := A_Temp "\" RegExReplace("cURLError_" commandName "_" singleAPIModelName "_" uniqueID ".txt",
            "[\/\\:*?`"<>|]", "")

        ; Write the JSON request and cURL command to files
        FileOpen(chatHistoryJSONRequestFile, "w", "UTF-8-RAW").Write(chatHistoryJSONRequest)
        if isFIM {
            cURLCommand := router.buildFIMcURLCommand(chatHistoryJSONRequestFile, cURLOutputFile)
            debugLog("Built FIM cURL command. outputFile=" cURLOutputFile)
        } else if stream && pasteMode = "chat" {
            ; Use streaming cURL command for streaming requests
            cURLCommand := router.buildStreamcURLCommand(chatHistoryJSONRequestFile, cURLOutputFile, cURLErrorFile)
            debugLog("Built STREAMING cURL command. outputFile=" cURLOutputFile)
        } else {
            cURLCommand := router.buildcURLCommand(chatHistoryJSONRequestFile, cURLOutputFile)
            debugLog("Built NON-STREAMING cURL command. stream=" stream " pasteMode=" pasteMode " outputFile=" cURLOutputFile)
        }
        FileOpen(cURLCommandFile, "w", "UTF-8-RAW").Write(cURLCommand)
        debugLog("Wrote cURL command to: " cURLCommandFile)
        debugLog("JSON request written to: " chatHistoryJSONRequestFile)
        debugLog("stream field in responseWindowDataObj: " (stream && pasteMode = "chat"))

        ; For chat mode, route through the persistent ChatWindow
        ; Note: multi-model (Council) is not supported in the single-window chat architecture.
        ; Only the first model is used for chat mode.
        if pasteMode = "chat" {
            if APIModels.Length > 1 {
                ; Log warning but proceed with first model
                debugLog("WARNING: Multi-model not supported in chat mode. Using only first model: " APIModels[1])
            }
            ; Create a new thread in the DB
            threadId := ChatDB.Thread_Create(commandName)

            ; Insert system message if present
            if systemMessage {
                ChatDB.Msg_Insert({
                    thread_id: threadId,
                    role: "system",
                    content: systemMessage,
                    parent_id: ""
                })
            }

            ; Insert captured text as first user message if any (isSet check for FIM mode)
            if IsSet(userMessage) && userMessage {
                path := ChatDB.Msg_GetActivePath(threadId)
                parentId := path.Length ? path[path.Length].id : ""
                ChatDB.Msg_Insert({
                    thread_id: threadId,
                    role: "user",
                    content: userMessage,
                    parent_id: parentId
                })
            }

            ; Open the ChatWindow with this thread
            OpenOrSpawnChatWindow(threadId)
            ; Only process the first model for chat mode (single-window limitation)
            break
        } else {
            ; Non-chat mode: run LLM inline and paste result directly (no window)
            ; Track in active models during processing (for tooltip and reload deferral)
            getActiveModels()[uniqueID] := {
                commandName: commandName,
                name: singleAPIModelName,
                provider: router,
                JSONFile: chatHistoryJSONRequestFile,
                cURLFile: cURLCommandFile,
                outputFile: cURLOutputFile,
                errorFile: cURLErrorFile,
                isLoading: true
            }
            manageCursorAndToolTip("Update")
            requestStartTime := A_TickCount
            cURLCommand := FileOpen(cURLCommandFile, "r", "UTF-8-RAW").Read()
            Run(cURLCommand, , "Hide", &cURLPID)
            while ProcessExist(cURLPID)
                Sleep 250
            responseFromLLM := ""
            if FileExist(cURLOutputFile) {
                JSONResponseFromLLM := FileOpen(cURLOutputFile, "r", "UTF-8-RAW").Read()
                try {
                    if isFIM
                        responseFromLLM := router.extractFIMResponse(jsongo.Parse(JSONResponseFromLLM))
                    else
                        responseFromLLM := router.extractJSONResponse(jsongo.Parse(JSONResponseFromLLM))
                }
            }
            if IsObject(responseFromLLM) && responseFromLLM.HasProp("response") {
                latencyMs := A_TickCount - requestStartTime
                A_Clipboard := responseFromLLM.response
                if pasteMode = "append" {
                    Send("{Right}")       ; Move cursor past the selection before pasting
                }
                Send("^v")
                Sleep 50
                if pasteMode = "append" {
                    Send("{Left}{Right}") ; Force scroll-to-cursor
                }
                ; Log the API call
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
            manageCursorAndToolTip("Update")
            getActiveModels().Delete(uniqueID)
            FileDelete(chatHistoryJSONRequestFile)
            FileDelete(cURLCommandFile)
            FileExist(cURLOutputFile) ? FileDelete(cURLOutputFile) : ""
            FileExist(cURLErrorFile) ? FileDelete(cURLErrorFile) : ""
        }
    }
}

; ----------------------------------------------------
; Options menu action
; ----------------------------------------------------

runOptionsMenuAction(command, *) {
    ; If command is "Program filepath" format (e.g., "Notepad C:\...\UserConfig.ahk"),
    ; skip FileExist check — the full string isn't a valid path. Run directly.
    if (spacePos := InStr(command, " ")) {
        firstWord := SubStr(command, 1, spacePos - 1)
        if !InStr(firstWord, "\") && !InStr(firstWord, ":") {
            Run(command)
            return
        }
    }
    ; Pure file path — check if it exists, show friendly tooltip if not
    if (InStr(command, ":") || InStr(command, "\")) {
        if !FileExist(command) && !InStr(command, "http") {
            ToolTip("No logs written yet — file hasn't been created", , , 19)
            SetTimer () => ToolTip(, , , 19), -3000
            return
        }
    }
    Run(command)
}