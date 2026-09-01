; ======================================================
; ChatUtils.test.ahk — Unit tests for ChatUtils
;
; Tests: cURLState (cURL PID management),
;        postWebMessage format (not WebView — just JSON)
; ======================================================

class ChatUtilsTest {

    static __New() {
        RegisterTestClass("ChatUtilsTest")
    }

    _openDb() {
        if ChatDB.isOpen {
            oldPath := ChatDB.dbPath
            ChatDB.Close()
            try FileDelete(oldPath)
        }
        ChatDB.Open(A_Temp "\test_chat_utils_" A_TickCount "_" Random(1000, 999999) ".db")
    }

    _closeDb() {
        if ChatDB.isOpen {
            dbPath := ChatDB.dbPath
            ChatDB.Close()
            try FileDelete(dbPath)
        }
    }

    ; --------------------
    ; cURLState — cURL PID management
    ; --------------------

    cURLState_SetAndGet() {
        cURLState("set", 12345)
        pid := cURLState("get")
        if pid != 12345
            throw Error("Expected PID 12345, got " pid)
    }

    cURLState_CloseNonExistent() {
        ; Should not throw when closing a PID that doesn't exist
        cURLState("set", 99999999)
        cURLState("close")
        pid := cURLState("get")
        if pid != 0
            throw Error("Expected PID 0 after close, got " pid)
    }

    cURLState_DoubleClose_DoesNotCrash() {
        ; Regression: cancelStreamFromWebView() calls cURLState("close"),
        ; then sendStreamingRequest's cancelled path calls it again.
        ; ProcessClose(0) must be safe — no crash, no error.
        cURLState("set", 0)
        try {
            cURLState("close")
            cURLState("close")  ; double-close with PID already 0
        } catch Error as err {
            throw Error("Double close should not throw: " err.Message)
        }
        pid := cURLState("get")
        if pid != 0
            throw Error("PID should remain 0 after double close, got " pid)
    }

    cURLState_CloseClearsPID() {
        ; Regression: when cancelStreamFromWebView kills cURL, PID must be
        ; cleared so sendStreamingRequest detects cancellation.
        cURLState("set", 54321)
        pid := cURLState("get")
        if pid != 54321
            throw Error("Expected PID 54321, got " pid)
        cURLState("close")
        pid := cURLState("get")
        if pid != 0
            throw Error("Expected PID 0 after close (cancellation detection), got " pid)
    }

    ; Regression discovered by the final artifact audit: force-killed runs can
    ; leave credential-bearing request/cURL/title files in %TEMP%. Startup and
    ; exit cleanup must remove only this app's explicit prefixes.
    CleanupOwnedTempFiles_RemovesStaleArtifacts() {
        suffix := ChatDB._UUID()
        files := [
            A_Temp "\ChatWindow_Req_" suffix ".json",
            A_Temp "\ChatWindow_cURL_" suffix ".txt",
            A_Temp "\ChatWindow_Out_" suffix ".json",
            A_Temp "\ChatWindow_Err_" suffix ".txt",
            A_Temp "\ChatWindow_TitleGen_" suffix ".json",
            A_Temp "\ChatWindow_TitleGen_Out_" suffix ".json",
            A_Temp "\DSearch_Req_" suffix ".json",
            A_Temp "\DSearch_Out_" suffix ".json",
            A_Temp "\DSearch_Err_" suffix ".txt",
            A_Temp "\Tavily_Req_" suffix ".json",
            A_Temp "\Tavily_Out_" suffix ".json",
            A_Temp "\Tavily_Err_" suffix ".txt"
        ]
        unrelated := A_Temp "\not-chat-window-" suffix ".txt"
        try {
            for filePath in files
                FileAppend("stale secret", filePath, "UTF-8-RAW")
            FileAppend("keep", unrelated, "UTF-8-RAW")
            CleanupOwnedTempFiles()
            for filePath in files
                if FileExist(filePath)
                    throw Error("stale app artifact survived cleanup: " filePath)
            if !FileExist(unrelated)
                throw Error("cleanup removed an unrelated temp file")
        } finally {
            for filePath in files
                try FileDelete(filePath)
            try FileDelete(unrelated)
        }
    }

