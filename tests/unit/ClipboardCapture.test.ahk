; ----------------------------------------------------
; ClipboardCapture.test.ahk — Structural regression tests
; for UIA-based FIM capture (keystroke-free approach).
; ----------------------------------------------------

class ClipboardCaptureTest {

    static __New() {
        RegisterTestClass("ClipboardCaptureTest")
    }

    ; _CaptureFIM_Fill must use UIA TextPattern, not keystroke selection
    Fill_UsesUIATextPattern() {
        src := ClipboardCaptureTest._ReadSrc()
        method := ClipboardCaptureTest._ExtractMethod(src, "_CaptureFIM_Fill")

        if !InStr(method, "UIA.GetFocusedElement()")
            throw Error("_CaptureFIM_Fill must use UIA.GetFocusedElement()")
        if !InStr(method, "IsTextPatternAvailable")
            throw Error("_CaptureFIM_Fill must check IsTextPatternAvailable")
        if !InStr(method, "textPattern.DocumentRange")
            throw Error("_CaptureFIM_Fill must use textPattern.DocumentRange (not el.DocumentRange)")
        if !InStr(method, "textPattern.GetSelection()")
            throw Error("_CaptureFIM_Fill must use textPattern.GetSelection() (not el.GetSelection())")
        if !InStr(method, "MoveEndpointByRange")
            throw Error("_CaptureFIM_Fill must use MoveEndpointByRange")

        ; Must NOT use scroll-causing keystrokes
        if InStr(method, "^+{Home}")
            throw Error("_CaptureFIM_Fill must NOT use ^+{Home}")
        if InStr(method, "+^{End}")
            throw Error("_CaptureFIM_Fill must NOT use +^{End}")

        ; Must cut selection (no scroll)
        if !InStr(method, 'SendInput("^x")')
            throw Error("_CaptureFIM_Fill must use SendInput(^x)")
    }

    ; _CaptureFIM_Continue: ^c path must set needsDeselect: true
    Continue_CopyPath_SetsNeedsDeselect() {
        src := ClipboardCaptureTest._ReadSrc()
        method := ClipboardCaptureTest._ExtractMethod(src, "_CaptureFIM_Continue")

        ; The ^c success path returns needsDeselect: true
        if !InStr(method, "needsDeselect: true")
            throw Error("_CaptureFIM_Continue ^c path must set needsDeselect: true")
    }

    ; _CaptureFIM_Continue: UIA fallback must set needsDeselect: false
    Continue_UIAFallback_SetsNeedsDeselectFalse() {
        src := ClipboardCaptureTest._ReadSrc()
        method := ClipboardCaptureTest._ExtractMethod(src, "_CaptureFIM_Continue")

        ; The UIA fallback returns needsDeselect: false
        if !InStr(method, "needsDeselect: false")
            throw Error("_CaptureFIM_Continue UIA fallback must set needsDeselect: false")
    }

    ; _CaptureFIM_Continue: UIA fallback must use TextPattern
    Continue_UIAFallback_UsesTextPattern() {
        src := ClipboardCaptureTest._ReadSrc()
        method := ClipboardCaptureTest._ExtractMethod(src, "_CaptureFIM_Continue")

        if !InStr(method, "UIA.GetFocusedElement()")
            throw Error("_CaptureFIM_Continue UIA fallback must use UIA.GetFocusedElement()")
        if !InStr(method, "IsTextPatternAvailable")
            throw Error("_CaptureFIM_Continue UIA fallback must check IsTextPatternAvailable")

        ; Must NOT use scroll-causing keystrokes in fallback
        if InStr(method, "^+{Home}")
            throw Error("_CaptureFIM_Continue must NOT use ^+{Home}")
    }

    ; _CaptureFIM routes to correct method based on pasteMode
    CaptureFIM_RoutesToFill_ForReplace() {
        src := ClipboardCaptureTest._ReadSrc()
        method := ClipboardCaptureTest._ExtractMethod(src, "_CaptureFIM(")

        if !InStr(method, 'pasteMode = "replace"')
            throw Error("_CaptureFIM must check pasteMode = replace")
        if !InStr(method, "_CaptureFIM_Fill")
            throw Error("_CaptureFIM must route replace to _CaptureFIM_Fill")
        if !InStr(method, "_CaptureFIM_Continue")
            throw Error("_CaptureFIM must route append to _CaptureFIM_Continue")
    }

    ; --- Helpers ---

    static _ReadSrc() {
        srcPath := A_ScriptDir "\..\app\ClipboardCapture.ahk"
        if !FileExist(srcPath)
            throw Error("ClipboardCapture.ahk not found at: " srcPath)
        return FileRead(srcPath)
    }

    static _ExtractMethod(src, methodName) {
        ; Search for the method definition (static keyword), not call sites
        pos := InStr(src, "static " methodName)
        if !pos
            throw Error("Method static " methodName " not found in ClipboardCapture.ahk")
        ; Extract a generous window around the method
        return SubStr(src, pos, 2000)
    }

}
