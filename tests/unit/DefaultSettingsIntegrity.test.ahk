; ======================================================
; DefaultSettingsIntegrity.test.ahk
;
; Validates DefaultSettings.ahk integrity:
; - No corrupted Unicode characters
; - models block has required metadata fields
; - thinkingFormat and thinkingOff consistency
; ======================================================

class DefaultSettingsIntegrityTest {

    static __New() {
        RegisterTestClass("DefaultSettingsIntegrityTest")
    }

    ; --------------------------------------------------------
    ; Read file as raw bytes and check for known corrupted
    ; UTF-8 sequences that indicate Windows-1252 misinterpretation.
    ; --------------------------------------------------------
    NoCorruptedUnicode_DefaultSettings() {
	path := A_ScriptDir "\..\default-settings\DefaultSettings.ahk"
        if !FileExist(path)
            throw Error("DefaultSettings.ahk not found at " path)

        ; Read as raw bytes to avoid encoding issues
        f := FileOpen(path, "r", "UTF-8-RAW")
        if !f
            throw Error("Could not open DefaultSettings.ahk")
        raw := f.Read(f.Length)
        f.Close()

        ; Byte sequences to check (corrupted UTF-8 patterns):
        ; 0xC2 0xA7 = A-circumflex + section sign (corrupted SS)
        ; 0xE2 0x80 0x93 = corrupted en dash
        ; 0xE2 0x80 0x94 = corrupted em dash
        ; 0xE2 0x80 0x99 = corrupted right single quote
        corruptions := Map(
            [0xC2, 0xA7], "corrupted section sign (A-circumflex + SS)",
            [0xE2, 0x80, 0x93], "corrupted en dash",
            [0xE2, 0x80, 0x94], "corrupted em dash",
            [0xE2, 0x80, 0x99], "corrupted right single quote",
            [0xE2, 0x80, 0x9C], "corrupted left double quote",
            [0xE2, 0x80, 0x9D], "corrupted right double quote",
            [0xC3, 0xA2, 0xE2, 0x80, 0x9A], "corrupted em dash (ANSI path)"
        )

        buf := Buffer(1)
        for seq, desc in corruptions {
            ; Build search pattern from byte array
            pattern := ""
            for byte in seq
                pattern .= Chr(byte)
            if InStr(raw, pattern) > 0 {
                ; Find the position for context
                pos := InStr(raw, pattern)
                ; Extract context safely
                start := pos > 20 ? pos - 20 : 1
                endLen := Min(40, StrLen(raw) - start + 1)
                context := SubStr(raw, start, endLen)
                throw Error("Found " desc " in DefaultSettings.ahk at byte " pos ": " context)
            }
        }
    }

    OpenRouterFree_IsBuiltInDefault() {
        settingsPath := A_ScriptDir "\..\default-settings\DefaultSettings.ahk"
        modelsPath := A_ScriptDir "\..\default-settings\DefaultModels.ahk"
        settings := FileRead(settingsPath)
        models := FileRead(modelsPath)
        if !InStr(settings, '"openrouter", {')
            throw Error("DefaultSettings must define the built-in OpenRouter provider")
        if !InStr(settings, 'endpoint: "https://openrouter.ai/api/v1/chat/completions"')
            throw Error("DefaultSettings must use OpenRouter chat completions")
        if !InStr(settings, 'authEnvVar: "OPENROUTER_API_KEY"')
            throw Error("DefaultSettings must use OPENROUTER_API_KEY")
        if !InStr(models, '"openrouter/free", {')
            throw Error("DefaultModels must contain the built-in openrouter/free model")
        modelStart := InStr(models, '"openrouter/free", {')
        modelEntry := SubStr(models, modelStart, 600)
        if !InStr(modelEntry, 'provider: "openrouter"')
            throw Error("openrouter/free metadata must resolve to OpenRouter")
        if !InStr(modelEntry, "reasoning: false, vision: true")
            throw Error("openrouter/free metadata must advertise vision support without enabling reasoning")
    }

