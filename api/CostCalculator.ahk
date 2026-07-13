; ----------------------------------------------------
; CostCalculator — Token cost estimation
;
; Computes cost estimates for a given model and token usage.
; Looks up pricing from the global models map (defined in UserConfig.ahk).
; Tries full "provider/model" key first, then falls back to a short-name
; lookup by stripping the provider prefix.
; ----------------------------------------------------

class CostCalculator {
    ; Extract pricing from a model object into the provided output variables
    static _ResolvePricing(m, &inputPrice, &cachedInputPrice, &outputPrice, &contextWin) {
        inputPrice       := m.HasOwnProp("input")       ? m.input       : 0
        cachedInputPrice := m.HasOwnProp("cachedInput") ? m.cachedInput : (inputPrice * 0.1)
        outputPrice      := m.HasOwnProp("output")      ? m.output      : 0
        contextWin       := m.HasOwnProp("context")     ? m.context     : ""
    }

    static ComputeTokenCosts(model, usage) {
        costs := { inputCost: "", cachedInputCost: "", outputCost: "", totalCost: "", contextWindow: "" }

        contextWin := ""
        cachedInputPrice := 0
        inputPrice := 0
        outputPrice := 0

        ; Lookup in the models map — try full "provider/model" key first
        if models.Has(model) {
            CostCalculator._ResolvePricing(models[model], &inputPrice, &cachedInputPrice, &outputPrice, &contextWin)
        }

        ; Fallback: strip provider prefix or version suffix
        if !models.Has(model) {
            modelShort := ModelParser.StripProvider(model)
            for fullKey, m in models {
                shortKey := ModelParser.StripProvider(fullKey)
                if shortKey = modelShort || ModelParser.StripVersion(shortKey) = ModelParser.StripVersion(modelShort) {
                    CostCalculator._ResolvePricing(m, &inputPrice, &cachedInputPrice, &outputPrice, &contextWin)
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
                costs.cachedInputCost := Round(cachedCost, 6)
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
