; ======================================================
; test_config.ahk — Test mode configuration overrides
;
; Included AFTER lib/Config.ahk to override production
; globals with test-safe values. Shared utilities (ModelParser)
; are loaded by Config.ahk.
; ======================================================
#Warn All, Off

; Override globals from UserConfig.ahk with test values
global APIKey := "sk-test-key"
global APIEndpoint := "https://api.test/chat/completions"
global FIMEndpoint := "https://api.test/beta/completions"
global responseWindowFontFace := "Arial"
global responseWindowFontSize := "17"
global chatDefaultModel := "deepseek/deepseek-v4-flash"
global mainHotkey := "``"
global saveReloadHotkey := "~^s"
global closeWindowsHotkey := "~^w"
global suspendHotkey := "CapsLock & ``"
global apiLogMaxEntries := 20
global iconOn := ""
global iconOff := ""

global models := Map(
    "deepseek/deepseek-v4-flash", { provider: "deepseek", input: 0.14, cachedInput: 0.0028, output: 0.28, context: 1000000, reasoning: true, vision: false },
    "google/gemini-2.5-flash", { provider: "google", input: 0.3, cachedInput: 0.03, output: 2.5, context: 1048576, reasoning: true, vision: true },
    "google/gemini-3.5-flash", { provider: "google", input: 1.5, cachedInput: 0.15, output: 9, context: 1048576, reasoning: true, vision: true },
    "google/gemma-4-31b-it", { provider: "google", input: 0, cachedInput: 0, output: 0, context: 262144, reasoning: true, vision: true }
)

global providers := Map(
    "deepseek", { displayName: "DeepSeek", endpoint: "https://api.deepseek.com/chat/completions", authEnvVar: "DEEPSEEK_API_KEY", fimEndpoint: "https://api.deepseek.com/beta/completions", icon: "" },
    "openai",   { displayName: "OpenAI", endpoint: "https://api.openai.com/v1/chat/completions", authEnvVar: "OPENAI_API_KEY", fimEndpoint: "", icon: "" },
    "google",   { displayName: "Google Gemini", endpoint: "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions", authEnvVar: "GEMINI_API_KEY", fimEndpoint: "", icon: "" }
)

global assistants := [
    { name: "Test Assistant", baseModel: "deepseek/deepseek-v4-flash", systemMessage: "", reasoning: "", temperature: "", isDefault: true }
]

global defaultAssistant := "Test Assistant"

global providerMap := Map(
    "deepseek", "deepseek",
    "gpt",      "openai"
)

global trayMenuItems := []
global quickAccessMenuItems := []
global submenuOrder := []
global commands := []

; ChatRequestBuilder/StreamHandler test setup globals
global requestParams := Map(
    "pasteMode", "chat",
    "windowTitle", "test",
    "providerName", "",
    "singleAPIModelName", "deepseek-v4-flash",
    "stream", true,
    "isFIM", false,
    "numberOfAPIModels", 1,
    "APIModelsIndex", 1,
    "chatHistoryJSONRequestFile", "",
    "cURLCommandFile", "",
    "cURLOutputFile", "",
    "cURLErrorFile", ""
)
global activeThreadId := ""
