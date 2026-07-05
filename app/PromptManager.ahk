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
        selectedPrompt.HasProp("stop") ? selectedPrompt.stop : "",
        selectedPrompt.HasProp("stream") && selectedPrompt.stream,
        selectedPrompt.HasProp("thinking") && selectedPrompt.thinking ? selectedPrompt.thinking["type"] : ""
    )
    customPromptInputWindow.EditControl.Value := ""
}