; ======================================================
; ChatHotkeys.test.ahk — Regression tests for chat/ChatHotkeys.ahk
;
; Bug: ChatWindow.ahk hardcoded "~^w:: ChatHotkeys("closeWindows")" and never
; read the configured closeWindowsHotkey setting, so changing Close Windows in
; Settings did nothing for the chat window. The chat process now registers the
; configured hotkey dynamically (empty = disabled), mirroring Main's registrar.
; ======================================================

class ChatHotkeysTest {

    static __New() {
        RegisterTestClass("ChatHotkeysTest")
    }

    ; The Hotkey()/WinActive() mocks are script-level definitions in
    ; HotkeyRegistrar.test.ahk; this class relies on them.

    Register_UsesConfiguredHotkey() {
        global closeWindowsHotkey, _activeChatHotkey, _mockHotkeyCalls
        closeWindowsHotkey := "^!c"
        _activeChatHotkey := ""
        _mockHotkeyCalls := []

        _registerChatHotkeys()

        if _mockHotkeyCalls.Length != 1
            throw Error("Expected 1 Hotkey() registration, got " _mockHotkeyCalls.Length)
        if _mockHotkeyCalls[1].key != "^!c" || _mockHotkeyCalls[1].options != "On"
            throw Error("Configured close hotkey not registered: " _mockHotkeyCalls[1].key " / " _mockHotkeyCalls[1].options)
        if Type(_mockHotkeyCalls[1].callback) != "Func"
            throw Error("Close hotkey callback should be a function")
        if _activeChatHotkey != "^!c"
            throw Error("Active chat hotkey not remembered")
    }

    Register_TurnsOffPreviousBinding() {
        global closeWindowsHotkey, _activeChatHotkey, _mockHotkeyCalls
        closeWindowsHotkey := "~^q"
        _activeChatHotkey := "~^w"
        _mockHotkeyCalls := []

        _registerChatHotkeys()

        if _mockHotkeyCalls.Length != 2
            throw Error("Expected 1 Off + 1 On, got " _mockHotkeyCalls.Length)
        if _mockHotkeyCalls[1].key != "~^w" || _mockHotkeyCalls[1].options != "Off"
            throw Error("Previous chat hotkey should be turned Off")
        if _mockHotkeyCalls[2].key != "~^q" || _mockHotkeyCalls[2].options != "On"
            throw Error("New chat hotkey should be registered")
    }

    ; Regression: empty hotkey = disabled — old binding Off, nothing re-registered.
    Register_EmptyValueDisablesHotkey() {
        global closeWindowsHotkey, _activeChatHotkey, _mockHotkeyCalls
        closeWindowsHotkey := ""
        _activeChatHotkey := "~^w"
        _mockHotkeyCalls := []

        _registerChatHotkeys()

        if _mockHotkeyCalls.Length != 1
            throw Error("Expected only the Off call, got " _mockHotkeyCalls.Length)
        if _mockHotkeyCalls[1].key != "~^w" || _mockHotkeyCalls[1].options != "Off"
            throw Error("Disabled hotkey should turn the old binding Off")
        if _activeChatHotkey != ""
            throw Error("Active chat hotkey should be cleared when disabled")
    }

    CloseWindows_HidesChatWindowWhenActive() {
        global chatWindow, _mockWinActiveResult, _mockHideWindowCalls
        _mockWinActiveResult := 777
        _mockHideWindowCalls := 0
        oldChatWindow := chatWindow
        chatWindow := { hWnd: 777, Hide: (*) => _mockHideWindowCalls++ }
        try {
            ChatHotkeys("closeWindows")
        } finally {
            chatWindow := oldChatWindow
            _mockWinActiveResult := ""
        }
        if _mockHideWindowCalls != 1
            throw Error("Active chat window should be hidden by the close hotkey")
    }

    CloseWindows_IgnoresOtherWindow() {
        global chatWindow, _mockWinActiveResult, _mockHideWindowCalls
        _mockWinActiveResult := 999
        _mockHideWindowCalls := 0
        oldChatWindow := chatWindow
        chatWindow := { hWnd: 777, Hide: (*) => _mockHideWindowCalls++ }
        try {
            ChatHotkeys("closeWindows")
        } finally {
            chatWindow := oldChatWindow
            _mockWinActiveResult := ""
        }
        if _mockHideWindowCalls != 0
            throw Error("Unrelated window should not trigger a hide")
    }
}
