; ======================================================
; ChatRequestBuilder.test.ahk — Regression tests for ChatRequestBuilder.ahk
;
; Tests: Gemini thinking_config vs reasoning_effort mutual exclusion.
; Root cause: Google Gemini API rejects requests containing both
; reasoning_effort (OpenAI-compatible) and thinking_config (Google-native)
; in the same request body.
; ======================================================

class ChatRequestBuilderTest {

    static __New() {
        RegisterTestClass("ChatRequestBuilderTest")
    }

    _setupDb() {
        if ChatDB.isOpen {
            oldPath := ChatDB.dbPath
            ChatDB.Close()
            try FileDelete(oldPath)
        }
        ChatDB.Open(A_Temp "\test_crb_" A_TickCount ".db")
    }

    _teardownDb() {
        if ChatDB.isOpen {
            dbPath := ChatDB.dbPath
            ChatDB.Close()
            try FileDelete(dbPath)
        }
    }

    ; Helper: create a thread with a user message, configure requestParams,
    ; call buildRequest, return the parsed request JSON.
    _buildRequest(providerModel, reasoningOverride := "") {
        global activeThreadId, requestParams

        ; Ensure API keys are set for the test (buildRequest validates).
        ; EnvSet is process-scoped — no cleanup needed between tests.
        EnvSet("DEEPSEEK_API_KEY", "sk-test-deepseek-key")
        EnvSet("OPENAI_API_KEY", "sk-test-openai-key")
        EnvSet("GEMINI_API_KEY", "sk-test-gemini-key")

        this._setupDb()

        ; Create a thread
        ChatDB.Thread_Create("Test Thread")
        threads := ChatDB.Thread_List()
        activeThreadId := threads[threads.Length].id

        ; Insert a user message so Msg_GetActivePath returns a non-empty path
        ChatDB.Msg_Insert({
            thread_id: activeThreadId,
            role: "user",
            content: "Hello",
            parent_id: "",
            sibling_group: "",
            sibling_index: 0,
            reasoning: "",
            prompt_tokens: 0,
            completion_tokens: 0,
            total_tokens: 0,
            cached_tokens: 0
        })

        ; Configure requestParams
        requestParams := Map(
            "singleAPIModelName", providerModel,
            "stream", true,
            "pasteMode", "chat",
            "windowTitle", "test",
            "providerName", "",
            "uniqueID", A_TickCount
        )
        if reasoningOverride != ""
            requestParams["reasoningOverride"] := reasoningOverride

        result := buildRequest()

        this._teardownDb()

        ; Clean up temp files
        if requestParams.Has("chatHistoryJSONRequestFile")
            try FileDelete(requestParams["chatHistoryJSONRequestFile"])
        if requestParams.Has("cURLCommandFile")
            try FileDelete(requestParams["cURLCommandFile"])
        if requestParams.Has("cURLOutputFile")
            try FileDelete(requestParams["cURLOutputFile"])
        if requestParams.Has("cURLErrorFile")
            try FileDelete(requestParams["cURLErrorFile"])

        return result
    }

    ; --------------------------------------------------------
    ; Gemini 2.5 + reasoning override: extra_body with
    ; thinking_budget (numeric) + include_thoughts.
    ; 2.5 models use thinking_budget, not thinking_level.
    ; --------------------------------------------------------
    Gemini25_WithReasoningOverride_UsesExtraBodyWithThinkingBudget() {
        result := this._buildRequest("google/gemini-2.5-flash", "medium")

        if result = ""
            throw Error("buildRequest returned empty for Gemini 2.5 with reasoning override")

        parsed := jsongo.Parse(result)

        ; reasoning_effort should NOT be present (Gemini uses extra_body)
        if parsed.Has("reasoning_effort")
            throw Error("Expected NO reasoning_effort for Gemini 2.5")

        ; extra_body.google.thinking_config with thinking_budget should be present
        if !parsed.Has("extra_body")
            throw Error("Expected extra_body for Gemini 2.5")
        eb := parsed["extra_body"]
        if !eb.Has("google") || !eb["google"].Has("thinking_config")
            throw Error("Expected extra_body.google.thinking_config")
        tc := eb["google"]["thinking_config"]
        if !tc.Has("thinking_budget") || tc["thinking_budget"] != 8192
            throw Error("Expected thinking_budget=8192 for medium, got '" (tc.Has("thinking_budget") ? tc["thinking_budget"] : "absent") "'")
        if !tc.Has("include_thoughts") || tc["include_thoughts"] != true
            throw Error("Expected include_thoughts=true")
    }

