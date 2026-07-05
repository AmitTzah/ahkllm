; ----------------------------------------------------
; Prompt menu building
; ----------------------------------------------------

buildPromptMenu() {
    activeModelsCount := getActiveModels().Count
    promptMenu := Menu()
    tagsMap := Map()

    ; Always show "&1 - Open Chat" as the first item
    promptMenu.Add("&1 - Open Chat", (*) => OpenChatPromptHandler())

    ; Send message to submenu if there are active models
    if (activeModelsCount > 0) {
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
        selectedPrompt.HasProp("pasteMode") ? selectedPrompt.pasteMode : "chat",
        selectedPrompt.HasProp("skipConfirmation") && selectedPrompt.skipConfirmation,
        selectedPrompt.HasProp("isFIM") && selectedPrompt.isFIM,
        "",  ; customPromptMessage (not applicable for non-custom prompts)
        selectedPrompt.HasProp("temperature") ? selectedPrompt.temperature : "",
        selectedPrompt.HasProp("maxTokens") ? selectedPrompt.maxTokens : "",
        selectedPrompt.HasProp("stop") ? selectedPrompt.stop : "",
        selectedPrompt.HasProp("stream") && selectedPrompt.stream,
        selectedPrompt.HasProp("thinking") && selectedPrompt.thinking ? selectedPrompt.thinking["type"] : "")
    }
}

; ----------------------------------------------------
; "&1 - Open Chat" handler — restores or spawns the persistent chat window
; ----------------------------------------------------

OpenChatPromptHandler(*) {
    ; Open or restore the persistent chat window at the last active thread
    OpenOrSpawnChatWindow()
}
