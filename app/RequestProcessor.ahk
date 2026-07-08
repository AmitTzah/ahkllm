; ----------------------------------------------------
; RequestProcessor — Command-triggered LLM request orchestrator
;
; Entry point for any command-triggered LLM request.
; Delegates clipboard capture to ClipboardCapture and
; inline cURL execution to InlineRequestRunner.
; Chat mode routes through the persistent ChatWindow.
; ----------------------------------------------------

; debugLog() is in lib/DebugLog.ahk — included via Config.ahk

processInitialRequest(commandName, menuText, systemMessage, APIModels, copyAsMarkdown, pasteMode, skipConfirmation, isFIM,
    customInputMessage := "", temperature := "", maxTokens := "", stop := "", stream := false, thinking := "") {
    debugLog("processInitialRequest: " commandName " stream=" stream " pasteMode=" pasteMode, "RequestProcessor")

    ; STEP 1: Capture text
    captured := ClipboardCapture.Capture(isFIM, pasteMode, customInputMessage)
    if !captured.success {
        updateLoadingUI("Reset")
        MsgBox captured.error, (isFIM ? "FIM" : "No text copied"), "IconX"
        return
    }

    ; Parse models
    APIModelsArr := StrSplit(RegExReplace(APIModels, "\s+", ""), ",")
    if isFIM {
        if APIModelsArr.Length > 1
            MsgBox "FIM does not support multiple models. Only the first model will be used.", "FIM Warning", "IconX"
        APIModelsArr := [APIModelsArr[1]]
    } else if pasteMode = "replace" || pasteMode = "append" {
        pasteMode := (APIModelsArr.Length > 1) ? "chat" : pasteMode
    }

    ; STEP 2: Build request and execute
    for i, fullAPIModelName in APIModelsArr {
        providerInfo := ProviderResolver.Resolve(fullAPIModelName)
        providerName := providerInfo.providerKey
        singleAPIModelName := providerInfo.modelName

        if pasteMode = "chat" {
            if APIModelsArr.Length > 1 {
                debugLog("WARNING: Multi-model not supported in chat mode. Using only first model: " APIModelsArr[1], "RequestProcessor")
            }

            threadId := ChatDB.Thread_Create(commandName)
            if systemMessage {
                ChatDB.Msg_Insert({
                    thread_id: threadId, role: "system",
                    content: systemMessage, parent_id: ""
                })
            }
            if captured.HasOwnProp("userMessage") && captured.userMessage {
                path := ChatDB.Msg_GetActivePath(threadId)
                parentId := path.Length ? path[path.Length].id : ""
                ChatDB.Msg_Insert({
                    thread_id: threadId, role: "user",
                    content: captured.userMessage, parent_id: parentId
                })
            }

            if fullAPIModelName != chatDefaultModel {
                ChatDB.Thread_UpdateSettings(threadId, {
                    modelOverride: fullAPIModelName,
                    assistantId: "",
                    systemOverride: "",
                    reasoningOverride: "",
                    temperatureOverride: ""
                })
            }

            openChatWindow(threadId)
            SetTimer(() => CustomMessages.notifyTriggerLLM(chatWindowhWnd), -100)
            break
        } else {
            InlineRequestRunner.Run(commandName, fullAPIModelName, providerName, singleAPIModelName,
                captured, isFIM, systemMessage, pasteMode, temperature, maxTokens, stop, stream, thinking)
        }
    }
}

; Options menu action
runOptionsMenuAction(command, *) {
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
