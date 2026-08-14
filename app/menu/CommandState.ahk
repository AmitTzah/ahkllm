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
    ; Bug #228: same guards as onCommandSelected - the command's API Model can
    ; be "Default" (empty APIModels) and Title/Label can be cleared, so never
    ; read these keys unguarded (an empty/missing value must fall through to
    ; processInitialRequest's #162 default-model substitution, not throw).
    processInitialRequest(
        cmd.HasProp("commandName") ? cmd.commandName : "",
        cmd.HasProp("menuText") ? cmd.menuText : "",
        _resolveSystemMessage(cmd),
        cmd.HasProp("APIModels") ? cmd.APIModels : "",
        params*)
    commandInputWindow.EditControl.Value := ""
}
