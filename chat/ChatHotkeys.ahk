; ======================================================
; ChatHotkeys.ahk — chat-window hotkey management
;
; Sub-process (ChatWindow.ahk) counterpart of Main's HotkeyRegistrar:
; registers the configured "Close Windows" hotkey in the chat process so the
; setting is honored there too (previously ChatWindow hardcoded ~^w and never
; consulted closeWindowsHotkey). Empty value = disabled — the old binding is
; turned Off and nothing re-registered.
; ======================================================

global _activeChatHotkey := ""

_registerChatHotkeys() {
    global closeWindowsHotkey, _activeChatHotkey

    ; Headless E2E workers run in parallel and must never install global
    ; shortcuts. The worker process is driven through CDP/IPC instead.
    if EnvGet("AHKLLM_E2E_WORKER") != "" {
        _activeChatHotkey := ""
        return
    }

    if _activeChatHotkey
        Hotkey(_activeChatHotkey, "Off")

    if closeWindowsHotkey
        Hotkey(closeWindowsHotkey, (*) => ChatHotkeys("closeWindows"), "On")

    _activeChatHotkey := closeWindowsHotkey
}

ChatHotkeys(action) {
    switch action {
        case "closeWindows":
            switch WinActive("A") {
                case chatWindow.hWnd: chatWindow.Hide()
            }
    }
}
