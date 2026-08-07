; ======================================================
; LLMRequestBuilder.test.ahk — Unit tests for LLMRequestBuilder class
;
; Tests: createJSONRequest, createFIMRequest,
;        CurlBuilder.Build, CurlBuilder.BuildFIM,
;        ComputeTokenCosts, appendToChatHistory
; ======================================================

class LLMRequestBuilderTest {

    static __New() {
        RegisterTestClass("LLMRequestBuilderTest")
    }

    _setup() {
        return LLMRequestBuilder("sk-test-key")
    }

    ; --------------------
    ; createJSONRequest
    ; --------------------

    CreateJSONRequest_Simple() {
        client := this._setup()
        result := LLMRequestBuilder.createJSONRequest("deepseek-v4-flash", "You are helpful", "Hello", "", "", "", false, "")
        parsed := jsongo.Parse(result)
        if parsed["model"] != "deepseek-v4-flash"
            throw Error("Expected model 'deepseek-v4-flash', got '" parsed["model"] "'")
        msgs := parsed["messages"]
        if msgs.Length != 2
            throw Error("Expected 2 messages, got " msgs.Length)
        if msgs[1]["role"] != "system"
            throw Error("Expected first message role 'system'")
        if msgs[2]["content"] != "Hello"
            throw Error("Expected second message content 'Hello'")
    }

    CreateJSONRequest_NoSystem() {
        client := this._setup()
        result := LLMRequestBuilder.createJSONRequest("test-model", "", "just user", "", "", "", false, "")
        parsed := jsongo.Parse(result)
        if parsed["messages"].Length != 1
            throw Error("Expected 1 message without system prompt, got " parsed["messages"].Length)
        if parsed["messages"][1]["role"] != "user"
            throw Error("Expected role 'user'")
    }

    CreateJSONRequest_WithStream() {
        client := this._setup()
        result := LLMRequestBuilder.createJSONRequest("test", "s", "u", "", "", "", true, "")
        parsed := jsongo.Parse(result)
        ; jsongo serializes true as 1 — we check for "stream" key existence
        if !parsed.Has("stream")
            throw Error("Expected 'stream' key in JSON")
    }

    CreateJSONRequest_WithTemperature() {
        client := this._setup()
        result := LLMRequestBuilder.createJSONRequest("test", "s", "u", "0.7", "", "", false, "")
        parsed := jsongo.Parse(result)
        if parsed["temperature"] != 0.7
            throw Error("Expected temperature 0.7, got " parsed["temperature"])
    }

    CreateJSONRequest_WithMaxTokens() {
        client := this._setup()
        result := LLMRequestBuilder.createJSONRequest("test", "s", "u", "", "500", "", false, "")
        parsed := jsongo.Parse(result)
        if parsed["max_tokens"] != 500
            throw Error("Expected max_tokens 500, got " parsed["max_tokens"])
    }

    ; --------------------
    ; createFIMRequest
    ; --------------------

    CreateFIMRequest_WithPrefixOnly() {
        client := this._setup()
        result := client.createFIMRequest("deepseek-v4-flash", "some code here", "")
        parsed := jsongo.Parse(result)
        if parsed["model"] != "deepseek-v4-flash"
            throw Error("Expected model 'deepseek-v4-flash'")
        if parsed["prompt"] != "some code here"
            throw Error("Expected prompt 'some code here'")
        if parsed.Has("suffix")
            throw Error("Expected no suffix")
        if parsed["max_tokens"] != 4000
            throw Error("Expected max_tokens 4000, got " parsed["max_tokens"])
    }

    CreateFIMRequest_WithSuffix() {
        client := this._setup()
        result := client.createFIMRequest("test", "prefix", "suffix", "", "100", "")
        parsed := jsongo.Parse(result)
        if parsed["prompt"] != "prefix"
            throw Error("Expected prompt 'prefix'")
        if parsed["suffix"] != "suffix"
            throw Error("Expected suffix 'suffix'")
        if parsed["max_tokens"] != 100
            throw Error("Expected max_tokens 100, got " parsed["max_tokens"])
    }

    ; --------------------
    ; ResponseParser.ParseChatResponse — returns Object (use dot notation)
    ; --------------------

