; ----------------------------------------------------
; InlineRequestRunner tests — verify HighlightInsertedText
; uses UIA TextPattern (no keystroke-based selection).
; ----------------------------------------------------

class InlineRequestRunnerTest {

    static __New() {
        RegisterTestClass("InlineRequestRunnerTest")
    }

    ; Verifies that HighlightInsertedText uses UIA TextPattern
    ; instead of keystroke-based selection (Send with Shift).
    Highlight_UsesUIATextPattern() {
        srcPath := A_ScriptDir "\..\app\InlineRequestRunner.ahk"
        if !FileExist(srcPath)
            throw Error("InlineRequestRunner.ahk not found at: " srcPath)

        src := FileRead(srcPath)

        ; Locate the HighlightInsertedText method
        highlightPos := InStr(src, "static HighlightInsertedText(responseText)")
        if !highlightPos
            throw Error("HighlightInsertedText method not found")

        ; Extract the method body (~40 lines)
        methodBlock := SubStr(src, highlightPos, 1500)

        ; Must use UIA TextPattern, not keystroke Send
        if !InStr(methodBlock, "UIA.GetFocusedElement()")
            throw Error("HighlightInsertedText must use UIA.GetFocusedElement()")
        if !InStr(methodBlock, "IsTextPatternAvailable")
            throw Error("HighlightInsertedText must check IsTextPatternAvailable")
        if !InStr(methodBlock, "MoveEndpointByUnit")
            throw Error("HighlightInsertedText must use MoveEndpointByUnit")
        if !InStr(methodBlock, "TextPatternRangeEndpoint.Start")
            throw Error("HighlightInsertedText must move Start endpoint")
        if !InStr(methodBlock, "TextUnit.Character")
            throw Error("HighlightInsertedText must use TextUnit.Character")
        if !InStr(methodBlock, "selRange.Select()")
            throw Error("HighlightInsertedText must call selRange.Select()")

        ; Must NOT use keystroke-based selection (Shift key for extending selection)
        if InStr(methodBlock, "Shift") && InStr(methodBlock, "Send(")
            throw Error("HighlightInsertedText must NOT use Send with Shift")

        ; Must NOT call removed _GetHighlightParams
        if InStr(methodBlock, "_GetHighlightParams")
            throw Error("_GetHighlightParams should be removed")
    }

}

RegisterTestClass("InlineRequestRunnerTest")
