; A wire-only workaround for providers that truncate literal null arguments.
; The original application schema and actual RPC contract remain authoritative.
class ApplicationNullableArguments {
    static Enabled(providerInfo) {
        global models
        model := ModelResolver.Lookup(models, providerInfo.providerKey "/" providerInfo.modelName)
        if !IsObject(model) || !model.HasOwnProp("compat")
            return false
        fallback := model.compat.Get("thinkingFormat", "") = "xiaomi" ? "omit" : "native"
        return model.compat.Get("nativeToolNulls", fallback) = "omit"
    }

    static AllowsNull(schema) {
        schemaType := schema.Get("type", "")
        if schemaType is Array {
            for value in schemaType
                if value = "null"
                    return true
            return false
        }
        return schemaType = "null"
    }

    static Definitions(tools) {
        result := []
        for tool in tools {
            copy := tool.Clone()
            copy["parameters"] := this.Project(tool["parameters"])
            ; Strict OpenAI schemas require every property to be required;
            ; this provider-compatible projection intentionally makes nulls optional.
            copy["strict"] := false
            result.Push(copy)
        }
        return result
    }

    static OnlyNull(schema) {
        schemaType := schema.Get("type", "")
        return schemaType is Array ? schemaType.Length = 1 && schemaType[1] = "null" : schemaType = "null"
    }

    static Project(schema, property := false) {
        copy := schema.Clone()
        if property && this.AllowsNull(schema) {
            types := []
            for schemaType in schema["type"]
                if schemaType != "null"
                    types.Push(schemaType)
            copy["type"] := types.Length = 1 ? types[1] : types
            copy["description"] := schema.Get("description", "") " Optional: omit this parameter to request null; do not send JSON null."
        }
        if schema.Has("properties") {
            properties := Map(), required := []
            for name, child in schema["properties"] {
                if !this.OnlyNull(child)
                    properties[name] := this.Project(child, true)
            }
            for name in schema.Get("required", [])
                if properties.Has(name) && !this.AllowsNull(schema["properties"][name])
                    required.Push(name)
            copy["properties"] := properties
            copy["required"] := required
        }
        if schema.Has("items") && schema["items"] is Map
            copy["items"] := this.Project(schema["items"])
        return copy
    }

    static Restore(value, schema) {
        if value is Map && schema.Has("properties") {
            properties := schema["properties"]
            for name in schema.Get("required", [])
                if !value.Has(name) && properties.Has(name) && this.AllowsNull(properties[name])
                    value[name] := ApplicationJsonLiteral("null")
            for name, child in value
                if properties.Has(name)
                    this.Restore(child, properties[name])
        } else if value is Array && schema.Has("items") && schema["items"] is Map {
            for child in value
                this.Restore(child, schema["items"])
        }
        return value
    }
}