    ExtractJSONResponse_Standard() {
        raw := '{"choices":[{"message":{"content":"Hello world"},"finish_reason":"stop"}],"model":"deepseek-v4-flash","usage":{"prompt_tokens":10,"completion_tokens":5,"total_tokens":15}}'
        parsed := jsongo.Parse(raw)
        result := ResponseParser.ParseChatResponse(parsed)
        if result.response != "Hello world"
            throw Error("Expected response 'Hello world'")
        if result.model != "deepseek-v4-flash"
            throw Error("Expected model 'deepseek-v4-flash'")
        if result.usage.totalTokens != 15
            throw Error("Expected 15 totalTokens, got " result.usage.totalTokens)
    }

    ExtractJSONResponse_WithCache() {
        raw := '{"choices":[{"message":{"content":"Hello"},"finish_reason":"stop"}],"model":"deepseek-v4-flash","usage":{"prompt_tokens":100,"completion_tokens":20,"total_tokens":120,"prompt_cache_hit_tokens":50}}'
        parsed := jsongo.Parse(raw)
        result := ResponseParser.ParseChatResponse(parsed)
        if result.usage.cachedTokens != 50
            throw Error("Expected 50 cachedTokens, got " result.usage.cachedTokens)
    }

    ; --------------------
    ; ResponseParser.ParseFIMResponse — returns Object (use dot notation)
    ; --------------------

    ExtractFIMResponse_Standard() {
        raw := '{"choices":[{"text":"completed code","finish_reason":"stop"}],"model":"deepseek-v4-flash"}'
        parsed := jsongo.Parse(raw)
        result := ResponseParser.ParseFIMResponse(parsed)
        if result.response != "completed code"
            throw Error("Expected response 'completed code'")
        if result.model != "deepseek-v4-flash"
            throw Error("Expected model 'deepseek-v4-flash'")
    }

    ; --------------------
    ; parseSSELine — instance method on LLMRequestBuilder
    ; --------------------

    ParseSSELine_Content() {
        result := SSEParser.ParseLine('data: {"choices":[{"delta":{"content":"Hello"}}]}')
        if result.type != "content"
            throw Error("Expected type 'content', got '" result.type "'")
        if result.content != "Hello"
            throw Error("Expected content 'Hello', got '" result.content "'")
    }

    ParseSSELine_Reasoning() {
        result := SSEParser.ParseLine('data: {"choices":[{"delta":{"reasoning_content":"thinking...", "content":""}}]}')
        if result.type != "reasoning"
            throw Error("Expected type 'reasoning', got '" result.type "'")
        if result.content != "thinking..."
            throw Error("Expected content 'thinking...', got '" result.content "'")
    }

    ParseSSELine_Done() {
        result := SSEParser.ParseLine("data: [DONE]")
        if result.type != "done"
            throw Error("Expected type 'done', got '" result.type "'")
    }

    ParseSSELine_Finish() {
        line := 'data: {"choices":[{"finish_reason":"stop"}],"model":"deepseek","usage":{"prompt_tokens":10,"completion_tokens":5,"total_tokens":15}}'
        result := SSEParser.ParseLine(line)
        if result.type != "finish"
            throw Error("Expected type 'finish', got '" result.type "'")
        if result.reason != "stop"
            throw Error("Expected reason 'stop', got '" result.reason "'")
        if result.usage.totalTokens != 15
            throw Error("Expected usage.totalTokens=15")
    }

    ParseSSELine_Ignore() {
        result := SSEParser.ParseLine("event: ping")
        if result.type != "ignore"
            throw Error("Expected type 'ignore', got '" result.type "'")
    }

    ParseSSELine_NotData() {
        client := this._setup()
        ; Input that doesn't start with "data: " — should return { type: "ignore" }
        result := SSEParser.ParseLine("just a random line without data prefix")
        if !IsObject(result)
            throw Error("Expected Object result")
        if result.type != "ignore"
            throw Error("Expected type 'ignore', got '" result.type "'")
    }

    ; --------------------
    ; ComputeTokenCosts — returns Object (use dot notation)
    ; --------------------

