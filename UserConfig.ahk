; ============================================================================
; UserConfig.ahk — Centralized user-facing configuration
; ============================================================================
; Edit this file to customize the LLM AutoHotkey Assistant.
; Changes take effect after saving and reloading (~^s).

; ============================================================================
; PROVIDERS — API endpoint configuration
; ============================================================================
; Each provider defines: display name, API endpoint, auth env var, and FIM endpoint.
; API keys are read from environment variables.

providers := Map(
    "deepseek", {
        displayName: "DeepSeek",
        endpoint: "https://api.deepseek.com/chat/completions",
        fimEndpoint: "https://api.deepseek.com/beta/completions",
        authEnvVar: "DEEPSEEK_API_KEY",
        icon: "icons/deepseek.ico",
        collapseThinking: false    ; DeepSeek thinking is raw reasoning — useful, show expanded
    },
    "openai", {
        displayName: "OpenAI",
        endpoint: "https://api.openai.com/v1/chat/completions",
        fimEndpoint: "",      ; No FIM support
        authEnvVar: "OPENAI_API_KEY",
        icon: "icons/openai.ico",
        collapseThinking: true     ; OpenAI sends summaries, not raw reasoning
    },
    "google", {
        displayName: "Google Gemini",
        endpoint: "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions",
        fimEndpoint: "",
        authEnvVar: "GEMINI_API_KEY",
        icon: "icons/google.ico",
        collapseThinking: true     ; Gemini sends thought summaries, not raw reasoning
    }
)

; ----------------------------------------------------
; API KEY CHECK — Ensures at least one provider key is set
; ----------------------------------------------------
; Check DeepSeek first (primary/default), then fallback to any other
if !EnvGet("DEEPSEEK_API_KEY") && !EnvGet("OPENAI_API_KEY") && !EnvGet("GEMINI_API_KEY") {
    msg := "No API keys found.`n`n"
        . "Set at least one environment variable and restart:"
        . "`n  DEEPSEEK_API_KEY  (for DeepSeek)"
        . "`n  OPENAI_API_KEY    (for OpenAI)"
        . "`n  GEMINI_API_KEY    (for Google Gemini)"
        . "`n`nExample:"
        . "`n  setx DEEPSEEK_API_KEY sk-your-key-here"
    MsgBox(msg, "Missing API Keys", "IconX")
    ExitApp()
}

; For backward compatibility — resolve the primary API key and endpoint
; from the first configured provider
for providerKey, p in providers {
    apiKey := EnvGet(p.authEnvVar)
    if apiKey {
        APIKey := apiKey                    ; Primary API key
        APIEndpoint := p.endpoint           ; Primary endpoint
        FIMEndpoint := p.fimEndpoint        ; FIM endpoint (may be empty)
        break
    }
}
if !IsSet(APIKey) {
    ; Fallback: use DeepSeek endpoint even without key (will fail at request time)
    APIKey := ""
    APIEndpoint := providers["deepseek"].endpoint
    FIMEndpoint := providers["deepseek"].fimEndpoint
}
FIMMaxTokens := 4000

; ----------------------------------------------------
; MODELS — Pricing and metadata
; ----------------------------------------------------
; Format: Map("provider/model-name", {provider, input, cachedInput, output, context, reasoning, vision})
; Prices are in USD per 1M tokens.
; Use Refresh-ModelPricing.ps1 to auto-generate this from models.dev.
;
; cachedInput defaults to 10% of input if not specified.
; If input or output is 0, cost is not calculated for that category.

models := Map(
    ; DeepSeek
    "deepseek/deepseek-v4-pro",   { provider: "deepseek", input: 0.435, cachedInput: 0.003625, output: 0.87,  context: 1000000, reasoning: true,  vision: false },
    "deepseek/deepseek-v4-flash", { provider: "deepseek", input: 0.14,  cachedInput: 0.0028,   output: 0.28,  context: 1000000, reasoning: true,  vision: false },
    "deepseek/deepseek-chat",     { provider: "deepseek", input: 0.14,  cachedInput: 0.0028,   output: 0.28,  context: 1000000, reasoning: false, vision: false },
    "deepseek/deepseek-reasoner", { provider: "deepseek", input: 0.14,  cachedInput: 0.0028,   output: 0.28,  context: 1000000, reasoning: true,  vision: false },

    ; OpenAI
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

    ; Google Gemini
    "google/gemini-2.5-flash",      { provider: "google", input: 0.3,   cachedInput: 0.03,  output: 2.5,  context: 1048576, reasoning: true, vision: true },
    "google/gemini-2.5-flash-lite", { provider: "google", input: 0.1,   cachedInput: 0.01,  output: 0.4,  context: 1048576, reasoning: true, vision: true },
    "google/gemini-2.5-pro",        { provider: "google", input: 1.25,  cachedInput: 0.125, output: 10,   context: 1048576, reasoning: true, vision: true },
    "google/gemini-3.5-flash",      { provider: "google", input: 1.5,   cachedInput: 0.15,  output: 9,    context: 1048576, reasoning: true, vision: true }
)

