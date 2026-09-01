; ======================================================
; ChatHotkeys.ahk — chat-window hotkey management
;
; Sub-process (ChatWindow.ahk) counterpart of Main's HotkeyRegistrar:
; registers the configured "Close Windows" hotkey in the chat process so the
; configured setting is honored there too. Empty value disables the binding;
; any currently registered binding is turned Off before reconfiguration.
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
