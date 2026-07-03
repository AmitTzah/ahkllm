#Include <Config>
#SingleInstance

; ----------------------------------------------------
; Hotkeys (registered dynamically from UserConfig.ahk)
; ----------------------------------------------------

Hotkey(mainHotkey, (*) => mainScriptHotkeyActions("showPromptMenu"))
Hotkey(saveReloadHotkey, (*) => mainScriptHotkeyActions("saveAndReloadScript"))
Hotkey(closeWindowsHotkey, (*) => mainScriptHotkeyActions("closeWindows"))
Hotkey(suspendHotkey, (*) => mainScriptHotkeyActions("suspendHotkey"), "S")

runOptionsMenuAction(command, *) {
    Run(command)
}

mainScriptHotkeyActions(action) {
    activeModelsCount := getActiveModels().Count

    switch action {
        case "showPromptMenu":
            promptMenu := Menu()
            tagsMap := Map()

            ; Process all active models once to build prompt maps
            if (activeModelsCount > 0) {

                for uniqueID, modelData in getActiveModels() {
                    getActiveModels().%modelData.promptName% := true
                }

                ; Send message to menu
                sendToMenu := Menu()
                promptMenu.Add("Send message to", sendToMenu)

                for uniqueID, modelData in getActiveModels() {
                    sendToMenu.Add(modelData.promptName, sendToPromptGroupHandler.Bind(modelData.promptName))
                }

                ; If there are more than one Response Windows, add "All" menu option
                if (activeModelsCount > 1) {
                    sendToMenu.Add("All", (*) => sendToAllModelsInputWindow.showInputWindow(, , "ahk_id " sendToAllModelsInputWindow
                        .guiObj.hWnd))
                }

                ; Line separator after Activate and Send message to
                promptMenu.Add()
            }

            ; Normal prompts
            for index, prompt in managePromptState("prompts", "get") {

                ; Check if prompt has tags
                hasTags := prompt.HasProp("tags") && prompt.tags && prompt.tags.Length > 0

                ; If prompt has a directAccelerator, add a top-level shortcut
                if prompt.HasProp("directAccelerator") && prompt.directAccelerator {
                    promptMenu.Add(prompt.directAccelerator . " - " . prompt.promptName, promptMenuHandler.Bind(index))
                }

                ; If no tags, add directly to menu and continue
                if !hasTags {
                    promptMenu.Add(prompt.menuText, promptMenuHandler.Bind(index))
                    continue
                }

                ; Process tags
                for tag in prompt.tags {
                    normalizedTag := StrLower(Trim(tag))

                    ; Create tag menu if doesn't exist
                    if !tagsMap.Has(normalizedTag) {
                        tagsMap[normalizedTag] := { menu: Menu(), displayName: tag }
                        promptMenu.Add(tag, tagsMap[normalizedTag].menu)
                    }

                    ; Add prompt to tag menu
                    tagsMap[normalizedTag].menu.Add(prompt.menuText, promptMenuHandler.Bind(index))
                }
            }

            ; Add menus ("Activate", "Minimize", "Close") that manages Response Windows
            ; after normal prompts if there are active models
            if (activeModelsCount > 0) {

                ; Line separator before managing Response Window menu
                promptMenu.Add()

                ; Define the action types
                actionTypes := ["Activate", "Minimize", "Close"]

                ; Create submenus for each action type
                for _, actionType in actionTypes {

                    ; Convert to lowercase for function names
                    actionKey := StrLower(actionType)

                    actionSubMenu := Menu()
                    promptMenu.Add(actionType, actionSubMenu)

                    ; Add menu items for each active model
                    for uniqueID, modelData in getActiveModels() {
                        actionSubMenu.Add(modelData.promptName, managePromptWindows.Bind(actionKey, modelData.promptName
                        ))
                    }

                    ; If there are more than one Response Windows, add "All" menu option
                    if (activeModelsCount > 1) {
                        actionSubMenu.Add("All", managePromptWindows.Bind(actionKey))
                    }
                }
            }

            ; Line separator before Options
            promptMenu.Add()

            ; Options menu — built dynamically from UserConfig.ahk
            promptMenu.Add("&Options", optionsMenu := Menu())
            for _, item in optionsMenuItems {
                optionsMenu.Add(item.menuText, runOptionsMenuAction.Bind(item.command))
            }
            promptMenu.Show()

        case "suspendHotkey":
            KeyWait "CapsLock", "L"
            SetCapsLockState "Off"
            toggleSuspend(A_IsSuspended)

        case "saveAndReloadScript":
            if !WinActive("UserConfig.ahk") {
                return
            }

            ; Small delay to ensure file operations are complete
            Sleep 100

            if (activeModelsCount > 0) {
                MsgBox("Script will automatically reload once all Response Windows are closed.",
                    "LLM AutoHotkey Assistant", 64)
                responseWindowState(0, 0, "reloadScript", 0)
            } else {
                Reload()
            }

        case "closeWindows":
            switch WinActive("A") {
                case customPromptInputWindow.guiObj.hWnd: customPromptInputWindow.closeButtonAction()
                case sendToPromptNameInputWindow.guiObj.hWnd: sendToPromptNameInputWindow.closeButtonAction()
                case sendToAllModelsInputWindow.guiObj.hWnd: sendToAllModelsInputWindow.closeButtonAction()
            }
    }
}

