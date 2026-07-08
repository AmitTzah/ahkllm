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

; New multi-provider globals
global models := Map(
    "deepseek/deepseek-v4-flash", { provider: "deepseek", input: 0.14, cachedInput: 0.0028, output: 0.28, context: 1000000, reasoning: true, vision: false }
)

global providers := Map(
    "deepseek", { displayName: "DeepSeek", endpoint: "https://api.deepseek.com/chat/completions", authEnvVar: "DEEPSEEK_API_KEY", fimEndpoint: "https://api.deepseek.com/beta/completions", icon: "" },
    "openai",   { displayName: "OpenAI", endpoint: "https://api.openai.com/v1/chat/completions", authEnvVar: "OPENAI_API_KEY", fimEndpoint: "", icon: "" },
    "google",   { displayName: "Google Gemini", endpoint: "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions", authEnvVar: "GEMINI_API_KEY", fimEndpoint: "", icon: "" }
)

global assistants := [
    { name: "Test Assistant", baseModel: "deepseek/deepseek-v4-flash", systemPrompt: "", reasoning: "", temperature: "", isDefault: true }
]

global defaultAssistant := "Test Assistant"

global providerMap := Map(
    "deepseek", "deepseek",
    "gpt",      "openai"
)

global trayMenuItems := []
global optionsMenuItems := []
global commands := []

; Mock responseWindow for ChatUtils/StreamHandler tests that use postWebMessage
; (*) variadic accepts 0+ params — AHK v2 method calls may pass 'this' implicitly
global responseWindow := {PostWebMessageAsJSON: (*) => ""}
