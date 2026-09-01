; ----------------------------------------------------
; TextCapture — Text capture via clipboard + UIA
;
; Handles both FIM and non-FIM capture.
; ----------------------------------------------------

class TextCapture {

    ; Returns { success, userMessage?, prefix?, suffix?, fullText?, modelsStr }
    static Capture(isFIM, pasteMode, inputText := "", includeFullText := false, expandNewlines := false, maxContextWords := 0) {
        clipboardBeforeCopy := A_Clipboard

        if isFIM
            return TextCapture._CaptureFIM(clipboardBeforeCopy, pasteMode, expandNewlines, maxContextWords)
        else
            return TextCapture._CaptureSelection(clipboardBeforeCopy, inputText, includeFullText, expandNewlines, maxContextWords)
    }

    static _CaptureFIM(clipboardBeforeCopy, pasteMode, expandNewlines := false, maxContextWords := 0) {
        if pasteMode = "replace"
            return TextCapture._CaptureFIM_Fill(clipboardBeforeCopy, expandNewlines, maxContextWords)
        else
            return TextCapture._CaptureFIM_Continue(clipboardBeforeCopy, expandNewlines, maxContextWords)
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
    ; Context window truncation
    ; ----------------------------------------------------

    ; Truncates fullText so that at most maxContextWords words surround the
    ; selection.  The selection itself is always fully included; only the
    ; surrounding text is trimmed.  Whitespace (including newlines) is preserved
    ; by _TruncateWords slicing at character positions rather than reconstructing.
    static _TruncateAround(fullText, selection, maxContextWords) {
        if !maxContextWords || !fullText || !selection
            return fullText
        selPos := InStr(fullText, selection)
        if !selPos
            return fullText
        half := maxContextWords // 2
        afterWords := maxContextWords - half   ; odd maxContextWords → extra word to after
        before := SubStr(fullText, 1, selPos - 1)
        after := SubStr(fullText, selPos + StrLen(selection))
        before := half ? TextCapture._TruncateWords(before, half, true) : ""
        after  := afterWords ? TextCapture._TruncateWords(after, afterWords, false) : ""
        ; No manual space-padding needed — _TruncateWords preserves original
        ; whitespace between words by slicing at character positions.
        return before . selection . after
    }

    ; Truncates text to at most maxWords, taking from the end if fromEnd is true,
    ; from the start otherwise.  Words are identified as runs of non-whitespace
    ; characters, and the result is sliced from the original text — this preserves
    ; ALL original whitespace (spaces, tabs, newlines) between words.
    static _TruncateWords(text, maxWords, fromEnd := false) {
        if !maxWords || text = ""
            return text

        ; Scan for word boundary positions
        wordStarts := [], wordEnds := []
        len := StrLen(text)
        inWord := false

        Loop len {
            char := SubStr(text, A_Index, 1)
            isSpace := RegExMatch(char, "\s")
            if !isSpace && !inWord {
                wordStarts.Push(A_Index)
                inWord := true
            } else if isSpace && inWord {
                wordEnds.Push(A_Index - 1)
                inWord := false
            }
        }
        if inWord
            wordEnds.Push(len)

        if wordStarts.Length <= maxWords
            return text

        if fromEnd {
            ; Take last maxWords words — slice from their start to end of text
            start := wordStarts.Length - maxWords + 1
            return SubStr(text, wordStarts[start])
        }

        ; Take first maxWords words + preserve original trailing whitespace
        trailing := RegExMatch(text, "(\s*)$", &m) ? m[0] : ""
        return SubStr(text, 1, wordEnds[maxWords]) . trailing
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
    static _CaptureFIM_Fill(clipboardBeforeCopy, expandNewlines := false, maxContextWords := 0) {
        hasSelection := false
        prefix := "", suffix := ""

        try {
            utp := TextCapture._AcquireTextPattern()
            docRange := utp.tp.DocumentRange

            selRanges := utp.tp.GetSelection()
            if !selRanges.Length {
                A_Clipboard := clipboardBeforeCopy
                return { success: false, error: "No text cursor found." }
            }
            gapRange := selRanges[1]
            hasSelection := gapRange.GetText() != ""

            parts := TextCapture._SplitAt(docRange, gapRange)
            ; Normalise before truncation so \r\n → \n and expandNewlines work
            prefix := TextCapture.NormalizeLineEndings(parts.prefix, expandNewlines)
            suffix := TextCapture.NormalizeLineEndings(parts.suffix, expandNewlines)

            ; Truncate context window: split limit evenly above/below cursor
            if maxContextWords {
                half := maxContextWords // 2
                suffixWords := maxContextWords - half  ; odd count → extra word below cursor
                prefix := half ? TextCapture._TruncateWords(prefix, half, true) : ""
                suffix := suffixWords ? TextCapture._TruncateWords(suffix, suffixWords, false) : ""
            }
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
    static _CaptureFIM_Continue(clipboardBeforeCopy, expandNewlines := false, maxContextWords := 0) {
        A_Clipboard := ""
        Send("^c")

        if !ClipWait(1) {
            ; No text selected — use UIA to get text from doc start to cursor
            try {
                utp := TextCapture._AcquireTextPattern()
                selRanges := utp.tp.GetSelection()
                if selRanges.Length {
                    docRange := utp.tp.DocumentRange
                    parts := TextCapture._SplitAt(docRange, selRanges[1])
                    prefix := TextCapture.NormalizeLineEndings(parts.prefix, expandNewlines)
                    prefix := maxContextWords ? TextCapture._TruncateWords(prefix, maxContextWords, true) : prefix
                    A_Clipboard := clipboardBeforeCopy
                    return { success: true, prefix: prefix, suffix: "",
                             modelsStr: "", isFIM: true, needsDeselect: false }
                }
            } catch Error as e {
                A_Clipboard := clipboardBeforeCopy
                return { success: false, error: "UIA text capture failed: " e.Message }
            }
            A_Clipboard := clipboardBeforeCopy
            return { success: false, error: "No text found before cursor." }
        }

        prefix := TextCapture.NormalizeLineEndings(A_Clipboard, expandNewlines)
        try
            prefix := maxContextWords ? TextCapture._TruncateWords(prefix, maxContextWords, true) : prefix
        catch Error as e
            debugLog("TextCapture clipboard truncation error: " e.Message, "ErrorHandler")
        catch Error as e {
            A_Clipboard := clipboardBeforeCopy
            return { success: false, error: "Text truncation failed: " e.Message }
        }
        A_Clipboard := clipboardBeforeCopy
        return { success: true, prefix: prefix, suffix: "", modelsStr: "", isFIM: true, needsDeselect: true }
    }

    ; ----------------------------------------------------
    ; Non-FIM capture (chat, refine, define, etc.)
    ;
    ; Captures selected text and optionally full document text.
    ; UIA-first, clipboard fallback for both.
    ; ----------------------------------------------------
    static _CaptureSelection(clipboardBeforeCopy, inputText := "", includeFullText := false, expandNewlines := false, maxContextWords := 0) {
        userMessage := ""
        fullText := ""

        ; Try UIA text capture first (zero visual impact, no clipboard)
        try {
            utp := TextCapture._AcquireTextPattern()
            selRanges := utp.tp.GetSelection()
            if selRanges.Length
                userMessage := selRanges[1].GetText()
            if includeFullText
                fullText := utp.tp.DocumentRange.GetText()
        }

        ; Fall back to clipboard cascade for selection.
        ; Always run when UIA didn't get text — clipboard may have a selection
        ; from applications where UIA TextPattern isn't available.
        ; Combine with inputText when both sources exist.
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
        ; Web selections commonly carry single newlines between
        ; paragraphs (HTML collapses the original blank lines when copying), so
        ; ALWAYS expand a single \n between text to \n\n — the universal
        ; paragraph break LLMs were trained on — instead of only when the
        ; command's expandNewlines toggle is on. Without it, summarizing or
        ; translating web text sends distinct paragraphs as one block. (FIM
        ; capture keeps the toggle-driven behavior: completions/code care about
        ; exact whitespace.)
        userMessage := TextCapture.NormalizeLineEndings(userMessage, true)
        fullText := TextCapture.NormalizeLineEndings(fullText, true)

        ; Truncate fullText around selection (selection always fully captured)
        fullText := TextCapture._TruncateAround(fullText, userMessage, maxContextWords)

        ; Allow empty userMessage (template may use only {{input}} or {{fullText}})
        return { success: true, userMessage: userMessage, fullText: fullText,
                 modelsStr: "", isFIM: false }
    }
}