; ----------------------------------------------------
; Generate tray menu dynamically from UserConfig.ahk
; ----------------------------------------------------

TraySetIcon(iconOn)
A_TrayMenu.Delete()
for _, item in trayMenuItems {
    switch item.action {
        case "reload": A_TrayMenu.Add(item.menuText, (*) => Reload())
        case "exit":   A_TrayMenu.Add(item.menuText, (*) => ExitApp())
    }
}
A_IconTip := "LLM AutoHotkey Assistant"

; ----------------------------------------------------
; Create new instance of LLMClient class
; ----------------------------------------------------

router := LLMClient(APIKey)

; ----------------------------------------------------
; Create Input Windows
; ----------------------------------------------------

customPromptInputWindow := InputWindow("Custom prompt")
sendToAllModelsInputWindow := InputWindow("Send message to all")
sendToPromptNameInputWindow := InputWindow("Send message to prompt")

; ----------------------------------------------------
; Register sendButtonActions
; ----------------------------------------------------

customPromptInputWindow.sendButtonAction(customPromptSendButtonAction)
sendToAllModelsInputWindow.sendButtonAction(sendToAllModelsSendButtonAction)
sendToPromptNameInputWindow.sendButtonAction(sendToGroupSendButtonAction)

; ----------------------------------------------------
; Input Window actions
; ----------------------------------------------------

customPromptSendButtonAction(*) {
    if !customPromptInputWindow.validateInputAndHide() {
        return
    }

    selectedPrompt := managePromptState("selectedPrompt", "get")
    processInitialRequest(selectedPrompt.promptName, selectedPrompt.menuText, selectedPrompt.systemPrompt,
        selectedPrompt.APIModels,
        selectedPrompt.HasProp("copyAsMarkdown") && selectedPrompt.copyAsMarkdown,
        selectedPrompt.HasProp("pasteMode") ? selectedPrompt.pasteMode : "",
        selectedPrompt.HasProp("skipConfirmation") && selectedPrompt.skipConfirmation,
        selectedPrompt.HasProp("isFIM") && selectedPrompt.isFIM,
        customPromptInputWindow.EditControl.Value,
        selectedPrompt.HasProp("temperature") ? selectedPrompt.temperature : "",
        selectedPrompt.HasProp("maxTokens") ? selectedPrompt.maxTokens : "",
        selectedPrompt.HasProp("stop") ? selectedPrompt.stop : ""
    )
    customPromptInputWindow.EditControl.Value := ""
}

