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
    inputText := "", temperature := "", maxTokens := "", stop := "", stream := false, thinking := "", thinkingLevel := "", userMessageTemplate := "", expandNewlines := false, maxContextWords := 0, includeImageContext := false) {
    debugLog("processInitialRequest: " commandName " stream=" stream " pasteMode=" pasteMode, "RequestProcessor")

    ; Determine if fullText is needed (lazy — avoid capturing 1M-word docs unnecessarily)
    includeFullText := InStr(systemMessage, "{{fullText}}") || InStr(userMessageTemplate, "{{fullText}}")

    ; STEP 1: Capture text
    captured := TextCapture.Capture(isFIM, pasteMode, inputText, includeFullText, expandNewlines, maxContextWords)
    if !captured.success {
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
            ToolTip("This model does not support images", , , 19)
            SetTimer(() => ToolTip(, , , 19), -3000)
            return
        }
        captureMsgId := ChatDB._UUID()
        screenshotPath := ImageUtils.CaptureScreen(captureMsgId)
    }

    ; STEP 2: Build request and execute
    for i, fullAPIModelName in APIModelsArr {
        providerInfo := ProviderResolver.Resolve(fullAPIModelName)
        providerName := providerInfo.providerKey
        singleAPIModelName := providerInfo.modelName

        if pasteMode = "chat" {
            threadId := ChatDB.Thread_Create(commandName)
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
                fullPath := A_AppData "\LLM-AutoHotkey-Assistant\" screenshotPath
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

            if fullAPIModelName != appDefaultModel {
                ChatDB.Thread_UpdateSettings(threadId, {
                    modelOverride: fullAPIModelName,
                    assistantId: "",
                    systemOverride: systemMessage,
                    reasoningOverride: thinking = "enabled" ? (thinkingLevel != "" ? thinkingLevel : "medium") : thinking,
                    temperatureOverride: temperature
                })
            }

            openChatWindow(threadId)
            SetTimer(() => CustomMessages.notifyTriggerLLM(chatWindowhWnd), -100)
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
