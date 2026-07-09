; ============================================================================
; UserConfig.ahk — Centralized user-facing configuration
; ============================================================================
; Edit this file to customize the LLM AutoHotkey Assistant.
; Changes take effect after saving (Ctrl+S auto-reloads).
;
; Quick reference — search for the section you need:
;   §1  Providers       — API endpoints, auth, display settings
;   §2  Models          — pricing and metadata per model
;   §3  Provider Map    — infers provider from model name prefixes
;   §4  Assistants      — named chat profiles
;   §5  Commands        — menu commands (the ` menu)
;   §6  Thread Titles   — auto-generation model and prompt
;   §7  Theme           — dark mode toggle
;   §8  UI              — chat window, input, suspend banner
;   §9  Icons           — tray icons
;   §10 Hotkeys         — main hotkey, suspend, close, save/reload
;   §11 API Logs        — max log entries
;   §12 Trash Retention — days before auto-purge
;   §13 Menu Items      — Quick Access submenu and Tray menu


; ============================================================================
; §1 PROVIDERS — API endpoint configuration
; ============================================================================
; Each provider: displayName, endpoint, fimEndpoint, authEnvVar, icon, collapseThinking.
; API keys are read from environment variables (set via `setx`).

providers := Map(
    "deepseek", {
        displayName: "DeepSeek",
        endpoint: "https://api.deepseek.com/chat/completions",
        fimEndpoint: "https://api.deepseek.com/beta/completions",
        authEnvVar: "DEEPSEEK_API_KEY",
        icon: "icons/deepseek.ico",
        collapseThinking: false
    },
    "openai", {
        displayName: "OpenAI",
        endpoint: "https://api.openai.com/v1/chat/completions",
        fimEndpoint: "",
        authEnvVar: "OPENAI_API_KEY",
        icon: "icons/openai.ico",
        collapseThinking: true
    },
    "google", {
        displayName: "Google Gemini",
        endpoint: "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions",
        fimEndpoint: "",
        authEnvVar: "GEMINI_API_KEY",
        icon: "icons/google.ico",
        collapseThinking: true
    }
)


; ============================================================================
; §2 MODELS — Pricing and metadata
; ============================================================================
; Format: Map("provider/model-name", {provider, input, cachedInput, output, context, reasoning, vision})
; Prices in USD per 1M tokens. cachedInput defaults to 10% of input if omitted.
;
; To refresh pricing: run Refresh-ModelPricing.ps1 (Quick Access → Refresh Model Pricing).
; The script opens models_pricing.txt with the latest data — copy the models := Map(...)
; block from that file and paste it here, replacing everything from "models := Map(" below.

models := Map(
    ; -- DeepSeek --
    "deepseek/deepseek-v4-pro",   { provider: "deepseek", input: 0.435, cachedInput: 0.003625, output: 0.87,  context: 1000000, reasoning: true,  vision: false },
    "deepseek/deepseek-v4-flash", { provider: "deepseek", input: 0.14,  cachedInput: 0.0028,   output: 0.28,  context: 1000000, reasoning: true,  vision: false },
    "deepseek/deepseek-chat",     { provider: "deepseek", input: 0.14,  cachedInput: 0.0028,   output: 0.28,  context: 1000000, reasoning: false, vision: false },
    "deepseek/deepseek-reasoner", { provider: "deepseek", input: 0.14,  cachedInput: 0.0028,   output: 0.28,  context: 1000000, reasoning: true,  vision: false },

    ; -- OpenAI --
    "openai/gpt-4.1",       { provider: "openai", input: 2.0,   cachedInput: 0.5,    output: 8.0,   context: 1047576, reasoning: false, vision: true },
    "openai/gpt-4.1-mini",  { provider: "openai", input: 0.4,   cachedInput: 0.1,    output: 1.6,   context: 1047576, reasoning: false, vision: true },
    "openai/gpt-4.1-nano",  { provider: "openai", input: 0.1,   cachedInput: 0.025,  output: 0.4,   context: 1047576, reasoning: false, vision: true },
    "openai/gpt-4o-mini",   { provider: "openai", input: 0.15,  cachedInput: 0.075,  output: 0.6,   context: 128000,   reasoning: false, vision: true },
    "openai/gpt-4o",        { provider: "openai", input: 2.5,   cachedInput: 1.25,   output: 10,    context: 128000,   reasoning: false, vision: true },
    "openai/gpt-5-mini",    { provider: "openai", input: 0.25,  cachedInput: 0.025,  output: 2.0,   context: 400000,   reasoning: true,  vision: true },
    "openai/gpt-5.1",       { provider: "openai", input: 1.25,  cachedInput: 0.125,  output: 10,    context: 400000,   reasoning: true,  vision: true },
    "openai/gpt-5.2",       { provider: "openai", input: 1.75,  cachedInput: 0.175,  output: 14,    context: 400000,   reasoning: true,  vision: true },
    "openai/gpt-5.4",       { provider: "openai", input: 2.5,   cachedInput: 0.25,   output: 15,    context: 1050000,  reasoning: true,  vision: true },
    "openai/gpt-5.4-mini",  { provider: "openai", input: 0.75,  cachedInput: 0.075,  output: 4.5,   context: 400000,   reasoning: true,  vision: true },
    "openai/o3-mini",       { provider: "openai", input: 1.1,   cachedInput: 0.55,   output: 4.4,   context: 200000,   reasoning: true,  vision: false },
    "openai/o4-mini",       { provider: "openai", input: 1.1,   cachedInput: 0.275,  output: 4.4,   context: 200000,   reasoning: true,  vision: true },

    ; -- Google Gemini --
    "google/gemini-2.5-flash",       { provider: "google", input: 0.3,   cachedInput: 0.03,  output: 2.5,  context: 1048576, reasoning: true, vision: true },
    "google/gemini-2.5-flash-lite",  { provider: "google", input: 0.1,   cachedInput: 0.01,  output: 0.4,  context: 1048576, reasoning: true, vision: true },
    "google/gemini-2.5-pro",         { provider: "google", input: 1.25,  cachedInput: 0.125, output: 10,   context: 1048576, reasoning: true, vision: true },
    "google/gemini-3.5-flash",       { provider: "google", input: 1.5,   cachedInput: 0.15,  output: 9,    context: 1048576, reasoning: true, vision: true },
    "google/gemini-3.1-pro-preview", { provider: "google", input: 2,     cachedInput: 0.2,   output: 12,   context: 1048576, reasoning: true, vision: true },
    "google/gemini-3-flash-preview", { provider: "google", input: 0.5,   cachedInput: 0.05,  output: 3,    context: 1048576, reasoning: true, vision: true },
    "google/gemma-4-31b-it",         { provider: "google", input: 0,     cachedInput: 0,     output: 0,    context: 262144,  reasoning: true, vision: true }
)


; ============================================================================
; §3 PROVIDER INFERENCE MAP
; ============================================================================
; When a model name is given WITHOUT a "provider/" prefix (e.g. "gpt-5-mini"
; instead of "openai/gpt-5-mini"), the script uses these prefix→provider
; mappings to figure out which provider to use. First prefix match wins.
; If no prefix matches, defaults to "deepseek".
;
; You only need to edit this when:
;   - Adding a new provider (e.g. "anthropic") — add a mapping for their model
;     name prefixes (e.g. "claude"→"anthropic").
;   - A provider releases a new model family with a different name prefix
;     (e.g. if OpenAI releases "nova-*" models — add "nova"→"openai").

providerMap := Map(
    "deepseek", "deepseek",
    "gpt",      "openai",
    "o1",       "openai",
    "o3",       "openai",
    "claude",   "anthropic",
    "gemini",   "google",
    "gemma",    "google"
)


; ============================================================================
; §4 ASSISTANTS — Named chat profiles
; ============================================================================
; Each assistant: name, baseModel ("provider/model"), systemMessage (or systemMessageFile), reasoning, temperature, isDefault.
;   Use systemMessageFile: "system-messages/my-assistant.txt" for longer prompts.
;   reasoning: "none" | "minimal" | "low" | "medium" | "high" | "xhigh" or "" for model default.
;     DeepSeek: "none" uses thinking:{type:"disabled"}; low/medium→high, xhigh→max
;     OpenAI:   "none" only on gpt-5.1+; "xhigh" only on gpt-5.1-codex-max+
;     Google:   "none" only on Gemini 2.5; "xhigh" not supported
;   temperature: 0–2 or "" for model default.

assistants := [

    {
        name: "Gemini Pro",
        baseModel: "google/gemini-2.5-pro",
        systemMessage: "You are a helpful assistant. Answer concisely and accurately.",
        reasoning: "",
        temperature: "",
        isDefault: false
    }
]


; ============================================================================
; §5 COMMANDS (Menu Commands)
; ============================================================================
; Each object in this array defines one command in the prompt menu.
;
; --- REQUIRED FIELDS ---
;
;   commandName:      Internal identifier string (used by the script to
;                     reference this command — not shown to the end user).
;
;   menuText:         Label displayed in the tray/hotkey menu. The & character
;                     defines an accelerator key (e.g. "&1" lets the user
;                     press 1 to select that item).
;
;   systemMessage:     The system message sent to the LLM. This sets the
;                      model's role / behaviour for this specific command.
;                      For longer messages, use systemMessageFile instead.
;
;   systemMessageFile: (Optional) Path to a .txt file containing the system
;                      message. Easier to edit than inline text, especially
;                      for multi-line prompts. Takes precedence over systemMessage.
;                      Example: systemMessageFile: "system-messages/rephrase.txt"
;
;   APIModels:        One or more model identifiers, comma-separated.
;                     Supports "provider/model" format (e.g. "openai/gpt-4o")
;                     or direct model names (e.g. "deepseek-v4-pro").
;                     When multiple models are listed, a Response Window is
;                     opened for each one (multi-model "Council" mode).
;
; --- OPTIONAL FIELDS ---
;
;   isCustomCommand:  (Optional) When true, the user is shown a text input
;                     window where they can type their own instruction instead
;                     of using only the selected text.  For FIM commands this
;                     input becomes the suffix.  Default: false.
;
;   customInputInitialMessage:
;                     (Optional) Pre-filled text in the custom command input
;                     window.  Only meaningful when isCustomCommand: true.
;
;   pasteMode:        (Optional) Where the LLM response goes:
;                       "chat"     — shows a full chat interface in the Response Window
;                       "replace"  — replaces the selected text in the active app
;                       "append"   — placed after the cursor/selection
;                     Default: "chat".
;
;   stream:           (Optional, chat mode only) When true, the LLM response
;                     streams token-by-token in real time instead of appearing
;                     all at once. Requires pasteMode: "chat". Default: false.
;
;   thinking:         (Optional) { type: "enabled"|"disabled", level?: "low"|"medium"|"high"|"xhigh" }
;                     Enables or disables reasoning/thinking for the model.
;                     "enabled" works across all providers (translated per API).
;                     Optional "level" controls the thinking depth (defaults to "medium").
;                     Default: omitted (model default).
;
;   isFIM:            (Optional) Use DeepSeek FIM (Fill In the Middle) beta
;                     endpoint instead of chat completions.
;                     FIM Fill (pasteMode: "replace"):
;                       Selection = gap to fill.  Script copies the full text
;                       with Ctrl+A, splits around the selection into prefix/suffix.
;                     FIM Continue (pasteMode: "append"):
;                       Selection = prefix (no suffix needed).  If nothing is
;                       selected, uses Ctrl+Shift+Home to grab text before cursor.
;                     Max output: 4K tokens.  Default: false.
;
;   temperature:      (Optional) Sampling temperature 0–2.  Higher = more
;                     creative/random, lower = more deterministic.
;                     Not set by default (API uses its own default).
;
;   maxTokens:        (Optional) Maximum tokens in the response.
;                     Not set by default (API decides). FIM commands
;                     should set this explicitly (default: 4000).
;
;   stop:             (Optional) Array of stop sequences (e.g. ["\n\n"]).
;                     Generation stops when any sequence appears.
;                     Not set by default (no stop sequences).
;
;   tags:             (Optional) Array of submenu names used to group commands
;                     in the menu.  Each tag creates a submenu containing all
;                     commands that share that tag.  Default: [] (no grouping).
;
;   directAccelerator:
;                     (Optional) Creates a top-level keyboard shortcut for
;                     commands that are inside tagged submenus. Press ` then
;                     the key (e.g. "&r") to fire the command without
;                     navigating into its submenu. Only useful with tags —
;                     without tags the command already appears in the main
;                     menu, making this redundant. Default: none.
;
; ============================================================================
; Example command template — remove /* and */ to activate, then paste into commands:
/*
    {
        commandName: "Your Command Name",
        menuText: "&9 - Your Menu Label",        ; & defines accelerator key
        systemMessage: "Your system message here. This sets the model's role.",
        ; systemMessageFile: "system-messages/my-command.txt",  ; use instead of systemMessage
        APIModels: "deepseek-v4-flash",          ; single model
        ; APIModels: "deepseek-v4-pro, deepseek-v4-flash",  ; multi-model (Council)
        ; APIModels: "openai/gpt-4o",            ; provider/model format

        isCustomCommand: true,                   ; Shows input window
        customInputInitialMessage: "",           ; (optional) pre-filled text
        pasteMode: "replace",                    ; "chat", "replace", or "append"
        stream: false,                           ; (optional, chat only) token-by-token response
        thinking: { type: "enabled" },           ; (optional) { type:, level?: }
        isFIM: false,                            ; Uses FIM beta endpoint
        temperature: 0.7,                        ; (optional) 0 to 2
        maxTokens: 500,                          ; (optional) max response tokens
        stop: ["\n\n"],                          ; (optional) stop sequences
        tags: ["&Your tag"],
        directAccelerator: "&y"                  ; (optional) ` then key shortcut
    },
*/
; ============================================================================

; ============================================================================
; SUBMENU ORDER — Controls the order of tagged submenus in the ` menu.
; Tags listed here appear first, in order. Tags not listed appear after,
; in the order their commands are defined. Omit to use command order for all.
submenuOrder := ["&Text manipulation", "&Digest", "&DeepSeek", "&OpenAI", "&Google", "&Multi-models"]

commands := [

        {
        commandName: "Quick ask (V4 Flash)",
        menuText: "&2 - Quick Ask DeepSeek V4 Flash",
        APIModels: "deepseek-v4-flash",          ; single model
        isCustomCommand: true,                   ; Shows input window
        pasteMode: "chat",                    ; "chat", "replace", or "append"
        stream: true,                           ; (optional, chat only) token-by-token response
        thinking: { type: "disabled" },           ; (optional) DeepSeek reasoning (thinking blocks)
        isFIM: false,                            ; Uses FIM beta endpoint
    },

    {
        commandName: "FIM Continue",
        menuText: "&1 - FIM Continue",
        systemMessage: "",
        APIModels: "deepseek/deepseek-v4-flash",
        pasteMode: "append",
        isFIM: true,
        temperature: 1,
        stop: ["\n"],
        maxTokens: 300,
        directAccelerator: "&3",
        tags: ["&Text manipulation"],

    },

         {
        commandName: "FIM Fill",
        menuText: "&2 - FIM Fill",
        systemMessage: "",
        APIModels: "deepseek/deepseek-v4-flash",
        pasteMode: "replace",
        isFIM: true,
        maxTokens: 300,
        directAccelerator: "&4",

        tags: ["&Text manipulation"],

    },
    {
        commandName: "Refine",
        menuText: "&3 - Refine",
        systemMessageFile: "system-messages/refine.txt",
        APIModels: "deepseek/deepseek-v4-flash",
        pasteMode: "replace",
        thinking: { type: "disabled" },
        tags: ["&Text manipulation"],
        directAccelerator: "&5"

    },
     {
        commandName: "Auto-paste custom command",
        menuText: "&4 - Auto-paste custom command",
        APIModels: "deepseek/deepseek-v4-flash",
        isCustomCommand: true,
        pasteMode: "replace",
        tags: ["&Text manipulation"],
    },

     {
        commandName: "Summarize",
        menuText: "&1 - Summarize",
        systemMessageFile: "system-messages/summarize.txt",
        APIModels: "deepseek/deepseek-v4-pro",
        thinking: { type: "enabled" },
        pasteMode: "chat",
        tags: ["&Digest"]

    }
    , {
        commandName: "Translate to English",
        menuText: "&2 - Translate to English",
        systemMessageFile: "system-messages/translate-to-english.txt",
        APIModels: "deepseek/deepseek-v4-pro",
        thinking: { type: "disabled" },
        pasteMode: "chat",
        tags: ["&Digest"]

    }
    , {
        commandName: "Define",
        menuText: "&3 - Define",
        systemMessageFile: "system-messages/define.txt",
        APIModels: "deepseek/deepseek-v4-pro",
        thinking: { type: "disabled" },
        pasteMode: "chat",
        tags: ["&Digest"]

    }

    , {
        commandName: "Multi-Provider Council",
        menuText: "&1 - Council (V4 Pro + GPT-5.4 + Gemini 3.5 Flash)",
        APIModels: "deepseek/deepseek-v4-pro, openai/gpt-5.4, google/gemini-3.5-flash",
        isCustomCommand: true,
        pasteMode: "chat",
        tags: ["&Multi-models"]
    }

    , {
        commandName: "DeepSeek V4 Pro",
        menuText: "&1 - DeepSeek V4 Pro",
        APIModels: "deepseek/deepseek-v4-pro",
        isCustomCommand: true,
        pasteMode: "chat",
        stream: true,
        thinking: { type: "enabled" },
        tags: ["&DeepSeek"]
    }
    , {
        commandName: "DeepSeek V4 Flash",
        menuText: "&2 - DeepSeek V4 Flash",
        APIModels: "deepseek/deepseek-v4-flash",
        isCustomCommand: true,
        pasteMode: "chat",
        stream: true,
        thinking: { type: "enabled" },
        tags: ["&DeepSeek"]
    }
    , {
        commandName: "GPT-5.4",
        menuText: "&1 - GPT-5.4",
        APIModels: "openai/gpt-5.4",
        isCustomCommand: true,
        pasteMode: "chat",
        stream: true,
        thinking: { type: "enabled" },
        tags: ["&OpenAI"]
    }
    , {
        commandName: "GPT-5.4 Mini",
        menuText: "&2 - GPT-5.4 Mini",
        APIModels: "openai/gpt-5.4-mini",
        isCustomCommand: true,
        pasteMode: "chat",
        stream: true,
        thinking: { type: "enabled" },
        tags: ["&OpenAI"]
    }
    , {
        commandName: "Gemini 3.5 Flash",
        menuText: "&1 - Gemini 3.5 Flash",
        APIModels: "google/gemini-3.5-flash",
        isCustomCommand: true,
        pasteMode: "chat",
        stream: true,
        thinking: { type: "enabled" },
        tags: ["&Google"]
    }
    , {
        commandName: "Gemini 3.1 Pro",
        menuText: "&2 - Gemini 3.1 Pro",
        APIModels: "google/gemini-3.1-pro-preview",
        systemMessage: "You are a brutal critic. Ask uses to provide a piece of text first",
        isCustomCommand: true,
        pasteMode: "chat",
        stream: true,
        thinking: { type: "enabled", level: "high" },
        tags: ["&Google"]
    }
]


; ============================================================================
; §6 THREAD TITLE AUTO-GENERATION
; ============================================================================
; After the first exchange in a chat thread, generates a short title via a
; separate, cheap LLM call. Set titleGenModel to "" to disable.

titleGenModel := "deepseek/deepseek-v4-flash"
titleGenSystemPrompt := "Generate a short, descriptive title (max 6 words) for a conversation based on the first exchange. Respond with ONLY the title, no quotes, no punctuation, no commentary."
titleGenMaxTokens := 50


; ============================================================================
; §7 THEME
; ============================================================================

darkMode := false    ; true = dark mode; false = light/system theme


; ============================================================================
; §8 UI SETTINGS
; ============================================================================

; -- Chat Window (also used for command responses) --
chatDefaultModel := "deepseek/deepseek-v4-flash"
responseWindowFontFace := "Arial, Segoe UI, Helvetica, Verdana, Tahoma, sans-serif"

; -- Command Input Window --
inputWindowBackground    := "0x212529"
inputWindowFontSize      := "s14"
inputWindowFontColor     := "cWhite"
inputWindowFontFace      := "Arial"
inputWindowWidth         := 500
inputWindowHeight        := 250

; -- Suspend Banner --
suspendBannerText        := "LLM AutoHotkey Assistant Suspended"
suspendBannerFontSize    := "s10"
suspendBannerFontFace    := "Arial"
suspendBannerTextColor   := "cBlack"
suspendBannerBackground  := "0xFFDF00"


; ============================================================================
; §9 ICONS
; ============================================================================

iconOn  := "icons\IconOn.ico" ; Tray icon when the script is active
iconOff := "icons\IconOff.ico" ; Tray icon when the script is suspended


; ============================================================================
; §10 HOTKEYS
; ============================================================================

mainHotkey         := "``"               ; Backtick — opens the command menu
saveReloadHotkey   := "~^s"              ; Ctrl+S — save UserConfig & reload
closeWindowsHotkey := "~^w"              ; Ctrl+W — close input pop-up
suspendHotkey      := "CapsLock & ``"    ; CapsLock+Backtick — toggle suspend


; ============================================================================
; §11 API LOGS
; ============================================================================

apiLogMaxEntries := 20    ; max request/response entries; 0 = disable logging


; ============================================================================
; §12 TRASH RETENTION
; ============================================================================

trashRetentionDays := 30    ; days before auto-purge; 0 = never auto-purge


; ============================================================================
; §13 MENU ITEMS
; ============================================================================
; -- Quick Access (appear under ` → Quick Access in the command menu) --
quickAccessMenuItems := [
    { menuText: "&1 - Edit UserConfig",        command: "Notepad " A_ScriptDir "\UserConfig.ahk" },
    { menuText: "&2 - DeepSeek Usage",         command: "https://platform.deepseek.com/usage" },
    { menuText: "&3 - OpenAI Usage",         command: "https://platform.openai.com/settings/organization/usage" },
    { menuText: "&4 - Gemini Usage",         command: "https://aistudio.google.com/spend?project=gen-lang-client-0627530864" },
    { menuText: "&5 - API Logs",               command: A_ScriptDir "\lib\ApiLogsViewer.ahk" },
    { menuText: "&6 - Model Pricing",          command: "cmd /c powershell -ExecutionPolicy Bypass -File " A_ScriptDir "\Refresh-ModelPricing.ps1 && start " A_ScriptDir "\models_pricing.txt" },
    { menuText: "&7 - Debug Log",              command: A_Temp "\LLM_Debug_Log.txt" },

]


; -- System tray menu (right-click the tray icon) --
; "Open Chat Window" and "New Chat" are hardcoded above these items.
; Supported actions: "reload" and "exit".
trayMenuItems := [
    { menuText: "&Reload Script", action: "reload" },
    { menuText: "E&xit",          action: "exit" }
]
