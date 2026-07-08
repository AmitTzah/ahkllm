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
        if CustomMessages.WM_RESPONSE_WINDOW_LOADING_START != 0x400 + 123
            throw Error("WM_RESPONSE_WINDOW_LOADING_START wrong")
        if CustomMessages.WM_RESPONSE_WINDOW_LOADING_FINISH != 0x400 + 124
            throw Error("WM_RESPONSE_WINDOW_LOADING_FINISH wrong")
        if CustomMessages.WM_RESPONSE_WINDOW_OPENED != 0x400 + 125
            throw Error("WM_RESPONSE_WINDOW_OPENED wrong")
        if CustomMessages.WM_RESPONSE_WINDOW_CLOSED != 0x400 + 126
            throw Error("WM_RESPONSE_WINDOW_CLOSED wrong")
        if CustomMessages.WM_SEND_TO_ALL_MODELS != 0x400 + 127
            throw Error("WM_SEND_TO_ALL_MODELS wrong")
        if CustomMessages.WM_CHAT_WINDOW_OPENED != 0x500 + 0
            throw Error("WM_CHAT_WINDOW_OPENED wrong")
        if CustomMessages.WM_CHAT_WINDOW_CLOSED != 0x500 + 1
            throw Error("WM_CHAT_WINDOW_CLOSED wrong")
        if CustomMessages.WM_LOAD_THREAD != 0x500 + 2
            throw Error("WM_LOAD_THREAD wrong")
        if CustomMessages.WM_NEW_CHAT != 0x500 + 3
            throw Error("WM_NEW_CHAT wrong")
        if CustomMessages.WM_TRIGGER_LLM != 0x500 + 4
            throw Error("WM_TRIGGER_LLM wrong")
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
            CustomMessages.notifyResponseWindowState(CustomMessages.WM_CHAT_WINDOW_OPENED, 123, 456, 789)
        } catch Error as err {
            throw Error("notifyResponseWindowState should not throw: " err.Message)
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

    NotifyNewChat_DoesNotCrash() {
        try {
            CustomMessages.notifyNewChat(12345)
        } catch Error as err {
            throw Error("notifyNewChat should not throw: " err.Message)
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
