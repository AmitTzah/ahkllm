; ----------------------------------------------------
; Input Window
; ----------------------------------------------------

global commandInputWindow := ""

class InputWindow {
    __New(windowTitle) {

        ; Create Input Window - uses settings from UserConfig.ahk
        this.guiObj := Gui("Resize", windowTitle)
        this.guiObj.OnEvent("Close", this.closeButtonAction.Bind(this))
        this.guiObj.OnEvent("Escape", this.closeButtonAction.Bind(this))
        this.guiObj.OnEvent("Size", this.resizeAction.Bind(this))
        this.guiObj.SetFont(inputWindowFontSize " " inputWindowFontColor, inputWindowFontFace)
        this.guiObj.BackColor := inputWindowBackground

        ; Screenshot commands can show the exact image that will be attached.
        ; The preview stays hidden for normal commands and uses a bounded size
        ; so a tall capture cannot make the prompt window enormous.
        this.PreviewControl := this.guiObj.Add("Picture", "x20 y10 w180 h110 Hidden")
        this._previewVisible := false
        this._previewHeight := 0
        this._closeCallback := ""

        ; The Edit control needs its own Background option: unlike the window,
        ; it does not inherit Gui.BackColor, so without this the configured dark
        ; background + light font would render as invisible light text on the
        ; control's default white field.
        this.EditControl := this.guiObj.Add("Edit", "-WantReturn x20 y10 w" inputWindowWidth " h" inputWindowHeight " Background" inputWindowBackground)
        this.SendButton := this.guiObj.Add("Button", "x240 y" (inputWindowHeight + 20) " w80", "Send")
        this.SendButton.Opt("+Default")   ; Make Send the default button (Enter triggers it)
    }

    showInputWindow(message := "", title := unset, windowID := unset, previewImagePath := "") {
        this.EditControl.Value := message
        if IsSet(title) {
            this.guiObj.Title := title
        }

        this.setPreview(previewImagePath)
        this.EditControl.Focus()
        this.guiObj.Show("AutoSize")
        if IsSet(windowID) && windowID {
            ControlSend("^{End}", "Edit1", windowID)
        }
    }

    setPreview(imagePath := "") {
        if imagePath && FileExist(imagePath) {
            imageSize := ImageUtils.GetImageDimensions(imagePath)
            if imageSize {
                previewSize := InputWindow._FitPreviewSize(imageSize.W, imageSize.H)
                this.PreviewControl.Value := imagePath
                this.PreviewControl.Move(20, 10, previewSize.W, previewSize.H)
                this.PreviewControl.Visible := true
                this._previewVisible := true
                this._previewHeight := previewSize.H
            } else {
                this.PreviewControl.Visible := false
                this._previewVisible := false
                this._previewHeight := 0
            }
        } else {
            this.PreviewControl.Visible := false
            this._previewVisible := false
            this._previewHeight := 0
        }
        this._layoutControls()
    }

    clearPreview() {
        this.PreviewControl.Visible := false
        this._previewVisible := false
        this._previewHeight := 0
        this._layoutControls()
    }

    static _FitPreviewSize(sourceW, sourceH, maxW := 180, maxH := 110) {
        if sourceW <= 0 || sourceH <= 0
            return { W: maxW, H: maxH }
        scale := Min(maxW / sourceW, maxH / sourceH)
        return {
            W: Max(1, Round(sourceW * scale)),
            H: Max(1, Round(sourceH * scale))
        }
    }

    _layoutControls() {
        editY := this._previewVisible ? 20 + this._previewHeight : 10
        this.EditControl.Move(20, editY, inputWindowWidth, inputWindowHeight)
        this.SendButton.Move(240, editY + inputWindowHeight + 10, 80)
    }

    validateInputAndHide(*) {
        ; Bug #91: "0" is a valid input - only empty/whitespace counts as empty
        ; (AHK treats the numeric string "0" as falsy).
        if Trim(this.EditControl.Value) = "" {
            MsgBox "Please enter a message or close the window.", "No text entered", "IconX"
            return false
        }
        this.guiObj.Hide
        return true
    }

    sendButtonAction(functionToCall) {
        this.SendButton.OnEvent("Click", functionToCall.Bind(this))
    }

    closeButtonCallback(functionToCall) {
        this._closeCallback := functionToCall
    }

    closeButtonAction(*) {
        this.EditControl.Value := ""
        this.guiObj.Hide
        this.clearPreview()
        if this._closeCallback
            this._closeCallback.Call()
        return true
    }

    resizeAction(guiObj, minMax, width, height) {
        if minMax = -1
            return
        editY := this._previewVisible ? 20 + this._previewHeight : 10
        editW := Max(100, width - 40)
        editH := Max(60, height - editY - 50)
        this.EditControl.Move(20, editY, editW, editH)
        this.SendButton.Move(Max(20, (width - 80) // 2), editY + editH + 10, 80)
    }

}

; Rebuild the command input window from the CURRENT settings globals. Called at
; startup and whenever settings change, so background/font/size edits apply
; live instead of requiring a restart (the GUI was previously built once with
; the startup values and never rebuilt).
_rebuildInputWindow(sendCallback, closeCallback := "") {
    global commandInputWindow

    if commandInputWindow && commandInputWindow.guiObj {
        ; Rebuilding the GUI while a screenshot prompt is pending is equivalent
        ; to cancelling it. Run the close callback so the unattached PNG is not
        ; left behind in AppData.
        commandInputWindow.closeButtonAction()
        commandInputWindow.guiObj.Destroy()
    }

    commandInputWindow := InputWindow("Custom command")
    commandInputWindow.sendButtonAction(sendCallback)
    if closeCallback
        commandInputWindow.closeButtonCallback(closeCallback)
}