; ----------------------------------------------------
; BACKWARD COMPATIBILITY — modelPricing map
; ----------------------------------------------------
; Maps model names (without provider prefix) to their pricing.
; Generated from the models map above for scripts that still use the old format.
modelPricing := Map()
for modelId, modelData in models {
    ; Extract just the model name after "provider/"
    slashPos := InStr(modelId, "/")
    if slashPos > 0 {
        shortName := SubStr(modelId, slashPos + 1)
    } else {
        shortName := modelId
    }
    if !modelPricing.Has(shortName) {
        modelPricing[shortName] := {
            input: modelData.input,
            cachedInput: modelData.cachedInput,
            output: modelData.output,
            context: modelData.context
        }
    }
}

; ----------------------------------------------------
; ASSISTANTS — Named profiles
; ----------------------------------------------------
; Each assistant has: name, baseModel, systemMessage?, reasoning?, temperature?
; baseModel uses "provider/model" format.
; - isDefault: true for the default assistant used in new chats
; - reasoning: "none" | "minimal" | "low" | "medium" | "high" | "xhigh" or "" for model default
; - temperature: 0-2 or "" for model default

assistants := [
    {
        name: "General Assistant",
        baseModel: "deepseek/deepseek-v4-pro",
        systemMessage: "You are a helpful assistant. Follow the instructions that I will provide or answer any questions that I will ask. My first query is the following:",
        reasoning: "",
        temperature: "",
        isDefault: true
    },

    {
        name: "Gemini Pro",
        baseModel: "google/gemini-2.5-pro",
        systemMessage: "You are a helpful assistant. Answer concisely and accurately.",
        reasoning: "",
        temperature: "",
        isDefault: false
    },
    {
        name: "GPT-5 Mini",
        baseModel: "openai/gpt-5-mini",
        systemMessage: "",
        reasoning: "",
        temperature: "",
        isDefault: false
    }
]

; Resolve default assistant
defaultAssistant := ""
for a in assistants {
    if a.isDefault {
        defaultAssistant := a.name
        break
    }
}
if !defaultAssistant && assistants.Length > 0 {
    defaultAssistant := assistants[1].name
    assistants[1].isDefault := true
}

; ----------------------------------------------------
; THEME (dark mode)
; ----------------------------------------------------
; Set to false for light/system theme, true for dark mode.
; Affects MsgBox, menus, tooltips, and the API Logs Viewer.

darkMode := false

; ----------------------------------------------------
; UI — Response Window (WebView)
; ----------------------------------------------------
; Font face for the Web-based Response Window (chat messages and markdown content).
; Uses CSS font-family syntax. Set to a system sans-serif font like "Arial" for
; better screen readability, or a serif font like "Georgia" if you prefer print-style.
; Fallback fonts are applied automatically.

responseWindowFontFace := "Arial, Segoe UI, Helvetica, Verdana, Tahoma, sans-serif"

