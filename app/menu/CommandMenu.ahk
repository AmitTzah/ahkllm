; ----------------------------------------------------
; Command menu building
; ----------------------------------------------------

buildCommandMenu() {
    commandMenu := Menu()
    tagsMap := Map()
    tagOrder := []    ; tracks first-seen order for tags not in submenuOrder

    ; Always show "&1 - Open Chat" as the first item
    commandMenu.Add("&1 - Open Chat", (*) => OpenChatCommandHandler())

    ; First pass: collect all commands by tag, build tagsMap
    for index, command in commands {
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
            tagInfo.menu.Add(cmd.menuText, onCommandSelected.Bind(cmd.index))
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
    if cmd.HasProp("systemMessageFile") && cmd.systemMessageFile {
        filePath := cmd.systemMessageFile
        if !InStr(filePath, ":") && !InStr(filePath, "\\")
            filePath := A_ScriptDir "\\" filePath
        try {
            return FileRead(filePath, "UTF-8")
        } catch Error as e {
            MsgBox("Failed to read system message file:`n" filePath "`n`n" e.Message,
                "System Message Error", "IconX")
            return cmd.HasProp("systemMessage") ? cmd.systemMessage : ""
        }
    }
    return cmd.HasProp("systemMessage") ? cmd.systemMessage : ""
}

; Extract optional command properties shared by onCommandSelected and onCommandInputSend.
; Returns a flat array for splatting into processInitialRequest after the first 4 required params.
_extractCommandParams(cmd, inputText := "") {
    return [
        cmd.HasProp("pasteMode") ? cmd.pasteMode : "chat",
        cmd.HasProp("isFIM") && cmd.isFIM,
        inputText,
        cmd.HasProp("temperature") ? cmd.temperature : "",
        cmd.HasProp("maxTokens") ? cmd.maxTokens : "",
        cmd.HasProp("stop") ? cmd.stop : "",
        cmd.HasProp("stream") && cmd.stream,
        cmd.HasProp("thinking") && cmd.thinking ? cmd.thinking.type : "",
        cmd.HasProp("thinking") && cmd.thinking && cmd.thinking.HasOwnProp("level") ? cmd.thinking.level : "",
        cmd.HasProp("userMessage") ? cmd.userMessage : "",
        cmd.HasProp("expandNewlines") && cmd.expandNewlines,
        cmd.HasProp("maxContextWords") ? cmd.maxContextWords : 0
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
        processInitialRequest(cmd.commandName, cmd.menuText, _resolveSystemMessage(cmd),
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