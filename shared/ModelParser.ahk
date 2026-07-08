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
}
