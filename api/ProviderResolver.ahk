; ----------------------------------------------------
; ProviderResolver.ahk — LLM provider resolution
;
; Given a model string, resolves which provider and
; endpoint to use. Extracted from LLMRequestBuilder.ahk.
; ----------------------------------------------------

class ProviderResolver {

    ; Given a model string like "deepseek/deepseek-v4-pro" or "deepseek-v4-pro",
    ; returns { providerKey, modelName, apiKey, endpoint, fimEndpoint }.
    ; Falls back to the old format (no provider prefix) resolving through providerMap.
    static Resolve(modelId) {
        slashPos := InStr(modelId, "/")
        if slashPos > 0 {
            providerKey := SubStr(modelId, 1, slashPos - 1)
            modelName := SubStr(modelId, slashPos + 1)

            if providers.Has(providerKey) {
                p := providers[providerKey]
                apiKey := EnvGet(p.authEnvVar)
                return {
                    providerKey: providerKey,
                    modelName: modelName,
                    apiKey: apiKey,
                    endpoint: p.endpoint,
                    fimEndpoint: p.fimEndpoint
                }
            }
        }

        ; Legacy format: no provider prefix — infer from providerMap
        providerKey := "deepseek"
        for prefix, prov in providerMap {
            if InStr(modelId, prefix) {
                providerKey := prov
                break
            }
        }

        if providers.Has(providerKey) {
            p := providers[providerKey]
            apiKey := EnvGet(p.authEnvVar)
            return {
                providerKey: providerKey,
                modelName: modelId,
                apiKey: apiKey,
                endpoint: p.endpoint,
                fimEndpoint: p.fimEndpoint
            }
        }

        ; Fallback to deepseek
        p := providers["deepseek"]
        apiKey := EnvGet(p.authEnvVar)
        return {
            providerKey: "deepseek",
            modelName: modelId,
            apiKey: apiKey,
            endpoint: p.endpoint,
            fimEndpoint: p.fimEndpoint
        }
    }
}
