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

prompts := [{
    promptName: "General assistant (V4 Pro)",
    menuText: "&1 - Ask DeepSeek V4 Pro",
    systemPrompt: "You are a helpful assistant. Follow the instructions that I will provide or answer any questions that I will ask. My first query is the following:",
    APIModels: "deepseek-v4-pro",
    isCustomPrompt: true,
    customPromptInitialMessage: "",
    tags: ["&DeepSeek"]
}, {
    promptName: "Quick ask (V4 Flash)",
    menuText: "&2 - Ask DeepSeek V4 Flash",
    systemPrompt: "You are a helpful assistant. Follow the instructions that I will provide or answer any questions that I will ask. My first query is the following:",
    APIModels: "deepseek-v4-flash",
    isCustomPrompt: true,
    customPromptInitialMessage: "",
    tags: ["&DeepSeek"]
}, {
    promptName: "Rephrase",
    menuText: "&3 - Rephrase",
    systemPrompt: "Your task is to rephrase the following text or paragraph in English to ensure clarity, conciseness, and a natural flow. If there are abbreviations present, expand it when it's used for the first time, like so: OCR (Optical Character Recognition). The revision should preserve the tone, style, and formatting of the original text. If possible, split it into paragraphs to improve readability. Additionally, correct any grammar and spelling errors you come across. You should also answer follow-up questions if asked. Respond with the rephrased text only:",
    APIModels: "deepseek-v4-pro",
    tags: ["&Text manipulation"]
}, {
    promptName: "Summarize",
    menuText: "&4 - Summarize",
    systemPrompt: "Your task is to summarize the following article in English to ensure clarity, conciseness, and a natural flow. If there are abbreviations present, expand it when it's used for the first time, like so: OCR (Optical Character Recognition). The summary should preserve the tone, style, and formatting of the original text, and should be in its original language. If possible, split it into paragraphs to improve readability. Additionally, correct any grammar and spelling errors you come across. You should also answer follow-up questions if asked. Respond with the rephrased text only:",
    APIModels: "deepseek-v4-pro",
    tags: ["&Text manipulation", "&Articles"]
}, {
    promptName: "Translate to English",
    menuText: "&5 - Translate to English",
    systemPrompt: "Generate an English translation for the following text or paragraph, ensuring the translation accurately conveys the intended meaning or idea without excessive deviation. If there are abbreviations present, expand it when it's used for the first time, like so: OCR (Optical Character Recognition). The translation should preserve the tone, style, and formatting of the original text. If possible, split it into paragraphs to improve readability. Additionally, correct any grammar and spelling errors you come across. You should also answer follow-up questions if asked. Respond with the rephrased text only:",
    APIModels: "deepseek-v4-pro",
    tags: ["&Text manipulation", "Language"]
}, {
    promptName: "Define",
    menuText: "&6 - Define",
    systemPrompt: "Provide and explain the definition of the following, providing analogies if needed. In addition, answer follow-up questions if asked:",
    APIModels: "deepseek-v4-pro",
    tags: ["&Text manipulation", "Learning"]
}, {
    promptName: "Auto-paste custom prompt",
    menuText: "&7 - Auto-paste custom prompt",
    systemPrompt: "You are a helpful assistant. Follow the instructions that I will provide or answer any questions that I will ask.",
    APIModels: "deepseek-v4-flash",
    isCustomPrompt: true,
    isAutoPaste: true,
    tags: ["&Custom prompts", "&Auto paste"]
}, {
    promptName: "DeepSeek Council",
    menuText: "&8 - Council (Pro + Flash)",
    systemPrompt: "You are a helpful assistant. Follow the instructions that I will provide or answer any questions that I will ask. My first query is the following:",
    APIModels: "deepseek-v4-pro, deepseek-v4-flash",
    isCustomPrompt: true,
    customPromptInitialMessage: "",
    tags: ["&DeepSeek", "&Multi-models"]
}]