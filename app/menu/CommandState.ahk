; ----------------------------------------------------
; Manage command states
; ----------------------------------------------------

; Currently selected command (set by onCommandSelected, read by onCommandInputSend)
global selectedCommand := {}
global selectedScreenshotPath := ""

setSelectedCommand(cmd, screenshotPath := "") {
    global selectedCommand, selectedScreenshotPath
    ; A stale pre-captured screenshot has no DB row to own it. Clean it before
    ; replacing the pending command state.
    if selectedScreenshotPath && selectedScreenshotPath != screenshotPath
        ImageUtils.DeleteStoredFile(selectedScreenshotPath)
    selectedCommand := cmd
    selectedScreenshotPath := screenshotPath
}

onCommandInputCancel(*) {
    global selectedCommand, selectedScreenshotPath
    if selectedScreenshotPath
        ImageUtils.DeleteStoredFile(selectedScreenshotPath)
    selectedScreenshotPath := ""
    selectedCommand := {}
}

; Custom command send action
onCommandInputSend(*) {
    global selectedScreenshotPath
    if !commandInputWindow.validateInputAndHide()
        return

    cmd := selectedCommand
    inputText := commandInputWindow.EditControl.Value
    screenshotPath := selectedScreenshotPath
    selectedScreenshotPath := ""
    commandInputWindow.clearPreview()

    params := _extractCommandParams(cmd, inputText)
    params.Push(screenshotPath)
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
