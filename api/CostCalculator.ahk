; ----------------------------------------------------
; CostCalculator — Token cost estimation
;
; Computes cost estimates for a given model and token usage.
; Looks up pricing from the global models map (defined in UserConfig.ahk).
; Falls back to the old modelPricing map for backward compatibility.
; Returns an object with formatted cost strings, or empty strings if pricing
; is not available for the model.
; ----------------------------------------------------

class CostCalculator {
    static ComputeTokenCosts(model, usage) {
        costs := { inputCost: "", outputCost: "", totalCost: "", contextWindow: "" }

        ; First try the full "provider/model" key in the new models map
        contextWin := ""
        cachedInputPrice := 0
        inputPrice := 0
        outputPrice := 0

        if models.Has(model) {
            m := models[model]
            inputPrice       := m.HasOwnProp("input")       ? m.input       : 0
            cachedInputPrice := m.HasOwnProp("cachedInput") ? m.cachedInput : (inputPrice * 0.1)
            outputPrice      := m.HasOwnProp("output")      ? m.output      : 0
            contextWin       := m.HasOwnProp("context")     ? m.context     : ""
        }

        ; Fallback: try the old modelPricing map (model name without provider prefix)
        if !inputPrice && !outputPrice {
            modelShort := model
            slashPos := InStr(model, "/")
            if slashPos > 0 {
                modelShort := SubStr(model, slashPos + 1)
            }

            if modelPricing.Has(modelShort) {
                pricing := modelPricing[modelShort]
                inputPrice       := pricing.HasOwnProp("input")       ? pricing.input       : 0
                cachedInputPrice := pricing.HasOwnProp("cachedInput") ? pricing.cachedInput : (inputPrice * 0.1)
                outputPrice      := pricing.HasOwnProp("output")      ? pricing.output      : 0
                contextWin       := pricing.HasOwnProp("context")     ? pricing.context     : ""
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
