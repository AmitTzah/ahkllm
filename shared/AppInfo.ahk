; ======================================================
; AppInfo.ahk - single source of truth for the app name.
;
; The data directory (%APPDATA%) and every visible title
; (window, tray, web UI) read from here, so the repo, the
; data dir, and the runtime UI can never drift apart again.
; ======================================================

class AppInfo {
    ; Display name used in the window title bar, tray tooltip, and web UI.
    static Name := "AhkLLM"
    ; Root data directory under %APPDATA% (e.g. ...\AppData\Roaming\AhkLLM).
    static DataDir := A_AppData "\AhkLLM"
}
