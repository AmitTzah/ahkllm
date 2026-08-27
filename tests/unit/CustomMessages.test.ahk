; ======================================================
; CustomMessages.test.ahk — Unit tests for CustomMessages class
;
; Tests: Message constants, registerHandlers, notifyResponseWindowState
;
; NOTE: WM_ messages can't be tested without real windows.
; We verify the constants are correct and the logic paths
; don't crash.
; ======================================================

class CustomMessagesTest {

    static __New() {
        RegisterTestClass("CustomMessagesTest")
    }

    ; --------------------
    ; Message constants
    ; --------------------

    Constants_HaveCorrectValues() {
        if CustomMessages.WM_LOADING_START != 0x400 + 123
            throw Error("WM_LOADING_START wrong")
        if CustomMessages.WM_LOADING_FINISH != 0x400 + 124
            throw Error("WM_LOADING_FINISH wrong")
        if CustomMessages.WM_CHAT_WINDOW_OPENED != 0x500 + 0
            throw Error("WM_CHAT_WINDOW_OPENED wrong")
        if CustomMessages.WM_LOAD_THREAD != 0x500 + 2
            throw Error("WM_LOAD_THREAD wrong")
        if CustomMessages.WM_TRIGGER_LLM != 0x500 + 4
            throw Error("WM_TRIGGER_LLM wrong")
        if CustomMessages.WM_SHOW_SETTINGS != 0x500 + 14
            throw Error("WM_SHOW_SETTINGS wrong")
    }

    ; --------------------
    ; notifyResponseWindowState — main script
    ; --------------------
    ; Can't test actual PostMessage without a real window.
    ; Verify it doesn't crash with valid inputs.

    Notify_OpenedDoesNotCrash() {
        ; This would normally PostMessage, but without a real window
        ; the call is silently dropped. No crash = pass.
        try {
            CustomMessages.notifyLoadingState(CustomMessages.WM_CHAT_WINDOW_OPENED, 123, 456, 789)
        } catch Error as err {
            throw Error("notifyLoadingState should not throw: " err.Message)
        }
    }

    ; --------------------
    ; notifyLoadThread — format verification
    ; --------------------

    NotifyLoadThread_DoesNotCrash() {
        try {
            CustomMessages.notifyLoadThread("test-thread-id", 12345)
        } catch Error as err {
            throw Error("notifyLoadThread should not throw: " err.Message)
        }
    }

    ; --------------------
    ; notifyLoadThread — temp file mechanism (uses PostMessage, not SendMessage)
    ; --------------------

    NotifyLoadThread_WritesThreadIdToTempFile() {
        testThreadId := "regression-test-thread-123"
        tempFile := A_Temp "\chat_load_thread.txt"
        ; Clean up any leftover
        if FileExist(tempFile)
            FileDelete(tempFile)
        try {
            CustomMessages.notifyLoadThread(testThreadId, 12345)
        } catch Error as err {
            throw Error("notifyLoadThread should not throw: " err.Message)
        }
        if !FileExist(tempFile)
            throw Error("notifyLoadThread should write threadId to temp file, but file not found")
        content := FileOpen(tempFile, "r", "UTF-8-RAW").Read()
        FileDelete(tempFile)
        if content != testThreadId
            throw Error("notifyLoadThread temp file content mismatch. Expected: '" testThreadId "', Got: '" content "'")
    }

    ; --------------------
    ; notifyTriggerLLM — should not crash
    ; --------------------

    NotifyTriggerLLM_DoesNotCrash() {
        try {
            CustomMessages.notifyTriggerLLM(12345)
        } catch Error as err {
            throw Error("notifyTriggerLLM should not throw: " err.Message)
        }
    }
}
