; ----------------------------------------------------
; RequestProcessor — Command-triggered LLM request orchestrator
;
; Entry point for any command-triggered LLM request.
; Delegates clipboard capture to TextCapture and
; inline cURL execution to InlineRequestRunner.
; Chat mode routes through the persistent ChatWindow.
; ----------------------------------------------------

; debugLog() is in lib/DebugLog.ahk — included via Config.ahk

processInitialRequest(commandName, menuText, systemMessage, APIModels, pasteMode, isFIM,
    inputText := "", temperature := "", maxTokens := "", stop := "", stream := false, thinking := "", thinkingLevel := "", userMessageTemplate := "", expandNewlines := false, maxContextWords := 0, includeImageContext := false, preselectedScreenshotArea := false) {
    debugLog("processInitialRequest: " commandName " stream=" stream " pasteMode=" pasteMode, "RequestProcessor")

    ; Determine if fullText is needed (lazy — avoid capturing 1M-word docs unnecessarily)
    includeFullText := InStr(systemMessage, "{{fullText}}") || InStr(userMessageTemplate, "{{fullText}}")

    ; Prepare the chat before capturing selection/input. Text capture can take
    ; a noticeable amount of time when it falls back through clipboard APIs;
    ; opening the new thread first makes that work invisible behind the new
    ; chat instead of leaving the previous chat on screen.
    commandThreadId := ""
    if pasteMode = "chat" {
        commandThreadId := ChatDB.Thread_Create(commandName)
        ; Hide the old chat immediately, but defer loading/showing the new
        ; thread until its system/user messages are ready. This prevents a
        ; blank new chat from appearing while capture is still in progress.
        prepareChatWindow()
        beginChatOpeningIndicator()
    }

    ; STEP 1: Capture text only when the command actually needs text from the
    ; foreground application. Prompt-only commands such as Screenshot already
    ; have their user input, so running the clipboard fallback here can waste up
    ; to three seconds trying Ctrl+C / Ctrl+Insert when nothing is selected.
    needsSelectionCapture := isFIM
        || inputText = ""
        || includeFullText
        || InStr(systemMessage, "{{selection}}")
        || InStr(userMessageTemplate, "{{selection}}")

    if needsSelectionCapture
        captured := TextCapture.Capture(isFIM, pasteMode, inputText, includeFullText, expandNewlines, maxContextWords)
    else
        captured := { success: true, userMessage: "", fullText: "", modelsStr: "", isFIM: false }
    if !captured.success {
        if commandThreadId
            ChatDB.Thread_Delete(commandThreadId)
        if commandThreadId
            endChatOpeningIndicator()
        updateLoadingUI("Reset")
        MsgBox captured.error, (isFIM ? "FIM" : "No text copied"), "IconX"
        return
    }

    ; Expand templates in system message (FIM has no user message — skip)
    if systemMessage && !isFIM
        systemMessage := TextCapture.ExpandTemplate(systemMessage, captured.userMessage, captured.fullText, inputText)

    ; Compose user message from template (explicit only — no default).
    ; FIM captures return {prefix, suffix} without userMessage — skip.
    if !isFIM {
        if userMessageTemplate
            captured.userMessage := TextCapture.ExpandTemplate(userMessageTemplate, captured.userMessage, captured.fullText, inputText)
        else if inputText
            captured.userMessage := inputText
        else
            captured.userMessage := captured.userMessage
    }

    ; Parse models — multiple models are collapsed to the first as a safety net
    APIModelsArr := StrSplit(RegExReplace(APIModels, "\s+", ""), ",")
    ; Bug #162: the command dropdown's "Default" option stores an EMPTY
    ; APIModels string. StrSplit("") returns an empty array, so the request
    ; loop below never ran and the command was a silent no-op. Substitute the
    ; app default model - the dropdown's documented behavior.
    if APIModelsArr.Length = 0 || (APIModelsArr.Length = 1 && APIModelsArr[1] = "")
        APIModelsArr := [appDefaultModel]
    if APIModelsArr.Length > 1 {
        if isFIM {
            MsgBox "FIM does not support multiple models. Only the first model will be used.", "FIM Warning", "IconX"
        }
        APIModelsArr := [APIModelsArr[1]]
    }

    ; STEP 1.5: Screenshot capture for includeImageContext
    if includeImageContext {
        ; Vision gate: check model supports images
        if !AttachmentUtils.HasVision(APIModelsArr[1]) {
            if commandThreadId {
                ChatDB.Thread_Delete(commandThreadId)
                endChatOpeningIndicator()
                openChatWindow()
            }
            ToolTip("This model does not support images", , , 19)
            SetTimer(() => ToolTip(, , , 19), -3000)
            return
        }
        captureMsgId := ChatDB._UUID()
        screenshotArea := preselectedScreenshotArea ? preselectedScreenshotArea : ScreenRegionSelector.Select()
        if !screenshotArea {
            if commandThreadId {
                ChatDB.Thread_Delete(commandThreadId)
                endChatOpeningIndicator()
                openChatWindow()
            }
            updateLoadingUI("Reset")
            return
        }

        ; Give Windows a moment to repaint after the selection overlay closes.
        Sleep 30
        screenshotPath := ImageUtils.CaptureRegion(captureMsgId, screenshotArea)
        if !screenshotPath {
            if commandThreadId {
                ChatDB.Thread_Delete(commandThreadId)
                endChatOpeningIndicator()
                openChatWindow()
            }
            updateLoadingUI("Reset")
            ToolTip("Screenshot capture failed", , , 19)
            SetTimer(() => ToolTip(, , , 19), -3000)
            return
        }
    }

    ; STEP 2: Build request and execute
    for i, fullAPIModelName in APIModelsArr {
        providerInfo := ProviderResolver.Resolve(fullAPIModelName)
        providerName := providerInfo.providerKey
        singleAPIModelName := providerInfo.modelName

        if pasteMode = "chat" {
            threadId := commandThreadId ? commandThreadId : ChatDB.Thread_Create(commandName)
            if systemMessage {
                ChatDB.Msg_Insert({
                    thread_id: threadId, role: "system",
                    content: systemMessage, parent_id: ""
                })
            }
            userMsgId := ""
            if captured.HasOwnProp("userMessage") && captured.userMessage {
                path := ChatDB.Msg_GetActivePath(threadId)
                parentId := path.Length ? path[path.Length].id : ""
                userMsgId := ChatDB.Msg_Insert({
                    thread_id: threadId, role: "user",
                    content: captured.userMessage, parent_id: parentId
                })
            } else if includeImageContext && screenshotPath {
                ; No user message text, but we have a screenshot — insert empty user message
                path := ChatDB.Msg_GetActivePath(threadId)
                parentId := path.Length ? path[path.Length].id : ""
                userMsgId := ChatDB.Msg_Insert({
                    thread_id: threadId, role: "user",
                    content: "Describe this screenshot.", parent_id: parentId
                })
            }

            ; Attach screenshot to user message
            if includeImageContext && screenshotPath && userMsgId {
                fullPath := AppInfo.DataDir "\" screenshotPath
                fileSize := FileExist(fullPath) ? FileGetSize(fullPath) : 0
                ChatDB.Attachment_Insert(userMsgId, {
                    attachment_type: "image",
                    file_path: screenshotPath,
                    mime_type: "image/png",
                    original_filename: "screenshot.png",
                    file_size: fileSize,
                    extracted_text: ""
                })
            }

            commandThreadSettings := {
                assistantId: "",
                systemOverride: systemMessage,
                reasoningOverride: thinking = "enabled" ? (thinkingLevel != "" ? thinkingLevel : "medium") : thinking,
                temperatureOverride: temperature
            }
            ; Bug #36: temperature/reasoning overrides must persist even when the
            ; command model equals the app default - only modelOverride is
            ; redundant in that case (the thread then uses the default model).
            if fullAPIModelName != appDefaultModel
                commandThreadSettings.modelOverride := fullAPIModelName
            ChatDB.Thread_UpdateSettings(threadId, commandThreadSettings)

            ; Show only after the system/user messages have been inserted, so
            ; the first visible frame is already the populated new chat.
            openChatWindow(threadId, true)
            ; Bug #203: the command's Stream Response toggle must reach the
            ; chat process - notifyTriggerLLM carries it in the WM wParam.
            SetTimer(() => CustomMessages.notifyTriggerLLM(chatWindowhWnd, stream), -100)
            break
        } else {
            InlineRequestRunner.Run(commandName, fullAPIModelName, providerName, singleAPIModelName,
                captured, isFIM, systemMessage, pasteMode, temperature, maxTokens, stop, stream, thinking, thinkingLevel)
        }
    }
}

; Options menu action.
; If HTTP URLs open then immediately close: check uBlock Origin Lite →
;   Settings → uncheck "Enable pop-up blocking" (closes externally-launched tabs).
runOptionsMenuAction(command, *) {
    if command = "apilogs:" {
        ShowApiLogs()
        return
    }
    if command = "usage:" {
        ShowUsageDashboard()
        return
    }
    if command = "settings:" {
        ShowSettingsPanel()
        return
    }
    if (spacePos := InStr(command, " ")) {
        firstWord := SubStr(command, 1, spacePos - 1)
        if !InStr(firstWord, "\") && !InStr(firstWord, ":") {
            Run(command)
            return
        }
    }
    if (InStr(command, ":") || InStr(command, "\")) {
        if !FileExist(command) && !InStr(command, "http") {
            ToolTip("No logs written yet — file hasn't been created", , , 19)
            SetTimer () => ToolTip(, , , 19), -3000
            return
        }
    }
    Run(command)
}