; ----------------------------------------------------
; UI — Chat Window (persistent chat via ChatWindow.ahk)
; ----------------------------------------------------
; Default model used for new free-form chats (opened from tray or ` menu).
; Must be a valid model name supported by APIEndpoint (e.g. "deepseek-v4-flash",
; "deepseek-v4-flash", etc.). Users can switch models mid-chat via the sidebar.
chatDefaultModel := "deepseek/deepseek-v4-flash"

; ----------------------------------------------------
; UI — Input Window
; ----------------------------------------------------

inputWindowBackground    := "0x212529"     ; Background color for the text input window
inputWindowFontSize      := "s14"
inputWindowFontColor     := "cWhite"
inputWindowFontFace      := "Arial"
inputWindowWidth         := 500            ; Width of the text input control in pixels
inputWindowHeight        := 250            ; Height of the text input control in pixels

; ----------------------------------------------------
; UI — Suspend Banner
; ----------------------------------------------------
; The yellow banner shown at the bottom of the screen when the script is suspended.

suspendBannerText        := "LLM AutoHotkey Assistant Suspended"
suspendBannerFontSize    := "s10"
suspendBannerFontFace    := "Arial"
suspendBannerTextColor   := "cBlack"
suspendBannerBackground  := "0xFFDF00"     ; Gold/yellow

; ----------------------------------------------------
; ICONS
; ----------------------------------------------------

iconOn  := "icons\IconOn.ico"   ; Tray icon when the script is active
iconOff := "icons\IconOff.ico"  ; Tray icon when the script is suspended

; ----------------------------------------------------
; HOTKEYS
; ----------------------------------------------------
; Main hotkey that opens the command menu.
; Change this to any key (e.g. "F1", "~^Space") to use a different hotkey.

mainHotkey     := "``"                ; Backtick — opens the command menu

; When you edit UserConfig.ahk (e.g. via mainHotkey> Options > Edit UserConfig which opens
; it in Notepad), Ctrl+S saves the file and the script auto-reloads to pick up
; the new settings.  The ~ prefix lets the keystroke pass through to the editor.
saveReloadHotkey := "~^s"             ; Ctrl+S — save config & reload script

; Dismisses the active input window (custom command, send to all, send to group)
; when focused.  The ~ prefix lets the keystroke pass through to other handlers.
closeWindowsHotkey := "~^w"           ; Ctrl+W — close input pop-up

; Temporarily freezes/unfreezes all hotkeys without closing the script.
; When suspended a yellow banner appears at the bottom of the screen and the
; tray icon changes.  Press again to resume.
suspendHotkey  := "CapsLock & ``"     ; CapsLock+Backtick — toggle script suspend

; ----------------------------------------------------
; API LOGS
; ----------------------------------------------------
; Maximum number of API request/response entries to keep in the log file.
; Set to 0 to disable logging entirely.

; ----------------------------------------------------
; TRASH RETENTION
; ----------------------------------------------------
; Number of days to keep deleted chats in trash before auto-purge.
; Set to 0 to disable auto-purge entirely (trash must be emptied manually).

trashRetentionDays := 30

; ----------------------------------------------------
; API LOGS
; ----------------------------------------------------

apiLogMaxEntries := 20

; ----------------------------------------------------
; OPTIONS MENU ITEMS
; ----------------------------------------------------
; Items shown under the "Options" submenu (press ` then Options).
; Each entry: { menuText, command }
;   command is either a URL to open ("https://...") or a file path to run.

optionsMenuItems := [
    { menuText: "&1 - Edit UserConfig",  command: "Notepad " A_ScriptDir "\UserConfig.ahk" },
    { menuText: "&2 - DeepSeek Platform", command: "https://platform.deepseek.com" },
    { menuText: "&3 - DeepSeek API Keys", command: "https://platform.deepseek.com/api_keys" },
    { menuText: "&4 - DeepSeek Usage",    command: "https://platform.deepseek.com/usage" },
    { menuText: "&5 - API Logs",          command: A_ScriptDir "\lib\ApiLogsViewer.ahk" },
    { menuText: "&6 - Debug Log",         command: A_Temp "\LLM_Debug_Log.txt" }
]

; ----------------------------------------------------
; TRAY MENU ITEMS
; ----------------------------------------------------
; Each entry: { menuText, action }
;   action is the callback function name to call when clicked.

trayMenuItems := [
    { menuText: "&Reload Script", action: "reload" },
    { menuText: "E&xit",          action: "exit" }
]

; ----------------------------------------------------
; THREAD TITLE AUTO-GENERATION
; ----------------------------------------------------
; After the first user+assistant exchange in a chat thread, the script generates
; a short title for the thread using a separate, cheap LLM call.
; Set titleGenModel to an empty string to disable auto-generation entirely.
;
; titleGenModel: The model used for title generation. Use a cheap/fast model.
; titleGenSystemPrompt: Instruction for the title generation model.
;   Keep it strict — only the title text, no commentary.
; titleGenMaxTokens: Maximum tokens for the generated title. Titles are short.

