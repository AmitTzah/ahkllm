; ----------------------------------------------------
; Command menu building
; ----------------------------------------------------

buildCommandMenu() {
    commandMenu := Menu()
    tagsMap := Map()

    ; Always show "&1 - Open Chat" as the first item
    commandMenu.Add("&1 - Open Chat", (*) => OpenChatCommandHandler())

    ; Normal commands
    for index, command in manageCommandState("commands", "get") {

        ; Check if command has tags
        hasTags := command.HasProp("tags") && command.tags && command.tags.Length > 0

        ; If command has a directAccelerator, add a top-level shortcut
        if command.HasProp("directAccelerator") && command.directAccelerator {
            commandMenu.Add(command.directAccelerator . " - " . command.commandName, commandMenuHandler.Bind(index))
        }

        ; If no tags, add directly to menu and continue
        if !hasTags {
            commandMenu.Add(command.menuText, commandMenuHandler.Bind(index))
            continue
        }

        ; Process tags
        for tag in command.tags {
            normalizedTag := StrLower(Trim(tag))

            ; Create tag menu if doesn't exist
            if !tagsMap.Has(normalizedTag) {
                tagsMap[normalizedTag] := { menu: Menu(), displayName: tag }
                commandMenu.Add(tag, tagsMap[normalizedTag].menu)
            }

            ; Add command to tag menu
            tagsMap[normalizedTag].menu.Add(command.menuText, commandMenuHandler.Bind(index))
        }
    }

    ; Line separator before Options
    commandMenu.Add()

    ; Options menu — built dynamically from UserConfig.ahk
    commandMenu.Add("&Options", optionsMenu := Menu())
    for _, item in optionsMenuItems {
        optionsMenu.Add(item.menuText, runOptionsMenuAction.Bind(item.command))
    }
    commandMenu.Show()
}

; ----------------------------------------------------
; Command menu handler function
; ----------------------------------------------------

commandMenuHandler(index, *) {
    commandsList := manageCommandState("commands", "get")
    selectedCommand := commandsList[index]
    if (selectedCommand.HasProp("isCustomCommand") && selectedCommand.isCustomCommand) {

        ; Save the command for future reference in customCommandSendButtonAction(*)
        manageCommandState("selectedCommand", "set", selectedCommand)

        ; Set skipConfirmation property based on the command
        customCommandInputWindow.setSkipConfirmation(selectedCommand.HasProp("skipConfirmation") ? selectedCommand.skipConfirmation : false)

        customCommandInputWindow.showInputWindow(selectedCommand.HasProp("customInputInitialMessage")
            ? selectedCommand.customInputInitialMessage : unset, selectedCommand.commandName, "ahk_id " customCommandInputWindow
        .guiObj.hWnd)
    } else {
    processInitialRequest(selectedCommand.commandName, selectedCommand.menuText, selectedCommand.systemMessage,
        selectedCommand.APIModels,
        selectedCommand.HasProp("copyAsMarkdown") && selectedCommand.copyAsMarkdown,
        selectedCommand.HasProp("pasteMode") ? selectedCommand.pasteMode : "chat",
        selectedCommand.HasProp("skipConfirmation") && selectedCommand.skipConfirmation,
        selectedCommand.HasProp("isFIM") && selectedCommand.isFIM,
        "",  ; customInputMessage (not applicable for non-custom commands)
        selectedCommand.HasProp("temperature") ? selectedCommand.temperature : "",
        selectedCommand.HasProp("maxTokens") ? selectedCommand.maxTokens : "",
        selectedCommand.HasProp("stop") ? selectedCommand.stop : "",
        selectedCommand.HasProp("stream") && selectedCommand.stream,
        selectedCommand.HasProp("thinking") && selectedCommand.thinking ? selectedCommand.thinking["type"] : "")
    }
}

; ----------------------------------------------------
; "&1 - Open Chat" handler — restores or spawns the persistent chat window
; ----------------------------------------------------

OpenChatCommandHandler(*) {
    ; Open or restore the persistent chat window at the last active thread
    OpenOrSpawnChatWindow()
}