sendToAllModelsSendButtonAction(*) {
    if (getActiveModels().Count = 0) {
        MsgBox "No Response Windows found. Message not sent.", "Send message to all models", "IconX"
        sendToAllModelsInputWindow.guiObj.Hide
        return
    }

    if !sendToAllModelsInputWindow.validateInputAndHide() {
        return
    }

    ; The main script must know each Response Window's JSON file
    ; so it can read it, parse it, append the new
    ; user message, then write it back
    for uniqueID, modelData in getActiveModels() {
        JSONStr := FileOpen(modelData.JSONFile, "r", "UTF-8").Read()
        router.appendToChatHistory("user", sendToAllModelsInputWindow.EditControl.Value, &JSONStr, modelData.JSONFile)

        ; Notify the Response Window to re-read the JSON file and call sendRequestToLLM() again
        responseWindowhWnd := modelData.hWnd
        CustomMessages.notifyResponseWindowState(CustomMessages.WM_SEND_TO_ALL_MODELS, uniqueID, responseWindowhWnd
        )
    }
}

sendToGroupSendButtonAction(*) {
    if (getActiveModels().Count = 0) {
        MsgBox "No Response Windows found. Message not sent.", "Send message to all models", "IconX"
        sendToAllModelsInputWindow.guiObj.Hide
        return
    }

    if !sendToPromptNameInputWindow.validateInputAndHide() {
        return
    }

    if (!targetPromptName := managePromptState("selectedPromptForMessage", "get")) {
        return
    }

    ; Send message only to active models that belong to this prompt
    for uniqueID, modelData in getActiveModels() {

        ; Check if this model belongs to the selected prompt
        if (modelData.promptName != targetPromptName) {
            continue
        }

        JSONStr := FileOpen(modelData.JSONFile, "r", "UTF-8").Read()
        router.appendToChatHistory("user", sendToPromptNameInputWindow.EditControl.Value, &JSONStr, modelData.JSONFile)

        ; Notify the Response Window to re-read the JSON file and call sendRequestToLLM() again
        responseWindowhWnd := modelData.hWnd
        CustomMessages.notifyResponseWindowState(CustomMessages.WM_SEND_TO_ALL_MODELS, uniqueID, responseWindowhWnd)
    }

    sendToPromptNameInputWindow.EditControl.Value := ""
}

sendToPromptGroupHandler(promptName, *) {
    promptsList := managePromptState("prompts", "get")

    ; Find the prompt with the matching promptName
    for _, prompt in promptsList {

        ; Check if the prompt has the same name as the one we're looking for
        if (prompt.promptName = promptName) {
            selectedPrompt := prompt
            break
        }
    }

    managePromptState("selectedPromptForMessage", "set", promptName)

    ; Check if the prompt has skipConfirmation property and set accordingly
    sendToPromptNameInputWindow.setSkipConfirmation(selectedPrompt.HasProp("skipConfirmation") ? selectedPrompt.skipConfirmation : false)
    sendToPromptNameInputWindow.showInputWindow(, "Send message to " promptName, "ahk_id " sendToPromptNameInputWindow.guiObj
        .hWnd
    )
}

; Generic function to perform an operation on prompt windows
;
; Parameters:
; - operation (activate, minimize, close): The operation to perform
; - promptName: Optional. If provided, only windows for this prompt will be affected
managePromptWindows(operation, promptName := "", *) {

    ; Create a list of window handles that match our criteria
    hWndsToManage := []

    ; Iterate through all active models
    for uniqueID, modelData in getActiveModels() {
        if (promptName = "All" || modelData.promptName = promptName) {
            hWndsToManage.Push(modelData.hWnd)
        }
    }

    ; Perform the requested operation on each window
    for _, hWnd in hWndsToManage {
        switch operation {
            case "activate": WinActivate("ahk_id " hWnd)
            case "minimize": WinMinimize("ahk_id " hWnd)
            case "close": WinClose("ahk_id " hWnd)
        }
    }
}

