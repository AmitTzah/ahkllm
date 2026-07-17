; ----------------------------------------------------
; RuntimeResolver.ahk — API key check, provider resolution, default assistant
;
; Checks that at least one configured provider has an API key, then resolves
; APIKey, APIEndpoint, FIMEndpoint, and defaultAssistant for runtime use.
; ----------------------------------------------------

; ----------------------------------------------------
; API KEY CHECK — Ensures at least one provider key is set
; ----------------------------------------------------
anyKeyFound := false
keyProviders := ""
for providerKey, p in providers {
    if EnvGet(p.authEnvVar) {
        anyKeyFound := true
        break
    }
    ; Build error message dynamically for any missing providers
    keyProviders .= "`n  " p.authEnvVar "  (for " p.displayName ")"
}
if !anyKeyFound {
    msg := "No API keys found.`n`n"
        . "Set at least one environment variable and restart:"
        . keyProviders
        . "`n`nExample:"
        . "`n  setx DEEPSEEK_API_KEY sk-your-key-here"
    MsgBox(msg, "Missing API Keys", "IconX")
    ExitApp()
}

; ----------------------------------------------------
; RESOLVE PRIMARY PROVIDER — first configured provider with a key
; ----------------------------------------------------
for providerKey, p in providers {
    apiKey := EnvGet(p.authEnvVar)
    if apiKey {
        APIKey := apiKey
        APIEndpoint := p.endpoint
        FIMEndpoint := p.fimEndpoint
        break
    }
}
; Safety net: if no provider matched (shouldn't happen after the check above),
; fall back to deepseek endpoint with empty key so errors are clear at API call time.
if !IsSet(APIKey) {
    APIKey := ""
    APIEndpoint := providers["deepseek"].endpoint
    FIMEndpoint := providers["deepseek"].fimEndpoint
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
