; ======================================================
; ChatWindowIcon.test.ahk - Regression tests for chat/ChatWindowIcon.ahk
;
; Bug: ChatWindow.ahk applied the window icon (WM_SETICON) only at startup,
; so changing "Active Icon" (iconOn) in Settings left the already-open chat
; window stale until restart. _applyChatWindowIcon() now re-applies the icon
; from the current globals, and ChatWindow registers it as a SettingsService
; hook so settings updates re-apply it live (headless scenario 138 asserts
; that wiring end-to-end).
; ======================================================

; Mock the Win32 message built-in so the test can observe WM_SETICON calls
; without touching a real window. The production call sites use the
; positional (Msg, wParam, lParam, Control, WinTitle) form.
SendMessage(msg, wParam := 0, lParam := 0, control := "", winTitle := "", *) {
    global _mockSendMessageCalls
    _mockSendMessageCalls.Push({ msg: msg, wParam: wParam, lParam: lParam, winTitle: winTitle })
    return 0
}

class ChatWindowIconTest {

    static __New() {
        RegisterTestClass("ChatWindowIconTest")
    }

    _reset() {
        global _mockSendMessageCalls, iconOn
        _mockSendMessageCalls := []
        iconOn := "icons\IconOn.ico"
    }

    ; The Active Icon must be applied to the open chat window as WM_SETICON
    ; (ICON_BIG + ICON_SMALL) when re-applied after a settings change.
    Apply_UsesConfiguredIconOn() {
        global _mockSendMessageCalls, chatWindow
        this._reset()
        oldWindow := chatWindow
        chatWindow := { hWnd: 777 }
        try {
            _applyChatWindowIcon()
            if _mockSendMessageCalls.Length != 2
                throw Error("Expected 2 WM_SETICON calls, got " _mockSendMessageCalls.Length)
            if _mockSendMessageCalls[1].msg != 0x80 || _mockSendMessageCalls[1].wParam != 0
                throw Error("Expected WM_SETICON ICON_BIG first, got " _mockSendMessageCalls[1].msg "/" _mockSendMessageCalls[1].wParam)
            if _mockSendMessageCalls[2].msg != 0x80 || _mockSendMessageCalls[2].wParam != 1
                throw Error("Expected WM_SETICON ICON_SMALL second, got " _mockSendMessageCalls[2].msg "/" _mockSendMessageCalls[2].wParam)
            if _mockSendMessageCalls[1].winTitle != "ahk_id 777"
                throw Error("WM_SETICON should target the chat window, got '" _mockSendMessageCalls[1].winTitle "'")
        } finally {
            chatWindow := oldWindow
        }
    }

    ; Empty iconOn means no window icon - no WM_SETICON calls.
    Apply_EmptyIcon_SkipsSendMessage() {
        global _mockSendMessageCalls, iconOn, chatWindow
        this._reset()
        oldWindow := chatWindow
        chatWindow := { hWnd: 777 }
        try {
            iconOn := ""
            _applyChatWindowIcon()
            if _mockSendMessageCalls.Length != 0
                throw Error("Empty iconOn must not send WM_SETICON, got " _mockSendMessageCalls.Length " calls")
        } finally {
            chatWindow := oldWindow
        }
    }

    ; No chat window yet (the hook ran before the WebView was created) - safe no-op.
    Apply_NoWindow_NoOp() {
        global _mockSendMessageCalls, chatWindow
        this._reset()
        oldWindow := chatWindow
        chatWindow := ""
        try {
            _applyChatWindowIcon()
            if _mockSendMessageCalls.Length != 0
                throw Error("No chat window should mean no WM_SETICON, got " _mockSendMessageCalls.Length " calls")
        } finally {
            chatWindow := oldWindow
        }
    }

    ; Static wiring: ChatWindow.ahk must register the chatWindowIcon settings
    ; hook (the tray-icon pattern from Main.ahk), so settings updates re-apply
    ; the icon live instead of only at startup.
    ChatWindow_RegistersSettingsHook() {
        cwPath := A_ScriptDir "\..\chat\ChatWindow.ahk"
        cw := FileRead(cwPath)
        if !InStr(cw, 'SettingsService.RegisterHook("chatWindowIcon"')
            throw Error("ChatWindow.ahk must register the chatWindowIcon settings hook (bug #138)")
        if !InStr(cw, "_applyChatWindowIcon()")
            throw Error("ChatWindow.ahk must apply the icon at startup via _applyChatWindowIcon()")
    }
}
