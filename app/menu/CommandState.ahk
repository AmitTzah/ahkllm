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
    params := _extractCommandParams(cmd, commandInputWindow.EditControl.Value)
    processInitialRequest(cmd.commandName, cmd.menuText, _resolveSystemMessage(cmd),
        cmd.APIModels, params*)
    commandInputWindow.EditControl.Value := ""
}
