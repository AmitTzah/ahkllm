; ----------------------------------------------------
; ProviderResolver.ahk — LLM provider resolution
;
; Given a model string, resolves which provider and
; endpoint to use. Extracted from LLMRequestBuilder.ahk.
; ----------------------------------------------------

class ProviderResolver {
    static _getApiKey(p) {
        if p.HasOwnProp("authMode") && p.authMode = "direct" && p.HasOwnProp("apiKey") && p.apiKey != ""
            return p.apiKey
        return EnvGet(p.authEnvVar)
    }

    static _buildResult(providerKey, modelName, p) {
        ; OpenRouter's built-in free router is itself addressed by the full
        ; model id "openrouter/free". Other built-in providers receive the
        ; provider-stripped model name (for example "deepseek-v4-flash").
        apiModelName := providerKey = "openrouter" ? providerKey "/" modelName : modelName
        resolvedKey := ProviderResolver._getApiKey(p)
        debugLog(ProviderResolver._AuthDiagnostic(providerKey, apiModelName, p, resolvedKey), "ProviderResolver")
        return {
            providerKey: providerKey,
            modelName: apiModelName,
            apiKey: resolvedKey,
            endpoint: p.endpoint,
            fimEndpoint: p.HasOwnProp("fimEndpoint") ? p.fimEndpoint : ""
        }
    }

    ; Redacted provider-auth diagnostics. Never include the credential itself
    ; or the cURL command line: both may contain sensitive bearer tokens.
    static _AuthDiagnostic(providerKey, apiModelName, p, resolvedKey) {
        authMode := p.HasOwnProp("authMode") ? p.authMode : "env"
        envVar := p.HasOwnProp("authEnvVar") ? p.authEnvVar : ""
        directConfigured := authMode = "direct" && p.HasOwnProp("apiKey") && p.apiKey != ""
        source := !resolvedKey ? "none" : (directConfigured ? "direct" : "env")
        return "provider=" providerKey " model=" apiModelName
            . " endpoint=" (p.HasOwnProp("endpoint") ? p.endpoint : "")
            . " authSource=" source " authEnvVar=" envVar
            . " keyPresent=" (resolvedKey != "" ? "true" : "false")
            . " keyLength=" StrLen(resolvedKey)
    }

    ; Given a model string like "deepseek/deepseek-v4-pro" or "deepseek-v4-pro",
    ; returns { providerKey, modelName, apiKey, endpoint, fimEndpoint }.
    ; Falls back to the old format (no provider prefix) resolving through providerMap.
    static Resolve(modelId) {
        parts := ModelParser.Split(modelId)
        if parts.provider {
            if providers.Has(parts.provider) {
                p := providers[parts.provider]
                return ProviderResolver._buildResult(parts.provider, parts.name, p)
            }
        }

        ; Legacy format: no provider prefix — infer from providerMap
        providerKey := "deepseek"
        for prefix, prov in providerMap {
            ; Bug #68: match by PREFIX only - a substring match (InStr) made
            ; "mygpt-custom" resolve to the gpt provider.
            if SubStr(modelId, 1, StrLen(prefix)) = prefix {
                providerKey := prov
                break
            }
        }

        if providers.Has(providerKey)
            return ProviderResolver._buildResult(providerKey, modelId, providers[providerKey])

        ; Bug #190: the old fallback was hardcoded to providers["deepseek"] -
        ; the Settings UI lets the user DELETE the deepseek provider (>=1
        ; provider must remain), and a missing-key Map index THROWS in AHK v2,
        ; crashing EVERY request for a model whose prefix is not covered.
        ; Fall back to the FIRST configured provider instead (a clean
        ; fallback; callers still surface api-key/endpoint errors) and never
        ; index a missing key.
        for firstKey in providers
            return ProviderResolver._buildResult(firstKey, modelId, providers[firstKey])
        return { providerKey: "", modelName: modelId, apiKey: "", endpoint: "", fimEndpoint: "" }
    }
}
