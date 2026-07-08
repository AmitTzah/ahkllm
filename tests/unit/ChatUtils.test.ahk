; ======================================================
; ChatUtils.test.ahk — Unit tests for ChatUtils
;
; Tests: manageState (cURL PID), manageState non-cURL,
;        postWebMessage format (not WebView — just JSON)
; ======================================================

class ChatUtilsTest {

    static __New() {
        RegisterTestClass("ChatUtilsTest")
    }

    ; --------------------
    ; manageState — cURL PID
    ; --------------------

    ManageState_SetAndGet() {
        manageState("cURL", "set", 12345)
        pid := manageState("cURL", "get")
        if pid != 12345
            throw Error("Expected PID 12345, got " pid)
    }

    ManageState_CloseNonExistent() {
        ; Should not throw when closing a PID that doesn't exist
        manageState("cURL", "set", 99999999)
        manageState("cURL", "close")
        pid := manageState("cURL", "get")
        if pid != 0
            throw Error("Expected PID 0 after close, got " pid)
    }

    ManageState_NonCURLReturnsEmpty() {
        ; manageState only handles "cURL" — other components return unset
        result := manageState("invalid", "get")
        if result != 0
            throw Error("Expected 0 for invalid component")
    }

    ManageState_DoubleClose_DoesNotCrash() {
        ; Regression: cancelStreamFromWebView() calls manageState("cURL","close"),
        ; then sendStreamingRequest's cancelled path calls it again.
        ; ProcessClose(0) must be safe — no crash, no error.
        manageState("cURL", "set", 0)
        try {
            manageState("cURL", "close")
            manageState("cURL", "close")  ; double-close with PID already 0
        } catch Error as err {
            throw Error("Double close should not throw: " err.Message)
        }
        pid := manageState("cURL", "get")
        if pid != 0
            throw Error("PID should remain 0 after double close, got " pid)
    }

    ManageState_CloseClearsPID() {
        ; Regression: when cancelStreamFromWebView kills cURL, PID must be
        ; cleared so sendStreamingRequest detects cancellation.
        manageState("cURL", "set", 54321)
        pid := manageState("cURL", "get")
        if pid != 54321
            throw Error("Expected PID 54321, got " pid)
        manageState("cURL", "close")
        pid := manageState("cURL", "get")
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
}
