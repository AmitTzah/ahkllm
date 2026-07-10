; ======================================================
; RequestProcessor.test.ahk — Regression tests for RequestProcessor.ahk
;
; Tests: FIM paste logic structure (Sleep between {Right} and ^v)
; ======================================================

class RequestProcessorTest {

    static __New() {
        RegisterTestClass("RequestProcessorTest")
    }

    ; Verifies that the FIM Continue paste sequence has Sleep between
    ; {Right} (deselect) and ^v (paste). Without this delay, ^v can
    ; replace the still-selected text instead of appending after it.
    ; Root cause: commit 06c56db moved paste inline from ResponseWindow.ahk
    ; and removed the implicit inter-process delay that prevented the race.
    FIMPaste_HasSleepBetweenRightAndPaste() {
        srcPath := A_ScriptDir "\..\app\InlineRequestRunner.ahk"
        if !FileExist(srcPath)
            throw Error("InlineRequestRunner.ahk not found at: " srcPath)

        src := FileRead(srcPath)

        ; Find the paste block: locate "NormalizeLineEndings(responseFromLLM.response"
        pasteStartPos := InStr(src, "NormalizeLineEndings(responseFromLLM.response")
        if !pasteStartPos
            throw Error("Paste block anchor not found in InlineRequestRunner.ahk")

        ; Extract a window: from the anchor line through ~15 lines after
        pasteBlock := SubStr(src, pasteStartPos, 2500)

        ; Find the Send("{Right}") line
        rightPos := InStr(pasteBlock, 'Send("{Right}")')
        if !rightPos
            throw Error('Send("{Right}") not found in paste block')

        ; Find the Send("^v") line
        pastePos := InStr(pasteBlock, 'Send("^v")')
        if !pastePos
            throw Error('Send("^v") not found in paste block')

        ; Extract the text between {Right} and ^v
        between := SubStr(pasteBlock, rightPos + 14, pastePos - rightPos - 14)

        ; Verify Sleep is present between {Right} and ^v
        if !InStr(between, "Sleep")
            throw Error("No Sleep between Send(`"{Right}`") and Send(`"^v`") — "
                . "this will cause FIM Continue to delete selected text instead of appending after it. "
                . "Between text: [" Trim(between) "]")

        ; Also verify that ^v comes AFTER {Right} (not before)
        if pastePos < rightPos
            throw Error("Send(`"^v`") appears before Send(`"{Right}`") — paste order is wrong")
        ; runOptionsMenuAction must handle "apilogs:" special command
        OptionsMenu_HandlesApiLogsCommand() {
            srcPath := A_ScriptDir "\..\app\RequestProcessor.ahk"
            if !FileExist(srcPath)
                throw Error("RequestProcessor.ahk not found at: " srcPath)
            src := FileRead(srcPath)
    
            if !InStr(src, '"apilogs:"')
                throw Error("runOptionsMenuAction must handle apilogs: command")
            if !InStr(src, "ShowApiLogs()")
                throw Error("runOptionsMenuAction must call ShowApiLogs() for apilogs:")
        }
    
    }

    ; Verifies that Sleep exists after ^v for scroll-to-cursor stability
    FIMPaste_HasSleepAfterPaste() {
        srcPath := A_ScriptDir "\..\app\InlineRequestRunner.ahk"
        src := FileRead(srcPath)
        pasteStartPos := InStr(src, "NormalizeLineEndings(responseFromLLM.response")
        pasteBlock := SubStr(src, pasteStartPos, 2500)

        pastePos := InStr(pasteBlock, 'Send("^v")')
        leftRightPos := InStr(pasteBlock, 'Send("{Left}{Right}")')

        if leftRightPos {
            between := SubStr(pasteBlock, pastePos + 10, leftRightPos - pastePos - 10)
            if !InStr(between, "Sleep")
                throw Error("No Sleep between Send(`"^v`") and Send(`"{Left}{Right}`") in paste block")
        }
    }

}
