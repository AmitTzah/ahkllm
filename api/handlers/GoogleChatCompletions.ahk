; ======================================================
; GoogleChatCompletions.ahk -- Google-specific thinking config
;
; Handles Google's extra_body.google.thinking_config for
; the OpenAI-compatible endpoint.
;
; Gemini 2.x: thinking_budget (numeric, 0 = off)
; Gemini 3.x / Gemma: thinking_level (string)
; ======================================================

class GoogleChatCompletions {

    ; Model-family detection via regex on the full model id.
    static _IsGemma4(modelId) {
        return RegExMatch(modelId, "i)gemma-?4")
    }

    static _IsGemini3Pro(modelId) {
        return RegExMatch(modelId, "i)gemini-3(?:\.\d+)?-pro")
    }

    static _IsGemini3Flash(modelId) {
        return RegExMatch(modelId, "i)gemini-3(?:\.\d+)?-flash")
            || modelId = "gemini-flash-latest"
            || modelId = "gemini-flash-lite-latest"
    }

    ; ----------------------------------------------------
    ; Get disabled thinking config per model family.
    ; ----------------------------------------------------
    static DisabledConfig(modelId) {
        if (GoogleChatCompletions._IsGemini3Pro(modelId))
            return { thinking_level: "LOW" }
        if (GoogleChatCompletions._IsGemini3Flash(modelId))
            return { thinking_level: "MINIMAL" }
        if (GoogleChatCompletions._IsGemma4(modelId))
            return { thinking_level: "MINIMAL" }
        ; Gemini 2.x: disable via budget 0; include_thoughts:false keeps the
        ; payload symmetric with the enabled config (bug #73).
        return { include_thoughts: false, thinking_budget: 0 }
    }

    ; ----------------------------------------------------
    ; Build thinking_config for an enabled thinking level.
    ; Uses thinking_level for 3.x/Gemma, budget for 2.x.
    ; Budget numbers are per-model-family tables (Gemini 2.x).
    ; ----------------------------------------------------
    static ThinkingConfig(modelId, levelValue) {
        tc := { include_thoughts: true }
        if (GoogleChatCompletions._IsGemini3Pro(modelId)
         || GoogleChatCompletions._IsGemini3Flash(modelId)
         || GoogleChatCompletions._IsGemma4(modelId)) {
            tc.thinking_level := levelValue
        } else {
            tc.thinking_budget := GoogleChatCompletions._GoogleBudget(modelId, levelValue)
        }
        return tc
    }

    ; ----------------------------------------------------
    ; Get budget token count for a Gemini 2.x model + effort.
    ; Hardcoded budget tables per Gemini 2.x model family.
    ; ----------------------------------------------------
    static _GoogleBudget(modelId, levelValue) {
        ; If levelValue is already a budget number (from models.dev data), use it
        if levelValue is Integer
            return levelValue

        ; Models.dev may provide budget strings like "1024" directly
        try {
            num := Integer(levelValue)
            if num > 0
                return num
        }

        ; Fallback: hardcoded budget tables matching pi
        budgets := GoogleChatCompletions._BudgetTable(modelId)
        if budgets.Has(levelValue)
            return budgets[levelValue]
        ; Minimal fallback
        return 1024
    }

    ; ----------------------------------------------------
    ; Budget tables per Gemini 2.x model family.
    ; ----------------------------------------------------
    static _BudgetTable(modelId) {
        ; Bug #75: match the Gemini FAMILY (gemini-2.5-pro), not any model whose
        ; name merely contains "2.5-pro" (e.g. my2.5-pro-custom).
        if InStr(modelId, "gemini-2.5-pro")
            return Map("minimal", 128, "low", 2048, "medium", 8192, "high", 32768)
        if InStr(modelId, "gemini-2.5-flash-lite")
            return Map("minimal", 512, "low", 2048, "medium", 8192, "high", 16384)
        if InStr(modelId, "gemini-2.5-flash")
            return Map("minimal", 1024, "low", 4096, "medium", 16384, "high", 65536)
        if InStr(modelId, "gemini-2.0-flash")
            return Map("minimal", 1024, "low", 4096, "medium", 8192, "high", 16384)
        ; Generic Gemini 2.x fallback
        return Map("minimal", 1024, "low", 4096, "medium", 8192, "high", 16384)
    }

    ; ----------------------------------------------------
    ; Apply Google thinking to a request object.
    ;
    ; @param requestObj  -- the API request object (mutated in place)
    ; @param model       -- model metadata (thinkingLevelMap)
    ; @param reasoning   -- reasoning level or "" for off
    ; @param modelId     -- full model ID for family detection
    ; ----------------------------------------------------
    static ApplyThinking(&requestObj, model, reasoning, modelId) {
        if (!IsObject(model))
            return

        hasLevelMap := model.HasOwnProp("thinkingLevelMap") && IsObject(model.thinkingLevelMap)

        if (reasoning && reasoning != "" && reasoning != "none") {
            ; Thinking enabled: use model-family-specific config
            if (hasLevelMap && model.thinkingLevelMap.Has(reasoning)) {
                tc := GoogleChatCompletions.ThinkingConfig(modelId, model.thinkingLevelMap[reasoning])
                requestObj.extra_body := { google: { thinking_config: tc } }
            }
        } else {
            ; Thinking disabled: use model-family-specific off config
            offConfig := GoogleChatCompletions.DisabledConfig(modelId)
            if (offConfig.HasOwnProp("thinking_level") || offConfig.HasOwnProp("thinking_budget"))
                requestObj.extra_body := { google: { thinking_config: offConfig } }
        }
    }

    ; ----------------------------------------------------
    ; Apply Google defaults (include_thoughts, no level/budget).
    ; Called when no reasoning override is set.
    ; ----------------------------------------------------
    static ApplyDefaults(&requestObj) {
        requestObj.extra_body := { google: { thinking_config: { include_thoughts: true } } }
    }
}
