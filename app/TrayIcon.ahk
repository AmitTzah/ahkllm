; ======================================================
; TrayIcon.ahk - tray icon lifecycle
;
; The tray icon is re-applied from the current icons.iconOn/iconOff globals
; whenever settings change, so icon edits take effect live instead of after a
; restart. It honors the current suspend state (iconOff while
; suspended, like toggleSuspend in LoadingUI.ahk) and is safe to call at
; startup and from Main's settings-updated hook chain.
; ======================================================

_trayIconForCurrentState() {
    global iconOn, iconOff
    return A_IsSuspended ? iconOff : iconOn
}

_rebuildTrayIcon() {
    ; Freeze the icon while suspended (matches toggleSuspend's TraySetIcon
    ; call) so the off-icon survives the suspend toggle's re-application.
    TraySetIcon(_trayIconForCurrentState(), , A_IsSuspended ? 1 : 0)
}