    ; --------------------
    ; postWebMessage — verify json format
    ; --------------------
    ; NOTE: postWebMessage sends to WebView2. We can't test the WebView
    ; side, but we can verify the JSON payload format is correct.
    ; We use jsongo.Stringify and check the structure.

    PostWebMessage_Format() {
        ; Create a mock responseWindow that captures the JSON
        ; AHK v2 passes 'this' as first param for method calls — accept (self, json)
        mockJson := ""
        mockResponseWindow := { PostWebMessageAsJSON: (self, json) => mockJson := json }
        ; Temporarily swap the global
        global responseWindow
        saved := responseWindow
        try {
            responseWindow := mockResponseWindow
            postWebMessage("testTarget", {foo: "bar"})
            parsed := jsongo.Parse(mockJson)
            if parsed["target"] != "testTarget"
                throw Error("Expected target 'testTarget', got '" parsed["target"] "'")
            if parsed["data"]["foo"] != "bar"
                throw Error("Expected data.foo 'bar', got '" parsed["data"]["foo"] "'")
        } finally {
            responseWindow := saved
        }
    }

    PostWebMessage_NoData() {
        mockJson := ""
        mockResponseWindow := { PostWebMessageAsJSON: (self, json) => mockJson := json }
        global responseWindow
        saved := responseWindow
        try {
            responseWindow := mockResponseWindow
            postWebMessage("noDataTarget")
            parsed := jsongo.Parse(mockJson)
            if parsed["target"] != "noDataTarget"
                throw Error("Expected target 'noDataTarget'")
            if parsed.Has("data")
                throw Error("Expected no 'data' key when data not provided")
        } finally {
            responseWindow := saved
        }
    }

    PostChatError_ScopesToOwnerThread() {
        mockJson := ""
        mockResponseWindow := { PostWebMessageAsJSON: (self, json) => mockJson := json }
        global responseWindow, activeThreadId
        savedWindow := responseWindow
        savedThread := activeThreadId
        try {
            responseWindow := mockResponseWindow
            activeThreadId := "visible-thread-b"
            _PostChatError("request failed", "owner-thread-a")
            parsed := jsongo.Parse(mockJson)
            if parsed["target"] != "showError"
                throw Error("Expected showError target")
            if parsed["data"]["message"] != "request failed"
                throw Error("Expected request failure message")
            if parsed["data"]["threadId"] != "owner-thread-a"
                throw Error("Expected owner thread id, got '" parsed["data"]["threadId"] "'")

            _PostChatError("visible failure")
            parsed := jsongo.Parse(mockJson)
            if parsed["data"]["threadId"] != "visible-thread-b"
                throw Error("Expected active thread fallback, got '" parsed["data"]["threadId"] "'")
        } finally {
            responseWindow := savedWindow
            activeThreadId := savedThread
        }
    }
    ; --- buildStructuredMessagesFromPath includes createdAt ---

    StructuredMessages_IncludesCreatedAt() {
        ; Minimal path with created_at set
        msg := {
            role: "user", content: "test", id: "msg-1",
            token_count: 0, thinking_tokens: 0, cached_tokens: 0,
            response_time_ms: 0, ttft_ms: 0,
            created_at: "2026-07-12 15:30:00",
            sibling_group: "", sibling_index: 0,
            reasoning: "", model: ""
        }
        result := buildStructuredMessagesFromPath([msg])
        if result.Length != 1
            throw Error("Expected 1 structured message, got " result.Length)
        if result[1].createdAt != "2026-07-12 15:30:00"
            throw Error("Expected createdAt='2026-07-12 15:30:00', got '" result[1].createdAt "'")
    }

    StructuredMessages_AssistantIncludesProvider() {
        msg := {
            role: "assistant", content: "ok", id: "msg-provider",
            token_count: 1, thinking_tokens: 0, cached_tokens: 0,
            response_time_ms: 0, ttft_ms: 0,
            sibling_group: "", sibling_index: 0,
            reasoning: "", model: "gpt-5.6-sol", provider: "openrouter"
        }
        result := buildStructuredMessagesFromPath([msg])
        if !result[1].HasOwnProp("provider") || result[1].provider != "openrouter"
            throw Error("Expected assistant provider=openrouter in structured message payload")
    }

