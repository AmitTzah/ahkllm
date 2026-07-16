; ----------------------------------------------------
; Usage Dashboard — inline in ChatWindow via IPC
;
; Included from Main.ahk. Sends IPC to ChatWindow
; to toggle the inline dashboard panel.
; ----------------------------------------------------

ShowUsageDashboard() {
    ; Find ChatWindow and tell it to show the inline dashboard
    if WinExist("Chat ahk_exe AutoHotkey64.exe") {
        hwnd := WinExist("Chat ahk_exe AutoHotkey64.exe")
        CustomMessages.notifyShowDashboard(hwnd)
        ; Also bring ChatWindow to front
        WinActivate("ahk_id " hwnd)
    }
    debugLog("[DASHBOARD] Sent showDashboard to ChatWindow")
}
