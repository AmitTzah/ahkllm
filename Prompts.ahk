; ----------------------------------------------------
; DeepSeek API Key
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
; Prompts
; ----------------------------------------------------

prompts := [
    ; ============================================================================
    ; Each object in this array defines one command in the prompt menu.
    ; Field guide (common to all prompts):
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
    ;   isCustomPrompt:   (Optional) When true, the user is shown a text input
    ;                     window where they can type their own instruction instead
    ;                     of using only the selected text. Default: false.
    ;
    ;   customPromptInitialMessage:
    ;                     (Optional) Pre-filled text in the custom prompt input
    ;                     window. Only meaningful when isCustomPrompt: true.
    ;
    ;   isAutoPaste:      (Optional) When true, the LLM response is automatically
    ;                     pasted into the active application (no manual copy/paste
    ;                     needed). Automatically disabled when >1 model is used.
    ;                     Default: false.
    ;
    ;   skipConfirmation: (Optional) When true, skips the confirmation dialog
    ;                     before sending the request. Default: false.
    ;
    ;   copyAsMarkdown:   (Optional) When true, the response is copied as
    ;                     Markdown-formatted text. Default: false.
    ;
    ;   tags:             (Optional) Array of submenu names used to group prompts
    ;                     in the menu. Each tag creates a submenu containing all
    ;                     prompts that share that tag. Default: [] (no grouping).
    ; ============================================================================

    {
        ; ---------- General assistant (V4 Pro) ----------
        promptName: "General assistant (V4 Pro)",
        menuText: "&1 - Ask DeepSeek V4 Pro",
        systemPrompt: "You are a helpful assistant. Follow the instructions that I will provide or answer any questions that I will ask. My first query is the following:",
        APIModels: "deepseek-v4-pro",
        isCustomPrompt: true,
        customPromptInitialMessage: "",
        tags: ["&DeepSeek"]
    }

    , {
        ; ---------- Quick ask (V4 Flash) ----------
        promptName: "Quick ask (V4 Flash)",
        menuText: "&2 - Ask DeepSeek V4 Flash",
        systemPrompt: "You are a helpful assistant. Follow the instructions that I will provide or answer any questions that I will ask. My first query is the following:",
        APIModels: "deepseek-v4-flash",
        isCustomPrompt: true,
        customPromptInitialMessage: "",
        tags: ["&DeepSeek"]
    }

    , {
        ; ---------- Rephrase ----------
        ; Copies selected text, sends it to the LLM with rephrase instructions,
        ; and replaces the original text with the rephrased version.
        promptName: "Rephrase",
        menuText: "&3 - Rephrase",
        systemPrompt: "Your task is to rephrase the following text or paragraph in English to ensure clarity, conciseness, and a natural flow. If there are abbreviations present, expand it when it's used for the first time, like so: OCR (Optical Character Recognition). The revision should preserve the tone, style, and formatting of the original text. If possible, split it into paragraphs to improve readability. Additionally, correct any grammar and spelling errors you come across. You should also answer follow-up questions if asked. Respond with the rephrased text only:",
        APIModels: "deepseek-v4-pro",
        tags: ["&Text manipulation"]
    }

    , {
        ; ---------- Summarize ----------
        promptName: "Summarize",
        menuText: "&4 - Summarize",
        systemPrompt: "Your task is to summarize the following article in English to ensure clarity, conciseness, and a natural flow. If there are abbreviations present, expand it when it's used for the first time, like so: OCR (Optical Character Recognition). The summary should preserve the tone, style, and formatting of the original text, and should be in its original language. If possible, split it into paragraphs to improve readability. Additionally, correct any grammar and spelling errors you come across. You should also answer follow-up questions if asked. Respond with the rephrased text only:",
        APIModels: "deepseek-v4-pro",
        tags: ["&Text manipulation", "&Articles"]
    }

    , {
        ; ---------- Translate to English ----------
        promptName: "Translate to English",
        menuText: "&5 - Translate to English",
        systemPrompt: "Generate an English translation for the following text or paragraph, ensuring the translation accurately conveys the intended meaning or idea without excessive deviation. If there are abbreviations present, expand it when it's used for the first time, like so: OCR (Optical Character Recognition). The translation should preserve the tone, style, and formatting of the original text. If possible, split it into paragraphs to improve readability. Additionally, correct any grammar and spelling errors you come across. You should also answer follow-up questions if asked. Respond with the rephrased text only:",
        APIModels: "deepseek-v4-pro",
        tags: ["&Text manipulation", "Language"]
    }

    , {
        ; ---------- Define ----------
        promptName: "Define",
        menuText: "&6 - Define",
        systemPrompt: "Provide and explain the definition of the following, providing analogies if needed. In addition, answer follow-up questions if asked:",
        APIModels: "deepseek-v4-pro",
        tags: ["&Text manipulation", "Learning"]
    }

    , {
        ; ---------- Auto-paste custom prompt ----------
        ; Combines two independent features:
        ;   isCustomPrompt: shows an input window where you type any instruction
        ;   isAutoPaste:    pastes the LLM response directly into the active window
        ; (You can enable auto-paste without custom prompt — just set isAutoPaste
        ;  on any prompt and the selected text is used directly.)
        promptName: "Auto-paste custom prompt",
        menuText: "&7 - Auto-paste custom prompt",
        systemPrompt: "You are a helpful assistant. Follow the instructions that I will provide or answer any questions that I will ask.",
        APIModels: "deepseek-v4-flash",
        isCustomPrompt: true,       ; Opens text input for you to type any instruction
        isAutoPaste: true,          ; Pastes the LLM response straight into the active app
        tags: ["&Custom prompts", "&Auto paste"]
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
        tags: ["&DeepSeek", "&Multi-models"]
    }
]
