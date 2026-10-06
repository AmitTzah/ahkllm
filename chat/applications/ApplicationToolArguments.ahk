#Include ApplicationArgumentJson.ahk

; Validate the JSON-schema subset used by application function arguments.
; Applications remain authoritative for permissions and domain validation.
class ApplicationToolArguments {
    static Validate(value, schema, location := "arguments") {
        if !(schema is Map)
            throw Error("Application tool has an invalid argument schema.")
        if schema.Has("$ref")
            throw Error("Text-protocol tools require inline argument schemas.")
        if schema.Has("enum") {
            matched := false
            for option in schema["enum"]
                if (value is ApplicationJsonLiteral && (value.kind = "boolean" ? option = value.value : option = ""))
                    || ApplicationArgumentJson.Serialize(option) = ApplicationArgumentJson.Serialize(value)
                    matched := true
            if !matched
                throw Error(location " is not an allowed value.")
        }
        for keyword in ["anyOf", "oneOf", "allOf"] {
            if !schema.Has(keyword)
                continue
            matches := 0
            for alternative in schema[keyword] {
                try {
                    this.Validate(value, alternative, location)
                    matches++
                }
            }
            if (keyword = "anyOf" && !matches) || (keyword = "oneOf" && matches != 1)
                || (keyword = "allOf" && matches != schema[keyword].Length)
                throw Error(location " does not match " keyword ".")
        }
        expected := schema.Get("type", "")
        if expected != "" && !this.MatchesType(value, expected)
            throw Error(location " has the wrong type.")
        if value is Map
            this.ValidateObject(value, schema, location)
        else if value is Array {
            if schema.Has("minItems") && value.Length < schema["minItems"]
                throw Error(location " has too few items.")
            if schema.Has("maxItems") && value.Length > schema["maxItems"]
                throw Error(location " has too many items.")
            if schema.Has("items")
                for index, item in value
                    this.Validate(item, schema["items"], location "[" index "]")
        } else if Type(value) = "String" {
            if schema.Has("minLength") && StrLen(value) < schema["minLength"]
                throw Error(location " is too short.")
            if schema.Has("maxLength") && StrLen(value) > schema["maxLength"]
                throw Error(location " is too long.")
            if schema.Has("pattern") && !RegExMatch(value, schema["pattern"])
                throw Error(location " does not match the required pattern.")
        } else if Type(value) = "Integer" || Type(value) = "Float" {
            if schema.Has("minimum") && value < schema["minimum"]
                throw Error(location " is below its minimum.")
            if schema.Has("maximum") && value > schema["maximum"]
                throw Error(location " exceeds its maximum.")
        }
    }

    static ValidateObject(value, schema, location) {
        for required in schema.Get("required", [])
            if !value.Has(required)
                throw Error(location " is missing " required ".")
        properties := schema.Get("properties", Map())
        additional := schema.Get("additionalProperties", true)
        for name, item in value {
            if properties.Has(name)
                this.Validate(item, properties[name], location "." name)
            else if additional is Map
                this.Validate(item, additional, location "." name)
            else if !additional
                throw Error(location " contains an unexpected field: " name)
        }
    }

    static MatchesType(value, expected) {
        if expected is Array {
            for alternative in expected
                if this.MatchesType(value, alternative)
                    return true
            return false
        }
        switch expected {
            case "object": return value is Map
            case "array": return value is Array
            case "string": return Type(value) = "String"
            case "integer": return Type(value) = "Integer"
            case "number": return Type(value) = "Integer" || Type(value) = "Float"
            case "boolean": return value is ApplicationJsonLiteral && value.kind = "boolean"
            case "null": return value is ApplicationJsonLiteral && value.kind = "null"
            default: throw Error("Unsupported application argument type: " expected)
        }
    }
}
