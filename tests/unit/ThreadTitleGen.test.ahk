; ======================================================
; ThreadTitleGen.test.ahk — Unit tests for chat/ThreadTitleGen.ahk
;
; ThreadTitleGen is only #Included by ChatWindow.ahk, so the test
; harness never loaded it before. These tests exercise every function
; in the module: the fire-and-forget generateThreadTitle() flow plus
; the _TitleGen_* helpers.
;
; The cURL execution built-ins (Run/ProcessExist/Sleep) are replaced
; with script-level mocks: Run extracts the -o output path from the
; generated command and writes a canned response there, which lets the
; real request/parse/usage/log pipeline run end to end.
; ======================================================

#Include ..\..\chat\ThreadTitleGen.ahk

; --- Script-level mocks for cURL execution built-ins ---
Run(cmd, workDir := "", options := "", &outPID := 0) {
    global _mockRunCalls, _mockTitleGenOutput
    _mockRunCalls.Push(cmd)
    if _mockTitleGenOutput != "" && RegExMatch(cmd, '-o "([^"]+)"', &m) {
        FileAppend(_mockTitleGenOutput, m[1], "UTF-8")
    }
    outPID := 9001
}

ProcessExist(pid) {
    return 0
}

Sleep(ms) {
    return
}

class ThreadTitleGenTest {

    static __New() {
        RegisterTestClass("ThreadTitleGenTest")
    }

    _setupDb() {
        if ChatDB.isOpen {
            oldPath := ChatDB.dbPath
            ChatDB.Close()
            try FileDelete(oldPath)
        }
        ChatDB.Open(A_Temp "\test_titlegen_" A_TickCount ".db")
    }

    _teardownDb() {
        if ChatDB.isOpen {
            dbPath := ChatDB.dbPath
            ChatDB.Close()
            try FileDelete(dbPath)
        }
    }

    _setGlobals() {
        global autoTitleGenerationEnabled, titleGenModel, titleGenSystemPrompt, titleGenMaxTokens
        autoTitleGenerationEnabled := true
        titleGenModel := "deepseek/deepseek-v4-flash"
        titleGenSystemPrompt := "Summarize the conversation into a short title."
        titleGenMaxTokens := 50
    }

    _captureWebView() {
        global responseWindow
        captured := []
        oldResponseWindow := responseWindow
        ; AHK v2 passes the receiver object as the first argument when calling
        ; a function stored in an object property, hence the leading param.
        responseWindow := { PostWebMessageAsJSON: (obj, json) => captured.Push(json) }
        return { captured: captured, restore: (obj) => (responseWindow := oldResponseWindow) }
    }

    Generate_Disabled_Returns() {
        global autoTitleGenerationEnabled, _mockRunCalls
        this._setupDb()
        this._setGlobals()
        autoTitleGenerationEnabled := false
        _mockRunCalls := []
        generateThreadTitle(ChatDB.Thread_Create("Disabled"))
        if _mockRunCalls.Length != 0
            throw Error("Disabled title gen should not run cURL")
        this._teardownDb()
    }

    Generate_NoModel_Returns() {
        global titleGenModel, _mockRunCalls
        this._setupDb()
        this._setGlobals()
        titleGenModel := ""
        _mockRunCalls := []
        generateThreadTitle(ChatDB.Thread_Create("NoModel"))
        if _mockRunCalls.Length != 0
            throw Error("Empty model should abort title gen")
        this._teardownDb()
    }

    Generate_NoPrompt_Returns() {
        global _mockRunCalls
        this._setupDb()
        this._setGlobals()
        threadId := ChatDB.Thread_Create("NoPrompt")
        ChatDB.Msg_Insert({ thread_id: threadId, role: "user", content: "Only a user message" })
        _mockRunCalls := []
        generateThreadTitle(threadId)
        if _mockRunCalls.Length != 0
            throw Error("Single-message thread should not run cURL")
        this._teardownDb()
    }

