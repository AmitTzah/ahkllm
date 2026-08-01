; ======================================================
; OpenAIChatCompletions.ahk -- OpenAI-compatible API handler
;
; Handles standard OpenAI chat completions endpoints for
; DeepSeek, OpenAI, and any OpenAI-compatible provider.
;
; Google models are delegated to GoogleChatCompletions
; (extra_body.google.thinking_config).
;
; model is an AHK Object with compat as a Map:
;   model.HasOwnProp("compat")        -- Object property check
;   model.compat.Has("thinkingFormat") -- Map key check
;
; Implements the OpenAI chat completions convention for thinking/reasoning
; parameters, with provider-specific shims for DeepSeek and Google.
; ======================================================

class OpenAIChatCompletions {

    ; ----------------------------------------------------
    ; Apply thinking/reasoning parameters to a request object.
    ;
    ; @param requestObj  -- the API request object (mutated in place)
    ; @param model       -- the model metadata Object (compat Map,
    ;                       thinkingLevelMap, thinkingOff)
    ; @param reasoning   -- the reasoning level string (e.g. "none", "low",
    ;                       "high", "xhigh") or "" for off
    ; @param modelId     -- (optional) full model ID for family detection
    ; ----------------------------------------------------
    static ApplyThinking(&requestObj, model, reasoning, modelId := "") {
        if !IsObject(model)
            return

        ; Resolve compat fields with safe defaults.
        ; model is an Object (HasOwnProp), model.compat is a Map (Has).
        thinkingFormat := model.HasOwnProp("compat") && model.compat.Has("thinkingFormat")
            ? model.compat["thinkingFormat"] : "openai"

        hasLevelMap := model.HasOwnProp("thinkingLevelMap") && IsObject(model.thinkingLevelMap)

        ; Google: delegate to GoogleChatCompletions
        if (thinkingFormat = "google") {
            GoogleChatCompletions.ApplyThinking(&requestObj, model, reasoning, modelId)
            return
        }

        if (reasoning && reasoning != "" && reasoning != "none") {
            ; --- Thinking ENABLED ---
            if (thinkingFormat = "deepseek") {
                requestObj.thinking := { type: "enabled" }
                if (hasLevelMap && model.thinkingLevelMap.Has(reasoning)
                    && model.compat.Has("supportsReasoningEffort")
                    && model.compat["supportsReasoningEffort"]) {
                    requestObj.reasoning_effort := model.thinkingLevelMap[reasoning]
                }
            } else {
                ; Standard OpenAI: reasoning_effort
                if (hasLevelMap && model.thinkingLevelMap.Has(reasoning))
                    requestObj.reasoning_effort := model.thinkingLevelMap[reasoning]
            }
        } else {
            ; --- Thinking DISABLED ---
            if (thinkingFormat = "deepseek") {
                offVal := model.HasOwnProp("thinkingOff") ? model.thinkingOff : ""
                if (offVal != "")
                    requestObj.thinking := { type: offVal }
            } else {
                offVal := model.HasOwnProp("thinkingOff") ? model.thinkingOff : ""
                if (offVal != "")
                    requestObj.reasoning_effort := offVal
            }
        }
    }

    ; ----------------------------------------------------
    ; Apply provider-specific defaults to a request object.
    ; Called when NO reasoning override is set.
    ; ----------------------------------------------------
    static ApplyDefaults(&requestObj, model) {
        if !IsObject(model)
            return
        thinkingFormat := model.HasOwnProp("compat") && model.compat.Has("thinkingFormat")
            ? model.compat["thinkingFormat"] : "openai"
        if (thinkingFormat = "google") {
            GoogleChatCompletions.ApplyDefaults(&requestObj)
        }
    }
}
