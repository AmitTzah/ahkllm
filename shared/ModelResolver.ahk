; ======================================================
; ModelResolver.ahk - single model-metadata lookup that
; accepts both full "provider/model" ids and short ids.
;
; Step 5 of the architecture refactor: AttachmentUtils,
; CostCalculator, TreeRepo, ChatRequestBuilder, and
; ThreadSettings each implemented (or skipped) this
; full-id -> short-id fallback differently, which produced
; the short-form bug cluster (#43 thinking dropped,
; #51 vision gate, #36 command temperature/reasoning).
; Lookup() is now the one implementation.
;
; Named ModelResolver (not ModelId) because AHK v2
; identifiers are case-insensitive and "modelId" is already
; used as a loop variable across the codebase - a class
; named ModelId is treated as an unset local inside
; functions and triggers #Warn dialogs (see ModelParser's
; header for the same warning).
; ======================================================

#Include ModelParser.ahk

class ModelResolver {

    ; Look up model metadata by full or short id. Returns "" when unknown.
    ; Order: exact "provider/model" key, then short-name match, then
    ; version-stripped match (mirrors the old TreeRepo/CostCalculator
    ; fallbacks exactly).
    static Lookup(models, modelName) {
        if models.Has(modelName)
            return models[modelName]

        modelShort := ModelParser.StripProvider(modelName)
        for fullKey, m in models {
            if ModelParser.StripProvider(fullKey) = modelShort
                return m
        }

        modelBase := ModelParser.StripVersion(modelShort)
        if modelBase != modelShort {
            for fullKey, m in models {
                if ModelParser.StripVersion(ModelParser.StripProvider(fullKey)) = modelBase
                    return m
            }
        }
        return ""
    }

    ; True when the model id (full or short) is present in the map.
    static Has(models, modelName) {
        return ModelResolver.Lookup(models, modelName) != ""
    }
}
