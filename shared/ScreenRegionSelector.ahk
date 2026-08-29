; ======================================================
; ScreenRegionSelector.ahk - minimal interactive screen-region picker
; Inspired by Fanatic Guru's Snipper script
; ======================================================

class ScreenRegionSelector {

    ; Dim the virtual desktop, let the user drag a rectangle, and return
    ; {X, Y, W, H}. Pressing Esc or making a tiny selection cancels.
    static Select(minSize := 8) {
        bounds := ScreenRegionSelector.VirtualScreenBounds()
        if bounds.W <= 0 || bounds.H <= 0
            return false

        overlay := Gui("+AlwaysOnTop -Caption +ToolWindow -DPIScale", "AhkLLM Screenshot")
        overlay.MarginX := 0
        overlay.MarginY := 0
        overlay.BackColor := "000000"
        overlay.SetFont("s11 cFFFFFF", "Segoe UI")
        overlay.Add("Text", "x0 y20 w" bounds.W " Center BackgroundTrans",
            "Drag to capture a region. Press Esc to cancel.")

        ; The selected rectangle is just a translucent click-through highlight.
        ; The full-screen overlay underneath continues to receive the mouse click.
        selection := Gui("+AlwaysOnTop -Caption +ToolWindow -DPIScale +E0x20", "AhkLLM Screenshot Selection")
        selection.MarginX := 0
        selection.MarginY := 0
        selection.BackColor := "4A90E2"

        try {
            overlay.Show("x" bounds.X " y" bounds.Y " w" bounds.W " h" bounds.H)
            WinSetTransparent(110, overlay)

            selection.Show("Hide x0 y0 w1 h1")
            WinSetTransparent(75, selection)

            ; A screenshot command can be triggered with the mouse. Do not treat
            ; the click that dismissed the command menu as the start of a snip.
            while GetKeyState("LButton", "P") {
                if GetKeyState("Esc", "P")
                    return false
                Sleep 10
            }

            ; Wait for the user to begin the drag.
            while !GetKeyState("LButton", "P") {
                if GetKeyState("Esc", "P")
                    return false
                Sleep 10
            }

            start := ScreenRegionSelector.CursorPosition()
            if !start
                return false

            ; Track the drag and show the selected rectangle.
            while GetKeyState("LButton", "P") {
                if GetKeyState("Esc", "P")
                    return false

                current := ScreenRegionSelector.CursorPosition()
                if current {
                    area := ScreenRegionSelector.NormalizeArea(start.X, start.Y, current.X, current.Y)
                    if area.W > 0 && area.H > 0
                        selection.Show("NA x" area.X " y" area.Y " w" area.W " h" area.H)
                }
                Sleep 10
            }

            finish := ScreenRegionSelector.CursorPosition()
            if !finish
                return false

            area := ScreenRegionSelector.NormalizeArea(start.X, start.Y, finish.X, finish.Y)
            if area.W < minSize || area.H < minSize
                return false

            return area
        } finally {
            try selection.Destroy()
            try overlay.Destroy()
        }
    }

    ; Windows virtual-screen metrics include every monitor and may start at
    ; negative coordinates when a display sits left of or above the primary.
    static VirtualScreenBounds() {
        return {
            X: DllCall("user32\GetSystemMetrics", "Int", 76, "Int"), ; SM_XVIRTUALSCREEN
            Y: DllCall("user32\GetSystemMetrics", "Int", 77, "Int"), ; SM_YVIRTUALSCREEN
            W: DllCall("user32\GetSystemMetrics", "Int", 78, "Int"), ; SM_CXVIRTUALSCREEN
            H: DllCall("user32\GetSystemMetrics", "Int", 79, "Int")  ; SM_CYVIRTUALSCREEN
        }
    }

    static CursorPosition() {
        point := Buffer(8, 0)
        if !DllCall("user32\GetCursorPos", "Ptr", point.Ptr, "Int")
            return false
        return {
            X: NumGet(point, 0, "Int"),
            Y: NumGet(point, 4, "Int")
        }
    }

    static NormalizeArea(x1, y1, x2, y2) {
        return {
            X: Min(x1, x2),
            Y: Min(y1, y2),
            W: Abs(x2 - x1),
            H: Abs(y2 - y1)
        }
    }
}