    Generate_Success_TitlesThread() {
        global _mockTitleGenOutput, _mockRunCalls
        this._setupDb()
        this._setGlobals()
        threadId := ChatDB.Thread_Create("Title Gen Test")
        sysId := ChatDB.Msg_Insert({ thread_id: threadId, role: "system", content: "You are helpful." })
        usrId := ChatDB.Msg_Insert({ thread_id: threadId, role: "user", content: "Hello world", parent_id: sysId })
        ChatDB.Msg_Insert({ thread_id: threadId, role: "assistant", content: "Hi there!", parent_id: usrId })

        _mockTitleGenOutput := '{"choices":[{"message":{"content":"\"My Great Title\""}}],"usage":{"prompt_tokens":12,"completion_tokens":7,"completion_tokens_details":{"reasoning_tokens":3}}}'
        _mockRunCalls := []
        web := this._captureWebView()
        try {
            generateThreadTitle(threadId)
        } finally {
            web.restore()
        }

        if _mockRunCalls.Length != 1
            throw Error("Expected exactly one cURL Run call, got " _mockRunCalls.Length)

        titlePosted := false
        listPosted := false
        for _, json in web.captured {
            if InStr(json, "updateTopbarTitle") && InStr(json, "My Great Title")
                titlePosted := true
            if InStr(json, "threadList")
                listPosted := true
        }
        if !titlePosted
            throw Error("Expected updateTopbarTitle with cleaned title")
        if !listPosted
            throw Error("Expected threadList refresh after title update")

        ; Usage must be tracked under "Title Generation"
        usage := ChatDB.Usage_Query(Map("timeRange", "all", "model", "", "type", "command"))
        found := false
        for cmd in usage.commands {
            if cmd.command_name = "Title Generation" {
                found := true
                if cmd.prompt_tokens != 12 || cmd.completion_tokens != 7 || cmd.thinking_tokens != 3
                    throw Error("Title gen usage tokens wrong")
            }
        }
        if !found
            throw Error("Title generation usage row not found")

        this._teardownDb()
    }

    Generate_EmptyResponse_NoTitle() {
        global _mockTitleGenOutput, _mockRunCalls
        this._setupDb()
        this._setGlobals()
        threadId := ChatDB.Thread_Create("Empty Resp")
        sysId := ChatDB.Msg_Insert({ thread_id: threadId, role: "system", content: "You are helpful." })
        usrId := ChatDB.Msg_Insert({ thread_id: threadId, role: "user", content: "Hello", parent_id: sysId })
        ChatDB.Msg_Insert({ thread_id: threadId, role: "assistant", content: "Hi", parent_id: usrId })

        _mockTitleGenOutput := ""
        web := this._captureWebView()
        try {
            generateThreadTitle(threadId)
        } finally {
            web.restore()
        }

        for _, json in web.captured {
            if InStr(json, "updateTopbarTitle")
                throw Error("Empty response must not publish a title")
        }
        ; Thread title must remain unchanged
        title := ""
        for t in ChatDB.Thread_List() {
            if t.id = threadId
                title := t.title
        }
        if title != "Empty Resp"
            throw Error("Thread title should be unchanged, got '" title "'")
        this._teardownDb()
    }

