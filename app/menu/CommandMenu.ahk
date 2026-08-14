; ----------------------------------------------------
; Command menu building
; ----------------------------------------------------

#Include ..\..\shared\SystemMessageResolver.ahk

buildCommandMenu() {
    commandMenu := Menu()
    tagsMap := Map()
    tagOrder := []    ; tracks first-seen order for tags not in submenuOrder

    ; Show "Open Chat" shortcut if configured
    if IsSet(chatShortcut) && chatShortcut != ""
        commandMenu.Add("&" chatShortcut " - Open Chat", (*) => OpenChatCommandHandler())

    ; First pass: collect all commands by tag, build tagsMap
    for index, command in commands {
        hasTags := command.HasProp("tags") && command.tags && command.tags.Length > 0

        ; If command has a directAccelerator, add a top-level shortcut
        if command.HasProp("directAccelerator") && command.directAccelerator {
            ; Bug #228: settings can clear the Command Title - the runtime
            ; command then carries commandName="" (or, for legacy/crafted
            ; settings, may lack the property entirely). Never index it
            ; unguarded or the whole menu build throws.
            cmdName := command.HasProp("commandName") ? command.commandName : ""
            commandMenu.Add(command.directAccelerator . " - " . cmdName, onCommandSelected.Bind(index))
        }

        ; If no tags, add directly to menu and continue
        if !hasTags {
            commandMenu.Add(command.HasProp("menuText") ? command.menuText : "", onCommandSelected.Bind(index))
            continue
        }

        for tag in command.tags {
            normalizedTag := StrLower(Trim(tag))

            if !tagsMap.Has(normalizedTag) {
                tagsMap[normalizedTag] := { menu: Menu(), displayName: tag, commands: [] }
                tagOrder.Push(normalizedTag)
            }
            tagsMap[normalizedTag].commands.Push({menuText: command.menuText, index: index})
        }
    }

    ; Second pass: determine submenu order — submenuOrder first, then remaining by first appearance
    orderedTags := []
    seenTags := Map()
    if IsSet(submenuOrder) {
        for tag in submenuOrder {
            normalizedTag := StrLower(Trim(tag))
            if tagsMap.Has(normalizedTag) && !seenTags.Has(normalizedTag) {
                orderedTags.Push(normalizedTag)
                seenTags[normalizedTag] := true
            }
        }
    }
    ; Append remaining tags in command-appearance order
    for normalizedTag in tagOrder {
        if !seenTags.Has(normalizedTag) {
            orderedTags.Push(normalizedTag)
            seenTags[normalizedTag] := true
        }
    }

    ; Third pass: add submenus and populate them
    for normalizedTag in orderedTags {
        tagInfo := tagsMap[normalizedTag]
        commandMenu.Add(tagInfo.displayName, tagInfo.menu)
        for cmd in tagInfo.commands {
            tagInfo.menu.Add(cmd.HasProp("menuText") ? cmd.menuText : "", onCommandSelected.Bind(cmd.index))
        }
    }

    ; Line separator before Quick Access
    commandMenu.Add()

    ; Quick Access menu — built dynamically from UserConfig.ahk
    commandMenu.Add("&Quick Access", optionsMenu := Menu())
    for _, item in quickAccessMenuItems {
        optionsMenu.Add(item.menuText, runOptionsMenuAction.Bind(item.command))
    }
    commandMenu.Show()
}

; ----------------------------------------------------
; Command menu handler functions
; ----------------------------------------------------

; Resolve systemMessage: if cmd has systemMessageFile, read the file;
; otherwise use cmd.systemMessage (inline text). Returns the message string.
_resolveSystemMessage(cmd) {
    ; Single resolver shared with the assistant path (bug #50 family).
    res := SystemMessageResolver.Resolve(cmd)
    if res.error != ""
        MsgBox("Failed to read system message file:`n" res.error,
            "System Message Error", "IconX")
    return res.text
}

; Extract optional command properties shared by onCommandSelected and onCommandInputSend.
; Returns a flat array for splatting into processInitialRequest after the first 4 required params.
; cmd.thinking may be a plain object or an AHK Map after a settings.json round-trip.
; Map entries are not own properties: HasOwnProp("type") is false for a Map (only
; Has() works), while Has("type") is false for a plain object — check the shape.
_thinkingHas(cmd, key) {
    if !cmd.HasProp("thinking") || !cmd.thinking
        return false
    if Type(cmd.thinking) = "Map"
        return cmd.thinking.Has(key)
    return cmd.thinking.HasOwnProp(key)
}
_extractCommandParams(cmd, inputText := "") {
    return [
        cmd.HasProp("pasteMode") ? cmd.pasteMode : "chat",
        cmd.HasProp("isFIM") && cmd.isFIM,
        inputText,
        cmd.HasProp("temperature") ? cmd.temperature : "",
        cmd.HasProp("maxTokens") ? cmd.maxTokens : "",
        cmd.HasProp("stop") ? cmd.stop : "",
        cmd.HasProp("stream") && cmd.stream,
        _thinkingHas(cmd, "type") ? (Type(cmd.thinking) = "Map" ? cmd.thinking["type"] : cmd.thinking.type) : "",
        _thinkingHas(cmd, "level") ? (Type(cmd.thinking) = "Map" ? cmd.thinking["level"] : cmd.thinking.level) : "",
        cmd.HasProp("userMessage") ? cmd.userMessage : "",
        cmd.HasProp("expandNewlines") && cmd.expandNewlines,
        cmd.HasProp("maxContextWords") ? cmd.maxContextWords : 0,
        cmd.HasProp("includeImageContext") && cmd.includeImageContext
    ]
}

onCommandSelected(index, *) {
    cmd := commands[index]
    showInput := cmd.HasProp("showInputBox") && cmd.showInputBox

    if showInput {
        ; Save the command for future reference in onCommandInputSend
        setSelectedCommand(cmd)

        inputDefault := cmd.HasProp("inputBoxDefault") ? cmd.inputBoxDefault : ""
        commandInputWindow.showInputWindow(inputDefault, cmd.commandName,
            "ahk_id " commandInputWindow.guiObj.hWnd)
    } else {
        params := _extractCommandParams(cmd, "")  ; no user input
        ; Bug #228: the command's API Model can be "Default" (empty
        ; APIModels) and the Title/Label can be cleared - guard every direct
        ; read so an empty (or legacy settings file with a missing key) can
        ; never throw inside the menu handler. processInitialRequest then
        ; substitutes the app default model for "" (#162).
        processInitialRequest(
            cmd.HasProp("commandName") ? cmd.commandName : "",
            cmd.HasProp("menuText") ? cmd.menuText : "",
            _resolveSystemMessage(cmd),
            cmd.HasProp("APIModels") ? cmd.APIModels : "",
            params*)
    }
}

; ----------------------------------------------------
; "&1 - Open Chat" handler — restores or spawns the persistent chat window
; ----------------------------------------------------

OpenChatCommandHandler(*) {
    ; Open or restore the persistent chat window at the last active thread
    openChatWindow()
}