    ; --------------------------------------------------------
    ; Gemini 3.x + reasoning override: extra_body.google.
    ; thinking_config with thinking_level + include_thoughts
    ; should be present (3.x models support thinking_level).
    ; --------------------------------------------------------
    Gemini3x_WithReasoningOverride_UsesExtraBodyWithThinkingLevel() {
        result := this._buildRequest("google/gemini-3.5-flash", "medium")

        if result = ""
            throw Error("buildRequest returned empty for Gemini 3.x with reasoning override")

        parsed := jsongo.Parse(result)

        ; reasoning_effort should NOT be present (3.x uses extra_body)
        if parsed.Has("reasoning_effort")
            throw Error("Expected NO reasoning_effort for Gemini 3.x")

        ; extra_body.google.thinking_config with thinking_level should be present
        if !parsed.Has("extra_body")
            throw Error("Expected extra_body for Gemini 3.x with reasoning override")
        eb := parsed["extra_body"]
        if !eb.Has("google") || !eb["google"].Has("thinking_config")
            throw Error("Expected extra_body.google.thinking_config")
        tc := eb["google"]["thinking_config"]
        if !tc.Has("thinking_level") || tc["thinking_level"] != "medium"
            throw Error("Expected thinking_level='medium', got '" (tc.Has("thinking_level") ? tc["thinking_level"] : "absent") "'")
        if !tc.Has("include_thoughts") || tc["include_thoughts"] != true
            throw Error("Expected include_thoughts=true")
    }

    ; --------------------------------------------------------
    ; Gemini 2.5 + reasoning=none: thinking_budget:0 via extra_body.
    ; Gemini 2.5 uses budget mechanism; "none" → budget 0 (disabled).
    ; --------------------------------------------------------
    Gemini25_WithReasoningNone_UsesExtraBodyBudgetZero() {
        result := this._buildRequest("google/gemini-2.5-flash", "none")

        if result = ""
            throw Error("buildRequest returned empty for Gemini 2.5 with reasoning=none")

        parsed := jsongo.Parse(result)

        ; reasoning_effort should NOT be present (Google uses extra_body)
        if parsed.Has("reasoning_effort")
            throw Error("Expected NO reasoning_effort for Gemini 2.5 with reasoning=none")

        ; extra_body.google.thinking_config with thinking_budget:0
        if !parsed.Has("extra_body")
            throw Error("Expected extra_body for Gemini 2.5 with reasoning=none")
        eb := parsed["extra_body"]
        if !eb.Has("google") || !eb["google"].Has("thinking_config")
            throw Error("Expected extra_body.google.thinking_config")
        tc := eb["google"]["thinking_config"]
        if !tc.Has("thinking_budget") || tc["thinking_budget"] != 0
            throw Error("Expected thinking_budget=0 for none, got '" (tc.Has("thinking_budget") ? tc["thinking_budget"] : "absent") "'")
    }

    ; --------------------------------------------------------
    ; Gemini 3.x + reasoning=none: thinking_level:MINIMAL via extra_body.
    ; Gemini 3.x can't fully disable; MINIMAL is best effort.
    ; --------------------------------------------------------
    Gemini3x_WithReasoningNone_UsesExtraBodyLevelMinimal() {
        result := this._buildRequest("google/gemini-3.5-flash", "none")

        if result = ""
            throw Error("buildRequest returned empty for Gemini 3.x with reasoning=none")

        parsed := jsongo.Parse(result)

        if parsed.Has("reasoning_effort")
            throw Error("Expected NO reasoning_effort for Gemini 3.x with reasoning=none")

        if !parsed.Has("extra_body")
            throw Error("Expected extra_body for Gemini 3.x with reasoning=none")
        tc := parsed["extra_body"]["google"]["thinking_config"]
        if !tc.Has("thinking_level") || tc["thinking_level"] != "MINIMAL"
            throw Error("Expected thinking_level='MINIMAL', got '" (tc.Has("thinking_level") ? tc["thinking_level"] : "absent") "'")
    }

