; ----------------------------------------------------
; Connect to LLM API and process request
; ----------------------------------------------------

processInitialRequest(promptName, menuText, systemPrompt, APIModels, copyAsMarkdown, pasteMode, skipConfirmation, isFIM,
    customPromptMessage := "", temperature := "", maxTokens := "", stop := "") {

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

        ; For FIM, auto-disable multi-model (FIM only makes sense with one model)
        if InStr(APIModels, ",") {
            MsgBox "FIM does not support multiple models. Only the first model will be used.", "FIM Warning", "IconX"
        }

        ; Process models (single model for FIM)
        APIModels := StrSplit(RegExReplace(APIModels, "\s+", ""), ",")
    } else {
        ; --- Chat text capture (existing logic) ---
        A_Clipboard := ""
        Send("^c")

        if !ClipWait(1) {
            if customPromptMessage != "" {
                userPrompt := customPromptMessage
            } else {
                manageCursorAndToolTip("Reset")
                A_Clipboard := clipboardBeforeCopy
                MsgBox "The attempt to copy text onto the clipboard failed.", "No text copied", "IconX"
                return
            }
        } else if customPromptMessage != "" {
            userPrompt := customPromptMessage "`n`n" A_Clipboard
        } else {
            userPrompt := A_Clipboard
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

        ; Build the JSON request — FIM or chat, with optional temperature/maxTokens/stop
        if isFIM {
            chatHistoryJSONRequest := router.createFIMRequest(fullAPIModelName, prefix, suffix,
                temperature, maxTokens, stop)
        } else {
            chatHistoryJSONRequest := router.createJSONRequest(fullAPIModelName, systemPrompt, userPrompt,
                temperature, maxTokens, stop)
        }

        ; Generate sanitized filenames
        chatHistoryJSONRequestFile := A_Temp "\" RegExReplace("chatHistoryJSONRequest_" promptName "_" singleAPIModelName "_" uniqueID ".json",
            "[\/\\:*?`"<>|]", "")
        cURLCommandFile := A_Temp "\" RegExReplace("cURLCommand_" promptName "_" singleAPIModelName "_" uniqueID ".txt",
            "[\/\\:*?`"<>|]", "")
        cURLOutputFile := A_Temp "\" RegExReplace("cURLOutput_" promptName "_" singleAPIModelName "_" uniqueID ".json",
            "[\/\\:*?`"<>|]", "")

        ; Write the JSON request and cURL command to files
        FileOpen(chatHistoryJSONRequestFile, "w", "UTF-8-RAW").Write(chatHistoryJSONRequest)
        if isFIM {
            cURLCommand := router.buildFIMcURLCommand(chatHistoryJSONRequestFile, cURLOutputFile)
        } else {
            cURLCommand := router.buildcURLCommand(chatHistoryJSONRequestFile, cURLOutputFile)
        }
        FileOpen(cURLCommandFile, "w", "UTF-8-RAW").Write(cURLCommand)

        ; Maintain a reference in the global map
        getActiveModels()[uniqueID] := {
            promptName: promptName,
            name: singleAPIModelName,
            provider: router,
            JSONFile: chatHistoryJSONRequestFile,
            cURLFile: cURLCommandFile,
            outputFile: cURLOutputFile,
            isLoading: false
        }

        ; Create the Response Window data object with pasteMode + isFIM
        responseWindowDataObj := {
            chatHistoryJSONRequestFile: chatHistoryJSONRequestFile,
            cURLCommandFile: cURLCommandFile,
            cURLOutputFile: cURLOutputFile,
            providerName: providerName,
            copyAsMarkdown: copyAsMarkdown,
            pasteMode: pasteMode,
            isFIM: isFIM,
            skipConfirmation: skipConfirmation,
            mainScriptHiddenhWnd: A_ScriptHwnd,
            responseWindowTitle: promptName " [" singleAPIModelName "]",
            singleAPIModelName: singleAPIModelName,
            numberOfAPIModels: APIModels.Length,
            APIModelsIndex: i,
            uniqueID: uniqueID
        }

        ; Write the object to a file and run ResponseWindow.ahk
        dataObjToJSONStr := jsongo.Stringify(responseWindowDataObj)
        dataObjToJSONStrFile := A_Temp "\" RegExReplace("responseWindowData_" promptName "_" singleAPIModelName "_" A_TickCount ".json",
            "[\/\\:*?`"<>|]", "")
        FileOpen(dataObjToJSONStrFile, "w", "UTF-8-RAW").Write(dataObjToJSONStr)
        getActiveModels()[uniqueID].JSONFile := chatHistoryJSONRequestFile
        Run(A_ScriptDir "\chat\ResponseWindow.ahk " "`"" dataObjToJSONStrFile)
    }
}

; ----------------------------------------------------
; Options menu action
; ----------------------------------------------------

runOptionsMenuAction(command, *) {
    Run(command)
}