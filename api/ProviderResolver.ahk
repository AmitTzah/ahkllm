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
        return {
            providerKey: providerKey,
            modelName: modelName,
            apiKey: ProviderResolver._getApiKey(p),
            endpoint: p.endpoint,
            fimEndpoint: p.fimEndpoint
        }
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

        ; Fallback to deepseek
        return ProviderResolver._buildResult("deepseek", modelId, providers["deepseek"])
    }
}