    ; --------------------------------------------------------
    ; Verify each model has required metadata fields.
    ; --------------------------------------------------------
    Models_HaveRequiredMetadataFields() {
        global models
        if !IsSet(models) || !IsObject(models)
            throw Error("models global is not set or not an object")

        requiredFields := ["provider", "api", "compat", "thinkingLevelMap", "thinkingOff",
                          "input", "cachedInput", "output", "context", "reasoning", "vision"]

        for modelId, m in models {
            for field in requiredFields {
                if !m.HasOwnProp(field)
                    throw Error("Model '" modelId "' missing required field: " field)
            }
            if !(m.compat is Map)
                throw Error("Model '" modelId "' compat must be a Map, got: " Type(m.compat))
            if !IsObject(m.thinkingLevelMap) || !(m.thinkingLevelMap is Map)
                throw Error("Model '" modelId "' thinkingLevelMap must be a Map, got: " Type(m.thinkingLevelMap))
            if m.api != "openai-completions"
                throw Error("Model '" modelId "' api must be 'openai-completions', got: " m.api)
        }
    }

    ; --------------------------------------------------------
    ; Verify thinkingFormat is valid.
    ; --------------------------------------------------------
    Models_HaveValidThinkingFormat() {
        global models
        validFormats := Map("openai", true, "deepseek", true, "google", true)

        for modelId, m in models {
            tf := m.compat.Has("thinkingFormat") ? m.compat["thinkingFormat"] : ""
            if !validFormats.Has(tf)
                throw Error("Model '" modelId "' has invalid thinkingFormat '" tf "'")
        }
    }

    ; --------------------------------------------------------
    ; Verify Google model thinkingOff is set for reasoning models.
    ; --------------------------------------------------------
    Models_GoogleThinkingOffConsistent() {
        global models
        for modelId, m in models {
            if m.provider != "google" || !m.reasoning
                continue
            offVal := m.HasOwnProp("thinkingOff") ? m.thinkingOff : ""
            if offVal = ""
                throw Error("Google reasoning model '" modelId "' should have thinkingOff set")
        }
    }

    ; --------------------------------------------------------
    ; Every default command's thinking config must use the new
    ; model-scoped format: {type:"enabled", level:"<level>"} where
    ; <level> is a key in the command's model thinkingLevelMap.
    ; This prevents a default command from showing "Model Default"
    ; in the single dropdown (e.g. the old {type:"disabled"} format).
    ; --------------------------------------------------------
    Commands_ThinkingLevelsMatchModelSupport() {
        global commands, models
        ; Note: AHK v2 has no IsArray() builtin — use Type() or the `is` operator.
        if !IsSet(commands) || !(Type(commands) = "Array")
            throw Error("commands global is not set or not an array")

        for i, c in commands {
            if !c.HasOwnProp("thinking") || !c.thinking
                continue
            thinking := c.thinking
            name := c.HasOwnProp("commandName") ? c.commandName : "index " i
            if !(Type(thinking) = "Object") || !thinking.HasOwnProp("type") || thinking.type != "enabled"
                throw Error("Command '" name "' thinking must be {type:'enabled', level:'<model-supported>'}; got: " jsongo.Stringify(thinking))
            if !thinking.HasOwnProp("level") || thinking.level = ""
                throw Error("Command '" name "' thinking must include a level")

            modelId := c.HasOwnProp("APIModels") ? c.APIModels : ""
            resolved := ""
            if modelId != "" && models.Has(modelId)
                resolved := modelId
            else if modelId != "" {
                for mid, m in models {
                    if SubStr(mid, InStr(mid, "/") + 1) = modelId {
                        resolved := mid
                        break
                    }
                }
            }
            if resolved = "" || !models.Has(resolved)
                continue  ; unknown model — cannot verify level support
            if !models[resolved].thinkingLevelMap.Has(thinking.level)
                throw Error("Command '" name "' thinking level '" thinking.level "' not supported by model '" resolved "' (level map: " jsongo.Stringify(models[resolved].thinkingLevelMap) ")")
        }
    }
}
