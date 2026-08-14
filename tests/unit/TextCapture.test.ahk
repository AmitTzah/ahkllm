; ----------------------------------------------------
; TextCapture.test.ahk — Structural + behavioral tests
; ----------------------------------------------------

class TextCaptureTest {

    static __New() {
        RegisterTestClass("TextCaptureTest")
    }

    ; ======================================================
    ; ExpandTemplate — behavioral (pure function, no UIA)
    ; ======================================================

    ExpandTemplate_ReplacesAllVars() {
        result := TextCapture.ExpandTemplate(
            "S:{{selection}} F:{{fullText}} I:{{input}}",
            "sel", "full", "inp")
        if result != "S:sel F:full I:inp"
            throw Error("Got: " result)
    }

    ExpandTemplate_EmptyInputsRenderEmpty() {
        result := TextCapture.ExpandTemplate(
            "S:{{selection}} F:{{fullText}} I:{{input}}",
            "", "", "")
        if result != "S: F: I:"
            throw Error("Got: " result)
    }

    ExpandTemplate_NoTemplates_ReturnsUnchanged() {
        result := TextCapture.ExpandTemplate(
            "Hello world", "sel", "full", "inp")
        if result != "Hello world"
            throw Error("Got: " result)
    }

    ExpandTemplate_OmittedParams_DefaultToEmpty() {
        result := TextCapture.ExpandTemplate("S:{{selection}}F:{{fullText}}I:{{input}}")
        if result != "S:F:I:"
            throw Error("Got: " result)
    }

    ; ======================================================
    ; NormalizeLineEndings — behavioral (pure function)
    ; ======================================================

    NormalizeLineEndings_CRLF_To_LF() {
        ; Without expand: CRLF → LF only
        result := TextCapture.NormalizeLineEndings("line1`r`nline2")
        if result != "line1`nline2"
            throw Error("CRLF not normalised: " result)
    }

    NormalizeLineEndings_BareCR_To_LF() {
        result := TextCapture.NormalizeLineEndings("line1`rline2")
        if result != "line1`nline2"
            throw Error("Bare CR not normalised: " result)
    }

    NormalizeLineEndings_LF_Untouched() {
        result := TextCapture.NormalizeLineEndings("line1`nline2")
        if result != "line1`nline2"
            throw Error("LF should be untouched without expand: " result)
    }

    NormalizeLineEndings_Mixed_AllNormalised() {
        result := TextCapture.NormalizeLineEndings("a`r`nb`rc`n")
        if result != "a`nb`nc`n"
            throw Error("Mixed line endings not normalised: " result)
    }

    NormalizeLineEndings_SingleNewline_Expanded() {
        result := TextCapture.NormalizeLineEndings("para1`npara2", true)
        if result != "para1`n`npara2"
            throw Error("Single newline not expanded: " result)
    }

    NormalizeLineEndings_DoubleNewline_Preserved() {
        result := TextCapture.NormalizeLineEndings("para1`n`npara2", true)
        if result != "para1`n`npara2"
            throw Error("Double newline should be preserved: " result)
    }

    NormalizeLineEndings_TrailingNewline_Expanded() {
        result := TextCapture.NormalizeLineEndings("text`n", true)
        if result != "text`n`n"
            throw Error("Trailing newline not expanded: " result)
    }

    NormalizeLineEndings_EmptyString() {
        result := TextCapture.NormalizeLineEndings("")
        if result != ""
            throw Error("Empty string should stay empty: " result)
    }

    ; Normalize without expand — single \n stays single
    NormalizeLineEndings_NoExpand_SingleStaysSingle() {
        result := TextCapture.NormalizeLineEndings("para1`npara2", false)
        if result != "para1`npara2"
            throw Error("Without expand, single LF should stay: " result)
    }

