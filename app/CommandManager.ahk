; ----------------------------------------------------
; Manage command states
; ----------------------------------------------------

manageCommandState(component, action, data := {}) {
    static state := {
        commands: commands,
        selectedCommand: {}
    }

    switch component {
        case "commands":
            switch action {
                case "get": return state.commands
                case "set": state.commands := data
            }

        case "selectedCommand":
            switch action {
                case "get": return state.selectedCommand
                case "set": state.selectedCommand := data
            }

    }
}

; Custom command send action
customCommandSendButtonAction(*) {
    if !customCommandInputWindow.validateInputAndHide() {
        return
    }

    selectedCommand := manageCommandState("selectedCommand", "get")
    processInitialRequest(selectedCommand.commandName, selectedCommand.menuText, selectedCommand.systemPrompt,
        selectedCommand.APIModels,
        selectedCommand.HasProp("copyAsMarkdown") && selectedCommand.copyAsMarkdown,
        selectedCommand.HasProp("pasteMode") ? selectedCommand.pasteMode : "chat",
        selectedCommand.HasProp("skipConfirmation") && selectedCommand.skipConfirmation,
        selectedCommand.HasProp("isFIM") && selectedCommand.isFIM,
        customCommandInputWindow.EditControl.Value,
        selectedCommand.HasProp("temperature") ? selectedCommand.temperature : "",
        selectedCommand.HasProp("maxTokens") ? selectedCommand.maxTokens : "",
        selectedCommand.HasProp("stop") ? selectedCommand.stop : "",
        selectedCommand.HasProp("stream") && selectedCommand.stream,
        selectedCommand.HasProp("thinking") && selectedCommand.thinking ? selectedCommand.thinking["type"] : ""
    )
    customCommandInputWindow.EditControl.Value := ""
}