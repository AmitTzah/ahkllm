; ModelResolver.ahk — model metadata lookup for full, short, and version-stripped ids.
; The class name avoids AHK v2's case-insensitive collision with common modelId locals.

#Include ModelParser.ahk

class ModelResolver {

    ; Look up model metadata by full or short id. Returns "" when unknown.
    ; Order: exact "provider/model" key, short-name match, then version-stripped match.
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
