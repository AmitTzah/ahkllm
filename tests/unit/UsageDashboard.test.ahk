; ======================================================
; UsageDashboard.test.ahk — tests for ShowUsageDashboard
;
; Verifies the IPC-based dashboard display function.
; ======================================================

; Include the module under test
#Include ..\..\app\viewers\UsageDashboard.ahk

class UsageDashboardTest {

    ; --- ShowUsageDashboard does not throw when called ---

    ShowUsageDashboard_DoesNotThrow() {
        ; Should not throw even when ChatWindow isn't running
        ; (WinExist returns 0, PostMessage is in try block)
        try {
            ShowUsageDashboard()
        } catch Error as e {
            throw Error("ShowUsageDashboard should not throw: " e.Message)
        }
    }

}

RegisterTestClass("UsageDashboardTest")
