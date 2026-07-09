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

    ; ----------------------------------------------------
    ; UIA helpers
    ; ----------------------------------------------------

    ; Acquires the focused element's TextPattern. Throws on failure
    ; (caught by caller's try block).
    static _AcquireTextPattern() {
        el := UIA.GetFocusedElement()
        if !el.IsTextPatternAvailable
            throw Error("This application does not support UIA text capture.")
        return { el: el, tp: el.TextPattern }
    }

    ; Splits the document at a gap range, returning text before and after.
    ; gapRange can be a selection or a degenerate cursor position.
    static _SplitAt(docRange, gapRange) {
        prefixRange := docRange.Clone()
        prefixRange.MoveEndpointByRange(
            UIA.TextPatternRangeEndpoint.End,
            gapRange,
            UIA.TextPatternRangeEndpoint.Start
        )
        suffixRange := docRange.Clone()
        suffixRange.MoveEndpointByRange(
            UIA.TextPatternRangeEndpoint.Start,
            gapRange,
            UIA.TextPatternRangeEndpoint.End
        )
        return { prefix: prefixRange.GetText(), suffix: suffixRange.GetText() }
    }

    ; ----------------------------------------------------
    ; FIM Fill (replace mode)
    ;
    ; Gets prefix/suffix via UIA TextPattern — zero visual impact.
    ; With text selected: selection = gap to fill, ^x cuts it.
    ; Without selection: cursor = zero-width gap, no cut needed.
    ; ----------------------------------------------------
    static _CaptureFIM_Fill(clipboardBeforeCopy) {
        hasSelection := false
        prefix := "", suffix := ""

        try {
            utp := ClipboardCapture._AcquireTextPattern()
            docRange := utp.tp.DocumentRange

            selRanges := utp.tp.GetSelection()
            if !selRanges.Length {
                A_Clipboard := clipboardBeforeCopy
                return { success: false, error: "No text cursor found." }
            }
            gapRange := selRanges[1]
            hasSelection := gapRange.GetText() != ""

            parts := ClipboardCapture._SplitAt(docRange, gapRange)
            prefix := parts.prefix
            suffix := parts.suffix
        } catch Error as e {
            A_Clipboard := clipboardBeforeCopy
            return { success: false, error: "UIA text capture failed: " e.Message }
        }

        if hasSelection {
            A_Clipboard := ""
            SendInput("^x")
            if !ClipWait(1) {
                A_Clipboard := clipboardBeforeCopy
                return { success: false, error: "Could not cut the selected text." }
            }
        }

        A_Clipboard := clipboardBeforeCopy
        return { success: true, prefix: prefix, suffix: suffix, modelsStr: "", isFIM: true }
    }

    ; ----------------------------------------------------
    ; FIM Continue (append mode)
    ;
    ; Copies text selection as prefix if present (^c);
    ; falls back to UIA for text-before-cursor when nothing is selected.
    ; ----------------------------------------------------
    static _CaptureFIM_Continue(clipboardBeforeCopy) {
        A_Clipboard := ""
        Send("^c")

        if !ClipWait(1) {
            ; No text selected — use UIA to get text from doc start to cursor
            try {
                utp := ClipboardCapture._AcquireTextPattern()
                selRanges := utp.tp.GetSelection()
                if selRanges.Length {
                    docRange := utp.tp.DocumentRange
                    parts := ClipboardCapture._SplitAt(docRange, selRanges[1])
                    A_Clipboard := clipboardBeforeCopy
                    return { success: true, prefix: parts.prefix, suffix: "",
                             modelsStr: "", isFIM: true, needsDeselect: false }
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

    ; ----------------------------------------------------
    ; Non-FIM capture (chat, refine, define, etc.)
    ;
    ; Tries UIA TextPattern first; falls back to clipboard cascade.
    ; ----------------------------------------------------
    static _CaptureChat(clipboardBeforeCopy, customInputMessage) {
        userMessage := ""

        ; Try UIA text capture first (zero visual impact, no clipboard)
        try {
            utp := ClipboardCapture._AcquireTextPattern()
            selRanges := utp.tp.GetSelection()
            if selRanges.Length
                userMessage := selRanges[1].GetText()
        }

        ; Fall back to clipboard cascade if UIA didn't get text
        if userMessage = "" {
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

            if !copied {
                if customInputMessage != "" {
                    userMessage := customInputMessage
                } else {
                    A_Clipboard := clipboardBeforeCopy
                    return { success: false, error: "The attempt to copy text onto the clipboard failed." }
                }
            } else {
                userMessage := A_Clipboard
            }
        }

        ; Apply custom input message prefix
        if customInputMessage != "" && userMessage != ""
            userMessage := customInputMessage "`n`n" userMessage

        A_Clipboard := clipboardBeforeCopy
        if userMessage = ""
            return { success: false, error: "The attempt to copy text onto the clipboard failed." }
        return { success: true, userMessage: userMessage, modelsStr: "", isFIM: false }
    }
}
