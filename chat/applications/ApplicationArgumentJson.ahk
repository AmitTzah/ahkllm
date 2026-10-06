; Preserve JSON boolean/null types while validating model-written arguments.
; jsongo normally represents booleans as integers and null as an empty string.
class ApplicationJsonLiteral {
    __New(raw) {
        this.raw := raw
        this.kind := raw = "null" ? "null" : "boolean"
        this.value := raw = "true"
    }
}

class ApplicationArgumentJson {
    static Parse(text) {
        replacements := Map()
        output := "", copied := 1, position := 1
        while RegExMatch(text, '"|\b(?:true|false|null)\b', &token, position) {
            if token[0] = '"' {
                closing := this._JsonStringEnd(text, token.Pos)
                if !closing
                    throw Error("Application JSON contains an unfinished string.")
                position := closing + 1
                continue
            }
            marker := "__ahkllm_literal_" ChatDB._UUID()
            replacements[marker] := ApplicationJsonLiteral(token[0])
            output .= SubStr(text, copied, token.Pos - copied) jsongo.Stringify(marker)
            copied := token.Pos + token.Len
            position := copied
        }
        output .= SubStr(text, copied)
        parsed := jsongo.Parse(output)
        if jsongo.error_log != ""
            throw Error("Application tool response contains invalid JSON.")
        return this.Restore(parsed, replacements)
    }

    static _JsonStringEnd(text, opening) {
        closing := opening
        while closing := InStr(text, '"', true, closing + 1) {
            backslashes := 0, beforeQuote := closing - 1
            while beforeQuote > opening && SubStr(text, beforeQuote, 1) = "\" {
                backslashes++
                beforeQuote--
            }
            if Mod(backslashes, 2) = 0
                return closing
        }
        return 0
    }

    static Restore(value, replacements) {
        if value is Map || value is Array {
            for key, item in value
                value[key] := this.Restore(item, replacements)
            return value
        }
        if Type(value) = "String" && replacements.Has(value)
            return replacements[value]
        return value
    }

    static Serialize(value) {
        if value is ApplicationJsonLiteral
            return value.raw
        if value is Map {
            fields := []
            for key, item in value
                fields.Push(jsongo.Stringify(key) ":" this.Serialize(item))
            return "{" this.Join(fields) "}"
        }
        if value is Array {
            fields := []
            for item in value
                fields.Push(this.Serialize(item))
            return "[" this.Join(fields) "]"
        }
        return jsongo.Stringify(value)
    }

    static Join(values) {
        result := ""
        for index, value in values
            result .= (index > 1 ? "," : "") value
        return result
    }
}
