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
    ; Parallel headless E2E workers use an explicit test-only data root. Both
    ; variables are required so a stray data-dir environment variable cannot
    ; redirect a normal AhkLLM launch.
    static DataDir := (EnvGet("AHKLLM_E2E_WORKER") != "" && EnvGet("AHKLLM_E2E_DATA_DIR") != "")
        ? EnvGet("AHKLLM_E2E_DATA_DIR")
        : A_AppData "\AhkLLM"
}
