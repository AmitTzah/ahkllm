; ----------------------------------------------------
; InlineRequestRunner tests — verify HighlightInsertedText
; uses UIA TextPattern (no keystroke-based selection).
; ----------------------------------------------------

#Include ..\..\app\InlineRequestRunner.ahk

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

    ; Regression (bug #46): a replace/append command with "Stream Response" ON
    ; used to send stream:true in the request body while the inline runner
    ; still executed a single-shot cURL and parsed the whole output as one JSON
    ; document. The API then answered SSE, the parse failed, and nothing was
    ; pasted. The runner must build its request with stream=false.
    NonFimRequest_BuildsWithoutStream() {
        srcPath := A_ScriptDir "\..\app\InlineRequestRunner.ahk"
        src := FileRead(srcPath)

        buildPos := InStr(src, "static _BuildAndWriteRequest(")
        if !buildPos
            throw Error("_BuildAndWriteRequest not found in InlineRequestRunner.ahk")
        buildBlock := SubStr(src, buildPos, 2200)

        if !InStr(buildBlock, "LLMRequestBuilder.createJSONRequest(")
            throw Error("non-FIM path must use LLMRequestBuilder.createJSONRequest")
        if !InStr(buildBlock, "temperature, maxTokens, stop, false, thinking, thinkingLevel)")
            throw Error("non-FIM request must build with stream=false (bug #46); passing the stream flag makes the API answer SSE the single-shot parser cannot read")
    }

    ; Regression (inline silent failure): a failed inline request must surface
    ; an error (tooltip + API-log error entry) instead of silently doing
    ; nothing - no paste, no message, nothing in the API log.
    Run_HasFailureBranch() {
        srcPath := A_ScriptDir "\..\app\InlineRequestRunner.ahk"
        src := FileRead(srcPath)
        runBlock := SubStr(src, InStr(src, "static Run(commandName"), 2600)
        if !InStr(runBlock, "result.success")
            throw Error("Run must branch on result.success")
        if !InStr(runBlock, "_HandleInlineError(")
            throw Error("Run must surface failed inline requests via _HandleInlineError")
    }

    ; Regression: the loading tooltip promises "Press ESC to cancel" for
    ; inline replace/append/FIM commands. Those commands run synchronously in
    ; Main and previously had no Escape handling at all, so whether ESC worked
    ; depended on the command using chat mode instead.
    InlineRun_PollsEscapeAndTreatsCancelSeparately() {
        srcPath := A_ScriptDir "\..\app\InlineRequestRunner.ahk"
        curlPath := A_ScriptDir "\..\api\CurlExecutor.ahk"
        src := FileRead(srcPath)
        curlSrc := FileRead(curlPath)

        executePos := InStr(src, 'static _ExecuteCurlAndParse(files, isFIM, cancelState := "")')
        if !executePos
            throw Error("inline executor must accept cancellation state")
        executeBlock := SubStr(src, executePos, 2200)
        if !InStr(executeBlock, "CurlExecutor.Run(cURLCommand, files.outputFile, 25, cancelState)")
            throw Error("inline commands must poll cancellation frequently enough to catch a normal Escape tap")

        runBlock := SubStr(src, InStr(src, "static Run(commandName"), 4200)
        cancelPos := InStr(runBlock, "if result.cancelled")
        successPos := InStr(runBlock, "else if result.success")
        errorPos := InStr(runBlock, "_HandleInlineError(")
        if !cancelPos || !successPos || !errorPos || !(cancelPos < successPos && successPos < errorPos)
            throw Error("cancelled inline requests must bypass both paste and failure handling")
        if !InStr(src, 'status: "cancelled"')
            throw Error("inline cancellation should be logged as cancelled, not error")

        if !InStr(curlSrc, 'GetKeyState("Esc", "P")')
            throw Error("CurlExecutor must observe the physical Escape key for global inline cancellation")
        if !InStr(curlSrc, "taskkill /PID") || !InStr(curlSrc, "/T /F")
            throw Error("inline cancellation must terminate the cmd+cURL process tree")
        if !InStr(curlSrc, "cancelState.cancelled := true")
            throw Error("CurlExecutor must report cancellation back to InlineRequestRunner")
    }

    FIMWithoutEndpoint_IsRejectedBeforeCurl() {
        srcPath := A_ScriptDir "\..\app\InlineRequestRunner.ahk"
        src := FileRead(srcPath)
        runBlock := SubStr(src, InStr(src, "static Run(commandName"), 1200)
        if !InStr(runBlock, "isFIM && !providerInfo.fimEndpoint")
            throw Error("FIM commands must be rejected when the provider has no explicit FIM endpoint")
        if !InStr(src, "_HandleUnsupportedFIM(")
            throw Error("Unsupported FIM must have a user-facing error path")
        if !InStr(src, "normal chat endpoint is not a safe fallback")
            throw Error("Unsupported FIM guard must document the no-chat-fallback rule")
    }

    FIMWithoutEndpoint_ShowsUsefulError() {
        global _mockToolTipCalls
        _mockToolTipCalls := []
        InlineRequestRunner.Run("FIM Fill", "openrouter/free", "openrouter", "free", {}, true, "", "replace", "", "", "", false, "")
        found := false
        for _, msg in _mockToolTipCalls {
            if InStr(msg, "FIM is not supported by OpenRouter") && InStr(msg, "free")
                found := true
        }
        if !found
            throw Error("Unsupported FIM should show a specific OpenRouter capability error")
    }

    Run_UsesUniqueId() {
        srcPath := A_ScriptDir "\..\app\InlineRequestRunner.ahk"
        src := FileRead(srcPath)
        runBlock := SubStr(src, InStr(src, "static Run(commandName"), 1000)
        if !InStr(runBlock, "ChatDB._UUID()")
            throw Error("Run must use a unique per-request id - A_TickCount collides for commands started in the same millisecond")
    }

    FailedRequest_ShowsErrorAndLogs() {
        global _mockToolTipCalls, apiLogMaxEntries
        oldLogPath := ApiLogger.logFilePath
        oldMax := apiLogMaxEntries
        ApiLogger.logFilePath := A_Temp "\test_inline_api_log_" A_TickCount "_" Random(1000, 999999) ".json"
        apiLogMaxEntries := 5
        try FileDelete(ApiLogger.logFilePath)
        _mockToolTipCalls := []
        errFile := A_Temp "\test_inline_err_" A_TickCount "_" Random(1000, 999999) ".txt"
        FileAppend("curl: (7) Failed to connect to 127.0.0.1 port 12345: Connection refused", errFile, "UTF-8")
        try {
            files := {
                errorFile: errFile,
                endpoint: "https://api.test",
                requestJSON: "{}",
                outputFile: A_Temp "\test_inline_out_" A_TickCount "_" Random(1000, 999999) ".json"
            }
            InlineRequestRunner._HandleInlineError({ rawJSON: "", responseTimeMs: 123 }, files, "My Command", "deepseek", "deepseek-v4-flash", false, "replace")
            found := false
            for _, msg in _mockToolTipCalls {
                if InStr(msg, "My Command") && InStr(msg, "Connection refused")
                    found := true
            }
            if !found
                throw Error("failed inline command must show a tooltip with the stderr message")
            raw := FileRead(ApiLogger.logFilePath, "UTF-8")
            if !InStr(raw, '"status":"error"') || !InStr(raw, "Connection refused")
                throw Error("failed inline command must be logged as an API error")
        } finally {
            ApiLogger.logFilePath := oldLogPath
            apiLogMaxEntries := oldMax
            try FileDelete(ApiLogger.logFilePath)
            try FileDelete(errFile)
        }
    }

}

RegisterTestClass("InlineRequestRunnerTest")
