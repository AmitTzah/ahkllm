; ======================================================
; CostCalculator.test.ahk — Unit tests for CostCalculator
; ======================================================

class CostCalculatorTest {

    static __New() {
        RegisterTestClass("CostCalculatorTest")
    }

    ; Regression (bug #173): a mid-stream failure can leave usage as an EMPTY
    ; object (no usage chunk). ComputeTokenCosts must not crash reading
    ; promptTokens/completionTokens - it returns empty costs instead.
    EmptyUsage_DoesNotCrash() {
        usage := {}
        costs := CostCalculator.ComputeTokenCosts("deepseek/deepseek-v4-flash", usage)
        if costs.totalCost != ""
            throw Error("Expected empty totalCost for usage-less call, got " costs.totalCost)
        if costs.inputCost != "" || costs.outputCost != ""
            throw Error("Expected empty input/output costs for usage-less call, got " costs.inputCost "/" costs.outputCost)
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


    ; --- Bug #29: blank/zero/missing cachedInput falls back to 10% of input ---

    CachedInput_BlankString_Fallback() {
        m := { input: 10, cachedInput: "", output: 2, context: 1000 }
        CostCalculator._ResolvePricing(m, &inp, &cached, &outp, &ctx)
        if cached != 1
            throw Error("Expected cachedInputPrice=1 (10% of 10) for blank string, got " cached)
    }

    CachedInput_Zero_Fallback() {
        m := { input: 10, cachedInput: 0, output: 2, context: 1000 }
        CostCalculator._ResolvePricing(m, &inp, &cached, &outp, &ctx)
        if cached != 1
            throw Error("Expected cachedInputPrice=1 (10% of 10) for cachedInput=0, got " cached)
    }

    CachedInput_Missing_Fallback() {
        m := { input: 10, output: 2, context: 1000 }
        CostCalculator._ResolvePricing(m, &inp, &cached, &outp, &ctx)
        if cached != 1
            throw Error("Expected cachedInputPrice=1 (10% of 10) for missing cachedInput, got " cached)
    }

    CachedInput_ExplicitValue_Preserved() {
        m := { input: 10, cachedInput: 2.5, output: 2, context: 1000 }
        CostCalculator._ResolvePricing(m, &inp, &cached, &outp, &ctx)
        if cached != 2.5
            throw Error("Expected cachedInputPrice=2.5 for explicit value, got " cached)
    }

    CachedInput_BlankString_ComputeDoesNotThrow() {
        global models
        hadKey := models.Has("test/blank-cached-regression")
        saved := hadKey ? models["test/blank-cached-regression"] : ""
        models["test/blank-cached-regression"] := { provider: "test", input: 10, cachedInput: "", output: 20, context: 1000000 }
        try {
            usage := { promptTokens: 1000000, completionTokens: 0, cachedTokens: 1000000 }
            costs := CostCalculator.ComputeTokenCosts("test/blank-cached-regression", usage)
            if costs.cachedInputCost != 1
                throw Error("Expected cachedInputCost=1 for blank cachedInput fallback, got " costs.cachedInputCost)
            if costs.inputCost != 1
                throw Error("Expected inputCost=1 for blank cachedInput fallback, got " costs.inputCost)
        } finally {
            if hadKey
                models["test/blank-cached-regression"] := saved
            else
                models.Delete("test/blank-cached-regression")
        }
    }

    CachedInput_Zero_ComputeDoesNotThrow() {
        global models
        hadKey := models.Has("test/zero-cached-regression")
        saved := hadKey ? models["test/zero-cached-regression"] : ""
        models["test/zero-cached-regression"] := { provider: "test", input: 10, cachedInput: 0, output: 20, context: 1000000 }
        try {
            usage := { promptTokens: 1000000, completionTokens: 0, cachedTokens: 1000000 }
            costs := CostCalculator.ComputeTokenCosts("test/zero-cached-regression", usage)
            if costs.cachedInputCost != 1
                throw Error("Expected cachedInputCost=1 for zero cachedInput fallback, got " costs.cachedInputCost)
        } finally {
            if hadKey
                models["test/zero-cached-regression"] := saved
            else
                models.Delete("test/zero-cached-regression")
        }
    }

}