; ----------------------------------------------------
; Initialize Suspend GUI
; ----------------------------------------------------

scriptSuspendStatus := Gui()
scriptSuspendStatus.SetFont(suspendBannerFontSize, suspendBannerFontFace)
scriptSuspendStatus.Add("Text", suspendBannerTextColor " Center", suspendBannerText)
scriptSuspendStatus.BackColor := suspendBannerBackground
scriptSuspendStatus.Opt("-Caption +Owner -SysMenu +AlwaysOnTop")
scriptSuspendStatusWidth := ""
scriptSuspendStatus.GetPos(, , &scriptSuspendStatusWidth)

; ----------------------------------------------------
; Toggle Suspend
; ----------------------------------------------------

toggleSuspend(*) {
    Suspend -1
    if (A_IsSuspended) {
        TraySetIcon(iconOff, , 1)
        A_IconTip := "LLM AutoHotkey Assistant - Suspended)"

        ; Show GUI at the bottom, centered
        scriptSuspendStatus.Show("AutoSize x" (A_ScreenWidth - scriptSuspendStatusWidth) / 2.3 " y990 NA")
    } else {
        TraySetIcon(iconOn)
        A_IconTip := "LLM AutoHotkey Assistant"
        scriptSuspendStatus.Hide()
    }
}

; ----------------------------------------------------
; Prompt menu handler function
; ----------------------------------------------------

promptMenuHandler(index, *) {
    promptsList := managePromptState("prompts", "get")
    selectedPrompt := promptsList[index]
    if (selectedPrompt.HasProp("isCustomPrompt") && selectedPrompt.isCustomPrompt) {

        ; Save the prompt for future reference in customPromptSendButtonAction(*)
        managePromptState("selectedPrompt", "set", selectedPrompt)

        ; Set skipConfirmation property based on the prompt
        customPromptInputWindow.setSkipConfirmation(selectedPrompt.HasProp("skipConfirmation") ? selectedPrompt.skipConfirmation : false)

        customPromptInputWindow.showInputWindow(selectedPrompt.HasProp("customPromptInitialMessage")
            ? selectedPrompt.customPromptInitialMessage : unset, selectedPrompt.promptName, "ahk_id " customPromptInputWindow
        .guiObj.hWnd)
    } else {
    processInitialRequest(selectedPrompt.promptName, selectedPrompt.menuText, selectedPrompt.systemPrompt,
        selectedPrompt.APIModels,
        selectedPrompt.HasProp("copyAsMarkdown") && selectedPrompt.copyAsMarkdown,
        selectedPrompt.HasProp("pasteMode") ? selectedPrompt.pasteMode : "",
        selectedPrompt.HasProp("skipConfirmation") && selectedPrompt.skipConfirmation,
        selectedPrompt.HasProp("isFIM") && selectedPrompt.isFIM,
        "",  ; customPromptMessage (not applicable for non-custom prompts)
        selectedPrompt.HasProp("temperature") ? selectedPrompt.temperature : "",
        selectedPrompt.HasProp("maxTokens") ? selectedPrompt.maxTokens : "",
        selectedPrompt.HasProp("stop") ? selectedPrompt.stop : "")
    }
}

; ----------------------------------------------------
; Manage prompt states
; ----------------------------------------------------

