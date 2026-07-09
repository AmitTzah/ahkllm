; ----------------------------------------------------
; CostCalculator — Token cost estimation
;
; Computes cost estimates for a given model and token usage.
; Looks up pricing from the global models map (defined in UserConfig.ahk).
; Tries full "provider/model" key first, then falls back to a short-name
; lookup by stripping the provider prefix.
; ----------------------------------------------------

class CostCalculator {
    static ComputeTokenCosts(model, usage) {
        costs := { inputCost: "", outputCost: "", totalCost: "", contextWindow: "" }

        contextWin := ""
        cachedInputPrice := 0
        inputPrice := 0
        outputPrice := 0

        ; Lookup in the models map — try full "provider/model" key first
        if models.Has(model) {
            m := models[model]
            inputPrice       := m.HasOwnProp("input")       ? m.input       : 0
            cachedInputPrice := m.HasOwnProp("cachedInput") ? m.cachedInput : (inputPrice * 0.1)
            outputPrice      := m.HasOwnProp("output")      ? m.output      : 0
            contextWin       := m.HasOwnProp("context")     ? m.context     : ""
        }

        ; Fallback: if the full key wasn't found, iterate models map by short
        ; name (strip provider prefix from each key) — some consumers pass
        ; model names without "provider/"
        if !models.Has(model) {
            modelShort := ModelParser.StripProvider(model)

            for fullKey, m in models {
                if ModelParser.StripProvider(fullKey) = modelShort {
                    inputPrice       := m.HasOwnProp("input")       ? m.input       : 0
                    cachedInputPrice := m.HasOwnProp("cachedInput") ? m.cachedInput : (inputPrice * 0.1)
                    outputPrice      := m.HasOwnProp("output")      ? m.output      : 0
                    contextWin       := m.HasOwnProp("context")     ? m.context     : ""
                    break
                }
            }
        }

        ; Calculate costs using resolved pricing
        if inputPrice > 0 || outputPrice > 0 || contextWin != "" {
            if contextWin != "" {
                costs.contextWindow := contextWin
            }

            ; Determine cached token count (default to 0 if not provided)
            cachedTokens := usage.HasOwnProp("cachedTokens") ? usage.cachedTokens : 0

            ; Calculate input cost: split cached vs non-cached
            if inputPrice > 0 && usage.promptTokens > 0 {
                nonCachedTokens := usage.promptTokens - cachedTokens
                nonCachedCost := nonCachedTokens * inputPrice / 1000000
                cachedCost := cachedTokens * cachedInputPrice / 1000000
                costs.inputCost := Round(nonCachedCost + cachedCost, 6)
            }

            ; Calculate output cost
            if outputPrice > 0 && usage.completionTokens > 0 {
                costs.outputCost := Round(usage.completionTokens * outputPrice / 1000000, 6)
            }

            ; Calculate total
            if (inputPrice > 0 || outputPrice > 0) && (costs.inputCost != "" || costs.outputCost != "") {
                total := (costs.inputCost != "" ? costs.inputCost : 0) + (costs.outputCost != "" ? costs.outputCost : 0)
                costs.totalCost := Round(total, 6)
            }
        }

        return costs
    }
}
