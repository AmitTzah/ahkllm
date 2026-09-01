; ======================================================
; ChatWindowIcon.ahk - chat window icon lifecycle
;
; The chat window icon (title bar / taskbar, WM_SETICON) is re-applied from
; the current iconOn global whenever settings change, so "Active Icon" edits
; take effect live instead of after a restart. The tray icon
; app/TrayIcon.ahk handles the tray icon separately.
; ======================================================

_applyChatWindowIcon() {
    global iconOn
    ; Guard: the hook can be invoked before the WebView window exists
    ; (SettingsService.Apply runs registered hooks at startup).
    if !IsSet(chatWindow) || !chatWindow || !chatWindow.hWnd
        return
    ; Resolve the configured path first (absolute paths used as-is,
    ; repo-relative ones against the repo root); empty means no icon.
    hIcon := 0
    if iconOn != ""
        hIcon := LoadPicture(ResolveIconPath(iconOn), "Icon1 w32 h32", &imgType)
    if hIcon {
        SendMessage(0x80, 0, hIcon, , "ahk_id " chatWindow.hWnd)  ; WM_SETICON, ICON_BIG (Alt+Tab)
        SendMessage(0x80, 1, hIcon, , "ahk_id " chatWindow.hWnd)  ; WM_SETICON, ICON_SMALL (title bar / taskbar)
    }
}
