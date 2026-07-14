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

}
