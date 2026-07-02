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
; THEME (dark mode components)
; ----------------------------------------------------
; Comment out any line below to disable that component's dark theme.

#Include lib\Dark_MsgBox.ahk              ; Dark mode MsgBox and InputBox
#Include lib\Dark_Menu.ahk                ; Dark mode menus
#Include lib\SystemThemeAwareToolTip.ahk  ; Dark mode tooltips

; ----------------------------------------------------
; UI — Input Window
; ----------------------------------------------------

inputWindowBackground    := "0x212529"     ; Background color for the text input window
inputWindowFontSize      := "s14"
inputWindowFontColor     := "cWhite"
inputWindowFontFace      := "Cambria"
inputWindowWidth         := 500            ; Width of the text input control in pixels
inputWindowHeight        := 250            ; Height of the text input control in pixels

; ----------------------------------------------------
; UI — Suspend Banner
; ----------------------------------------------------
; The yellow banner shown at the bottom of the screen when the script is suspended.

suspendBannerText        := "LLM AutoHotkey Assistant Suspended"
suspendBannerFontSize    := "s10"
suspendBannerFontFace    := "Cambria"
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
; OPTIONS MENU ITEMS
; ----------------------------------------------------
; Items shown under the "Options" submenu (press ` then Options).
; Each entry: { menuText, command }
;   command is either a URL to open ("https://...") or a file path to run.

optionsMenuItems := [
    { menuText: "&1 - Edit UserConfig",  command: "Notepad " A_ScriptDir "\UserConfig.ahk" },
    { menuText: "&2 - DeepSeek Platform", command: "https://platform.deepseek.com" },
    { menuText: "&3 - DeepSeek API Keys", command: "https://platform.deepseek.com/api_keys" },
    { menuText: "&4 - DeepSeek Usage",    command: "https://platform.deepseek.com/usage" }
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
;                       "" (empty) — stays in the Response Window (no paste)
;                       "replace"  — replaces the selected text in the active app
;                       "append"   — placed after the cursor/selection
;                     Default: "".
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

prompts := [
    {
        ; ---------- General assistant (V4 Pro) ----------
        promptName: "General assistant (V4 Pro)",
        menuText: "&1 - Ask DeepSeek V4 Pro",
        systemPrompt: "You are a helpful assistant. Follow the instructions that I will provide or answer any questions that I will ask. My first query is the following:",
        APIModels: "deepseek-v4-pro",
        isCustomPrompt: true,               ; Shows input window for your instruction
        customPromptInitialMessage: "",     ; (no pre-filled text)
        pasteMode: "",                      ; Response stays in Response Window
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
        pasteMode: "",
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
        pasteMode: "",                      ; Response stays in window
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
        pasteMode: "append",                ; Continuation placed after cursor
        skipConfirmation: false,
        copyAsMarkdown: false,
        isFIM: true,
        tags: ["&FIM"],
        directAccelerator: "&1"
    }
]