; ----------------------------------------------------
; Prompt menu building
; ----------------------------------------------------

buildPromptMenu() {
    promptMenu := Menu()
    tagsMap := Map()

    ; Always show "&1 - Open Chat" as the first item
    promptMenu.Add("&1 - Open Chat", (*) => OpenChatPromptHandler())

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