    StructuredMessages_CreatedAtEmptyWhenMissing() {
        msg := {
            role: "user", content: "test", id: "msg-2",
            token_count: 0, thinking_tokens: 0, cached_tokens: 0,
            response_time_ms: 0, ttft_ms: 0,
            sibling_group: "", sibling_index: 0,
            reasoning: "", model: ""
        }
        result := buildStructuredMessagesFromPath([msg])
        if result[1].createdAt != ""
            throw Error("Expected empty createdAt when missing, got '" result[1].createdAt "'")
    }

    ; Regression (bug #38): switching threads must update the chat window
    ; title. Only the renameThread handler updated chatWindow.Title before, so
    ; after renaming one thread and switching to another the title bar kept the
    ; stale renamed title.
    LoadThreadAndRefreshUI_UpdatesWindowTitle() {
        global chatWindow, activeThreadId

        this._openDb()
        oldChatWindow := chatWindow
        oldActiveThreadId := activeThreadId
        chatWindow := { hWnd: 0, Hide: (*) => "", Title: "" }

        try {
            threadId := ChatDB.Thread_Create("Title Test Thread")
            _LoadThreadAndRefreshUI(threadId, false)
            expected := AppInfo.Name " - Title Test Thread"
            if chatWindow.Title != expected
                throw Error("window title not updated to the active thread: got '" chatWindow.Title "' expected '" expected "'")
        } finally {
            chatWindow := oldChatWindow
            activeThreadId := oldActiveThreadId
            this._closeDb()
        }
    }

    ; Regression (bug #125): branch position labels must be 1-based positions
    ; among the REMAINING siblings, not the raw sibling_index+1 (which goes
    ; stale after a sibling is deleted and grows with every retry).
    StructuredMessages_BranchLabelsArePositions() {
        this._openDb()
        threadId := ChatDB.Thread_Create("Branch Labels")
        u1Id := ChatDB.Msg_Insert({thread_id: threadId, role: "user", content: "root"})
        a1Id := ChatDB.Msg_Insert({thread_id: threadId, role: "assistant", content: "A", parent_id: u1Id, sibling_group: "sg-125", sibling_index: 0})
        a1bId := ChatDB.Msg_Insert({thread_id: threadId, role: "assistant", content: "B", parent_id: u1Id, sibling_group: "sg-125", sibling_index: 1})
        a1cId := ChatDB.Msg_Insert({thread_id: threadId, role: "assistant", content: "C", parent_id: u1Id, sibling_group: "sg-125", sibling_index: 2})

        ; Before any delete: branch C shows 3/3.
        path := ChatDB.Msg_GetActivePath(threadId)
        structured := buildStructuredMessagesFromPath(path, threadId)
        if structured[2].siblingInfo.index != 3 || structured[2].siblingInfo.total != 3
            throw Error("expected 3/3 before delete, got " structured[2].siblingInfo.index "/" structured[2].siblingInfo.total)

        ; Delete branch A (index 0): B and C must become 1/2 and 2/2.
        ChatDB.Msg_HardDelete(a1Id)
        ChatDB.Msg_SetActiveLeaf(threadId, a1bId)
        path := ChatDB.Msg_GetActivePath(threadId)
        structured := buildStructuredMessagesFromPath(path, threadId)
        if structured[2].siblingInfo.index != 1 || structured[2].siblingInfo.total != 2
            throw Error("branch B label after deleting A should be 1/2, got " structured[2].siblingInfo.index "/" structured[2].siblingInfo.total)
        ChatDB.Msg_SetActiveLeaf(threadId, a1cId)
        path := ChatDB.Msg_GetActivePath(threadId)
        structured := buildStructuredMessagesFromPath(path, threadId)
        if structured[2].siblingInfo.index != 2 || structured[2].siblingInfo.total != 2
            throw Error("branch C label after deleting A should be 2/2, got " structured[2].siblingInfo.index "/" structured[2].siblingInfo.total)
        this._closeDb()
    }

}
