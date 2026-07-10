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
        return SubStr(src, pos, 2500)
    }

}
