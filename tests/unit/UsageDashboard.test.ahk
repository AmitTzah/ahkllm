; ======================================================
; UsageDashboard.test.ahk — tests for OnDashboardWebMessage
;
; Verifies the postMessage → ShowApiLogs dispatch chain
; that replaces the broken host object sync call.
; ======================================================

; Mock ShowApiLogs to track calls and avoid spawning WebViewToo
global _showApiLogsCalled := false
global _showApiLogsCallCount := 0

ShowApiLogs() {
    global _showApiLogsCalled, _showApiLogsCallCount
    _showApiLogsCalled := true
    _showApiLogsCallCount++
}

; Include the module under test (defines OnDashboardWebMessage)
; InitUsageDashboard() won't be called — it references WebViewToo
; which is resolved at runtime, so safe to include.
#Include ..\..\lib\UsageDashboard.ahk

class UsageDashboardTest {

    ; --- showApiLogs action dispatches to ShowApiLogs() ---

    WebMessage_DispatchesShowApiLogs() {
        global _showApiLogsCalled
        _showApiLogsCalled := false

        mockArgs := { TryGetWebMessageAsString: (self) => '{"action":"showApiLogs"}' }
        OnDashboardWebMessage("", mockArgs)

        if !_showApiLogsCalled
            throw Error("ShowApiLogs() was not called for 'showApiLogs' action")
    }

    ; --- Unknown actions are ignored ---

    WebMessage_IgnoresUnknownAction() {
        global _showApiLogsCalled
        _showApiLogsCalled := false

        mockArgs := { TryGetWebMessageAsString: (self) => '{"action":"refresh"}' }
        OnDashboardWebMessage("", mockArgs)

        if _showApiLogsCalled
            throw Error("ShowApiLogs() was called for unknown action")
    }

    ; --- Empty message is handled gracefully ---

    WebMessage_HandlesEmptyMessage() {
        global _showApiLogsCalled
        _showApiLogsCalled := false

        mockArgs := { TryGetWebMessageAsString: (self) => "" }
        OnDashboardWebMessage("", mockArgs)

        if _showApiLogsCalled
            throw Error("ShowApiLogs() was called for empty message")
    }

    ; --- Invalid JSON is caught, does not throw ---

    WebMessage_HandlesInvalidJson() {
        global _showApiLogsCalled
        _showApiLogsCalled := false

        mockArgs := { TryGetWebMessageAsString: (self) => "not-valid-json" }
        ; Must not throw — errors are caught by try/catch in OnDashboardWebMessage
        OnDashboardWebMessage("", mockArgs)

        if _showApiLogsCalled
            throw Error("ShowApiLogs() was called for invalid JSON")
    }

    ; --- Missing 'action' key in JSON is ignored ---

    WebMessage_IgnoresMessageWithoutAction() {
        global _showApiLogsCalled
        _showApiLogsCalled := false

        mockArgs := { TryGetWebMessageAsString: (self) => '{"other":"value"}' }
        OnDashboardWebMessage("", mockArgs)

        if _showApiLogsCalled
            throw Error("ShowApiLogs() was called for message without action key")
    }

    ; --- Multiple calls are tracked correctly ---

    WebMessage_CallsShowApiLogsOncePerMessage() {
        global _showApiLogsCallCount
        _showApiLogsCallCount := 0

        mockArgs := { TryGetWebMessageAsString: (self) => '{"action":"showApiLogs"}' }
        OnDashboardWebMessage("", mockArgs)
        OnDashboardWebMessage("", mockArgs)

        if _showApiLogsCallCount != 2
            throw Error("Expected 2 calls to ShowApiLogs(), got " _showApiLogsCallCount)
    }

    ; --- CloseUsageDashboard handles uninitialized dashboard ---

    CloseUsageDashboard_HandlesUnset() {
        global usageDashboard
        saved := unset
        if IsSet(usageDashboard)
            saved := usageDashboard, usageDashboard := unset
        try {
            ; Must not throw when dashboard was never initialized
            CloseUsageDashboard()
        } catch Error as e {
            throw Error("CloseUsageDashboard should not throw when unset: " e.Message)
        } finally {
            if IsSet(saved)
                usageDashboard := saved
        }
    }

    ; --- CloseUsageDashboard calls Destroy and clears reference ---

    CloseUsageDashboard_DestroysAndClears() {
        global usageDashboard
        saved := unset
        if IsSet(usageDashboard)
            saved := usageDashboard
        destroyCalled := false
        mockDashboard := { Destroy: (self) => destroyCalled := true }
        usageDashboard := mockDashboard
        try {
            CloseUsageDashboard()
            if !destroyCalled
                throw Error("Expected Destroy() to be called")
            if IsSet(usageDashboard)
                throw Error("Expected usageDashboard to be cleared after close")
        } finally {
            usageDashboard := unset
            if IsSet(saved)
                usageDashboard := saved
        }
    }

}

RegisterTestClass("UsageDashboardTest")
