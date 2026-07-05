; ============================================================================
; UserConfig.ahk — Centralized user-facing configuration
; ============================================================================
; Edit this file to customize the LLM AutoHotkey Assistant.
; Changes take effect after saving and reloading (~^s).

; ----------------------------------------------------
; API KEY
; ----------------------------------------------------
; Reads from DEEPSEEK_API_KEY environment variable.
; Set it via:  setx DEEPSEEK_API_KEY "sk-your-key-here"
; Get your key at: https://platform.deepseek.com/api_keys

APIKey := EnvGet("DEEPSEEK_API_KEY")

if (!APIKey || APIKey = "") {
    MsgBox("DEEPSEEK_API_KEY environment variable is not set.`n`nSet it via:`n  setx DEEPSEEK_API_KEY `"sk-your-key-here`"`n`nThen restart this script.", "Missing API Key", "IconX")
    ExitApp()
}

; ----------------------------------------------------
; API ENDPOINT (chat completions)
; ----------------------------------------------------

APIEndpoint := "https://api.deepseek.com/chat/completions"

; ----------------------------------------------------
; FIM ENDPOINT (Fill In the Middle — beta)
; ----------------------------------------------------
; For code completion and text continuation.
; Max tokens is 4K.  Prefix = selected text (or text before cursor),
; suffix = text after the selection (optional).

FIMEndpoint       := "https://api.deepseek.com/beta/completions"
FIMMaxTokens      := 4000

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
chatDefaultModel := "deepseek-v4-flash"

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
; Main hotkey that opens the prompt menu.
; Change this to any key (e.g. "F1", "~^Space") to use a different hotkey.

mainHotkey     := "``"                ; Backtick — opens the prompt menu

; When you edit UserConfig.ahk (e.g. via mainHotkey> Options > Edit UserConfig which opens
; it in Notepad), Ctrl+S saves the file and the script auto-reloads to pick up
; the new settings.  The ~ prefix lets the keystroke pass through to the editor.
saveReloadHotkey := "~^s"             ; Ctrl+S — save config & reload script

; Dismisses the active input window (custom prompt, send to all, send to group)
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
; MODEL PRICING (for token usage display and cost estimation)
; ----------------------------------------------------
; Prices are in USD per 1M tokens. Set to 0 or omit to disable cost display.
; Format: Map("model-name", {input: price_per_1M_input, cachedInput: price_per_1M_cached, output: price_per_1M_output, context: context_window_tokens})
; To add pricing for other models/providers, add entries to this map.
; If a model is not found here, tokens will be displayed without cost estimates.
; If input or output is 0, cost is not calculated for that category.
; cachedInput defaults to 10% of input price if not specified.

modelPricing := Map(
    "deepseek-v4-pro",   {input: 0.435, cachedInput: 0.003625, output: 0.87, context: 1048576},
    "deepseek-v4-flash", {input: 0.14, cachedInput: 0.0028, output: 0.28, context: 1048576}
)

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

titleGenModel := "deepseek-v4-flash"
titleGenSystemPrompt := "Generate a short, descriptive title (max 6 words) for a conversation based on the first exchange. Respond with ONLY the title, no quotes, no punctuation, no commentary."
titleGenMaxTokens := 20

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
; PROMPTS (menu commands)
; ============================================================================
; Each object in this array defines one command in the prompt menu.
;
; --- REQUIRED FIELDS ---
;
;   promptName:       Internal identifier string (used by the script to
;                     reference this prompt — not shown to the end user).
;
;   menuText:         Label displayed in the tray/hotkey menu. The & character
;                     defines an accelerator key (e.g. "&1" lets the user
;                     press 1 to select that item).
;
;   systemPrompt:     The system message sent to the LLM. This sets the
;                     model's role / behaviour for this specific command.
;
;   APIModels:        One or more model identifiers, comma-separated.
;                     Supports "provider/model" format (e.g. "openai/gpt-4o")
;                     or direct model names (e.g. "deepseek-v4-pro").
;                     When multiple models are listed, a Response Window is
;                     opened for each one (multi-model "Council" mode).
;
; --- OPTIONAL FIELDS ---
;
;   isCustomPrompt:   (Optional) When true, the user is shown a text input
;                     window where they can type their own instruction instead
;                     of using only the selected text.  For FIM prompts this
;                     input becomes the suffix.  Default: false.
;
;   customPromptInitialMessage:
;                     (Optional) Pre-filled text in the custom prompt input
;                     window.  Only meaningful when isCustomPrompt: true.
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
;                     prompts this overrides FIMMaxTokens (which defaults to
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
;   tags:             (Optional) Array of submenu names used to group prompts
;                     in the menu.  Each tag creates a submenu containing all
;                     prompts that share that tag.  Default: [] (no grouping).
;
;   directAccelerator:
;                     (Optional) A keyboard accelerator string (e.g. "&r")
;                     that creates a top-level menu item as a shortcut to
;                     this prompt.  Press ` followed by the accelerator key
;                     to fire it without navigating into submenus.
;                     The prompt also stays in its original tagged submenu.
;                     Default: none.
; ============================================================================

; ============================================================================
; Example prompt template — copy and paste to create new commands:
;
; {
;     ; ---------- Copy this template ----------
;     promptName: "Your Prompt Name",
;     menuText: "&9 - Your Menu Label",        ; & defines accelerator key
;     systemPrompt: "Your system message here. This sets the model's role.",
;     APIModels: "deepseek-v4-flash",          ; single model
;     ; APIModels: "deepseek-v4-pro, deepseek-v4-flash",  ; multi-model (Council)
;     ; APIModels: "openai/gpt-4o",            ; provider/model format
;
;     isCustomPrompt: true,                    ; Shows input window
;     customPromptInitialMessage: "",          ; (optional) pre-filled text
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

prompts := [
    {
        ; ---------- General assistant (V4 Pro) ----------
        promptName: "General assistant (V4 Pro)",
        menuText: "&1 - Ask DeepSeek V4 Pro",
        systemPrompt: "You are a helpful assistant. Follow the instructions that I will provide or answer any questions that I will ask. My first query is the following:",
        APIModels: "deepseek-v4-pro",
        isCustomPrompt: false,               ; Shows input window for your instruction
        customPromptInitialMessage: "",     ; (no pre-filled text)
        pasteMode: "chat",                      ; Chat interface
        skipConfirmation: false,            ; Shows confirmation before sending
        copyAsMarkdown: false,              ; Copies as plain text
        isFIM: false,
        tags: ["&DeepSeek"],
        directAccelerator: ""               ; (no top-level shortcut)
    }

    , {
        ; ---------- Quick ask (V4 Flash) ----------
        ; Same as General assistant, but uses the faster (and cheaper) Flash model.
        promptName: "Quick ask (V4 Flash)",
        menuText: "&2 - Ask DeepSeek V4 Flash",
        systemPrompt: "You are a helpful assistant. Follow the instructions that I will provide or answer any questions that I will ask. My first query is the following:",
        APIModels: "deepseek-v4-flash",
        isCustomPrompt: true,
        customPromptInitialMessage: "",
        pasteMode: "chat",
        stream: true,                           ; (optional, chat only) token-by-token response
        skipConfirmation: false,
        copyAsMarkdown: false,
        isFIM: false,
        tags: ["&DeepSeek"],
        directAccelerator: ""
    }

    , {
        ; ---------- Rephrase ----------
        ; Copies selected text, sends it to the LLM with rephrase instructions,
        ; and replaces the original text with the rephrased version.
        promptName: "Rephrase",
        menuText: "&3 - Rephrase",
        systemPrompt: "Your task is to rephrase the following text or paragraph in English to ensure clarity, conciseness, and a natural flow. If there are abbreviations present, expand it when it's used for the first time, like so: OCR (Optical Character Recognition). The revision should preserve the tone, style, and formatting of the original text. If possible, split it into paragraphs to improve readability. Additionally, correct any grammar and spelling errors you come across. You should also answer follow-up questions if asked. Respond with the rephrased text only:",
        APIModels: "deepseek-v4-flash",
        isCustomPrompt: false,              ; Uses selected text directly (no input window)
        customPromptInitialMessage: "",
        pasteMode: "replace",               ; Replaces selected text with rephrased version
        skipConfirmation: false,
        copyAsMarkdown: false,
        isFIM: false,
        tags: ["&Text manipulation"],
        directAccelerator: "&r"             ; Press ` then R to fire directly
    }

    , {
        ; ---------- Summarize ----------
        promptName: "Summarize",
        menuText: "&4 - Summarize",
        systemPrompt: "Your task is to summarize the following article in English to ensure clarity, conciseness, and a natural flow. If there are abbreviations present, expand it when it's used for the first time, like so: OCR (Optical Character Recognition). The summary should preserve the tone, style, and formatting of the original text, and should be in its original language. If possible, split it into paragraphs to improve readability. Additionally, correct any grammar and spelling errors you come across. You should also answer follow-up questions if asked. Respond with the rephrased text only:",
        APIModels: "deepseek-v4-flash",
        isCustomPrompt: false,
        customPromptInitialMessage: "",
        pasteMode: "replace",
        skipConfirmation: false,
        copyAsMarkdown: false,
        isFIM: false,
        tags: ["&Text manipulation", "&Articles"],
        directAccelerator: ""
    }

    , {
        ; ---------- Translate to English ----------
        promptName: "Translate to English",
        menuText: "&5 - Translate to English",
        systemPrompt: "Generate an English translation for the following text or paragraph, ensuring the translation accurately conveys the intended meaning or idea without excessive deviation. If there are abbreviations present, expand it when it's used for the first time, like so: OCR (Optical Character Recognition). The translation should preserve the tone, style, and formatting of the original text. If possible, split it into paragraphs to improve readability. Additionally, correct any grammar and spelling errors you come across. You should also answer follow-up questions if asked. Respond with the rephrased text only:",
        APIModels: "deepseek-v4-flash",
        isCustomPrompt: false,
        customPromptInitialMessage: "",
        pasteMode: "replace",
        skipConfirmation: false,
        copyAsMarkdown: false,
        isFIM: false,
        tags: ["&Text manipulation", "Language"],
        directAccelerator: ""
    }

    , {
        ; ---------- Define ----------
        promptName: "Define",
        menuText: "&6 - Define",
        systemPrompt: "Provide and explain the definition of the following, providing analogies if needed. In addition, answer follow-up questions if asked:",
        APIModels: "deepseek-v4-flash",
        isCustomPrompt: false,
        customPromptInitialMessage: "",
        pasteMode: "replace",
        skipConfirmation: false,
        copyAsMarkdown: false,
        isFIM: false,
        tags: ["&Text manipulation", "Learning"],
        directAccelerator: ""
    }

    , {
        ; ---------- Auto-paste custom prompt ----------
        ; Combines two independent features:
        ;   isCustomPrompt: shows an input window where you type any instruction
        ;   pasteMode:      "replace" pastes the result back into the active app
        ; (You can enable paste without custom prompt — just set pasteMode on any prompt
        ;  and the selected text is used directly.)
        promptName: "Auto-paste custom prompt",
        menuText: "&7 - Auto-paste custom prompt",
        systemPrompt: "You are a helpful assistant. Follow the instructions that I will provide or answer any questions that I will ask.",
        APIModels: "deepseek-v4-flash",
        isCustomPrompt: true,               ; Shows input window for any instruction
        customPromptInitialMessage: "",
        pasteMode: "replace",               ; Pastes response straight into active app
        skipConfirmation: false,
        copyAsMarkdown: false,
        isFIM: false,
        tags: ["&Custom prompts", "&Auto paste"],
        directAccelerator: ""
    }

    , {
        ; ---------- DeepSeek Council (Pro + Flash) ----------
        ; Sends the same request to two models simultaneously, spawning
        ; separate Response Windows so you can compare answers side-by-side.
        promptName: "DeepSeek Council",
        menuText: "&8 - Council (Pro + Flash)",
        systemPrompt: "You are a helpful assistant. Follow the instructions that I will provide or answer any questions that I will ask. My first query is the following:",
        APIModels: "deepseek-v4-pro, deepseek-v4-flash",   ; Two models = two Response Windows
        isCustomPrompt: true,
        customPromptInitialMessage: "",
        pasteMode: "chat",                      ; Chat interface (multi-model, each window has its own chat)
        skipConfirmation: false,
        copyAsMarkdown: false,
        isFIM: false,
        tags: ["&DeepSeek", "&Multi-models"],
        directAccelerator: ""
    }

    , {
        ; ---------- FIM Fill ----------
        ; Select the gap you want filled.  Script copies the selection, then
        ; copies the full text (Ctrl+A), splits around the selected text into
        ; prefix + suffix, and FIM fills the middle.  The result replaces the
        ; selection.
        promptName: "FIM Fill",
        menuText: "&9 - FIM Fill",
        systemPrompt: "",
        APIModels: "deepseek-v4-flash",
        isCustomPrompt: false,
        customPromptInitialMessage: "",
        pasteMode: "replace",               ; FIM output replaces the selected gap
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
        promptName: "FIM Continue",
        menuText: "&0 - FIM Continue",
        systemPrompt: "",
        APIModels: "deepseek-v4-flash",
        isCustomPrompt: false,
        customPromptInitialMessage: "",
        pasteMode: "append",          ; FIM Continue — pastes result after cursor
        skipConfirmation: false,
        copyAsMarkdown: false,
        isFIM: true,
        tags: ["&FIM"],
        directAccelerator: "&1",
        temperature: 1,
        maxTokens: 300
    }
]
