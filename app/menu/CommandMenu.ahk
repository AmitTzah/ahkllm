; ----------------------------------------------------
; Command menu building
; ----------------------------------------------------

buildCommandMenu() {
    commandMenu := Menu()
    tagsMap := Map()

    ; Always show "&1 - Open Chat" as the first item
    commandMenu.Add("&1 - Open Chat", (*) => OpenChatCommandHandler())

    ; Normal commands
    for index, command in commands {

        ; Check if command has tags
        hasTags := command.HasProp("tags") && command.tags && command.tags.Length > 0

        ; If command has a directAccelerator, add a top-level shortcut
        if command.HasProp("directAccelerator") && command.directAccelerator {
            commandMenu.Add(command.directAccelerator . " - " . command.commandName, onCommandSelected.Bind(index))
        }

        ; If no tags, add directly to menu and continue
        if !hasTags {
            commandMenu.Add(command.menuText, onCommandSelected.Bind(index))
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
            tagsMap[normalizedTag].menu.Add(command.menuText, onCommandSelected.Bind(index))
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

; Extract optional command properties shared by onCommandSelected and onCommandInputSend.
; Returns a flat array for splatting into processInitialRequest after the first 4 required params.
_extractCommandParams(cmd, customInputMessage := "") {
    return [
        cmd.HasProp("copyAsMarkdown") && cmd.copyAsMarkdown,
        cmd.HasProp("pasteMode") ? cmd.pasteMode : "chat",
        cmd.HasProp("skipConfirmation") && cmd.skipConfirmation,
        cmd.HasProp("isFIM") && cmd.isFIM,
        customInputMessage,
        cmd.HasProp("temperature") ? cmd.temperature : "",
        cmd.HasProp("maxTokens") ? cmd.maxTokens : "",
        cmd.HasProp("stop") ? cmd.stop : "",
        cmd.HasProp("stream") && cmd.stream,
        cmd.HasProp("thinking") && cmd.thinking ? cmd.thinking["type"] : ""
    ]
}

onCommandSelected(index, *) {
    cmd := commands[index]
    if (cmd.HasProp("isCustomCommand") && cmd.isCustomCommand) {

        ; Save the command for future reference in customCommandSendButtonAction(*)
        setSelectedCommand(cmd)

        ; Set skipConfirmation property based on the command
        commandInputWindow.setSkipConfirmation(cmd.HasProp("skipConfirmation") ? cmd.skipConfirmation : false)

        commandInputWindow.showInputWindow(cmd.HasProp("customInputInitialMessage")
            ? cmd.customInputInitialMessage : unset, cmd.commandName, "ahk_id " commandInputWindow
        .guiObj.hWnd)
    } else {
        params := _extractCommandParams(cmd, "")  ; no custom input for non-custom commands
        processInitialRequest(cmd.commandName, cmd.menuText, cmd.systemMessage,
            cmd.APIModels, params*)
    }
}

; ----------------------------------------------------
; "&1 - Open Chat" handler — restores or spawns the persistent chat window
; ----------------------------------------------------

OpenChatCommandHandler(*) {
    ; Open or restore the persistent chat window at the last active thread
    openChatWindow()
}