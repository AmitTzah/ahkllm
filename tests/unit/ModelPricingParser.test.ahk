; ======================================================
; ModelPricingParser.test.ahk — Unit tests for
; ModelPricingParser (models_metadata.txt parsing)
;
; Regression: "Fetch Latest Models" reads the multi-line
; output of scripts/Refresh-Models.ps1 and must surface
; the full entry (including pricing) to the WebUI.
; ======================================================

class ModelPricingParserTest {

    static __New() {
        RegisterTestClass("ModelPricingParserTest")
    }

    ParsesMultilineEntries_WithIdsAndFullRaw() {
        content := (
            "models := Map(`n"
            . "    `"deepseek/deepseek-chat`", {`n"
            . "        provider: `"deepseek`", api: `"openai-completions`",`n"
            . "        thinkingLevelMap: Map(`"high`", `"high`"),`n"
            . "        thinkingOff: `"disabled`",`n"
            . "        input: 0.14, cachedInput: 0.0028, output: 0.28, context: 1000000, reasoning: true, vision: false`n"
            . "    },`n"
            . "    `"openai/gpt-5`", {`n"
            . "        provider: `"openai`",`n"
            . "        input: 1.25, cachedInput: 0.125, output: 10, context: 400000, reasoning: true, vision: true`n"
            . "    },`n"
            . ")"
        )
        models := ModelPricingParser.Parse(content)
        if models.Length != 2
            throw Error("Expected 2 models, got " models.Length)
        if models[1].id != "deepseek/deepseek-chat"
            throw Error("Unexpected first id: '" models[1].id "'")
        if InStr(models[1].raw, "input: 0.14") = 0
            throw Error("raw is missing pricing fields: " models[1].raw)
        if InStr(models[1].raw, "cachedInput: 0.0028") = 0
            throw Error("raw is missing cachedInput: " models[1].raw)
        if models[2].id != "openai/gpt-5"
            throw Error("Unexpected second id: '" models[2].id "'")
    }

    ParsesSingleLineEntries_ForBackwardCompatibility() {
        content := "models := Map(`n    `"openai/gpt-4`", { provider: `"openai`", input: 30, cachedInput: 0, output: 60, context: 8192, reasoning: false, vision: false },`n)"
        models := ModelPricingParser.Parse(content)
        if models.Length != 1
            throw Error("Expected 1 model, got " models.Length)
        if models[1].id != "openai/gpt-4"
            throw Error("Unexpected id: '" models[1].id "'")
        if InStr(models[1].raw, "input: 30") = 0
            throw Error("raw is missing pricing: " models[1].raw)
    }

    ParsesGeneratedMetadataFile() {
        ; Prefer the locally generated metadata (scripts/models_metadata.txt,
        ; written by scripts/Refresh-Models.ps1 and gitignored); fall back to
        ; the committed sample (tests/fixtures/models_metadata.txt) so the
        ; parser is always exercised in CI, where the generated file does not
        ; exist (regression: CI failed with "models_metadata.txt not found").
        ; An EMPTY generated file (a refresh that fetched 0 models - e.g. a
        ; failed models.dev call) is treated the same as a missing one: the
        ; parser must still be exercised against the committed sample.
        path := A_ScriptDir "\..\scripts\models_metadata.txt"
        models := []
        if FileExist(path)
            models := ModelPricingParser.Parse(FileRead(path, "UTF-8"))
        if models.Length = 0 {
            path := A_ScriptDir "\fixtures\models_metadata.txt"
            if !FileExist(path)
                throw Error("models_metadata.txt not found at " path)
            models := ModelPricingParser.Parse(FileRead(path, "UTF-8"))
        }
        if models.Length = 0
            throw Error("Expected at least one model from generated metadata file")
        for m in models {
            if !m.id
                throw Error("Model entry is missing id")
            if InStr(m.raw, "input:") = 0
                throw Error("Entry '" m.id "' is missing input pricing in raw")
            if InStr(m.raw, "context:") = 0
                throw Error("Entry '" m.id "' is missing context in raw")
        }
    }
}
