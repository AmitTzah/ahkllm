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
global appDefaultModel := "deepseek/deepseek-v4-flash"
global mainHotkey := "``"
global reloadHotkey := "~^!r"
global closeWindowsHotkey := "~^w"
global suspendHotkey := "CapsLock & ``"
global apiLogMaxEntries := 20
global iconOn := ""
global iconOff := ""

global models := Map(
    "deepseek/deepseek-v4-flash", {
        provider: "deepseek", api: "openai-completions",
        compat: Map("thinkingFormat", "deepseek", "supportsReasoningEffort", true, "supportsUsageInStreaming", true, "maxTokensField", "max_tokens"),
        thinkingLevelMap: Map("none", "none", "low", "low", "high", "high", "max", "max"),
        thinkingOff: "disabled",
        input: 0.14, cachedInput: 0.0028, output: 0.28, context: 1000000, reasoning: true, vision: false
    },
    "openai/gpt-5-mini", {
        provider: "openai", api: "openai-completions",
        compat: Map("thinkingFormat", "openai", "supportsReasoningEffort", true, "supportsUsageInStreaming", true, "maxTokensField", "max_completion_tokens"),
        thinkingLevelMap: Map("none", "none", "low", "low", "medium", "medium", "high", "high"),
        thinkingOff: "none",
        input: 0.25, cachedInput: 0.025, output: 2.0, context: 400000, reasoning: true, vision: true
    },
    "google/gemini-2.5-flash", {
        provider: "google", api: "openai-completions",
        compat: Map("thinkingFormat", "google", "supportsUsageInStreaming", true, "maxTokensField", "max_tokens"),
        thinkingLevelMap: Map("minimal", "1024", "low", "4096", "medium", "8192", "high", "16384"),
        thinkingOff: "0",
        input: 0.3, cachedInput: 0.03, output: 2.5, context: 1048576, reasoning: true, vision: true
    },
    "google/gemini-3.5-flash", {
        provider: "google", api: "openai-completions",
        compat: Map("thinkingFormat", "google", "supportsUsageInStreaming", true, "maxTokensField", "max_tokens"),
        thinkingLevelMap: Map("minimal", "MINIMAL", "low", "LOW", "medium", "MEDIUM", "high", "HIGH"),
        thinkingOff: "MINIMAL",
        input: 1.5, cachedInput: 0.15, output: 9, context: 1048576, reasoning: true, vision: true
    },
    "google/gemma-4-31b-it", {
        provider: "google", api: "openai-completions",
        compat: Map("thinkingFormat", "google", "supportsUsageInStreaming", true, "maxTokensField", "max_tokens"),
        thinkingLevelMap: Map("minimal", "MINIMAL", "low", "LOW", "medium", "MEDIUM", "high", "HIGH"),
        thinkingOff: "MINIMAL",
        input: 0, cachedInput: 0, output: 0, context: 262144, reasoning: true, vision: true
    }
)

global providers := Map(
    "deepseek", { displayName: "DeepSeek", endpoint: "https://api.deepseek.com/chat/completions", authEnvVar: "DEEPSEEK_API_KEY", fimEndpoint: "https://api.deepseek.com/beta/completions", icon: "" },
    "openai",   { displayName: "OpenAI", endpoint: "https://api.openai.com/v1/chat/completions", authEnvVar: "OPENAI_API_KEY", fimEndpoint: "", icon: "" },
    "google",   { displayName: "Google Gemini", endpoint: "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions", authEnvVar: "GEMINI_API_KEY", fimEndpoint: "", icon: "" }
)

global assistants := [
    { name: "Test Assistant", baseModel: "deepseek/deepseek-v4-flash", systemMessage: "", reasoning: "", temperature: "" }
]

global newChatStartsWith := ""

global providerMap := Map(
    "deepseek", "deepseek",
    "gpt",      "openai"
)

global trayMenuItems := []
global quickAccessMenuItems := []
global submenuOrder := []
global commands := []

; ----------------------------------------------------
; Mock-record globals for the settings-branch AHK tests
; (HotkeyRegistrar / ThreadTitleGen / ChatDispatch test files).
; Declared here — early in the include order — because ChatSettings.ahk
; calls SetTimer at top level during auto-execute, before the test files'
; own top-level initializers would run.
; ----------------------------------------------------
global _mockHotkeyCalls := []
global _mockKeyWaitCalls := []
global _mockCapsLockCalls := []
global _mockReloadCalls := 0
global _mockToolTipCalls := []
global _mockSetTimerCalls := []
global _mockWinActiveResult := ""
global _mockToggleSuspendCalls := []
global _mockCloseWindowCalls := 0
global _mockRunCalls := []
global _mockTitleGenOutput := ""
global _mockRunWaitExitCode := 0
global _mockRunWaitCalls := []
global _mockFileSelectResult := ""
global _mockHideWindowCalls := 0

; ChatRequestBuilder/StreamHandler test setup globals
global requestParams := Map(
    "pasteMode", "chat",
    "windowTitle", "test",
    "providerName", "",
    "mainScriptHiddenHwnd", "0x0",
    "uniqueID", "test-unique-id",
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