    ComputeTokenCosts_KnownModel() {
        usage := {promptTokens: 100, completionTokens: 50, totalTokens: 150, cachedTokens: 0}
        costs := CostCalculator.ComputeTokenCosts("deepseek-v4-flash", usage)
        if costs.inputCost = "" || costs.inputCost <= 0
            throw Error("Expected positive inputCost, got '" costs.inputCost "'")
        if costs.outputCost = "" || costs.outputCost <= 0
            throw Error("Expected positive outputCost")
        if costs.totalCost = "" || costs.totalCost <= 0
            throw Error("Expected positive totalCost")
    }

    ComputeTokenCosts_WithCache() {
        usage := {promptTokens: 200, completionTokens: 50, totalTokens: 250, cachedTokens: 100}
        costs := CostCalculator.ComputeTokenCosts("deepseek-v4-flash", usage)
        if costs.inputCost = "" || costs.inputCost <= 0
            throw Error("Expected positive inputCost with cache")
        if costs.totalCost = "" || costs.totalCost <= 0
            throw Error("Expected positive totalCost with cache")
    }

    ComputeTokenCosts_UnknownModel() {
        usage := {promptTokens: 100, completionTokens: 50, totalTokens: 150, cachedTokens: 0}
        costs := CostCalculator.ComputeTokenCosts("unknown-model", usage)
        if costs.inputCost != ""
            throw Error("Expected empty inputCost for unknown model")
        if costs.totalCost != ""
            throw Error("Expected empty totalCost for unknown model")
    }

    ; --------------------
    ; CurlBuilder.Build (static)
    ; --------------------

    CurlBuilderBuild_Format() {
        ; Build a minimal providerInfo for the test
        pi := { providerKey: "deepseek", endpoint: "https://api.deepseek.com/chat/completions", apiKey: "sk-test-key" }
        cmd := CurlBuilder.Build(pi, "req.json", "out.json")
        if !InStr(cmd, "cURL.exe")
            throw Error("Expected cURL.exe in command")
        if !InStr(cmd, "sk-test-key")
            throw Error("Expected API key in command")
        if !InStr(cmd, "req.json")
            throw Error("Expected request file in command")
        if !InStr(cmd, "out.json")
            throw Error("Expected output file in command")
    }

    CurlBuilderBuildFIM_Format() {
        pi := { providerKey: "deepseek", endpoint: "https://api.deepseek.com/chat/completions", fimEndpoint: "https://api.deepseek.com/beta/completions", apiKey: "sk-test-key" }
        cmd := CurlBuilder.BuildFIM(pi, "fim-req.json", "fim-out.json")
        if !InStr(cmd, "cURL.exe")
            throw Error("Expected cURL.exe in FIM command")
        if !InStr(cmd, "fim-req.json")
            throw Error("Expected FIM request file in command")
    }

    ; --------------------
    ; appendToChatHistory
    ; --------------------

    AppendToChatHistory_AddsAssistant() {
        client := this._setup()
        request := '{"model":"test","messages":[{"role":"user","content":"hi"}]}'
        tempFile := A_Temp "\test_append_" A_TickCount ".json"
        ; Pass by ref (AHK v2 syntax)
        localRef := request
        client.appendToChatHistory("assistant", "Hello!", &localRef, tempFile)
        parsed := jsongo.Parse(localRef)
        msgs := parsed["messages"]
        if msgs.Length != 2
            throw Error("Expected 2 messages after append, got " msgs.Length)
        if msgs[2]["role"] != "assistant"
            throw Error("Expected assistant role")
        if msgs[2]["content"] != "Hello!"
            throw Error("Expected content 'Hello!'")
        FileDelete(tempFile)
    }

    ; --------------------
    ; LogRequest
    ; --------------------

