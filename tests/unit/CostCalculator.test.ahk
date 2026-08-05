; ======================================================
; CostCalculator.test.ahk — Unit tests for CostCalculator
; ======================================================

class CostCalculatorTest {

    static __New() {
        RegisterTestClass("CostCalculatorTest")
    }

    ; --- cachedInputCost is returned ---

    CachedInputCost_Returned() {
        usage := { promptTokens: 100000, completionTokens: 50000, cachedTokens: 40000 }
        costs := CostCalculator.ComputeTokenCosts("deepseek/deepseek-v4-flash", usage)
        if !costs.HasOwnProp("cachedInputCost")
            throw Error("Expected cachedInputCost property in costs object")
        if costs.cachedInputCost = ""
            throw Error("Expected non-empty cachedInputCost, got empty string")
        ; 40000 cached x $0.0028/1M = 0.000112
        if costs.cachedInputCost <= 0
            throw Error("Expected cachedInputCost > 0, got " costs.cachedInputCost)
    }

    ; --- cachedInputCost is zero when no cached tokens ---

    CachedInputCost_ZeroForNoCache() {
        usage := { promptTokens: 100, completionTokens: 50, cachedTokens: 0 }
        costs := CostCalculator.ComputeTokenCosts("deepseek/deepseek-v4-flash", usage)
        if costs.cachedInputCost != 0
            throw Error("Expected cachedInputCost=0 when no cache, got " costs.cachedInputCost)
    }

    ; --- inputCost is correct for uncached tokens ---

    InputCost_UncachedOnly() {
        usage := { promptTokens: 100, completionTokens: 50, cachedTokens: 0 }
        costs := CostCalculator.ComputeTokenCosts("deepseek/deepseek-v4-flash", usage)
        ; 100 x $0.14/1M = 0.000014
        if costs.inputCost < 0.000013 || costs.inputCost > 0.000015
            throw Error("Expected inputCost ~0.000014 for 100 uncached tokens, got " costs.inputCost)
    }

    ; --- inputCost splits cached and uncached correctly ---

    InputCost_WithCache() {
        usage := { promptTokens: 100000, completionTokens: 50000, cachedTokens: 60000 }
        costs := CostCalculator.ComputeTokenCosts("deepseek/deepseek-v4-flash", usage)
        ; uncached: 40 x $0.14/1M = 0.0000056
        ; cached: 60 x $0.0028/1M = 0.000000168
        ; total input: 0.000005768
        if costs.inputCost <= 0
            throw Error("Expected inputCost > 0, got " costs.inputCost)
        if costs.cachedInputCost <= 0
            throw Error("Expected cachedInputCost > 0, got " costs.cachedInputCost)
    }

    ; --- output cost is correct ---

    OutputCost() {
        usage := { promptTokens: 100, completionTokens: 200, cachedTokens: 0 }
        costs := CostCalculator.ComputeTokenCosts("deepseek/deepseek-v4-flash", usage)
        ; 200 x $0.28/1M = 0.000056
        if costs.outputCost < 0.00005 || costs.outputCost > 0.00006
            throw Error("Expected outputCost ~0.000056, got " costs.outputCost)
    }

    ; --- total cost is input + output ---

    TotalCost() {
        usage := { promptTokens: 1000000, completionTokens: 1000000, cachedTokens: 0 }
        costs := CostCalculator.ComputeTokenCosts("deepseek/deepseek-v4-flash", usage)
        expectedTotal := costs.inputCost + costs.outputCost
        if Abs(costs.totalCost - expectedTotal) > 0.000001
            throw Error("Expected totalCost = inputCost + outputCost, got " costs.totalCost " vs " expectedTotal)
    }

    ; --- lookup by short name (no provider prefix) ---

    LookupByShortName() {
        usage := { promptTokens: 1000, completionTokens: 100, cachedTokens: 0 }
        costs := CostCalculator.ComputeTokenCosts("deepseek-v4-flash", usage)
        if costs.inputCost = ""
            throw Error("Expected to find pricing for short name 'deepseek-v4-flash'")
    }

    ; Step 5: short-form ids resolve through ModelId.Lookup for every caller.
    LookupByShortName_OpenAI() {
        usage := { promptTokens: 1000, completionTokens: 100, cachedTokens: 0 }
        costs := CostCalculator.ComputeTokenCosts("gpt-5-mini", usage)
        if costs.inputCost = ""
            throw Error("Expected to find pricing for short name 'gpt-5-mini'")
    }

    ; --- context window is returned ---

    ContextWindow() {
        usage := { promptTokens: 100, completionTokens: 50, cachedTokens: 0 }
        costs := CostCalculator.ComputeTokenCosts("google/gemma-4-31b-it", usage)
        if costs.contextWindow != 262144
            throw Error("Expected contextWindow=262144 for gemma, got " costs.contextWindow)
    }

}