titleGenModel := "deepseek/deepseek-v4-flash"
titleGenSystemPrompt := "Generate a short, descriptive title (max 6 words) for a conversation based on the first exchange. Respond with ONLY the title, no quotes, no punctuation, no commentary."
titleGenMaxTokens := 50

; ----------------------------------------------------
; PROVIDER INFERENCE MAP
; ----------------------------------------------------
; When a model name doesn't use "provider/model" format (e.g. "openai/gpt-4o"),
; the script infers the provider by checking if the name contains any of these
; prefixes. The first match wins. If no match, defaults to "deepseek".
;
; Format: Map("prefix", "provider-name", ...)

providerMap := Map(
    "deepseek", "deepseek",
    "gpt",      "openai",
    "o1",       "openai",
    "o3",       "openai",
    "claude",   "anthropic",
    "gemini",   "google"
)

; ----------------------------------------------------
; COMMANDS (Menu Commands)
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
;   thinking:         (Optional) Map with "type": "enabled" to enable DeepSeek
;                     reasoning (thinking blocks). When streaming, thinking
;                     content appears in a collapsible block before the response.
;                     In non-streaming mode, it's included in the response JSON
;                     as reasoning_content. Default: omitted (no thinking).
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
;   maxTokens:        (Optional) Maximum tokens in the response.  For FIM
;                     commands this overrides FIMMaxTokens (which defaults to
;                     4000).  Not set by default (API decides).
;
;   stop:             (Optional) Array of stop sequences (e.g. ["\n\n"]).
;                     Generation stops when any sequence appears.
;                     Not set by default (no stop sequences).
;
;   skipConfirmation: (Optional) When true, skips the confirmation dialog
;                     before sending the request.  Default: false.
;
;   copyAsMarkdown:   (Optional) When true, the response is copied as
;                     Markdown-formatted text.  Default: false.
;
;   tags:             (Optional) Array of submenu names used to group commands
;                     in the menu.  Each tag creates a submenu containing all
;                     commands that share that tag.  Default: [] (no grouping).
;
;   directAccelerator:
;                     (Optional) A keyboard accelerator string (e.g. "&r")
;                     that creates a top-level menu item as a shortcut to
;                     this command.  Press ` followed by the accelerator key
;                     to fire it without navigating into submenus.
;                     The command also stays in its original tagged submenu.
;                     Default: none.
; ============================================================================

; ============================================================================
; Example command template — copy and paste to create new commands:
;
; {
;     ; ---------- Copy this template ----------
;     commandName: "Your Command Name",
;     menuText: "&9 - Your Menu Label",        ; & defines accelerator key
;     systemMessage: "Your system message here. This sets the model's role.",
;     APIModels: "deepseek-v4-flash",          ; single model
;     ; APIModels: "deepseek-v4-pro, deepseek-v4-flash",  ; multi-model (Council)
;     ; APIModels: "openai/gpt-4o",            ; provider/model format
;
;     isCustomCommand: true,                   ; Shows input window
;     customInputInitialMessage: "",           ; (optional) pre-filled text
;     pasteMode: "replace",                    ; "chat", "replace", or "append"
;     stream: false,                           ; (optional, chat only) token-by-token response
;     thinking: { type: "enabled" },           ; (optional) DeepSeek reasoning (thinking blocks)
;     skipConfirmation: false,
;     copyAsMarkdown: false,
;     isFIM: false,                            ; Uses FIM beta endpoint
;     temperature: 0.7,                        ; (optional) 0 to 2
;     maxTokens: 500,                          ; (optional) overrides FIMMaxTokens
;     stop: ["\n\n"],                          ; (optional) stop sequences
;     tags: ["&Your tag"],
;     directAccelerator: "&y"                  ; (optional) ` then key shortcut
; }
; ============================================================================

