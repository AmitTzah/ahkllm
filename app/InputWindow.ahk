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
        this.PreviewControl := this.guiObj.Add("Picture", "x20 y16 w180 h110 Hidden")
        this._previewVisible := false
        this._previewHeight := 0
        this._closeCallback := ""

        ; The chat composer is a soft rounded card with a borderless text area.
        ; Reproduce that visual hierarchy with two static background layers, then
        ; place the native Edit control inside with enough inset to act as padding.
        ; The border is intentionally light rather than the stock Win32 client edge.
        this.CardBorder := this.guiObj.Add("Text", "x20 y16 w" inputWindowWidth " h" inputWindowHeight " Background0xE5E7EB")
        this.CardSurface := this.guiObj.Add("Text", "x21 y17 w" (inputWindowWidth - 2) " h" (inputWindowHeight - 2) " Background" inputWindowBackground)
        this.EditControl := this.guiObj.Add("Edit", "-Border -E0x200 -WantReturn x32 y28 w" (inputWindowWidth - 24) " h" (inputWindowHeight - 24) " Background" inputWindowBackground)

        ; There is only one action in this popup. A centered, comfortably sized
        ; default button is easier to target and balances the card above it.
        this.SendButton := this.guiObj.Add("Button", "x0 y0 w96 h34", "Send")
        this.SendButton.Opt("+Default")   ; Make Send the default button (Enter triggers it)

        this._layoutControls()
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
                this.PreviewControl.Move(20, 16, previewSize.W, previewSize.H)
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

    static _SetRoundedRegion(hwnd, width, height, radius := 12) {
        if !hwnd || width <= 0 || height <= 0
            return
        diameter := Max(2, radius * 2)
        region := DllCall("gdi32\CreateRoundRectRgn",
            "Int", 0, "Int", 0, "Int", width + 1, "Int", height + 1,
            "Int", diameter, "Int", diameter, "Ptr")
        if !region
            return
        ; On success Windows owns the region handle. Delete it only if applying
        ; the region failed.
        if !DllCall("user32\SetWindowRgn", "Ptr", hwnd, "Ptr", region, "Int", true, "Int")
            DllCall("gdi32\DeleteObject", "Ptr", region)
    }

    _layoutCard(cardX, cardY, cardW, cardH) {
        surfaceW := Max(1, cardW - 2)
        surfaceH := Max(1, cardH - 2)
        padding := 12

        this.CardBorder.Move(cardX, cardY, cardW, cardH)
        this.CardSurface.Move(cardX + 1, cardY + 1, surfaceW, surfaceH)
        this.EditControl.Move(
            cardX + padding,
            cardY + padding,
            Max(40, cardW - (padding * 2)),
            Max(32, cardH - (padding * 2))
        )

        InputWindow._SetRoundedRegion(this.CardBorder.Hwnd, cardW, cardH, 12)
        InputWindow._SetRoundedRegion(this.CardSurface.Hwnd, surfaceW, surfaceH, 11)
    }

    _layoutControls(width := 0, height := 0) {
        marginX := 20
        topMargin := 16
        previewGap := 14
        buttonGap := 14
        buttonW := 96
        buttonH := 34
        bottomMargin := 16

        cardY := this._previewVisible ? topMargin + this._previewHeight + previewGap : topMargin

        if width > 0 && height > 0 {
            cardW := Max(180, width - (marginX * 2))
            cardH := Max(80, height - cardY - buttonGap - buttonH - bottomMargin)
        } else {
            cardW := inputWindowWidth
            cardH := inputWindowHeight
        }

        this._layoutCard(marginX, cardY, cardW, cardH)

        buttonX := marginX + Max(0, (cardW - buttonW) // 2)
        buttonY := cardY + cardH + buttonGap
        this.SendButton.Move(buttonX, buttonY, buttonW, buttonH)
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
        this._layoutControls(width, height)
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
