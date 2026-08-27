; ----------------------------------------------------
; Settings Panel — inline in ChatWindow via IPC
; ----------------------------------------------------

ShowSettingsPanel() {
    ; Don't send IPC in test mode — would activate the running Chat window
    if IsSet(testMode) && testMode
        return
    ; Find ChatWindow and tell it to show the Settings panel
    if WinExist("Chat ahk_exe AutoHotkey64.exe") {
        hwnd := WinExist("Chat ahk_exe AutoHotkey64.exe")
        CustomMessages.notifyShowSettings(hwnd)
        ; Also bring ChatWindow to front
        WinActivate("ahk_id " hwnd)
    }
    debugLog("[SETTINGS] Sent showSettings to ChatWindow")
}