    LogRequest_CreatesEntry() {
        logPath := ApiLogger.logFilePath
        hadLog := FileExist(logPath)
        backupPath := ""
        if hadLog {
            backupPath := logPath ".bak"
            FileCopy(logPath, backupPath, 1)
        }
        ApiLogger.LogRequest({
            timestamp: "2025-01-01 00:00:00",
            promptName: "Test",
            provider: "deepseek",
            model: "deepseek-v4-flash",
            isFIM: false,
            endpoint: "https://api.test",
            pasteMode: "chat",
            request: "{}",
            response: "{}",
            status: "success"
        })
        logs := ApiLogger.ReadLogs()
        if logs.Length < 1
            throw Error("Expected at least 1 log entry, got " logs.Length)
        if logs[1]["promptName"] != "Test"
            throw Error("Expected log promptName 'Test'")
        FileDelete(logPath)
        if backupPath && FileExist(backupPath)
            FileMove(backupPath, logPath, 1)
    }

    ; ----------------------------------------------------
    ; ResolveProvider tests
    ; ----------------------------------------------------

    ResolveProvider_NewFormat() {
        info := ProviderResolver.Resolve("openai/gpt-4.1-mini")
        if info.providerKey != "openai"
            throw Error("Expected providerKey 'openai', got '" info.providerKey "'")
        if info.modelName != "gpt-4.1-mini"
            throw Error("Expected modelName 'gpt-4.1-mini', got '" info.modelName "'")
        if !InStr(info.endpoint, "openai.com")
            throw Error("Expected OpenAI endpoint, got '" info.endpoint "'")
    }

    ResolveProvider_LegacyFormat() {
        info := ProviderResolver.Resolve("deepseek-v4-flash")
        if info.providerKey != "deepseek"
            throw Error("Expected providerKey 'deepseek', got '" info.providerKey "'")
        if info.modelName != "deepseek-v4-flash"
            throw Error("Expected modelName 'deepseek-v4-flash', got '" info.modelName "'")
    }

    ResolveProvider_UnknownModel_FallsBackToDeepSeek() {
        info := ProviderResolver.Resolve("unknown-model-xyz")
        if info.providerKey != "deepseek"
            throw Error("Expected fallback to deepseek, got '" info.providerKey "'")
    }

    ; ----------------------------------------------------
    ; _FixStreamBoolean tests
    ; ----------------------------------------------------

    FixStreamBoolean_FixesStreamTrue() {
        result := LLMRequestBuilder._FixStreamBoolean('{"stream":1,"model":"test"}')
        if !InStr(result, '"stream":true')
            throw Error("Expected stream:true, got: " result)
    }

    FixStreamBoolean_FixesStreamFalse() {
        result := LLMRequestBuilder._FixStreamBoolean('{"stream":0}')
        if !InStr(result, '"stream":false')
            throw Error("Expected stream:false, got: " result)
    }

    FixStreamBoolean_FixesIncludeUsage() {
        result := LLMRequestBuilder._FixStreamBoolean('{"include_usage":1}')
        if !InStr(result, '"include_usage":true')
            throw Error("Expected include_usage:true, got: " result)
    }

    FixStreamBoolean_FixesIncludeThoughts() {
        result := LLMRequestBuilder._FixStreamBoolean('{"include_thoughts":1}')
        if !InStr(result, '"include_thoughts":true')
            throw Error("Expected include_thoughts:true, got: " result)
    }

    FixStreamBoolean_KeepsOtherBooleans() {
        result := LLMRequestBuilder._FixStreamBoolean('{"other":1}')
        ; Only stream/include_usage/include_thoughts are fixed — others stay as 1
        if InStr(result, '"stream":1') || InStr(result, '"include_usage":1') || InStr(result, '"include_thoughts":1')
            throw Error("Non-target booleans should remain unchanged")
    }

