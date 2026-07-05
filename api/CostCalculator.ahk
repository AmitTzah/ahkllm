; ----------------------------------------------------
; CostCalculator — Token cost estimation
;
; Computes cost estimates for a given model and token usage.
; Looks up pricing from the global modelPricing map (defined in UserConfig.ahk).
; Returns an object with formatted cost strings, or empty strings if pricing
; is not available for the model.
; ----------------------------------------------------

class CostCalculator {
    static ComputeTokenCosts(model, usage) {
        costs := { inputCost: "", outputCost: "", totalCost: "", contextWindow: "" }

        ; Handle provider/model format — use just the model part for lookup
        modelShort := model
        slashPos := InStr(model, "/")
        if slashPos > 0 {
            modelShort := SubStr(model, slashPos + 1)
        }

        ; Look up pricing for this model
        if modelPricing.Has(modelShort) {
            pricing := modelPricing[modelShort]
            inputPrice       := pricing.HasOwnProp("input")       ? pricing.input       : 0
            cachedInputPrice := pricing.HasOwnProp("cachedInput") ? pricing.cachedInput : (inputPrice * 0.1)
            outputPrice      := pricing.HasOwnProp("output")      ? pricing.output      : 0
            contextWin       := pricing.HasOwnProp("context")     ? pricing.context     : ""

            ; Determine cached token count (default to 0 if not provided)
            cachedTokens := usage.HasProp("cachedTokens") ? usage.cachedTokens : 0

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
            if contextWin != "" {
                costs.contextWindow := contextWin
            }
        }

        return costs
    }
}
