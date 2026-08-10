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

        ; Find the paste block: locate "NormalizeLineEndings(result.response.response"
        pasteStartPos := InStr(src, "NormalizeLineEndings(result.response.response")
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
    }

    ; Verifies that runOptionsMenuAction handles the "apilogs:" special command.
    OptionsMenu_HandlesApiLogsCommand() {
        srcPath := A_ScriptDir "\..\app\RequestProcessor.ahk"
        if !FileExist(srcPath)
            throw Error("RequestProcessor.ahk not found at: " srcPath)
        src := FileRead(srcPath)

        if !InStr(src, '"apilogs:"')
            throw Error("runOptionsMenuAction must handle apilogs: command")
        if !InStr(src, "ShowApiLogs()")
            throw Error("runOptionsMenuAction must call ShowApiLogs() for apilogs:")
        ; Verifies that FIM path is guarded against accessing captured.userMessage.
        ; Regression: FIM captures return {prefix, suffix} — no userMessage property.
        ; The userMessage template block must be wrapped in `if !isFIM`.
        FIMCapture_GuardsUserMessageAccess() {
            srcPath := A_ScriptDir "\..\app\RequestProcessor.ahk"
            if !FileExist(srcPath)
                throw Error("RequestProcessor.ahk not found at: " srcPath)
            src := FileRead(srcPath)
    
            ; Find the user message composition block: "Compose user message from template"
            templateStart := InStr(src, "Compose user message from template")
            if !templateStart
                throw Error("User message template block not found in RequestProcessor.ahk")
    
            ; Extract a window around the template block
            block := SubStr(src, templateStart, 500)
    
            ; The block must guard with !isFIM before accessing captured.userMessage
            if !InStr(block, "if !isFIM")
                throw Error("FIM guard (!isFIM) missing in user message template block — FIM captures have no userMessage")
    
            ; Verify the guard appears BEFORE the first captured.userMessage access in the block
            guardPos := InStr(block, "if !isFIM")
            firstAccessPos := InStr(block, "captured.userMessage")
            if guardPos > firstAccessPos
                throw Error("FIM guard (!isFIM) appears AFTER captured.userMessage access — guard must come first")
        }
    
    }

    ; Verifies that Sleep exists after ^v for scroll-to-cursor stability
    FIMPaste_HasSleepAfterPaste() {
        srcPath := A_ScriptDir "\..\app\InlineRequestRunner.ahk"
        src := FileRead(srcPath)
        pasteStartPos := InStr(src, "NormalizeLineEndings(result.response.response")
        pasteBlock := SubStr(src, pasteStartPos, 2500)

        pastePos := InStr(pasteBlock, 'Send("^v")')
        leftRightPos := InStr(pasteBlock, 'Send("{Left}{Right}")')

        if leftRightPos {
            between := SubStr(pasteBlock, pastePos + 10, leftRightPos - pastePos - 10)
            if !InStr(between, "Sleep")
                throw Error("No Sleep between Send(`"^v`") and Send(`"{Left}{Right}`") in paste block")
        }
    }

    ; Regression (bug #162): the command dropdown's "Default" option stores an
    ; EMPTY APIModels string. StrSplit("") returns an empty array, so
    ; processInitialRequest's request loop never ran - the command was a
    ; silent no-op. The parser must substitute the app default model.
    DefaultModel_SubstitutesAppDefault() {
        srcPath := A_ScriptDir "\..\app\RequestProcessor.ahk"
        src := FileRead(srcPath)
        modelsStart := InStr(src, "APIModelsArr := StrSplit")
        if !modelsStart
            throw Error("model parsing block not found in RequestProcessor.ahk")
        block := SubStr(src, modelsStart, 800)
        if !InStr(block, "appDefaultModel")
            throw Error("empty APIModels must fall back to appDefaultModel (bug #162)")
        if !RegExMatch(block, "APIModelsArr\.Length = 0")
            throw Error("empty-array guard missing in model parsing (bug #162)")
    }

    ; Regression (bug #36): a chat-mode command whose model equals the app
    ; default must still persist its temperature/reasoning overrides.
    ; processInitialRequest previously nested the whole Thread_UpdateSettings
    ; call inside `if fullAPIModelName != appDefaultModel`, so default-model
    ; commands silently dropped temperature/reasoning (the fired request used
    ; the model defaults).
    ChatModeCommand_PersistsOverridesWhenModelEqualsDefault() {
        srcPath := A_ScriptDir "\..\app\RequestProcessor.ahk"
        src := FileRead(srcPath)

        gatePos := InStr(src, "if fullAPIModelName != appDefaultModel")
        if !gatePos
            throw Error("model-default gate not found in RequestProcessor.ahk")

        ; The gate block must not contain temperature/reasoning/system overrides
        ; (only modelOverride is redundant when the model equals the default).
        gateBlock := SubStr(src, gatePos, 500)
        if InStr(gateBlock, "temperatureOverride") || InStr(gateBlock, "reasoningOverride") || InStr(gateBlock, "systemOverride")
            throw Error("overrides still nested inside the model-default gate (bug #36 not fixed)")

        ; The unconditional settings object must carry the overrides.
        objPos := InStr(src, "commandThreadSettings := {")
        if !objPos
            throw Error("unconditional command settings object not found in RequestProcessor.ahk")
        objBlock := SubStr(src, objPos, 500)
        if !InStr(objBlock, "temperatureOverride") || !InStr(objBlock, "reasoningOverride")
            throw Error("temperature/reasoning overrides missing from the unconditional command settings object")
    }

}