managePromptState(component, action, data := {}) {
    static state := {
        prompts: prompts,
        selectedPrompt: {},
        selectedPromptForMessage: {}
    }

    switch component {
        case "prompts":
            switch action {
                case "get": return state.prompts
                case "set": state.prompts := data
            }

        case "selectedPrompt":
            switch action {
                case "get": return state.selectedPrompt
                case "set": state.selectedPrompt := data
            }

        case "selectedPromptForMessage":
            switch action {
                case "get": return state.selectedPromptForMessage
                case "set": state.selectedPromptForMessage := data
            }
    }
}

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

        ; For pasteMode "replace" or "append", auto-disable if multi-model
        if pasteMode = "replace" || pasteMode = "append" {
            pasteMode := (APIModels.Length > 1) ? "" : pasteMode
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
        FileOpen(cURLCommandFile, "w").Write(cURLCommand)

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

        ; Write the object to a file and run Response Window.ahk
        dataObjToJSONStr := jsongo.Stringify(responseWindowDataObj)
        dataObjToJSONStrFile := A_Temp "\" RegExReplace("responseWindowData_" promptName "_" singleAPIModelName "_" A_TickCount ".json",
            "[\/\\:*?`"<>|]", "")
        FileOpen(dataObjToJSONStrFile, "w", "UTF-8-RAW").Write(dataObjToJSONStr)
        getActiveModels()[uniqueID].JSONFile := chatHistoryJSONRequestFile
        Run("lib\Response Window.ahk " "`"" dataObjToJSONStrFile)
    }
}

; ----------------------------------------------------
; Tracks active models
; ----------------------------------------------------

getActiveModels() {
    static activeModels := Map()
    return activeModels
}

; ----------------------------------------------------
; Custom messages and handlers for detecting
; Response Window states
; ----------------------------------------------------

CustomMessages.registerHandlers("mainScript", responseWindowState)
responseWindowState(uniqueID, responseWindowhWnd, state, mainScriptHiddenhWnd) {
    static responseWindowLoadingCount := 0
    static reloadScript := false

    switch state {
        case CustomMessages.WM_RESPONSE_WINDOW_OPENED:
            getActiveModels()[uniqueID].hWnd := responseWindowhWnd

        case CustomMessages.WM_RESPONSE_WINDOW_CLOSED:
            if getActiveModels().Has(uniqueID) {
                getActiveModels().Delete(uniqueID)
                manageCursorAndToolTip("Update")
            }

            if (getActiveModels().Count = 0) && reloadScript {
                Reload()
            }
        case CustomMessages.WM_RESPONSE_WINDOW_LOADING_START:
            getActiveModels()[uniqueID].isLoading := true
            responseWindowLoadingCount++
            if (responseWindowLoadingCount = 1) {
                manageCursorAndToolTip("Loading")
            }

            manageCursorAndToolTip("Update")

        case CustomMessages.WM_RESPONSE_WINDOW_LOADING_FINISH:
            if (responseWindowLoadingCount > 0 && getActiveModels().Has(uniqueID)) {
                responseWindowLoadingCount--
                getActiveModels()[uniqueID].isLoading := false
                if (responseWindowLoadingCount = 0) {
                    manageCursorAndToolTip("Reset")
                } else {
                    manageCursorAndToolTip("Update")
                }
            }

        case "reloadScript": reloadScript := true
    }
}

; ----------------------------------------------------
; Cursor and Tooltip management
; ----------------------------------------------------

manageCursorAndToolTip(action) {
    switch action {
        case "Update":
            activeCount := 0
            for key, data in getActiveModels() {
                if data.isLoading {
                    activeCount++
                }
            }

            if (activeCount = 0) {
                ToolTip
                return
            }

            toolTipMessage := "Retrieving response for the following prompt"

            ; Singular and plural forms of the word "model"
            if (activeCount > 1) {
                toolTipMessage .= "s"
            }

            toolTipMessage .= " (Press ESC to cancel):"
            for key, data in getActiveModels() {
                if (data.isLoading) {
                    toolTipMessage .= "`n- " data.promptName " [" data.name "]"
                }
            }

            ToolTipEX(toolTipMessage, 0)

        case "Loading":
            ; Change default arrow cursor (32512) to "working in background" cursor (32650)
            ; Ensure that other cursors remain unchanged to preserve their functionality
            Cursor := DllCall("LoadCursor", "uint", 0, "uint", 32650)
            DllCall("SetSystemCursor", "Ptr", Cursor, "UInt", 32512)

        case "Reset":
            ToolTip
            DllCall("SystemParametersInfo", "UInt", 0x57, "UInt", 0, "Ptr", 0, "UInt", 0)
    }
}