    ; Regression (bug #231): web selections carry single newlines between
    ; paragraphs (HTML collapses the blank lines) - the LLM context must get
    ; \n\n paragraph breaks.
    NormalizeLineEndings_WebSelection_ParagraphsExpand() {
        result := TextCapture.NormalizeLineEndings(
            "First paragraph of the page.`nSecond paragraph of the page.`nThird paragraph.", true)
        if result != "First paragraph of the page.`n`nSecond paragraph of the page.`n`nThird paragraph."
            throw Error("Web selection single newlines should expand to \n\n: " result)
    }

    ; ======================================================
    ; _TruncateWords — behavioral (pure function)
    ; ======================================================

    TruncateWords_NoLimit_ReturnsFull() {
        result := TextCapture._TruncateWords("one two three four five", 0)
        if result != "one two three four five"
            throw Error("No limit should return full text: " result)
    }

    TruncateWords_FromStart() {
        result := TextCapture._TruncateWords("one two three four five", 3, false)
        if result != "one two three"
            throw Error("First 3 words: " result)
    }

    TruncateWords_FromEnd() {
        result := TextCapture._TruncateWords("one two three four five", 3, true)
        if result != "three four five"
            throw Error("Last 3 words: " result)
    }

    TruncateWords_LimitExceeds_ReturnsFull() {
        result := TextCapture._TruncateWords("one two", 10, false)
        if result != "one two"
            throw Error("Limit exceeds text, should return full: " result)
    }

    TruncateWords_Empty() {
        result := TextCapture._TruncateWords("", 5)
        if result != ""
            throw Error("Empty should stay empty: " result)
    }

    TruncateWords_LeadingWhitespace() {
        ; Character-slice preserves leading whitespace (part of the text before word 1)
        result := TextCapture._TruncateWords("   hello world foo bar", 3, false)
        if result != "   hello world foo"
            throw Error("Leading whitespace preserved by slice: " result)
    }

    TruncateWords_TrailingWhitespace() {
        result := TextCapture._TruncateWords("hello world foo bar   ", 3, false)
        ; Trailing whitespace is preserved from the original text by design
        if result != "hello world foo   "
            throw Error("Trailing whitespace should be preserved: " result)
    }

    TruncateWords_OneWordOnly() {
        ; maxWords=1 should truncate to exactly 1 word
        result := TextCapture._TruncateWords("one two three", 1, false)
        if result != "one"
            throw Error("maxWords=1 should return first word only: " result)
    }

    TruncateWords_OneWordFromEnd() {
        result := TextCapture._TruncateWords("one two three", 1, true)
        if result != "three"
            throw Error("maxWords=1 fromEnd should return last word only: " result)
    }

    ; ======================================================
    ; _TruncateWords — newline preservation (regression: \n must survive truncation)
    ; ======================================================

    TruncateWords_PreservesNewlines() {
        text := "line1`nline2`nline3`nline4`nline5"
        result := TextCapture._TruncateWords(text, 3, false)
        ; First 3 "words" (each line is a word since \n is whitespace)
        if result != "line1`nline2`nline3"
            throw Error("Newlines should be preserved in truncated text: " result)
    }

    TruncateWords_PreservesNewlinesFromEnd() {
        text := "line1`nline2`nline3`nline4`nline5"
        result := TextCapture._TruncateWords(text, 3, true)
        if result != "line3`nline4`nline5"
            throw Error("Newlines preserved from end: " result)
    }

    TruncateWords_ExpandNewlinesCombo() {
        ; Simulate what happens after NormalizeLineEndings with expandSingle:
        ; single \n between paragraphs becomes \n\n
        text := "para1`n`npara2`n`npara3`n`npara4"
        result := TextCapture._TruncateWords(text, 2, false)
        if result != "para1`n`npara2"
            throw Error("Double-newline paragraphs should survive truncation: " result)
    }

    TruncateWords_CodeWithIndent() {
        text := "    def foo():`n        pass`n`n    def bar():`n        return 1"
        result := TextCapture._TruncateWords(text, 3, false)
        ; "def"(1) "foo():"(2) "pass"(3) — with original whitespace
        if result != "    def foo():`n        pass"
            throw Error("Code indentation should survive truncation: " result)
    }

    TruncateWords_LeadingWhitespace_FromEnd() {
        result := TextCapture._TruncateWords("   hello world foo bar", 3, true)
        ; fromEnd takes last 3 words: "world foo bar" from their start position
        if result != "world foo bar"
            throw Error("fromEnd should skip leading whitespace of truncated prefix: " result)
    }

    TruncateWords_OneWord_WithLeadingSpace() {
        result := TextCapture._TruncateWords("   hello", 1, false)
        ; Single word with leading spaces: slice includes them
        if result != "   hello"
            throw Error("Single word with leading whitespace: " result)
    }

    TruncateWords_OneWord_WithLeadingSpace_FromEnd() {
        ; 1 word with maxWords=1: unchanged (word count ≤ limit)
        result := TextCapture._TruncateWords("   hello", 1, true)
        if result != "   hello"
            throw Error("Single word fromEnd at limit, unchanged: " result)
    }

    TruncateWords_OnlyWhitespace() {
        result := TextCapture._TruncateWords("   `n`n  ", 5)
        ; No words found — wordStarts is empty, empty.Length(0) <= 5 → return unchanged
        if result != "   `n`n  "
            throw Error("Whitespace-only text should pass through unchanged: " result)
    }

    ; ======================================================
    ; NormalizeLineEndings → _TruncateWords pipeline (expandNewlines combo)
    ; ======================================================

    NormalizeThenTruncate_CRLF() {
        ; CRLF text → normalize → truncate
        text := TextCapture.NormalizeLineEndings("line1`r`nline2`r`nline3`r`nline4", false)
        result := TextCapture._TruncateWords(text, 2, false)
        if result != "line1`nline2"
            throw Error("CRLF normalized then truncated: " result)
    }

    NormalizeThenTruncate_CRLF_FromEnd() {
        text := TextCapture.NormalizeLineEndings("line1`r`nline2`r`nline3`r`nline4", false)
        result := TextCapture._TruncateWords(text, 2, true)
        if result != "line3`nline4"
            throw Error("CRLF normalized then truncated from end: " result)
    }

    NormalizeThenTruncate_ExpandSingle() {
        ; Single \n between paragraphs → expanded to \n\n → truncated
        text := TextCapture.NormalizeLineEndings("para1`npara2`npara3`npara4", true)
        ; After expansion: "para1\n\npara2\n\npara3\n\npara4"
        result := TextCapture._TruncateWords(text, 3, false)
        ; 3 words: para1, para2, para3 — with \n\n between them
        if result != "para1`n`npara2`n`npara3"
            throw Error("ExpandSingle then truncate: " result)
    }

    NormalizeThenTruncate_ExpandSingle_FromEnd() {
        text := TextCapture.NormalizeLineEndings("para1`npara2`npara3`npara4", true)
        result := TextCapture._TruncateWords(text, 2, true)
        if result != "para3`n`npara4"
            throw Error("ExpandSingle then truncate from end: " result)
    }

    NormalizeThenTruncate_BareCR() {
        ; Bare CR → normalized to \n → truncated
        text := TextCapture.NormalizeLineEndings("line1`rline2`rline3", false)
        result := TextCapture._TruncateWords(text, 2, false)
        if result != "line1`nline2"
            throw Error("Bare CR normalized then truncated: " result)
    }

    NormalizeThenTruncate_MixedEndings() {
        ; Mixed \r\n, \r, \n → all normalized to \n
        text := TextCapture.NormalizeLineEndings("a`r`nb`rc`n", false)
        ; After normalization: "a\nb\nc\n" — 3 words, truncated to 2
        ; Trailing \n from original preserved
        result := TextCapture._TruncateWords(text, 2, false)
        if result != "a`nb`n"
            throw Error("Mixed endings normalized then truncated: " result)
    }

    ; ======================================================
    ; _TruncateAround — behavioral (pure function)
    ; ======================================================

    TruncateAround_SelectionFound_Truncates() {
        fullText := "aa bb cc dd SELECTION ee ff gg hh ii"
        result := TextCapture._TruncateAround(fullText, "SELECTION", 4)
        ; 4 words total context: 2 before (cc dd) + SELECTION + 2 after (ee ff)
        if result != "cc dd SELECTION ee ff"
            throw Error("Got: " result)
    }

    TruncateAround_SelectionNotFound_ReturnsFull() {
        result := TextCapture._TruncateAround("the quick brown fox", "MISSING", 4)
        if result != "the quick brown fox"
            throw Error("Should return full text when selection not found: " result)
    }

    TruncateAround_OddContextWords() {
        fullText := "a b c d e SELECTION f g h i j"
        result := TextCapture._TruncateAround(fullText, "SELECTION", 5)
        ; 5 words total: 2 before (d e) + SELECTION + 3 after (f g h)
        if result != "d e SELECTION f g h"
            throw Error("Odd maxContextWords should give extra word to after: " result)
    }

    TruncateAround_OneContextWord() {
        fullText := "a b SELECTION c d"
        result := TextCapture._TruncateAround(fullText, "SELECTION", 1)
        ; 1 word total: 0 before + SELECTION + 1 after (c)
        if result != "SELECTION c"
            throw Error("maxContextWords=1 should give 1 after word: " result)
    }

    TruncateAround_NoLimit_ReturnsFull() {
        result := TextCapture._TruncateAround("a b c SELECTION d e f", "SELECTION", 0)
        if result != "a b c SELECTION d e f"
            throw Error("maxContextWords=0 should return full text: " result)
    }

    TruncateAround_NewlinesPreserved() {
        fullText := "line1`nline2`nline3`nSELECTION`nline4`nline5`nline6"
        result := TextCapture._TruncateAround(fullText, "SELECTION", 4)
        ; 2 before (line2, line3) + SELECTION + 2 after (line4, line5)
        ; Whitespace (\n) between words preserved by character-slice
        if result != "line2`nline3`nSELECTION`nline4`nline5"
            throw Error("Newlines around selection should be preserved: " result)
    }

    TruncateAround_SelectionAtStart() {
        ; Selection at position 1 — no "before" text
        fullText := "SELECTION a b c d e"
        result := TextCapture._TruncateAround(fullText, "SELECTION", 3)
        ; 1 before (none) + SELECTION + 2 after (a, b)
        if result != "SELECTION a b"
            throw Error("Selection at start: " result)
    }

    TruncateAround_SelectionAtEnd() {
        ; Selection at end — no "after" text, half=1 → 1 before word
        fullText := "a b c d e SELECTION"
        result := TextCapture._TruncateAround(fullText, "SELECTION", 3)
        ; half=1 before (e) + SELECTION + 0 after (empty, words allocated to after wasted)
        if result != "e SELECTION"
            throw Error("Selection at end: " result)
    }

    TruncateAround_EvenTwo() {
        ; maxContextWords=2: 1 before + SELECTION + 1 after
        fullText := "a b SELECTION c d"
        result := TextCapture._TruncateAround(fullText, "SELECTION", 2)
        if result != "b SELECTION c"
            throw Error("maxContextWords=2 even split: " result)
    }

    TruncateAround_ExpandNewlinesCombo() {
        ; Full pipeline: normalize with expandSingle → truncate around selection
        fullText := TextCapture.NormalizeLineEndings(
            "intro`nbody1`nbody2`nTARGET`noutro1`noutro2`nend", true)
        ; After expansion: "intro\n\nbody1\n\nbody2\n\nTARGET\n\noutro1\n\noutro2\n\nend"
        result := TextCapture._TruncateAround(fullText, "TARGET", 4)
        ; 2 before (body1, body2) + TARGET + 2 after (outro1, outro2)
        ; \n\n between words is preserved by character-slice
        if result != "body1`n`nbody2`n`nTARGET`n`noutro1`n`noutro2"
            throw Error("ExpandNewlines around selection: " result)
    }

    ; ======================================================
    ; ExpandTemplate — behavioral
    ; ======================================================

    ExpandTemplate_DuplicatePlaceholders() {
        result := TextCapture.ExpandTemplate(
            "{{selection}} + {{selection}}", "x")
        if result != "x + x"
            throw Error("Got: " result)
    }

    ExpandTemplate_PartialPlaceholder_NotExpanded() {
        result := TextCapture.ExpandTemplate(
            "{{selection_extra}} {{fullText_extra}}", "sel", "full")
        if result != "{{selection_extra}} {{fullText_extra}}"
            throw Error("Got: " result)
    }

    ; ======================================================
    ; _CaptureChat — structural (UIA-dependent, guard rails)
    ; ======================================================

    Chat_AllowsEmptyUserMessage() {
        src := TextCaptureTest._ReadSrc()
        method := TextCaptureTest._ExtractMethod(src, "_CaptureSelection(")

        ; Must not return error when userMessage is empty
        if InStr(method, 'error: "The attempt to copy')
            throw Error("_CaptureChat must allow empty userMessage (templates may use only {{input}} or {{fullText}})")
        ; Success return must not require userMessage
        if !InStr(method, "success: true")
            throw Error("_CaptureChat must return success even with empty userMessage")
    }

    Chat_HasFullTextClipboardFallback() {
        src := TextCaptureTest._ReadSrc()
        method := TextCaptureTest._ExtractMethod(src, "_CaptureSelection(")

        ; Must have ^a^c fallback for fullText
        if !InStr(method, 'Send("^a")')
            throw Error("_CaptureChat must have ^a fallback for fullText")
        if !InStr(method, "fullText :=")
            throw Error("_CaptureChat must populate fullText")
    }

    Chat_LazyFullText_ChecksIncludeFullText() {
        src := TextCaptureTest._ReadSrc()
        method := TextCaptureTest._ExtractMethod(src, "_CaptureSelection(")

        ; fullText capture must be guarded by includeFullText param
        if !InStr(method, "includeFullText")
            throw Error("_CaptureChat must check includeFullText before capturing fullText")
    }

    ; Regression (bug #231): _CaptureSelection must ALWAYS expand single
    ; newlines in the captured selection and fullText - the toggle-driven
    ; normalization left web selections with single-\n paragraph breaks.
    CaptureSelection_AlwaysExpandsSingleNewlines() {
        src := TextCaptureTest._ReadSrc()
        method := TextCaptureTest._ExtractMethod(src, "_CaptureSelection(")
        if !RegExMatch(method, "NormalizeLineEndings\(userMessage,\s*true\)")
            throw Error("_CaptureSelection must always expand single newlines in userMessage (bug #231)")
        if !RegExMatch(method, "NormalizeLineEndings\(fullText,\s*true\)")
            throw Error("_CaptureSelection must always expand single newlines in fullText (bug #231)")
        if RegExMatch(method, "NormalizeLineEndings\((?:userMessage|fullText),\s*expandNewlines\)")
            throw Error("_CaptureSelection must not use the command toggle for non-FIM capture (bug #231)")
    }

    ; ======================================================
    ; ExpandTemplate in _CaptureChat (structural)
    ; ======================================================

    Chat_UsesExpandTemplate() {
        src := TextCaptureTest._ReadSrc()
        ; Check that ExpandTemplate exists as a separate method
        method := TextCaptureTest._ExtractMethod(src, "ExpandTemplate(")

        if !InStr(method, "{{selection}}")
            throw Error("ExpandTemplate must handle {{selection}}")
        if !InStr(method, "{{fullText}}")
            throw Error("ExpandTemplate must handle {{fullText}}")
        if !InStr(method, "{{input}}")
            throw Error("ExpandTemplate must handle {{input}}")
    }

    ; ======================================================
    ; Capture signature — accepts includeFullText
    ; ======================================================

    Capture_AcceptsIncludeFullText() {
        src := TextCaptureTest._ReadSrc()
        method := TextCaptureTest._ExtractMethod(src, "Capture(")

        if !InStr(method, "includeFullText")
            throw Error("Capture must accept includeFullText parameter")
    }

    Capture_AcceptsExpandNewlines() {
        src := TextCaptureTest._ReadSrc()
        method := TextCaptureTest._ExtractMethod(src, "Capture(")
        if !InStr(method, "expandNewlines")
            throw Error("Capture must accept expandNewlines parameter")
    }

    ; ======================================================
    ; FIM Fill (unchanged, guard rails)
    ; ======================================================

    Fill_UsesUIATextPattern() {
        src := TextCaptureTest._ReadSrc()
        method := TextCaptureTest._ExtractMethod(src, "_CaptureFIM_Fill")

        if !InStr(method, "_AcquireTextPattern()")
            throw Error("_CaptureFIM_Fill must use _AcquireTextPattern()")
        if !InStr(method, "_SplitAt")
            throw Error("_CaptureFIM_Fill must use _SplitAt helper")

        if InStr(method, "^+{Home}")
            throw Error("_CaptureFIM_Fill must NOT use ^+{Home}")
        if InStr(method, "+^{End}")
            throw Error("_CaptureFIM_Fill must NOT use +^{End}")

        if !InStr(method, 'SendInput("^x")')
            throw Error("_CaptureFIM_Fill must use SendInput(^x)")
    }

    ; ======================================================
    ; FIM Continue (unchanged, guard rails)
    ; ======================================================

    Continue_CopyPath_SetsNeedsDeselect() {
        src := TextCaptureTest._ReadSrc()
        method := TextCaptureTest._ExtractMethod(src, "_CaptureFIM_Continue")
        if !InStr(method, "needsDeselect: true")
            throw Error("_CaptureFIM_Continue ^c path must set needsDeselect: true")
    }

    Continue_UIAFallback_SetsNeedsDeselectFalse() {
        src := TextCaptureTest._ReadSrc()
        method := TextCaptureTest._ExtractMethod(src, "_CaptureFIM_Continue")
        if !InStr(method, "needsDeselect: false")
            throw Error("_CaptureFIM_Continue UIA fallback must set needsDeselect: false")
    }

    Continue_UIAFallback_UsesTextPattern() {
        src := TextCaptureTest._ReadSrc()
        method := TextCaptureTest._ExtractMethod(src, "_CaptureFIM_Continue")
        if !InStr(method, "_AcquireTextPattern()")
            throw Error("_CaptureFIM_Continue UIA fallback must use _AcquireTextPattern()")
        if InStr(method, "^+{Home}")
            throw Error("_CaptureFIM_Continue must NOT use ^+{Home}")
    }

    CaptureFIM_RoutesToFill_ForReplace() {
        src := TextCaptureTest._ReadSrc()
        method := TextCaptureTest._ExtractMethod(src, "_CaptureFIM(")
        if !InStr(method, 'pasteMode = "replace"')
            throw Error("_CaptureFIM must check pasteMode = replace")
        if !InStr(method, "_CaptureFIM_Fill")
            throw Error("_CaptureFIM must route replace to _CaptureFIM_Fill")
        if !InStr(method, "_CaptureFIM_Continue")
            throw Error("_CaptureFIM must route append to _CaptureFIM_Continue")
    }

    ; ======================================================
    ; Helper guards
    ; ======================================================

    Helper_AcquireTextPattern() {
        src := TextCaptureTest._ReadSrc()
        method := TextCaptureTest._ExtractMethod(src, "_AcquireTextPattern(")
        if !InStr(method, "UIA.GetFocusedElement()")
            throw Error("_AcquireTextPattern must use UIA.GetFocusedElement()")
        if !InStr(method, "IsTextPatternAvailable")
            throw Error("_AcquireTextPattern must check IsTextPatternAvailable")
        if !InStr(method, "el.TextPattern")
            throw Error("_AcquireTextPattern must access .TextPattern")
    }

    Helper_SplitAt() {
        src := TextCaptureTest._ReadSrc()
        method := TextCaptureTest._ExtractMethod(src, "_SplitAt(")
        if !InStr(method, "MoveEndpointByRange")
            throw Error("_SplitAt must use MoveEndpointByRange")
    }

    ; --- Helpers ---

    static _ReadSrc() {
        srcPath := A_ScriptDir "\..\app\TextCapture.ahk"
        if !FileExist(srcPath)
            throw Error("TextCapture.ahk not found at: " srcPath)
        return FileRead(srcPath)
    }

    static _ExtractMethod(src, methodName) {
        pos := InStr(src, "static " methodName)
        if !pos
            throw Error("Method static " methodName " not found in TextCapture.ahk")
        return SubStr(src, pos, 5000)
    }

}
