; ----------------------------------------------------
; ClipboardCapture — Text capture via clipboard
;
; Handles both FIM and non-FIM clipboard capture.
; Extracted from RequestProcessor.ahk.
; ----------------------------------------------------

class ClipboardCapture {

    ; Returns { success, userMessage?, prefix?, suffix?, modelsStr }
    static Capture(isFIM, pasteMode, customInputMessage) {
        clipboardBeforeCopy := A_Clipboard

        if isFIM
            return ClipboardCapture._CaptureFIM(clipboardBeforeCopy, pasteMode)
        else
            return ClipboardCapture._CaptureChat(clipboardBeforeCopy, customInputMessage)
    }

    static _CaptureFIM(clipboardBeforeCopy, pasteMode) {
        if pasteMode = "replace"
            return ClipboardCapture._CaptureFIM_Fill(clipboardBeforeCopy)
        else
            return ClipboardCapture._CaptureFIM_Continue(clipboardBeforeCopy)
    }

    ; FIM Fill (replace mode): gets prefix (before selection) and suffix (after selection)
    ; using UIA TextPattern — zero visual impact, no scroll, no flash.
    static _CaptureFIM_Fill(clipboardBeforeCopy) {
        prefix := "", suffix := ""

        try {
            el := UIA.GetFocusedElement()

            if !el.IsTextPatternAvailable {
                A_Clipboard := clipboardBeforeCopy
                return { success: false, error: "This application does not support UIA text capture." }
            }

            textPattern := el.TextPattern
            docRange := textPattern.DocumentRange

            selRanges := textPattern.GetSelection()
            if !selRanges.Length {
                A_Clipboard := clipboardBeforeCopy
                return { success: false, error: "No text selected." }
            }
            selRange := selRanges[1]

            ; Prefix: from document start to selection start
            prefixRange := docRange.Clone()
            prefixRange.MoveEndpointByRange(
                UIA.TextPatternRangeEndpoint.End,
                selRange,
                UIA.TextPatternRangeEndpoint.Start
            )
            prefix := prefixRange.GetText()

            ; Suffix: from selection end to document end
            suffixRange := docRange.Clone()
            suffixRange.MoveEndpointByRange(
                UIA.TextPatternRangeEndpoint.Start,
                selRange,
                UIA.TextPatternRangeEndpoint.End
            )
            suffix := suffixRange.GetText()
        } catch Error as e {
            A_Clipboard := clipboardBeforeCopy
            return { success: false, error: "UIA text capture failed: " e.Message }
        }

        ; Cut the selection (no scroll — just removes text in place)
        A_Clipboard := ""
        SendInput("^x")
        if !ClipWait(1) {
            A_Clipboard := clipboardBeforeCopy
            return { success: false, error: "Could not cut the selected text." }
        }

        A_Clipboard := clipboardBeforeCopy
        return { success: true, prefix: prefix, suffix: suffix, modelsStr: "", isFIM: true }
    }

    ; FIM Continue (append mode): copies text selection as prefix if present (^c);
    ; falls back to UIA for text-before-cursor when nothing is selected.
    static _CaptureFIM_Continue(clipboardBeforeCopy) {
        A_Clipboard := ""
        Send("^c")

        if !ClipWait(1) {
            ; No text selected — use UIA to get text from doc start to cursor
            try {
                el := UIA.GetFocusedElement()

                if !el.IsTextPatternAvailable {
                    A_Clipboard := clipboardBeforeCopy
                    return { success: false, error: "This application does not support UIA text capture." }
                }

                textPattern := el.TextPattern
                selRanges := textPattern.GetSelection()
                if selRanges.Length {
                    ; Degenerate (zero-width) range at cursor position
                    cursorRange := selRanges[1]
                    docRange := textPattern.DocumentRange
                    prefixRange := docRange.Clone()
                    prefixRange.MoveEndpointByRange(
                        UIA.TextPatternRangeEndpoint.End,
                        cursorRange,
                        UIA.TextPatternRangeEndpoint.Start
                    )
                    prefix := prefixRange.GetText()
                    A_Clipboard := clipboardBeforeCopy
                    return { success: true, prefix: prefix, suffix: "", modelsStr: "", isFIM: true, needsDeselect: false }
                }
            } catch Error as e {
                A_Clipboard := clipboardBeforeCopy
                return { success: false, error: "UIA text capture failed: " e.Message }
            }
            A_Clipboard := clipboardBeforeCopy
            return { success: false, error: "No text found before cursor." }
        }

        prefix := A_Clipboard
        A_Clipboard := clipboardBeforeCopy
        return { success: true, prefix: prefix, suffix: "", modelsStr: "", isFIM: true, needsDeselect: true }
    }

    static _CaptureChat(clipboardBeforeCopy, customInputMessage) {
        A_Clipboard := ""
        Critical("On")
        SendInput("^c")
        copied := ClipWait(0.5)
        if !copied {
            A_Clipboard := ""
            Send("^c")
            copied := ClipWait(1.5)
        }
        if !copied {
            A_Clipboard := ""
            Send("^{Insert}")
            copied := ClipWait(1)
        }
        Critical("Off")

        userMessage := ""
        if !copied {
            if customInputMessage != "" {
                userMessage := customInputMessage
            } else {
                A_Clipboard := clipboardBeforeCopy
                return { success: false, error: "The attempt to copy text onto the clipboard failed." }
            }
        } else if customInputMessage != "" {
            userMessage := customInputMessage "`n`n" A_Clipboard
        } else {
            userMessage := A_Clipboard
        }

        A_Clipboard := clipboardBeforeCopy
        return { success: true, userMessage: userMessage, modelsStr: "", isFIM: false }
    }
}
