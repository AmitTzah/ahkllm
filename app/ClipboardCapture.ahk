; ----------------------------------------------------
; ClipboardCapture — Text capture via clipboard + UIA
;
; Handles both FIM and non-FIM capture.
; ----------------------------------------------------

class ClipboardCapture {

    ; Returns { success, userMessage?, prefix?, suffix?, fullText?, modelsStr }
    static Capture(isFIM, pasteMode, inputText := "", includeFullText := false, expandNewlines := false) {
        clipboardBeforeCopy := A_Clipboard

        if isFIM
            return ClipboardCapture._CaptureFIM(clipboardBeforeCopy, pasteMode, expandNewlines)
        else
            return ClipboardCapture._CaptureChat(clipboardBeforeCopy, inputText, includeFullText, expandNewlines)
    }

    static _CaptureFIM(clipboardBeforeCopy, pasteMode, expandNewlines := false) {
        if pasteMode = "replace"
            return ClipboardCapture._CaptureFIM_Fill(clipboardBeforeCopy, expandNewlines)
        else
            return ClipboardCapture._CaptureFIM_Continue(clipboardBeforeCopy, expandNewlines)
    }

    ; ----------------------------------------------------
    ; Text normalisation
    ; ----------------------------------------------------

    ; Normalises line endings to LF (\n).  Different apps produce different
    ; endings (Notepad = CRLF, Chrome = LF, some = bare CR).  The LLM API
    ; consistently expects \n, and paragraph breaks (\n\n) must be uniform.
    static NormalizeLineEndings(text, expandSingle := false) {
        ; CRLF before bare CR — order matters
        text := StrReplace(text, "`r`n", "`n")
        text := StrReplace(text, "`r", "`n")
        if expandSingle {
            ; Expand single \n between text to \n\n (preserves existing \n\n)
            text := RegExReplace(text, "([^\n])\n([^\n])", "$1`n`n$2")
            ; Also expand trailing single \n (browser collapses double-Enter at end)
            text := RegExReplace(text, "([^\n])\n$", "$1`n`n")
        }
        return text
    }

    ; ----------------------------------------------------
    ; Template expansion
    ; ----------------------------------------------------

    ; Replaces {{selection}}, {{fullText}}, {{input}} in a template string.
    static ExpandTemplate(template, selection := "", fullText := "", input := "") {
        result := template
        result := StrReplace(result, "{{selection}}", selection)
        result := StrReplace(result, "{{fullText}}", fullText)
        result := StrReplace(result, "{{input}}", input)
        return result
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
    static _CaptureFIM_Fill(clipboardBeforeCopy, expandNewlines := false) {
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
        prefix := ClipboardCapture.NormalizeLineEndings(prefix, expandNewlines)
        suffix := ClipboardCapture.NormalizeLineEndings(suffix, expandNewlines)
        return { success: true, prefix: prefix, suffix: suffix, modelsStr: "", isFIM: true }
    }

    ; ----------------------------------------------------
    ; FIM Continue (append mode)
    ;
    ; Copies text selection as prefix if present (^c);
    ; falls back to UIA for text-before-cursor when nothing is selected.
    ; ----------------------------------------------------
    static _CaptureFIM_Continue(clipboardBeforeCopy, expandNewlines := false) {
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
                    return { success: true, prefix: ClipboardCapture.NormalizeLineEndings(parts.prefix, expandNewlines), suffix: "",
                             modelsStr: "", isFIM: true, needsDeselect: false }
                }
            } catch Error as e {
                A_Clipboard := clipboardBeforeCopy
                return { success: false, error: "UIA text capture failed: " e.Message }
            }
            A_Clipboard := clipboardBeforeCopy
            return { success: false, error: "No text found before cursor." }
        }

        prefix := ClipboardCapture.NormalizeLineEndings(A_Clipboard, expandNewlines)
        A_Clipboard := clipboardBeforeCopy
        return { success: true, prefix: prefix, suffix: "", modelsStr: "", isFIM: true, needsDeselect: true }
    }

    ; ----------------------------------------------------
    ; Non-FIM capture (chat, refine, define, etc.)
    ;
    ; Captures selected text and optionally full document text.
    ; UIA-first, clipboard fallback for both.
    ; ----------------------------------------------------
    static _CaptureChat(clipboardBeforeCopy, inputText := "", includeFullText := false, expandNewlines := false) {
        userMessage := ""
        fullText := ""

        ; Try UIA text capture first (zero visual impact, no clipboard)
        try {
            utp := ClipboardCapture._AcquireTextPattern()
            selRanges := utp.tp.GetSelection()
            if selRanges.Length
                userMessage := selRanges[1].GetText()
            if includeFullText
                fullText := utp.tp.DocumentRange.GetText()
        }

        ; Fall back to clipboard cascade for selection
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

            if copied
                userMessage := A_Clipboard
        }

        ; Fall back to ^a^c for fullText (one-time scroll, acceptable as rare fallback)
        if includeFullText && fullText = "" {
            Critical("On")
            A_Clipboard := ""
            Send("^a")
            Send("^c")
            if ClipWait(1)
                fullText := A_Clipboard
            Critical("Off")
        }

        A_Clipboard := clipboardBeforeCopy

        ; Normalise line endings — different apps produce different formats
        ; (Notepad = CRLF, Chrome = LF).  The LLM API expects consistent \n.
        userMessage := ClipboardCapture.NormalizeLineEndings(userMessage, expandNewlines)
        fullText := ClipboardCapture.NormalizeLineEndings(fullText, expandNewlines)

        ; Allow empty userMessage (template may use only {{input}} or {{fullText}})
        return { success: true, userMessage: userMessage, fullText: fullText,
                 modelsStr: "", isFIM: false }
    }
}