    ; Regression (bug #100): the rewrite must only touch real JSON keys, never
    ; string values. User content containing `"stream":1` (escaped inside a
    ; JSON string) must survive unchanged while the real top-level stream is
    ; still converted.
    FixStreamBoolean_DoesNotCorruptUserContent() {
        raw := '{"messages":[{"content":"{\"stream\":1,\"include_usage\":1}","role":"user"}],"stream":1}'
        result := LLMRequestBuilder._FixStreamBoolean(raw)
        parsed := jsongo.Parse(result)
        if !parsed.Has("stream") || parsed["stream"] != true
            throw Error("top-level stream should become true, got: " (parsed.Has("stream") ? parsed["stream"] : "(absent)"))
        content := parsed["messages"][1]["content"]
        if content != '{"stream":1,"include_usage":1}'
            throw Error("user content must survive unchanged, got: " content)
    }

    ; Regression (bug #100): end-to-end through createJSONRequest - a user
    ; prompt containing `"stream":1` must be sent verbatim.
    CreateJSONRequest_UserContentWithStreamSnippet_Survives() {
        prompt := '{"stream":1,"include_usage":1} in my prompt'
        result := LLMRequestBuilder.createJSONRequest("deepseek-v4-flash", "sys", prompt, "", "", "", true, "")
        parsed := jsongo.Parse(result)
        if parsed["stream"] != true
            throw Error("top-level stream should be true, got: " parsed["stream"])
        msgs := parsed["messages"]
        userContent := msgs[msgs.Length]["content"]
        if userContent != prompt
            throw Error("user prompt must survive unchanged, got: " userContent)
    }

    ; ----------------------------------------------------
    ; createJSONRequest — strengthened assertions
    ; ----------------------------------------------------

    CreateJSONRequest_WithStream_ValueIsTrue() {
        client := this._setup()
        result := LLMRequestBuilder.createJSONRequest("test", "s", "u", "", "", "", true, "")
        parsed := jsongo.Parse(result)
        if !parsed.Has("stream") || parsed["stream"] != true
            throw Error("Expected stream:true, got: " parsed["stream"])
    }

    ; ----------------------------------------------------
    ; Model Default (empty reasoningEffort) — no thinking config.
    ; Regression: empty reasoning must NOT emit disabled/off config;
    ; "Model Default" means "do not send ANY thinking config".
    ; ----------------------------------------------------

    CreateJSONRequest_ModelDefault_DeepSeek_OmitsThinking() {
        result := LLMRequestBuilder.createJSONRequest("deepseek/deepseek-v4-flash", "s", "u", "", "", "", false, "")
        parsed := jsongo.Parse(result)
        if parsed.Has("thinking")
            throw Error("Model Default DeepSeek should omit 'thinking', got: " jsongo.Stringify(parsed["thinking"]))
        if parsed.Has("reasoning_effort")
            throw Error("Model Default DeepSeek should omit 'reasoning_effort', got: " jsongo.Stringify(parsed["reasoning_effort"]))
    }

    CreateJSONRequest_ModelDefault_OpenAI_OmitsThinking() {
        result := LLMRequestBuilder.createJSONRequest("openai/gpt-5-mini", "s", "u", "", "", "", false, "")
        parsed := jsongo.Parse(result)
        if parsed.Has("reasoning_effort")
            throw Error("Model Default OpenAI should omit 'reasoning_effort', got: " jsongo.Stringify(parsed["reasoning_effort"]))
    }

    CreateJSONRequest_ModelDefault_Google_OmitsThinking() {
        result := LLMRequestBuilder.createJSONRequest("google/gemini-3.5-flash", "s", "u", "", "", "", false, "")
        parsed := jsongo.Parse(result)
        if parsed.Has("extra_body")
            throw Error("Model Default Google should omit 'extra_body', got: " jsongo.Stringify(parsed["extra_body"]))
    }

    ; ----------------------------------------------------
    ; Commands: type "enabled" + level → level is used as the
    ; reasoning value (it was previously dropped). type "disabled"
    ; → explicit off preserved. empty type → no config.
    ; ----------------------------------------------------

    CreateJSONRequest_CommandEnabledWithLevel_UsesLevel() {
        result := LLMRequestBuilder.createJSONRequest("deepseek/deepseek-v4-flash", "s", "u", "", "", "", false, "enabled", "high")
        parsed := jsongo.Parse(result)
        if !parsed.Has("reasoning_effort") || parsed["reasoning_effort"] != "high"
            throw Error("Command enabled+high should set reasoning_effort='high', got: " jsongo.Stringify(parsed.Has("reasoning_effort") ? parsed["reasoning_effort"] : "(absent)"))
        if !parsed.Has("thinking") || !parsed["thinking"].Has("type") || parsed["thinking"]["type"] != "enabled"
            throw Error("Command enabled+high should set thinking:{type:'enabled'}, got: " jsongo.Stringify(parsed.Has("thinking") ? parsed["thinking"] : "(absent)"))
    }

    CreateJSONRequest_CommandEnabledNoLevel_KeepsEnabled() {
        result := LLMRequestBuilder.createJSONRequest("deepseek/deepseek-v4-flash", "s", "u", "", "", "", false, "enabled", "")
        parsed := jsongo.Parse(result)
        if !parsed.Has("thinking") || !parsed["thinking"].Has("type") || parsed["thinking"]["type"] != "enabled"
            throw Error("Command enabled (no level) should still set thinking:{type:'enabled'}")
    }

    CreateJSONRequest_CommandDisabled_SendsDisabled() {
        result := LLMRequestBuilder.createJSONRequest("deepseek/deepseek-v4-flash", "s", "u", "", "", "", false, "disabled")
        parsed := jsongo.Parse(result)
        if !parsed.Has("thinking") || !parsed["thinking"].Has("type") || parsed["thinking"]["type"] != "disabled"
            throw Error("Command disabled should set thinking:{type:'disabled'}, got: " jsongo.Stringify(parsed.Has("thinking") ? parsed["thinking"] : "(absent)"))
    }

    ; "disabled" must turn thinking OFF for ANY model, not just DeepSeek.
    CreateJSONRequest_CommandDisabled_OpenAI_SendsOff() {
        result := LLMRequestBuilder.createJSONRequest("openai/gpt-5-mini", "s", "u", "", "", "", false, "disabled")
        parsed := jsongo.Parse(result)
        if !parsed.Has("reasoning_effort") || parsed["reasoning_effort"] != "none"
            throw Error("OpenAI disabled should set reasoning_effort='none', got: " jsongo.Stringify(parsed.Has("reasoning_effort") ? parsed["reasoning_effort"] : "(absent)"))
    }

    CreateJSONRequest_CommandDisabled_Google_SendsOff() {
        result := LLMRequestBuilder.createJSONRequest("google/gemini-2.5-flash", "s", "u", "", "", "", false, "disabled")
        parsed := jsongo.Parse(result)
        if !parsed.Has("extra_body")
            throw Error("Google disabled should set extra_body")
        tc := parsed["extra_body"]["google"]["thinking_config"]
        if !tc.Has("thinking_budget") || tc["thinking_budget"] != 0
            throw Error("Google disabled should set thinking_budget=0 (off), got: " jsongo.Stringify(tc))
    }

    ; ----------------------------------------------------
    ; OpenAIChatCompletions.ApplyThinking — metadata-driven
    ; ----------------------------------------------------

    ; Helper: build a model metadata object
    static _mkModel(compat, thinkingLevelMap := "", thinkingOff := "") {
        m := { compat: compat }
        if IsObject(thinkingLevelMap)
            m.thinkingLevelMap := thinkingLevelMap
        if thinkingOff != ""
            m.thinkingOff := thinkingOff
        return m
    }

    Thinking_DeepSeek_Enabled() {
        model := LLMRequestBuilderTest._mkModel(
            Map("thinkingFormat", "deepseek", "supportsReasoningEffort", true),
            Map("high", "high", "max", "max"),
            "disabled"
        )
        requestObj := {}
        OpenAIChatCompletions.ApplyThinking(&requestObj, model, "high")
        if !requestObj.HasOwnProp("thinking") || requestObj.thinking.type != "enabled"
            throw Error("DeepSeek 'high' should set thinking:{type:'enabled'}")
        if requestObj.reasoning_effort != "high"
            throw Error("DeepSeek 'high' should set reasoning_effort:'high', got: " requestObj.reasoning_effort)
    }

    Thinking_DeepSeek_Disabled() {
        model := LLMRequestBuilderTest._mkModel(
            Map("thinkingFormat", "deepseek"),
            ,
            "disabled"
        )
        requestObj := {}
        OpenAIChatCompletions.ApplyThinking(&requestObj, model, "")
        if !requestObj.HasOwnProp("thinking") || requestObj.thinking.type != "disabled"
            throw Error("DeepSeek off should set thinking:{type:'disabled'}")
    }

    Thinking_OpenAI_Enabled() {
        model := LLMRequestBuilderTest._mkModel(
            Map("thinkingFormat", "openai", "supportsReasoningEffort", true),
            Map("none", "none", "low", "low", "medium", "medium", "high", "high", "xhigh", "xhigh"),
            "none"
        )
        requestObj := {}
        OpenAIChatCompletions.ApplyThinking(&requestObj, model, "high")
        if requestObj.reasoning_effort != "high"
            throw Error("OpenAI 'high' should set reasoning_effort:'high', got: " requestObj.reasoning_effort)
    }

    Thinking_OpenAI_Off() {
        model := LLMRequestBuilderTest._mkModel(
            Map("thinkingFormat", "openai", "supportsReasoningEffort", true),
            Map("none", "none"),
            "none"
        )
        requestObj := {}
        OpenAIChatCompletions.ApplyThinking(&requestObj, model, "")
        if requestObj.reasoning_effort != "none"
            throw Error("OpenAI off should set reasoning_effort='none', got: " requestObj.reasoning_effort)
    }

    Thinking_Google_Level_Enabled() {
        model := LLMRequestBuilderTest._mkModel(
            Map("thinkingFormat", "google"),
            Map("minimal", "MINIMAL", "low", "LOW", "medium", "MEDIUM", "high", "HIGH"),
            "MINIMAL"
        )
        requestObj := {}
        OpenAIChatCompletions.ApplyThinking(&requestObj, model, "high", "google/gemini-3.5-flash")
        if !requestObj.HasOwnProp("extra_body")
            throw Error("Google 'high' should set extra_body thinking_config")
        tc := requestObj.extra_body.google.thinking_config
        if tc.thinking_level != "HIGH"
            throw Error("Google level 'high' should set thinking_level='HIGH', got: " tc.thinking_level)
    }

    Thinking_Google_Level_Off() {
        model := LLMRequestBuilderTest._mkModel(
            Map("thinkingFormat", "google"),
            Map("minimal", "MINIMAL", "low", "LOW"),
            "MINIMAL"
        )
        requestObj := {}
        OpenAIChatCompletions.ApplyThinking(&requestObj, model, "", "google/gemini-3.5-flash")
        if !requestObj.HasOwnProp("extra_body")
            throw Error("Google off should set extra_body for MINIMAL thinking")
        tc := requestObj.extra_body.google.thinking_config
        if tc.thinking_level != "MINIMAL"
            throw Error("Google off should set thinking_level='MINIMAL', got: " tc.thinking_level)
    }

    Thinking_Google_Budget_Enabled() {
        model := LLMRequestBuilderTest._mkModel(
            Map("thinkingFormat", "google"),
            Map("minimal", "1024", "low", "4096", "medium", "8192", "high", "16384"),
            "0"
        )
        requestObj := {}
        OpenAIChatCompletions.ApplyThinking(&requestObj, model, "medium", "google/gemini-2.5-flash")
        if !requestObj.HasOwnProp("extra_body")
            throw Error("Google budget 'medium' should set extra_body")
        tc := requestObj.extra_body.google.thinking_config
        if tc.thinking_budget != 8192
            throw Error("Google budget 'medium' should set thinking_budget=8192, got: " tc.thinking_budget)
    }

    Thinking_Google_Budget_Off() {
        model := LLMRequestBuilderTest._mkModel(
            Map("thinkingFormat", "google"),
            Map("minimal", "1024"),
            "0"
        )
        requestObj := {}
        OpenAIChatCompletions.ApplyThinking(&requestObj, model, "", "google/gemini-2.5-flash")
        if !requestObj.HasOwnProp("extra_body")
            throw Error("Google budget off should set extra_body")
        tc := requestObj.extra_body.google.thinking_config
        if tc.thinking_budget != 0
            throw Error("Google budget off should set thinking_budget=0, got: " tc.thinking_budget)
    }

    Thinking_EmptyString_NoOp() {
        model := LLMRequestBuilderTest._mkModel(Map("thinkingFormat", "openai"))
        requestObj := {}
        OpenAIChatCompletions.ApplyThinking(&requestObj, model, "")
        if requestObj.HasOwnProp("reasoning_effort")
            throw Error("Empty reasoning with no thinkingOff should be a no-op")
    }

    Thinking_NonReasoningModel_NoOp() {
        ; Model with no thinkingLevelMap — handler should not set fields
        model := LLMRequestBuilderTest._mkModel(Map("thinkingFormat", "openai"))
        requestObj := {}
        OpenAIChatCompletions.ApplyThinking(&requestObj, model, "low")
        if requestObj.HasOwnProp("reasoning_effort")
            throw Error("Model with no thinkingLevelMap should not set reasoning_effort")
    }

    Thinking_DefaultFormat_FallsBackToOpenAI() {
        ; Missing thinkingFormat → defaults to "openai"
        model := LLMRequestBuilderTest._mkModel(
            Map(),
            Map("low", "low"),
            "none"
        )
        requestObj := {}
        OpenAIChatCompletions.ApplyThinking(&requestObj, model, "low")
        if requestObj.reasoning_effort != "low"
            throw Error("Default format should set reasoning_effort='low', got: " requestObj.reasoning_effort)
    }

    ; Regression (bug #68): legacy short ids resolve by PREFIX - a model whose
    ; name merely CONTAINS the provider prefix (e.g. mygpt-custom) must not
    ; match the gpt provider.
    ProviderResolver_LegacyPrefixIsPrefixOnly() {
        r1 := ProviderResolver.Resolve("gpt-4o")
        if r1.providerKey != "openai"
            throw Error("gpt-4o should resolve to openai, got '" r1.providerKey "'")
        r2 := ProviderResolver.Resolve("mygpt-custom")
        if r2.providerKey = "openai"
            throw Error("mygpt-custom must NOT match the gpt prefix (bug #68), got '" r2.providerKey "'")
        if r2.providerKey != "deepseek"
            throw Error("mygpt-custom should fall back to deepseek, got '" r2.providerKey "'")
    }

    ; Regression (bug #73): the Gemini 2.x disabled thinking config must
    ; include include_thoughts:false (symmetric with the enabled config).
    GoogleDisabledConfig_IncludesThoughtsFalse() {
        cfg := GoogleChatCompletions.DisabledConfig("google/gemini-2.0-flash")
        if !cfg.HasOwnProp("include_thoughts")
            throw Error("Gemini 2.x disabled config must include include_thoughts")
        if cfg.include_thoughts != false
            throw Error("include_thoughts should be false, got '" cfg.include_thoughts "'")
        if cfg.thinking_budget != 0
            throw Error("thinking_budget should be 0, got '" cfg.thinking_budget "'")
    }

    ; Regression (bug #75): the budget table must match the Gemini family
    ; (gemini-2.5-pro), not any model whose name merely contains "2.5-pro".
    GoogleBudgetTable_FamilyCheckOnly() {
        t1 := GoogleChatCompletions._BudgetTable("google/gemini-2.5-pro-preview-09-13")
        if t1["high"] != 32768
            throw Error("gemini-2.5-pro should use its own budget table, got high=" t1["high"])
        t2 := GoogleChatCompletions._BudgetTable("custom/my2.5-pro-custom")
        if t2["high"] = 32768
            throw Error("my2.5-pro must NOT match the 2.5-pro table (bug #75)")
        if !t2.Has("high")
            throw Error("custom model should fall back to the generic table")
    }

    ; Regression (bug #89, security): the API key must be sanitized before it
    ; is embedded in the cURL Authorization header.
    CurlBuilder_SanitizesApiKey() {
        providerInfo := { endpoint: "https://api.test/v1", apiKey: 'sk-" && echo pwned && "', fimEndpoint: "" }
        cmd := CurlBuilder.Build(providerInfo, "req.json", "out.json")
        if InStr(cmd, 'sk-"')
            throw Error("crafted key must not appear raw in the curl command: " cmd)
        if !InStr(cmd, "Authorization: Bearer sk-")
            throw Error("sanitized key should remain in the header: " cmd)
        ; The quote break and command separators must be gone (the remaining
        ; words are inert header text, not a second command).
        if InStr(cmd, '&&')
            throw Error("command separator survived in the curl command: " cmd)
        if InStr(cmd, '" echo ')
            throw Error("quote break survived in the curl command: " cmd)
    }
}