    ; ----------------------------------------------------
    ; Regression: title generation must post the thread's REAL folder name,
    ; not the hardcoded "Unfiled" that previously overwrote the topbar label.
    ; ----------------------------------------------------
    Generate_Success_PostsRealFolder() {
        global _mockTitleGenOutput, _mockRunCalls
        this._setupDb()
        this._setGlobals()
        threadId := ChatDB.Thread_Create("Folder Title")
        sysId := ChatDB.Msg_Insert({ thread_id: threadId, role: "system", content: "sys" })
        usrId := ChatDB.Msg_Insert({ thread_id: threadId, role: "user", content: "Hello", parent_id: sysId })
        ChatDB.Msg_Insert({ thread_id: threadId, role: "assistant", content: "Hi", parent_id: usrId })

        ; Move the thread into a folder (same SQL the sidebar folder actions use).
        ChatDB.db.Exec("INSERT INTO chat_folders (id, name) VALUES('fold-1', 'Work Folder');")
        ChatDB.db.Exec("UPDATE chat_threads SET folder_id='fold-1' WHERE id='" threadId "';")

        _mockTitleGenOutput := '{"choices":[{"message":{"content":"Folder Title"}}],"usage":{"prompt_tokens":4,"completion_tokens":2}}'
        web := this._captureWebView()
        try {
            generateThreadTitle(threadId)
        } finally {
            web.restore()
        }

        titlePosted := ""
        listPosted := ""
        for _, json in web.captured {
            if InStr(json, "updateTopbarTitle") {
                titlePosted := json
                break
            }
            if InStr(json, "threadList")
                listPosted := json
        }
        if !titlePosted
            throw Error("Expected updateTopbarTitle post")
        if !InStr(titlePosted, "Work Folder")
            throw Error("updateTopbarTitle should carry the real folder name, got: " titlePosted)
        if InStr(titlePosted, '"Unfiled"')
            throw Error("updateTopbarTitle must not hardcode Unfiled: " titlePosted)
        ; Regression: the threadList post must include the folders array so the
        ; sidebar keeps rendering folder groups (a bare threads array made the
        ; whole folder section — and its chats — disappear until re-render).
        if !listPosted
            throw Error("Expected threadList post after title update")
        if !InStr(listPosted, '"threads"') || !InStr(listPosted, '"folders"')
            throw Error("threadList post must carry threads + folders, got: " listPosted)
        if !InStr(listPosted, "Work Folder")
            throw Error("threadList folders should include Work Folder, got: " listPosted)

        this._teardownDb()
    }

    BuildPrompt_ReturnsTruncatedExchange() {
        this._setupDb()
        this._setGlobals()
        threadId := ChatDB.Thread_Create("BP")
        sysId := ChatDB.Msg_Insert({ thread_id: threadId, role: "system", content: "sys" })
        longUser := ""
        loop 250
            longUser .= "u"
        longAsst := ""
        loop 250
            longAsst .= "a"
        usrId := ChatDB.Msg_Insert({ thread_id: threadId, role: "user", content: longUser, parent_id: sysId })
        ChatDB.Msg_Insert({ thread_id: threadId, role: "assistant", content: longAsst, parent_id: usrId })

        prompt := _TitleGen_BuildPrompt(threadId)
        if InStr(prompt, "User: ") != 1
            throw Error("Prompt should start with User: ")
        if InStr(prompt, "`nAssistant: ") = 0
            throw Error("Prompt should contain the assistant section")
        if InStr(prompt, SubStr(longUser, 1, 200)) = 0
            throw Error("Prompt should truncate user content to 200 chars")
        if InStr(prompt, SubStr(longAsst, 1, 200)) = 0
            throw Error("Prompt should truncate assistant content to 200 chars")
        this._teardownDb()
    }

    BuildPrompt_TooFewMessages_ReturnsEmpty() {
        this._setupDb()
        this._setGlobals()
        threadId := ChatDB.Thread_Create("BP2")
        if _TitleGen_BuildPrompt(threadId) != ""
            throw Error("Empty thread should yield empty prompt")
        ChatDB.Msg_Insert({ thread_id: threadId, role: "user", content: "only user" })
        if _TitleGen_BuildPrompt(threadId) != ""
            throw Error("User-only thread should yield empty prompt")
        this._teardownDb()
    }

    CleanTitle_StripsQuotesAndPeriod() {
        if _TitleGen_CleanTitle('"Quoted."') != "Quoted"
            throw Error("Double-quoted title with period should strip both")
        if _TitleGen_CleanTitle("'Single'") != "Single"
            throw Error("Single-quoted title should strip quotes")
        if _TitleGen_CleanTitle("Trailing.") != "Trailing"
            throw Error("Trailing period should be removed")
        long := ""
        loop 70
            long .= "x"
        if StrLen(_TitleGen_CleanTitle(long)) != 60
            throw Error("Title should be truncated to 60 chars")
        if _TitleGen_CleanTitle("Plain") != "Plain"
            throw Error("Plain title should pass through")
        if _TitleGen_CleanTitle("'Lead only") != "Lead only"
            throw Error("Leading quote only should be stripped")
        if _TitleGen_CleanTitle("Tail only'") != "Tail only"
            throw Error("Trailing quote only should be stripped")
    }

