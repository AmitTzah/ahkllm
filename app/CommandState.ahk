; ----------------------------------------------------
; Manage command states
; ----------------------------------------------------

; Currently selected command (set by onCommandSelected, read by onCommandInputSend)
global selectedCommand := {}

setSelectedCommand(cmd) {
    global selectedCommand
    selectedCommand := cmd
}

; Custom command send action
onCommandInputSend(*) {
    if !commandInputWindow.validateInputAndHide()
        return

    cmd := selectedCommand
    processInitialRequest(cmd.commandName, cmd.menuText, cmd.systemMessage,
        cmd.APIModels,
        cmd.HasProp("copyAsMarkdown") && cmd.copyAsMarkdown,
        cmd.HasProp("pasteMode") ? cmd.pasteMode : "chat",
        cmd.HasProp("skipConfirmation") && cmd.skipConfirmation,
        cmd.HasProp("isFIM") && cmd.isFIM,
        commandInputWindow.EditControl.Value,
        cmd.HasProp("temperature") ? cmd.temperature : "",
        cmd.HasProp("maxTokens") ? cmd.maxTokens : "",
        cmd.HasProp("stop") ? cmd.stop : "",
        cmd.HasProp("stream") && cmd.stream,
        cmd.HasProp("thinking") && cmd.thinking ? cmd.thinking["type"] : ""
    )
    commandInputWindow.EditControl.Value := ""
}
