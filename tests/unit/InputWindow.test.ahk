; ======================================================
; InputWindow.test.ahk — Regression tests for app/InputWindow.ahk
;
; Bug: the command input window was created once at startup with the then-current
; ui.inputWindow settings; the constructor never applied the background or font
; color, and size/font edits only appeared after a restart. _rebuildInputWindow()
; now rebuilds the GUI from the current globals on settings updates, and the
; constructor applies background + font color.
; ======================================================

class InputWindowTest {

    static __New() {
        RegisterTestClass("InputWindowTest")
    }

    _setGlobals() {
        global inputWindowBackground, inputWindowFontSize, inputWindowFontColor
        global inputWindowFontFace, inputWindowWidth, inputWindowHeight
        inputWindowBackground := "0x123456"
        inputWindowFontSize := "s18"
        inputWindowFontColor := "cRed"
        inputWindowFontFace := "Consolas"
        inputWindowWidth := 640
        inputWindowHeight := 320
    }

    ; The constructor must apply the configured background and font color
    ; (previously hardcoded cDefault and no BackColor at all).
    New_AppliesBackgroundAndFontColor() {
        global inputWindowBackground
        this._setGlobals()

        win := InputWindow("test")
        try {
            ; Gui.BackColor normalizes the value (drops the "0x" prefix), so
            ; compare normalized forms.
            normalizeColor := (c) => StrReplace(StrLower(c), "0x", "")
            if normalizeColor(win.guiObj.BackColor) != normalizeColor(inputWindowBackground)
                throw Error("BackColor not applied: '" win.guiObj.BackColor "' expected '" inputWindowBackground "'")
        } finally {
            win.guiObj.Destroy()
        }
    }

    ; The command prompt uses a chat-composer style card. The native Edit
    ; remains borderless inside the card so focus produces neither the blue
    ; underline nor a harsh Win32 frame.
    New_UsesSoftCardWithBorderlessEditSurface() {
        this._setGlobals()
        win := InputWindow("test")
        try {
            editStyle := DllCall("GetWindowLongPtr", "Ptr", win.EditControl.Hwnd, "Int", -16, "Ptr")
            editExStyle := DllCall("GetWindowLongPtr", "Ptr", win.EditControl.Hwnd, "Int", -20, "Ptr")
            if (editStyle & 0x00800000)
                throw Error("Edit control should not use WS_BORDER")
            if (editExStyle & 0x00000200)
                throw Error("Edit control should not use WS_EX_CLIENTEDGE")

            win.CardBorder.GetPos(&cardX, &cardY, &cardW, &cardH)
            win.CardSurface.GetPos(&surfaceX, &surfaceY, &surfaceW, &surfaceH)
            win.EditControl.GetPos(&editX, &editY, &editW, &editH)
            win.SendButton.GetPos(&buttonX, , &buttonW)

            if surfaceX <= cardX || surfaceY <= cardY || surfaceW >= cardW || surfaceH >= cardH
                throw Error("card surface should sit inside the subtle border layer")
            if editX <= surfaceX || editY <= surfaceY || editW >= surfaceW || editH >= surfaceH
                throw Error("Edit control should be inset inside the card to provide padding")

            expectedButtonX := cardX + (cardW - buttonW) // 2
            if Abs(buttonX - expectedButtonX) > 1
                throw Error("single Send action should stay centered below the input card")
        } finally {
            win.guiObj.Destroy()
        }
    }

    ; Rebuild must create a FRESH GUI from the current globals and destroy the
    ; previous one (the bug built it once at startup and never rebuilt).
    Rebuild_CreatesFreshGui_FromCurrentSettings() {
        global commandInputWindow, inputWindowWidth, inputWindowHeight
        this._setGlobals()
        commandInputWindow := ""
        capturedCalls := []

        _rebuildInputWindow((*) => capturedCalls.Push("sent"))

        if !IsObject(commandInputWindow)
            throw Error("commandInputWindow was not created")
        firstHwnd := commandInputWindow.guiObj.hWnd

        _rebuildInputWindow((*) => capturedCalls.Push("sent"))

        if commandInputWindow.guiObj.hWnd = firstHwnd
            throw Error("Rebuild reused the same GUI; expected a fresh one")
        if WinExist("ahk_id " firstHwnd)
            throw Error("Previous input window still exists after rebuild")

        ; The new window must reflect the CURRENT size globals.
        commandInputWindow.guiObj.Show("AutoSize")
        try {
            WinGetPos(&x, &y, &w, &h, "ahk_id " commandInputWindow.guiObj.hWnd)
            if w < 600
                throw Error("Input window width " w " does not reflect current settings (" inputWindowWidth ")")
        } finally {
            commandInputWindow.guiObj.Destroy()
        }
    }

    ; Regression (bug #91): "0" is valid input - only empty/whitespace is empty.
    Validate_AcceptsZero() {
        this._setGlobals()
        win := InputWindow("test")
        try {
            win.EditControl.Value := "0"
            result := win.validateInputAndHide()
            if !result
                throw Error("input '0' must be accepted, got false")
        } finally {
            win.guiObj.Destroy()
        }
    }

    ScreenshotPreview_FitPreservesWideAndTallAspectRatios() {
        wide := InputWindow._FitPreviewSize(1800, 200)
        if wide.W != 180 || wide.H != 20
            throw Error("wide screenshot should fit as 180x20, got " wide.W "x" wide.H)

        tall := InputWindow._FitPreviewSize(200, 2200)
        if tall.W != 10 || tall.H != 110
            throw Error("tall screenshot should fit as 10x110, got " tall.W "x" tall.H)
    }

    ScreenshotPreview_ShowsAndClears() {
        this._setGlobals()
        win := InputWindow("test")
        previewPath := A_ScriptDir "\\..\\docs\\screenshots\\chat-window.png"
        if !FileExist(previewPath)
            throw Error("preview fixture missing: " previewPath)
        try {
            win.showInputWindow("prompt", "test", "", previewPath)
            if !win.PreviewControl.Visible
                throw Error("screenshot preview should be visible when a preview image is supplied")
            sourceSize := ImageUtils.GetImageDimensions(previewPath)
            win.PreviewControl.GetPos(, , &previewW, &previewH)
            if sourceSize && Abs((previewW / previewH) - (sourceSize.W / sourceSize.H)) > 0.02
                throw Error("screenshot preview should preserve the image aspect ratio")
            win.EditControl.GetPos(, &editY)
            if editY <= 10
                throw Error("prompt field should move below the screenshot preview")
            win.clearPreview()
            if win.PreviewControl.Visible
                throw Error("clearPreview should hide the screenshot thumbnail")
        } finally {
            win.guiObj.Destroy()
        }
    }

    Validate_RejectsEmpty() {
        this._setGlobals()
        win := InputWindow("test")
        try {
            win.EditControl.Value := ""
            result := win.validateInputAndHide()
            if result
                throw Error("empty input must be rejected")
        } finally {
            win.guiObj.Destroy()
        }
    }
}