commands := [
    {
        ; ---------- General assistant (V4 Pro) ----------
        commandName: "General assistant (V4 Pro)",
        menuText: "&1 - Ask DeepSeek V4 Pro",
        systemMessage: "You are a helpful assistant. Follow the instructions that I will provide or answer any questions that I will ask. My first query is the following:",
        APIModels: "deepseek/deepseek-v4-pro",
        isCustomCommand: false,
        customInputInitialMessage: "",
        pasteMode: "chat",
        skipConfirmation: false,
        copyAsMarkdown: false,
        isFIM: false,
        tags: ["&DeepSeek"],
        directAccelerator: ""
    }

    , {
        ; ---------- Quick ask (V4 Flash) ----------
        ; Same as General assistant, but uses the faster (and cheaper) Flash model.
        commandName: "Quick ask (V4 Flash)",
        menuText: "&2 - Ask DeepSeek V4 Flash",
        systemMessage: "You are a helpful assistant. Follow the instructions that I will provide or answer any questions that I will ask. My first query is the following:",
        APIModels: "deepseek/deepseek-v4-flash",
        isCustomCommand: true,
        customInputInitialMessage: "",
        pasteMode: "chat",
        stream: true,
        skipConfirmation: false,
        copyAsMarkdown: false,
        isFIM: false,
        tags: ["&DeepSeek"],
        directAccelerator: ""
    }

    , {
        ; ---------- Google Gemini ----------
        commandName: "Google Gemini",
        menuText: "&3 - Gemini 2.5 Pro",
        systemMessage: "You are a helpful assistant. Answer concisely and accurately.",
        APIModels: "google/gemini-2.5-pro",
        isCustomCommand: true,
        customInputInitialMessage: "",
        pasteMode: "chat",
        stream: true,
        skipConfirmation: false,
        copyAsMarkdown: false,
        isFIM: false,
        tags: ["&Google"],
        directAccelerator: ""
    }

    , {
        ; ---------- OpenAI GPT ----------
        commandName: "OpenAI GPT",
        menuText: "&4 - GPT-5 Mini",
        systemMessage: "You are a helpful assistant. Answer concisely and accurately.",
        APIModels: "openai/gpt-5-mini",
        isCustomCommand: true,
        customInputInitialMessage: "",
        pasteMode: "chat",
        stream: true,
        skipConfirmation: false,
        copyAsMarkdown: false,
        isFIM: false,
        tags: ["&OpenAI"],
        directAccelerator: ""
    }

    , {
        ; ---------- Rephrase ----------
        ; Copies selected text, sends it to the LLM with rephrase instructions,
        ; and replaces the original text with the rephrased version.
        commandName: "Rephrase",
        menuText: "&5 - Rephrase",
        systemMessage: "Your task is to rephrase the following text or paragraph in English to ensure clarity, conciseness, and a natural flow. If there are abbreviations present, expand it when it's used for the first time, like so: OCR (Optical Character Recognition). The revision should preserve the tone, style, and formatting of the original text. If possible, split it into paragraphs to improve readability. Additionally, correct any grammar and spelling errors you come across. You should also answer follow-up questions if asked. Respond with the rephrased text only:",
        APIModels: "deepseek/deepseek-v4-flash",
        isCustomCommand: false,
        customInputInitialMessage: "",
        pasteMode: "replace",
        skipConfirmation: false,
        copyAsMarkdown: false,
        isFIM: false,
        tags: ["&Text manipulation"],
        directAccelerator: "&r"
    }

    , {
        ; ---------- Summarize ----------
        commandName: "Summarize",
        menuText: "&6 - Summarize",
        systemMessage: "Your task is to summarize the following article in English to ensure clarity, conciseness, and a natural flow. If there are abbreviations present, expand it when it's used for the first time, like so: OCR (Optical Character Recognition). The summary should preserve the tone, style, and formatting of the original text, and should be in its original language. If possible, split it into paragraphs to improve readability. Additionally, correct any grammar and spelling errors you come across. You should also answer follow-up questions if asked. Respond with the rephrased text only:",
        APIModels: "deepseek/deepseek-v4-flash",
        isCustomCommand: false,
        customInputInitialMessage: "",
        pasteMode: "replace",
        skipConfirmation: false,
        copyAsMarkdown: false,
        isFIM: false,
        tags: ["&Text manipulation", "&Articles"],
        directAccelerator: ""
    }

    , {
        ; ---------- Translate to English ----------
        commandName: "Translate to English",
        menuText: "&7 - Translate to English",
        systemMessage: "Generate an English translation for the following text or paragraph, ensuring the translation accurately conveys the intended meaning or idea without excessive deviation. If there are abbreviations present, expand it when it's used for the first time, like so: OCR (Optical Character Recognition). The translation should preserve the tone, style, and formatting of the original text. If possible, split it into paragraphs to improve readability. Additionally, correct any grammar and spelling errors you come across. You should also answer follow-up questions if asked. Respond with the rephrased text only:",
        APIModels: "deepseek/deepseek-v4-flash",
        isCustomCommand: false,
        customInputInitialMessage: "",
        pasteMode: "replace",
        skipConfirmation: false,
        copyAsMarkdown: false,
        isFIM: false,
        tags: ["&Text manipulation", "Language"],
        directAccelerator: ""
    }

    , {
        ; ---------- Define ----------
        commandName: "Define",
        menuText: "&8 - Define",
        systemMessage: "Provide and explain the definition of the following, providing analogies if needed. In addition, answer follow-up questions if asked:",
        APIModels: "deepseek/deepseek-v4-flash",
        isCustomCommand: false,
        customInputInitialMessage: "",
        pasteMode: "replace",
        skipConfirmation: false,
        copyAsMarkdown: false,
        isFIM: false,
        tags: ["&Text manipulation", "Learning"],
        directAccelerator: ""
    }

    , {
        ; ---------- Auto-paste custom command ----------
        ; Combines two independent features:
        ;   isCustomCommand: shows an input window where you type any instruction
        ;   pasteMode:       "replace" pastes the result back into the active app
        ; (You can enable paste without custom command — just set pasteMode on any command
        ;  and the selected text is used directly.)
        commandName: "Auto-paste custom command",
        menuText: "&9 - Auto-paste custom command",
        systemMessage: "You are a helpful assistant. Follow the instructions that I will provide or answer any questions that I will ask.",
        APIModels: "deepseek/deepseek-v4-flash",
        isCustomCommand: true,
        customInputInitialMessage: "",
        pasteMode: "replace",
        skipConfirmation: false,
        copyAsMarkdown: false,
        isFIM: false,
        tags: ["&Custom commands", "&Auto paste"],
        directAccelerator: ""
    }

    , {
        ; ---------- Council (Pro + Flash) ----------
        ; Sends the same request to two models simultaneously, spawning
        ; separate Response Windows so you can compare answers side-by-side.
        commandName: "Multi-Provider Council",
        menuText: "&0 - Council (Pro + Flash + Gemini)",
        systemMessage: "You are a helpful assistant. Follow the instructions that I will provide or answer any questions that I will ask. My first query is the following:",
        APIModels: "deepseek/deepseek-v4-pro, deepseek/deepseek-v4-flash, google/gemini-2.5-flash",
        isCustomCommand: true,
        customInputInitialMessage: "",
        pasteMode: "chat",
        skipConfirmation: false,
        copyAsMarkdown: false,
        isFIM: false,
        tags: ["&Multi-models"],
        directAccelerator: ""
    }

    , {
        ; ---------- FIM Fill ----------
        ; Select the gap you want filled.  Script copies the selection, then
        ; copies the full text (Ctrl+A), splits around the selected text into
        ; prefix + suffix, and FIM fills the middle.  The result replaces the
        ; selection.
        commandName: "FIM Fill",
        menuText: "&F1 - FIM Fill",
        systemMessage: "",
        APIModels: "deepseek/deepseek-v4-flash",
        isCustomCommand: false,
        customInputInitialMessage: "",
        pasteMode: "replace",
        skipConfirmation: false,
        copyAsMarkdown: false,
        isFIM: true,
        tags: ["&FIM"],
        directAccelerator: ""
    }

    , {
        ; ---------- FIM Continue ----------
        ; Select prefix text (or just place cursor).  If nothing is selected,
        ; grabs text before the cursor (Ctrl+Shift+Home).  FIM generates a
        ; natural continuation that gets appended after the selection/cursor.
        commandName: "FIM Continue",
        menuText: "&F2 - FIM Continue",
        systemMessage: "",
        APIModels: "deepseek/deepseek-v4-flash",
        isCustomCommand: false,
        customInputInitialMessage: "",
        pasteMode: "append",
        skipConfirmation: false,
        copyAsMarkdown: false,
        isFIM: true,
        tags: ["&FIM"],
        directAccelerator: "&1",
        temperature: 1,
        maxTokens: 300
    }
]