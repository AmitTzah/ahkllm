; ----------------------------------------------------
; Manage prompt states
; ----------------------------------------------------

managePromptState(component, action, data := {}) {
    static state := {
        prompts: prompts,
        selectedPrompt: {},
        selectedPromptForMessage: {}
    }

    switch component {
        case "prompts":
            switch action {
                case "get": return state.prompts
                case "set": state.prompts := data
            }

        case "selectedPrompt":
            switch action {
                case "get": return state.selectedPrompt
                case "set": state.selectedPrompt := data
            }

        case "selectedPromptForMessage":
            switch action {
                case "get": return state.selectedPromptForMessage
                case "set": state.selectedPromptForMessage := data
            }
    }
}

; Generic function to perform an operation on prompt windows
;
; Parameters:
; - operation (activate, minimize, close): The operation to perform
; - promptName: Optional. If provided, only windows for this prompt will be affected
managePromptWindows(operation, promptName := "", *) {

    ; Create a list of window handles that match our criteria
    hWndsToManage := []

    ; Iterate through all active models
    for uniqueID, modelData in getActiveModels() {
        if (promptName = "All" || modelData.promptName = promptName) {
            hWndsToManage.Push(modelData.hWnd)
        }
    }

    ; Perform the requested operation on each window
    for _, hWnd in hWndsToManage {
        switch operation {
            case "activate": WinActivate("ahk_id " hWnd)
            case "minimize": WinMinimize("ahk_id " hWnd)
            case "close": WinClose("ahk_id " hWnd)
        }
    }
}

; Handle "Send message to prompt" from the menu
sendToPromptGroupHandler(promptName, *) {
    promptsList := managePromptState("prompts", "get")

    ; Find the prompt with the matching promptName
    for _, prompt in promptsList {
        ; Check if the prompt has the same name as the one we're looking for
        if (prompt.promptName = promptName) {
            selectedPrompt := prompt
            break
        }
    }

    managePromptState("selectedPromptForMessage", "set", promptName)

    ; Check if the prompt has skipConfirmation property and set accordingly
    sendToPromptNameInputWindow.setSkipConfirmation(selectedPrompt.HasProp("skipConfirmation") ? selectedPrompt.skipConfirmation : false)
    sendToPromptNameInputWindow.showInputWindow(, "Send message to " promptName, "ahk_id " sendToPromptNameInputWindow.guiObj
        .hWnd
    )
}

; Input window actions for sending
sendToGroupSendButtonAction(*) {
    if (getActiveModels().Count = 0) {
        MsgBox "No Response Windows found. Message not sent.", "Send message to all models", "IconX"
        sendToAllModelsInputWindow.guiObj.Hide
        return
    }

    if !sendToPromptNameInputWindow.validateInputAndHide() {
        return
    }

    if (!targetPromptName := managePromptState("selectedPromptForMessage", "get")) {
        return
    }

    ; Send message only to active models that belong to this prompt
    for uniqueID, modelData in getActiveModels() {

        ; Check if this model belongs to the selected prompt
        if (modelData.promptName != targetPromptName) {
            continue
        }

        JSONStr := FileOpen(modelData.JSONFile, "r", "UTF-8").Read()
        router.appendToChatHistory("user", sendToPromptNameInputWindow.EditControl.Value, &JSONStr, modelData.JSONFile)

        ; Notify the Response Window to re-read the JSON file and call sendRequestToLLM() again
        responseWindowhWnd := modelData.hWnd
        CustomMessages.notifyResponseWindowState(CustomMessages.WM_SEND_TO_ALL_MODELS, uniqueID, responseWindowhWnd)
    }

    sendToPromptNameInputWindow.EditControl.Value := ""
}

sendToAllModelsSendButtonAction(*) {
    if (getActiveModels().Count = 0) {
        MsgBox "No Response Windows found. Message not sent.", "Send message to all models", "IconX"
        sendToAllModelsInputWindow.guiObj.Hide
        return
    }

    if !sendToAllModelsInputWindow.validateInputAndHide() {
        return
    }

    ; The main script must know each Response Window's JSON file
    ; so it can read it, parse it, append the new
    ; user message, then write it back
    for uniqueID, modelData in getActiveModels() {
        JSONStr := FileOpen(modelData.JSONFile, "r", "UTF-8").Read()
        router.appendToChatHistory("user", sendToAllModelsInputWindow.EditControl.Value, &JSONStr, modelData.JSONFile)

        ; Notify the Response Window to re-read the JSON file and call sendRequestToLLM() again
        responseWindowhWnd := modelData.hWnd
        CustomMessages.notifyResponseWindowState(CustomMessages.WM_SEND_TO_ALL_MODELS, uniqueID, responseWindowhWnd
        )
    }
}

; Custom prompt send action
customPromptSendButtonAction(*) {
    if !customPromptInputWindow.validateInputAndHide() {
        return
    }

    selectedPrompt := managePromptState("selectedPrompt", "get")
    processInitialRequest(selectedPrompt.promptName, selectedPrompt.menuText, selectedPrompt.systemPrompt,
        selectedPrompt.APIModels,
        selectedPrompt.HasProp("copyAsMarkdown") && selectedPrompt.copyAsMarkdown,
        selectedPrompt.HasProp("pasteMode") ? selectedPrompt.pasteMode : "chat",
        selectedPrompt.HasProp("skipConfirmation") && selectedPrompt.skipConfirmation,
        selectedPrompt.HasProp("isFIM") && selectedPrompt.isFIM,
        customPromptInputWindow.EditControl.Value,
        selectedPrompt.HasProp("temperature") ? selectedPrompt.temperature : "",
        selectedPrompt.HasProp("maxTokens") ? selectedPrompt.maxTokens : "",
        selectedPrompt.HasProp("stop") ? selectedPrompt.stop : ""
    )
    customPromptInputWindow.EditControl.Value := ""
}