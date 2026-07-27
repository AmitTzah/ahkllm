; ----------------------------------------------------
; RuntimeResolver.ahk — API key check, provider resolution, default assistant
;
; Checks that at least one configured provider has an API key, then resolves
; APIKey, APIEndpoint, FIMEndpoint, and defaultAssistant for runtime use.
; ----------------------------------------------------

; ----------------------------------------------------
; API KEY CHECK — Ensures at least one provider key is set
; Called AFTER SettingsHandler.Load() so direct-entry keys are available.
; ----------------------------------------------------
RuntimeResolver_CheckApiKeys() {
    global providers
    anyKeyFound := false
    keyProviders := ""
    for providerKey, p in providers {
        key := ""
        if p.HasOwnProp("authMode") && p.authMode = "direct" && p.HasOwnProp("apiKey") && p.apiKey != ""
            key := p.apiKey
        else if p.HasOwnProp("authEnvVar")
            key := EnvGet(p.authEnvVar)
        if key != "" {
            anyKeyFound := true
            break
        }
        keyProviders .= "`n  " (p.HasOwnProp("authEnvVar") ? p.authEnvVar : "direct") "  (for " p.displayName ")"
    }
    if !anyKeyFound {
        msg := "No API keys found.`n`n"
            . "Set at least one environment variable or enter a direct key in Settings and restart:"
            . keyProviders
            . "`n`nExample:"
            . "`n  setx DEEPSEEK_API_KEY sk-your-key-here"
        MsgBox(msg, "Missing API Keys", "IconX")
        ExitApp()
    }
}

; ----------------------------------------------------
; RESOLVE PRIMARY PROVIDER — first configured provider with a key
; ----------------------------------------------------
RuntimeResolver_ResolvePrimaryProvider() {
    global providers, APIKey, APIEndpoint, FIMEndpoint
    for providerKey, p in providers {
        apiKey := ""
        if p.HasOwnProp("authMode") && p.authMode = "direct" && p.HasOwnProp("apiKey") && p.apiKey != ""
            apiKey := p.apiKey
        else if p.HasOwnProp("authEnvVar")
            apiKey := EnvGet(p.authEnvVar)
        if apiKey != "" {
            APIKey := apiKey
            APIEndpoint := p.endpoint
            FIMEndpoint := p.HasOwnProp("fimEndpoint") ? p.fimEndpoint : ""
            return
        }
    }
    ; Safety net: fall back to deepseek
    if providers.Has("deepseek") {
        APIKey := ""
        APIEndpoint := providers["deepseek"].endpoint
        FIMEndpoint := providers["deepseek"].HasOwnProp("fimEndpoint") ? providers["deepseek"].fimEndpoint : ""
    }
}

; ----------------------------------------------------
; DEFAULT ASSISTANT — resolve from assistants array
; ----------------------------------------------------
; Does NOT mutate the assistants array — only reads isDefault.
defaultAssistant := ""
for a in assistants {
    if a.isDefault {
        defaultAssistant := a.name
        break
    }
}
if !defaultAssistant && assistants.Length > 0
    defaultAssistant := assistants[1].name
