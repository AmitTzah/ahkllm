; ======================================================
; ModelPricingParser.ahk — parse generated model metadata
; for the "Fetch Latest Models" refresh modal.
;
; Input: scripts/models_metadata.txt (output of
; scripts/Refresh-Models.ps1), e.g.
;
;   models := Map(
;       "deepseek/deepseek-chat", {
;           provider: "deepseek", api: "openai-completions",
;           ...
;           input: 0.14, cachedInput: 0.0028, output: 0.28,
;               context: 1000000, reasoning: true, vision: false
;       },
;   )
;
; Output: Array of { id: "provider/model", raw: "<full entry text>" }.
; The raw text keeps the pricing line so the WebUI can extract
; input/cachedInput/output/context/reasoning/vision from it.
; Single-line entries (old models_pricing.txt style) also parse.
; ======================================================

class ModelPricingParser {
    static Parse(content) {
        result := []
        inBlock := false
        currentModel := ""
        entryLines := []

        for line in StrSplit(content, "`n", "`r") {
            trimmed := Trim(line)

            if !inBlock {
                if InStr(trimmed, "models := Map(") {
                    inBlock := true
                }
                continue
            }

            if trimmed = ")"
                break

            if currentModel = "" {
                ; Entry header:  "provider/model", {
                if InStr(line, ", {") {
                    modelPart := StrSplit(line, ",")
                    currentModel := Trim(Trim(modelPart[1]), "`" ")
                    entryLines := [line]
                    ; Single-line entry: pricing is on the same line, ends with "},"
                    if InStr(trimmed, "},") || trimmed = "}" {
                        result.Push({ id: currentModel, raw: line })
                        currentModel := ""
                    }
                }
                continue
            }

            ; Collect multi-line entry until its closing "},"
            entryLines.Push(line)
            if trimmed = "}," || trimmed = "}" {
                result.Push({ id: currentModel, raw: ModelPricingParser._JoinLines(entryLines) })
                currentModel := ""
                entryLines := []
            }
        }

        return result
    }

    static _JoinLines(lines) {
        out := ""
        for i, line in lines
            out .= (i = 1 ? "" : "`n") line
        return out
    }
}