    ; --------------------------------------------------------
    ; Gemini WITHOUT reasoning override: extra_body.google.
    ; thinking_config should be present, reasoning_effort NOT.
    ; --------------------------------------------------------
    Gemini_WithoutReasoningOverride_UsesThinkingConfig() {
        result := this._buildRequest("google/gemini-2.5-flash", "")

        if result = ""
            throw Error("buildRequest returned empty for Gemini without reasoning override")

        parsed := jsongo.Parse(result)

        ; reasoning_effort should NOT be present
        if parsed.Has("reasoning_effort")
            throw Error("Expected NO reasoning_effort for Gemini without reasoning override")

        ; extra_body.google.thinking_config should be present
        if !parsed.Has("extra_body")
            throw Error("Expected extra_body to be present for Gemini without reasoning override")
        eb := parsed["extra_body"]
        if !eb.Has("google")
            throw Error("Expected extra_body.google to be present")
        if !eb["google"].Has("thinking_config")
            throw Error("Expected extra_body.google.thinking_config to be present")
        tc := eb["google"]["thinking_config"]
        if !tc.Has("include_thoughts") || tc["include_thoughts"] != true
            throw Error("Expected extra_body.google.thinking_config.include_thoughts=true")
    }

    ; --------------------------------------------------------
    ; DeepSeek with reasoning=none: should use thinking:{type:"disabled"}
    ; NOT reasoning_effort.
    ; --------------------------------------------------------
    DeepSeek_WithReasoningNone_UsesThinkingDisabled() {
        result := this._buildRequest("deepseek/deepseek-v4-flash", "none")

        if result = ""
            throw Error("buildRequest returned empty for DeepSeek with reasoning=none")

        parsed := jsongo.Parse(result)

        ; reasoning_effort should NOT be present (DeepSeek rejects "none")
        if parsed.Has("reasoning_effort")
            throw Error("Expected NO reasoning_effort for DeepSeek with reasoning=none (DeepSeek rejects it)")

        ; thinking:{type:"disabled"} should be present
        if !parsed.Has("thinking")
            throw Error("Expected thinking to be present for DeepSeek with reasoning=none")
        if !parsed["thinking"].Has("type") || parsed["thinking"]["type"] != "disabled"
            throw Error("Expected thinking.type='disabled' for DeepSeek reasoning=none")
    }

    ; --------------------------------------------------------
    ; DeepSeek with reasoning level: should use reasoning_effort
    ; AND thinking:{type:"enabled"} (explicit toggle per API docs).
    ; --------------------------------------------------------
    DeepSeek_WithReasoningLevel_UsesReasoningEffortAndThinkingEnabled() {
        result := this._buildRequest("deepseek/deepseek-v4-flash", "high")

        if result = ""
            throw Error("buildRequest returned empty for DeepSeek with reasoning=high")

        parsed := jsongo.Parse(result)

        if !parsed.Has("reasoning_effort")
            throw Error("Expected reasoning_effort for DeepSeek with reasoning=high")
        if parsed["reasoning_effort"] != "high"
            throw Error("Expected reasoning_effort='high', got '" parsed["reasoning_effort"] "'")

        ; thinking:{type:"enabled"} should also be present (explicit toggle)
        if !parsed.Has("thinking")
            throw Error("Expected thinking toggle for DeepSeek with reasoning=high")
        if !parsed["thinking"].Has("type") || parsed["thinking"]["type"] != "enabled"
            throw Error("Expected thinking.type='enabled' for DeepSeek reasoning=high")
    }

    ; --------------------------------------------------------
    ; OpenAI with reasoning=none: should use reasoning_effort:"none".
    ; --------------------------------------------------------
    OpenAI_WithReasoningNone_UsesReasoningEffort() {
        result := this._buildRequest("openai/gpt-5-mini", "none")

        if result = ""
            throw Error("buildRequest returned empty for OpenAI with reasoning=none")

        parsed := jsongo.Parse(result)

        if !parsed.Has("reasoning_effort")
            throw Error("Expected reasoning_effort for OpenAI with reasoning=none")
        if parsed["reasoning_effort"] != "none"
            throw Error("Expected reasoning_effort='none', got '" parsed["reasoning_effort"] "'")
    }

    ; --------------------------------------------------------
    ; OpenAI with reasoning level: should use reasoning_effort.
    ; --------------------------------------------------------
    OpenAI_WithReasoningLevel_UsesReasoningEffort() {
        result := this._buildRequest("openai/gpt-5-mini", "high")

        if result = ""
            throw Error("buildRequest returned empty for OpenAI with reasoning=high")

        parsed := jsongo.Parse(result)

        if !parsed.Has("reasoning_effort")
            throw Error("Expected reasoning_effort for OpenAI with reasoning=high")
        if parsed["reasoning_effort"] != "high"
            throw Error("Expected reasoning_effort='high', got '" parsed["reasoning_effort"] "'")
    }
}
