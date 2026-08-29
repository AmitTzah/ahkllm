; ----------------------------------------------------
; Command menu building
; ----------------------------------------------------

#Include ..\..\shared\SystemMessageResolver.ahk

; Return command indexes in the saved order for a group, then append any
; commands missing from an older/corrupt order. AHK arrays are one-based;
; commandGroupOrders is populated by SettingsApply from the UI's saved order.
_CommandIndexesForGroup(tag) {
    global commands, commandGroupOrders
    result := []
    seen := Map()
    if IsSet(commandGroupOrders) && IsObject(commandGroupOrders) && commandGroupOrders.Has(tag) {
        for _, index in commandGroupOrders[tag] {
            if index >= 1 && index <= commands.Length && !seen.Has(index) && _CommandBelongsToGroup(commands[index], tag) {
                result.Push(index)
                seen[index] := true
            }
        }
    }
    for index, command in commands {
        if !seen.Has(index) && _CommandBelongsToGroup(command, tag) {
            result.Push(index)
            seen[index] := true
        }
    }
    return result
}

_CommandBelongsToGroup(command, tag) {
    hasTags := command.HasProp("tags") && command.tags && command.tags.Length > 0
    if tag = "__main__"
        return !hasTags || (command.HasProp("directAccelerator") && command.directAccelerator)
    if !hasTags
        return false
    for commandTag in command.tags {
        if StrLower(Trim(commandTag)) = StrLower(Trim(tag))
            return true
    }
    return false
}

_OrderTaggedCommands(tagInfo) {
    global commandGroupOrders
    if !IsSet(commandGroupOrders) || !IsObject(commandGroupOrders) || !commandGroupOrders.Has(tagInfo.displayName)
        return
    original := tagInfo.commands
    ordered := []
    seen := Map()
    for _, index in commandGroupOrders[tagInfo.displayName] {
        for _, item in original {
            if item.index = index && !seen.Has(index) {
                ordered.Push(item)
                seen[index] := true
                break
            }
        }
    }
    for _, item in original {
        if !seen.Has(item.index) {
            ordered.Push(item)
            seen[item.index] := true
        }
    }
    tagInfo.commands := ordered
}

buildCommandMenu() {
    commandMenu := Menu()
    tagsMap := Map()
    tagOrder := []    ; tracks first-seen order for tags not in submenuOrder

    ; Show "Open Chat" shortcut if configured
    if IsSet(chatShortcut) && chatShortcut != ""
        commandMenu.Add("&" chatShortcut " - Open Chat", (*) => OpenChatCommandHandler())

    ; First pass: add Main Menu commands in its saved order. Tagged commands
    ; are collected below so their own group order can remain independent.
    for _, index in _CommandIndexesForGroup("__main__") {
        command := commands[index]
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
        }
    }

    ; Collect every tagged command in the global order as the fallback for
    ; groups without saved metadata, and to determine first-seen tag order.
    for index, command in commands {
        hasTags := command.HasProp("tags") && command.tags && command.tags.Length > 0
        if !hasTags
            continue
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
        _OrderTaggedCommands(tagInfo)
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

_CommandPrimaryModel(cmd) {
    global appDefaultModel
    modelText := cmd.HasProp("APIModels") ? Trim(cmd.APIModels) : ""
    if !modelText
        return appDefaultModel
    models := StrSplit(RegExReplace(modelText, "\\s+", ""), ",")
    return models.Length ? models[1] : appDefaultModel
}

_CaptureCommandScreenshot(cmd) {
    pasteMode := cmd.HasProp("pasteMode") ? cmd.pasteMode : "chat"
    if pasteMode != "chat" {
        ToolTip("Attach Screenshot requires Paste Mode: chat", , , 19)
        SetTimer(() => ToolTip(, , , 19), -3000)
        return ""
    }
    if cmd.HasProp("isFIM") && cmd.isFIM {
        ToolTip("Attach Screenshot cannot be used with FIM Mode", , , 19)
        SetTimer(() => ToolTip(, , , 19), -3000)
        return ""
    }

    model := _CommandPrimaryModel(cmd)
    if !AttachmentUtils.HasVision(model) {
        ToolTip("This model does not support images", , , 19)
        SetTimer(() => ToolTip(, , , 19), -3000)
        return ""
    }

    area := ScreenRegionSelector.Select()
    if !area
        return ""

    ; Let the selection overlay disappear before copying screen pixels.
    Sleep 30
    screenshotPath := ImageUtils.CaptureRegion(ChatDB._UUID(), area)
    if !screenshotPath {
        ToolTip("Screenshot capture failed", , , 19)
        SetTimer(() => ToolTip(, , , 19), -3000)
    }
    return screenshotPath
}

onCommandSelected(index, *) {
    cmd := commands[index]
    showInput := cmd.HasProp("showInputBox") && cmd.showInputBox

    if showInput {
        screenshotPath := ""
        if cmd.HasProp("includeImageContext") && cmd.includeImageContext {
            ; Capture now rather than after the user types. The input window can
            ; preview the exact PNG that will later be attached, and screen
            ; contents cannot change between preview and send.
            screenshotPath := _CaptureCommandScreenshot(cmd)
            if !screenshotPath
                return
        }

        ; Save the command and any pre-captured screenshot for onCommandInputSend.
        setSelectedCommand(cmd, screenshotPath)

        inputDefault := cmd.HasProp("inputBoxDefault") ? cmd.inputBoxDefault : ""
        previewPath := screenshotPath ? AppInfo.DataDir "\" screenshotPath : ""
        commandInputWindow.showInputWindow(inputDefault, cmd.commandName,
            "ahk_id " commandInputWindow.guiObj.hWnd, previewPath)
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
