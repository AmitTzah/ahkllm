; ----------------------------------------------------
; Input Window
; ----------------------------------------------------

class InputWindow {
    __New(windowTitle) {

        ; Create Input Window — uses settings from UserConfig.ahk
        this.guiObj := Gui("Resize", windowTitle)
        this.guiObj.OnEvent("Close", this.closeButtonAction.Bind(this))
        this.guiObj.OnEvent("Escape", this.closeButtonAction.Bind(this))
        this.guiObj.OnEvent("Size", this.resizeAction.Bind(this))
        this.guiObj.SetFont(inputWindowFontSize " cDefault", inputWindowFontFace)
        this.EditControl := this.guiObj.Add("Edit", "-WantReturn x20 y+5 w" inputWindowWidth " h" inputWindowHeight)
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