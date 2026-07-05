; ======================================================
; test_config.ahk — Test mode configuration
;
; Must be #Include'd FIRST before any production modules.
; Provides mock config globals and suppresses GUI dialogs
; so UserConfig.ahk is never loaded in test mode.
;
; SAFETY: ChatDB.Open() guards against production DB paths.
; #Warn Off: Suppresses AHK load-time warnings (popups).
; Runtime errors caught by OnError in run_tests.ahk.
; ======================================================
#Warn All, Off

; Suppress GUI — pipe to stdout instead
MsgBox(text, title := "", options := "") {
    FileAppend("[MSGBOX] " title ": " text "`n", "*")
    return "OK"
}
ExitApp(ExitCode := 0) {
    FileAppend("[EXITAPP suppressed in test mode]`n", "*")
}

; Safety guard is in ChatDB.Open() — checks 'testMode' global
; and aborts if production path is used.
global testMode := true

; -------------------------------------------------------------------
; Mock config globals (replace UserConfig.ahk)
; -------------------------------------------------------------------
global APIKey := "sk-test-key"
global APIEndpoint := "https://api.test/chat/completions"
global FIMEndpoint := "https://api.test/beta/completions"
global FIMMaxTokens := 4000
global darkMode := false
global responseWindowFontFace := "Arial"
global chatDefaultModel := "deepseek-v4-flash"
global mainHotkey := "``"
global saveReloadHotkey := "~^s"
global closeWindowsHotkey := "~^w"
global suspendHotkey := "CapsLock & ``"
global apiLogMaxEntries := 20
global iconOn := ""
global iconOff := ""

; Minimal pricing (deepseek-v4-flash from UserConfig)
global modelPricing := Map(
    "deepseek-v4-flash", {input: 0.14, cachedInput: 0.0028, output: 0.28, context: 1048576}
)

global providerMap := Map(
    "deepseek", "deepseek",
    "gpt",      "openai"
)

global trayMenuItems := []
global optionsMenuItems := []
global prompts := []
