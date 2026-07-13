; ----------------------------------------------------
; ModelParser — Model ID parsing and sanitization
;
; Centralizes the "provider/model" parsing pattern.
; Named ModelParser (not ModelId) to avoid AHK v2
; case-insensitive conflict with UserConfig's modelId.
; ----------------------------------------------------

class ModelParser {
    static Split(fullId) {
        slashPos := InStr(fullId, "/")
        if slashPos > 0
            return { provider: SubStr(fullId, 1, slashPos - 1), name: SubStr(fullId, slashPos + 1) }
        return { provider: "", name: fullId }
    }

    static StripProvider(fullId) {
        slashPos := InStr(fullId, "/")
        return slashPos > 0 ? SubStr(fullId, slashPos + 1) : fullId
    }

    static Sanitize(fullId) {
        return StrReplace(ModelParser.StripProvider(fullId), ":", "-")
    }

    ; Strip version/date suffixes from model names.
    ; "gpt-4.1-2025-04-14" → "gpt-4.1"
    ; "claude-3-5-sonnet-20241022" → "claude-3-5-sonnet"
    static StripVersion(modelName) {
        ; Match trailing date suffix: -YYYY-MM-DD or -YYYYMMDD
        if RegExMatch(modelName, "-\d{4}-?\d{2}-?\d{2}$")
            return RegExReplace(modelName, "-\d{4}-?\d{2}-?\d{2}$", "")
        return modelName
    }
}
