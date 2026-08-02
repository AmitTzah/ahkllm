; ----------------------------------------------------
; Input Window
; ----------------------------------------------------

global commandInputWindow := ""

class InputWindow {
    __New(windowTitle) {

        ; Create Input Window — uses settings from UserConfig.ahk
        this.guiObj := Gui("Resize", windowTitle)
        this.guiObj.OnEvent("Close", this.closeButtonAction.Bind(this))
        this.guiObj.OnEvent("Escape", this.closeButtonAction.Bind(this))
        this.guiObj.OnEvent("Size", this.resizeAction.Bind(this))
        this.guiObj.SetFont(inputWindowFontSize " " inputWindowFontColor, inputWindowFontFace)
        this.guiObj.BackColor := inputWindowBackground
        ; The Edit control needs its own Background option: unlike the window,
        ; it does not inherit Gui.BackColor, so without this the configured dark
        ; background + light font would render as invisible light text on the
        ; control's default white field.
        this.EditControl := this.guiObj.Add("Edit", "-WantReturn x20 y+5 w" inputWindowWidth " h" inputWindowHeight " Background" inputWindowBackground)
        this.SendButton := this.guiObj.Add("Button", "x240 y+10 w80", "Send")
        this.SendButton.Opt("+Default")   ; Make Send the default button (Enter triggers it)
    }

    showInputWindow(message := "", title := unset, windowID := unset) {
        this.EditControl.Value := message
        if IsSet(title) {
            this.guiObj.Title := title
        }

        this.EditControl.Focus()
        this.guiObj.Show("AutoSize")
        if IsSet(windowID) {
            ControlSend("^{End}", "Edit1", windowID)
        }
    }

    validateInputAndHide(*) {
        if !this.EditControl.Value {
            MsgBox "Please enter a message or close the window.", "No text entered", "IconX"
            return false
        }
        this.guiObj.Hide
        return true
    }

    sendButtonAction(functionToCall) {
        this.SendButton.OnEvent("Click", functionToCall.Bind(this))
    }

    closeButtonAction(*) {
        this.EditControl.Value := ""
        this.guiObj.Hide
        return true
    }

    resizeAction(*) {
        AutoXYWH("wh", this.EditControl)
        AutoXYWH("x0.5 y", this.SendButton)
    }

}

; Rebuild the command input window from the CURRENT settings globals. Called at
; startup and whenever settings change, so background/font/size edits apply
; live instead of requiring a restart (the GUI was previously built once with
; the startup values and never rebuilt).
_rebuildInputWindow(sendCallback) {
    global commandInputWindow

    if commandInputWindow && commandInputWindow.guiObj
        commandInputWindow.guiObj.Destroy()

    commandInputWindow := InputWindow("Custom command")
    commandInputWindow.sendButtonAction(sendCallback)
}
