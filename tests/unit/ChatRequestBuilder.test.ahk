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
        ChatDB.Open(A_Temp "\test_crb_" A_TickCount "_" Random(1000, 999999) ".db")
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
    _buildRequest(providerModel, reasoningOverride := "", toggleFlags := unset) {
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
        if IsSet(toggleFlags) {
            for toggleKey, toggleValue in toggleFlags
                requestParams[toggleKey] := toggleValue
        }

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
    ; Right-rail Advanced toggles are STUBS: they persist their state but
    ; must NEVER alter the API request body. response_format/tools would be
    ; wrong here (the features aren't implemented yet) — keep the body clean.
    ; --------------------------------------------------------
    AdvancedToggles_AreStubs_DoNotTouchRequestBody() {
        result := this._buildRequest("deepseek/deepseek-v4-flash", "", Map(
            "codeExecution", true,
            "webSearch", true
        ))

        if result = ""
            throw Error("buildRequest returned empty")

        parsed := jsongo.Parse(result)
        if parsed.Has("response_format")
            throw Error("stub toggles must not add response_format to the request")
        if parsed.Has("tools")
            throw Error("stub toggles must not add tools to the request")
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
    ; "none" is NOT an option in these models' sidebars (their level
    ; maps have no "none"), so it displays as "Model Default" → NO
    ; thinking config is sent.
    ; --------------------------------------------------------
    Gemini25_WithReasoningNone_OmitsThinkingConfig() {
        result := this._buildRequest("google/gemini-2.5-flash", "none")

        if result = ""
            throw Error("buildRequest returned empty for Gemini 2.5 with reasoning=none")

        parsed := jsongo.Parse(result)

        if parsed.Has("reasoning_effort")
            throw Error("Expected NO reasoning_effort for Gemini 2.5 with reasoning=none")
        if parsed.Has("extra_body")
            throw Error("Expected NO extra_body for Gemini 2.5 with reasoning=none (Model Default), got: " jsongo.Stringify(parsed["extra_body"]))
    }

    Gemini3x_WithReasoningNone_OmitsThinkingConfig() {
        result := this._buildRequest("google/gemini-3.5-flash", "none")

        if result = ""
            throw Error("buildRequest returned empty for Gemini 3.x with reasoning=none")

        parsed := jsongo.Parse(result)

        if parsed.Has("reasoning_effort")
            throw Error("Expected NO reasoning_effort for Gemini 3.x with reasoning=none")
        if parsed.Has("extra_body")
            throw Error("Expected NO extra_body for Gemini 3.x with reasoning=none (Model Default), got: " jsongo.Stringify(parsed["extra_body"]))
    }

    ; --------------------------------------------------------
    ; Violet/Gemma scenario (regression): gemma-4-31b-it's level map
    ; has no "none", but Violet's assistant config defaults to "none".
    ; The sidebar shows "Model Default" → NO thinking config sent.
    ; This is the exact case that produced thinking_level:"MINIMAL".
    ; --------------------------------------------------------
    Gemma_WithNoneReasoning_OmitsThinkingConfig() {
        result := this._buildRequest("google/gemma-4-31b-it", "none")

        if result = ""
            throw Error("buildRequest returned empty for Gemma with reasoning=none")

        parsed := jsongo.Parse(result)

        if parsed.Has("extra_body")
            throw Error("Expected NO extra_body for Gemma with reasoning=none (Model Default), got: " jsongo.Stringify(parsed["extra_body"]))
        if parsed.Has("reasoning_effort")
            throw Error("Expected NO reasoning_effort for Gemma with reasoning=none")
    }

    ; --------------------------------------------------------
    ; No reasoning override (Model Default): NO thinking config for
    ; any provider.
    ; --------------------------------------------------------
    Gemini_WithoutReasoningOverride_OmitsThinkingConfig() {
        result := this._buildRequest("google/gemini-2.5-flash", "")

        if result = ""
            throw Error("buildRequest returned empty for Gemini without reasoning override")

        parsed := jsongo.Parse(result)

        if parsed.Has("reasoning_effort")
            throw Error("Expected NO reasoning_effort for Gemini without reasoning override")
        if parsed.Has("extra_body")
            throw Error("Expected NO extra_body for Gemini without reasoning override (Model Default), got: " jsongo.Stringify(parsed["extra_body"]))
    }

    DeepSeek_WithoutReasoningOverride_OmitsThinkingConfig() {
        result := this._buildRequest("deepseek/deepseek-v4-flash", "")

        if result = ""
            throw Error("buildRequest returned empty for DeepSeek without reasoning override")

        parsed := jsongo.Parse(result)

        if parsed.Has("thinking")
            throw Error("Expected NO thinking for DeepSeek without reasoning override, got: " jsongo.Stringify(parsed["thinking"]))
        if parsed.Has("reasoning_effort")
            throw Error("Expected NO reasoning_effort for DeepSeek without reasoning override")
    }

    OpenAI_WithoutReasoningOverride_OmitsThinkingConfig() {
        result := this._buildRequest("openai/gpt-5-mini", "")

        if result = ""
            throw Error("buildRequest returned empty for OpenAI without reasoning override")

        parsed := jsongo.Parse(result)

        if parsed.Has("reasoning_effort")
            throw Error("Expected NO reasoning_effort for OpenAI without reasoning override, got: " jsongo.Stringify(parsed["reasoning_effort"]))
    }

    ; --------------------------------------------------------
    ; DeepSeek with reasoning=none: "none" is a supported level (added
    ; via models-corrections.json — DeepSeek disables thinking through
    ; the {"thinking":{"type":"disabled"}} toggle). Selecting it sends
    ; thinking:{type:"disabled"} (explicit off), no reasoning_effort.
    ; --------------------------------------------------------
    DeepSeek_WithReasoningNone_SendsDisabledConfig() {
        result := this._buildRequest("deepseek/deepseek-v4-flash", "none")

        if result = ""
            throw Error("buildRequest returned empty for DeepSeek with reasoning=none")

        parsed := jsongo.Parse(result)

        if parsed.Has("reasoning_effort")
            throw Error("Expected NO reasoning_effort for DeepSeek with reasoning=none")
        if !parsed.Has("thinking")
            throw Error("Expected thinking config for DeepSeek with reasoning=none")
        if !parsed["thinking"].Has("type") || parsed["thinking"]["type"] != "disabled"
            throw Error("Expected thinking:{type:'disabled'} for DeepSeek with reasoning=none, got: " jsongo.Stringify(parsed["thinking"]))
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

    ; ----------------------------------------------------
    ; Bug #142 regression: a follow-up request must keep the EARLIER user
    ; message's image content part (multi-turn vision). The old code only
    ; processed the LAST user message's attachments, so from exchange 2 on the
    ; API payload was pure text and the model could not answer follow-up
    ; questions about an attached image.
    ; ----------------------------------------------------
    FollowUpRequest_KeepsEarlierImageContext() {
        global activeThreadId, requestParams

        EnvSet("OPENAI_API_KEY", "sk-test-openai-key")

        this._setupDb()
        ChatDB.Thread_Create("Vision Follow-up")
        threads := ChatDB.Thread_List()
        activeThreadId := threads[threads.Length].id

        ; A real image file in a temp data dir (the request builder base64-
        ; encodes it into the API payload; content bytes do not need to be a
        ; valid image).
        oldDataDir := AppInfo.DataDir
        testDataDir := A_Temp "\llm_attach_test_" A_TickCount
        AppInfo.DataDir := testDataDir
        DirCreate(testDataDir "\attachments")
        imgPath := testDataDir "\attachments\img.png"
        FileAppend("fake-png-bytes", imgPath)

        try {
            ; Exchange 1: user message with an image attachment + assistant reply.
            u1Id := ChatDB.Msg_Insert({
                thread_id: activeThreadId, role: "user", content: "what is this?",
                parent_id: "", sibling_group: "", sibling_index: 0
            })
            ChatDB.Attachment_Insert(u1Id, {
                attachment_type: "image", file_path: "attachments\img.png",
                mime_type: "image/png", original_filename: "img.png",
                file_size: 14, extracted_text: ""
            })
            a1Id := ChatDB.Msg_Insert({
                thread_id: activeThreadId, role: "assistant", content: "a dog",
                model: "openai/gpt-5-mini", parent_id: u1Id
            })
            ; Exchange 2: plain-text follow-up about the same image.
            u2Id := ChatDB.Msg_Insert({
                thread_id: activeThreadId, role: "user", content: "and what about the colors?",
                parent_id: a1Id
            })

            requestParams := Map(
                "singleAPIModelName", "openai/gpt-5-mini",
                "stream", true,
                "pasteMode", "chat",
                "windowTitle", "test",
                "providerName", "",
                "uniqueID", A_TickCount
            )

            result := buildRequest()
            if result = ""
                throw Error("buildRequest returned empty for a vision follow-up")
            parsed := jsongo.Parse(result)
            msgs := parsed["messages"]

            ; The FIRST user message must keep its image content part in the
            ; follow-up request (bug #142 fixed), plus its original text.
            first := msgs[1]
            if first["role"] != "user" || Type(first["content"]) != "Array"
                throw Error("exchange-1 user message lost its content array: " jsongo.Stringify(first))
            hasImage := false
            hasText := false
            for part in first["content"] {
                if part.Has("type") && part["type"] = "image_url" && InStr(part["image_url"]["url"], "data:image/png;base64,")
                    hasImage := true
                if part.Has("type") && part["type"] = "text" && part["text"] = "what is this?"
                    hasText := true
            }
            if !hasImage
                throw Error("follow-up request dropped the earlier image part: " jsongo.Stringify(first))
            if !hasText
                throw Error("follow-up request dropped the earlier message text: " jsongo.Stringify(first))

            ; The follow-up user message itself has no attachments and stays text.
            last := msgs[msgs.Length]
            if last["role"] != "user" || Type(last["content"]) != "String"
                throw Error("follow-up message should stay plain text: " jsongo.Stringify(last))
        } finally {
            AppInfo.DataDir := oldDataDir
            try DirDelete(testDataDir, true)
            if requestParams.Has("chatHistoryJSONRequestFile")
                try FileDelete(requestParams["chatHistoryJSONRequestFile"])
            if requestParams.Has("cURLCommandFile")
                try FileDelete(requestParams["cURLCommandFile"])
            if requestParams.Has("cURLOutputFile")
                try FileDelete(requestParams["cURLOutputFile"])
            if requestParams.Has("cURLErrorFile")
                try FileDelete(requestParams["cURLErrorFile"])
            this._teardownDb()
        }
    }

    ; Regression (bug #199): with NO configured providers,
    ; ProviderResolver.Resolve returns providerKey="", and _ShowApiKeyError
    ; must NOT index providers[""] (a missing Map key THROWS in AHK v2). The
    ; friendly key error path has to survive the empty-provider state.
    ShowApiKeyError_EmptyProviders_DoesNotThrow() {
        global providers, providerMap, requestParams
        oldProviders := providers
        oldProviderMap := providerMap
        providers := Map()
        providerMap := Map()
        providerInfo := ProviderResolver.Resolve("deepseek/deepseek-v4-flash")
        requestParams["uniqueID"] := "test-empty-providers"
        requestParams["mainScriptHiddenHwnd"] := 0
        threw := ""
        try {
            _ShowApiKeyError(providerInfo)
        } catch Error as e {
            threw := e.Message
        }
        if threw != ""
            throw Error("_ShowApiKeyError must not throw with zero providers (bug #199): " threw)
        providers := oldProviders
        providerMap := oldProviderMap
    }
}