    ParseResponse_EmptyRaw_ReturnsDefaults() {
        result := _TitleGen_ParseResponse("")
        if result.title != "" || result.promptTokens != 0 || result.completionTokens != 0 || result.thinkingTokens != 0
            throw Error("Empty raw should return default result")
    }

    ParseResponse_ExtractsTitleAndUsage() {
        raw := '{"choices":[{"message":{"content":"\"Title from API\""}}],"usage":{"prompt_tokens":5,"completion_tokens":9,"completion_tokens_details":{"reasoning_tokens":4}}}'
        result := _TitleGen_ParseResponse(raw)
        if result.title != "Title from API"
            throw Error("Title not extracted: '" result.title "'")
        if result.promptTokens != 5 || result.completionTokens != 9 || result.thinkingTokens != 4
            throw Error("Token usage not extracted")
    }

    ParseResponse_NoChoices_ReturnsEmptyTitle() {
        raw := '{"usage":{"prompt_tokens":2,"completion_tokens":1}}'
        result := _TitleGen_ParseResponse(raw)
        if result.title != ""
            throw Error("Missing choices should yield empty title")
        if result.promptTokens != 2 || result.completionTokens != 1 || result.thinkingTokens != 0
            throw Error("Usage without details should still parse")
    }

    ParseResponse_InvalidJson_ReturnsDefaults() {
        result := _TitleGen_ParseResponse("not json at all")
        if result.title != "" || result.promptTokens != 0
            throw Error("Invalid JSON should return defaults")
    }

    TrackUsage_SkipsZeroPromptTokens() {
        this._setupDb()
        _TitleGen_TrackUsage("deepseek/deepseek-v4-flash", "deepseek", 0, 5, 0, A_TickCount)
        usage := ChatDB.Usage_Query(Map("timeRange", "all", "model", "", "type", "command"))
        if usage.commands.Length != 0
            throw Error("Zero prompt tokens should not write usage")
        this._teardownDb()
    }

    TrackUsage_InsertsRow() {
        this._setupDb()
        start := A_TickCount
        _TitleGen_TrackUsage("deepseek/deepseek-v4-flash", "deepseek", 20, 10, 2, start)
        usage := ChatDB.Usage_Query(Map("timeRange", "all", "model", "", "type", "command"))
        if usage.commands.Length != 1
            throw Error("Expected one command usage row")
        cmd := usage.commands[1]
        if cmd.command_name != "Title Generation" || cmd.prompt_tokens != 20 || cmd.completion_tokens != 10 || cmd.thinking_tokens != 2
            throw Error("Usage row contents wrong")
        this._teardownDb()
    }

    LogRequest_WritesApiLog() {
        global apiLogMaxEntries
        oldLogPath := ApiLogger.logFilePath
        oldMax := apiLogMaxEntries
        ApiLogger.logFilePath := A_Temp "\test_titlegen_api_log_" A_TickCount ".json"
        apiLogMaxEntries := 5
        try FileDelete(ApiLogger.logFilePath)
        try {
            _TitleGen_LogRequest("deepseek/deepseek-v4-flash", "deepseek", "https://api.test", "{payload}", "raw-response", "A Title", A_TickCount)
            raw := FileRead(ApiLogger.logFilePath, "UTF-8")
            if !InStr(raw, "Thread Title Generation")
                throw Error("Api log should contain the title generation entry")
        } finally {
            ApiLogger.logFilePath := oldLogPath
            apiLogMaxEntries := oldMax
            try FileDelete(ApiLogger.logFilePath)
        }
    }

}
