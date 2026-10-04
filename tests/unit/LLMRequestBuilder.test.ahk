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
        return LLMRequestBuilder("[REDACTED_SECRET]")
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
        pi := { providerKey: "deepseek", endpoint: "https://api.deepseek.com/chat/completions", apiKey: "[REDACTED_SECRET]" }
        cmd := CurlBuilder.Build(pi, "req.json", "out.json")
        if !InStr(cmd, "cURL.exe")
            throw Error("Expected cURL.exe in command")
        if !InStr(cmd, "[REDACTED_SECRET]")
            throw Error("Expected API key in command")
        if !InStr(cmd, "req.json")
            throw Error("Expected request file in command")
        if !InStr(cmd, "out.json")
            throw Error("Expected output file in command")
    }

    CurlBuilderBuildFIM_Format() {
        pi := { providerKey: "deepseek", endpoint: "https://api.deepseek.com/chat/completions", fimEndpoint: "https://api.deepseek.com/beta/completions", apiKey: "[REDACTED_SECRET]" }
        cmd := CurlBuilder.BuildFIM(pi, "fim-req.json", "fim-out.json")
        if !InStr(cmd, "cURL.exe")
            throw Error("Expected cURL.exe in FIM command")
        if !InStr(cmd, "fim-req.json")
            throw Error("Expected FIM request file in command")
        if !InStr(cmd, "https://api.deepseek.com/beta/completions")
            throw Error("DeepSeek FIM must use its explicit beta completions endpoint")
    }

    ; Regression (bug #112): CurlBuilder must not build a URL-less cURL
    ; command when the provider endpoint is empty.
    CurlBuilder_EmptyEndpoint_ReturnsEmpty() {
        pi := { providerKey: "test", endpoint: "", fimEndpoint: "", apiKey: "[REDACTED_SECRET]" }
        if CurlBuilder.Build(pi, "req.json", "out.json") != ""
            throw Error("Build should return empty for an empty endpoint")
        if CurlBuilder.BuildStream(pi, "req.json", "out.json", "err.txt") != ""
            throw Error("BuildStream should return empty for an empty endpoint")
        if CurlBuilder.BuildFIM(pi, "req.json", "out.json") != ""
            throw Error("BuildFIM should return empty when both endpoints are empty")
        piNoFim := { providerKey: "openrouter", endpoint: "https://openrouter.ai/api/v1/chat/completions", fimEndpoint: "", apiKey: "[REDACTED_SECRET]" }
        if CurlBuilder.BuildFIM(piNoFim, "req.json", "out.json") != ""
            throw Error("BuildFIM must reject providers without an explicit FIM endpoint")
        pi2 := { providerKey: "test", endpoint: "https://api.test/v1", fimEndpoint: "https://api.test/fim", apiKey: "[REDACTED_SECRET]" }
        cmd := CurlBuilder.BuildFIM(pi2, "req.json", "out.json")
        if !InStr(cmd, "https://api.test/fim")
            throw Error("BuildFIM should use the FIM endpoint when configured")
    }

    ; Regression (bug #204): the streaming cURL command must carry an overall
    ; --max-time so a stalled upstream cannot hang the chat UI forever.
    CurlBuilderBuildStream_HasMaxTime() {
        pi := { providerKey: "deepseek", endpoint: "https://api.deepseek.com/chat/completions", fimEndpoint: "", apiKey: "[REDACTED_SECRET]" }
        cmd := CurlBuilder.BuildStream(pi, "req.json", "out.json", "err.txt")
        if !InStr(cmd, "--max-time 120")
            throw Error("BuildStream must include --max-time 120 (bug #204), got: " cmd)
    }

    ; --------------------
    ; appendToChatHistory
    ; --------------------

    AppendToChatHistory_AddsAssistant() {
        client := this._setup()
        request := '{"model":"test","messages":[{"role":"user","content":"hi"}]}'
        tempFile := A_Temp "\test_append_" A_TickCount "_" Random(1000, 999999) ".json"
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

    ; Regression (bug #111): the API log must be written atomically (temp file
    ; + rename), so a crash mid-write cannot leave truncated JSON.
    LogRequest_IsAtomic() {
        global apiLogMaxEntries
        oldPath := ApiLogger.logFilePath
        oldLimit := apiLogMaxEntries
        target := A_Temp "\test_api_log_" A_TickCount "_" Random(1000, 999999) ".json"
        ApiLogger.logFilePath := target
        apiLogMaxEntries := 10
        try {
            try FileDelete(target)
            ApiLogger.LogRequest({ promptName: "one", request: "{}", response: "{}", status: "success" })
            ApiLogger.LogRequest({ promptName: "two", request: "{}", response: "{}", status: "success" })
            if FileExist(target ".tmp")
                throw Error("temp file should be renamed away after a successful log write")
            logs := ApiLogger.ReadLogs()
            if logs.Length != 2 || logs[1]["promptName"] != "two"
                throw Error("log should contain both entries newest-first")
        } finally {
            ApiLogger.logFilePath := oldPath
            apiLogMaxEntries := oldLimit
            try FileDelete(target)
            try FileDelete(target ".tmp")
        }
    }

    ; Regression (runtime error dialog): a corrupt/unparseable API log file
    ; used to crash the app - _readLogFile had no catch, and a torn file
    ; could parse into a non-array value. Reads must degrade to [] instead of
    ; raising "This value of type 'String' has no property named 'Length'".
    ReadLogs_CorruptFile_ReturnsEmptyArray() {
        oldPath := ApiLogger.logFilePath
        target := A_Temp "\test_api_log_corrupt_" A_TickCount "_" Random(1000, 999999) ".json"
        ApiLogger.logFilePath := target
        try {
            try FileDelete(target)
            FileOpen(target, "w", "UTF-8-RAW").Write('[{not json,,,')
            logs := ApiLogger.ReadLogs()
            if Type(logs) != "Array" || logs.Length != 0
                throw Error("corrupt log must read as an empty array, got: " Type(logs))
        } finally {
            ApiLogger.logFilePath := oldPath
            try FileDelete(target)
        }
    }

    ; Regression: a log file whose top level is a JSON string (valid JSON,
    ; wrong shape) previously parsed fine and crashed on logs.Length. The
    ; next LogRequest must repair the file instead of raising.
    LogRequest_CorruptFile_RepairsInsteadOfCrashing() {
        global apiLogMaxEntries
        oldPath := ApiLogger.logFilePath
        oldLimit := apiLogMaxEntries
        target := A_Temp "\test_api_log_corrupt2_" A_TickCount "_" Random(1000, 999999) ".json"
        ApiLogger.logFilePath := target
        apiLogMaxEntries := 10
        try {
            try FileDelete(target)
            FileOpen(target, "w", "UTF-8-RAW").Write('"not an array"')
            ApiLogger.LogRequest({ promptName: "fixed", request: "{}", response: "{}", status: "success" })
            logs := ApiLogger.ReadLogs()
            if logs.Length != 1 || logs[1]["promptName"] != "fixed"
                throw Error("LogRequest should replace the corrupt log with a fresh array")
        } finally {
            ApiLogger.logFilePath := oldPath
            apiLogMaxEntries := oldLimit
            try FileDelete(target)
        }
    }

    ; Regression: _WriteLogs must use a per-write unique temp name. The old
    ; shared ".tmp" path let two concurrent app instances interleave bytes
    ; into the same temp file, which was then moved over the real log.
    WriteLogs_UsesUniqueTempName() {
        src := FileRead(A_ScriptDir "\..\api\ApiLogger.ahk", "UTF-8")
        if !InStr(src, '".tmp" A_TickCount')
            throw Error("_WriteLogs must use a unique temp file per write (shared .tmp interleaves across concurrent app instances)")
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

    ResolveProvider_CodexUsesIndependentCliTransport() {
        info := ProviderResolver.Resolve("codex/gpt-5.6-luna")
        if info.providerKey != "codex"
            throw Error("Codex model must resolve to codex provider, got '" info.providerKey "'")
        if info.modelName != "gpt-5.6-luna"
            throw Error("Codex must send the bare model slug, got '" info.modelName "'")
        if info.transport != "codex-cli"
            throw Error("Codex must use CLI transport")
    }

    ResolveProvider_LegacyFormat() {
        info := ProviderResolver.Resolve("deepseek-v4-flash")
        if info.providerKey != "deepseek"
            throw Error("Expected providerKey 'deepseek', got '" info.providerKey "'")
        if info.modelName != "deepseek-v4-flash"
            throw Error("Expected modelName 'deepseek-v4-flash', got '" info.modelName "'")
    }

    ; Disabling API logging removes the previously retained log instead of
    ; leaving a stale file behind in TEMP.
    LogRequest_DisabledClearsExistingFile() {
        global apiLogMaxEntries
        oldPath := ApiLogger.logFilePath
        oldLimit := apiLogMaxEntries
        target := A_Temp "\test_api_log_disabled_" A_TickCount "_" Random(1000, 999999) ".json"
        ApiLogger.logFilePath := target
        apiLogMaxEntries := 5
        try {
            ApiLogger.LogRequest({ promptName: "retained", request: "{}", response: "{}", status: "success" })
            if !FileExist(target)
                throw Error("setup: expected retained log file")
            apiLogMaxEntries := 0
            ApiLogger.TrimToLimit()
            if FileExist(target)
                throw Error("disabling API logging must remove the existing log file")
        } finally {
            ApiLogger.logFilePath := oldPath
            apiLogMaxEntries := oldLimit
            try FileDelete(target)
        }
    }

    ; The byte budget protects TEMP even when a small number of entries carry
    ; very large request/response bodies.
    LogRequest_ByteBudgetBoundsEntries() {
        global apiLogMaxEntries
        oldPath := ApiLogger.logFilePath
        oldLimit := apiLogMaxEntries
        oldBytes := ApiLogger.maxLogBytes
        target := A_Temp "\test_api_log_bytes_" A_TickCount "_" Random(1000, 999999) ".json"
        ApiLogger.logFilePath := target
        ApiLogger.maxLogBytes := 200
        apiLogMaxEntries := 20
        try {
            large := ""
            loop 1000
                large .= "x"
            ApiLogger.LogRequest({ promptName: "huge", request: large, response: "", status: "success" })
            if FileExist(target) && FileGetSize(target) > ApiLogger.maxLogBytes
                throw Error("API log exceeded byte budget: " FileGetSize(target))
        } finally {
            ApiLogger.logFilePath := oldPath
            ApiLogger.maxLogBytes := oldBytes
            apiLogMaxEntries := oldLimit
            try FileDelete(target)
        }
    }

    ResolveProvider_OpenRouterFree() {
        EnvSet("OPENROUTER_API_KEY", "[REDACTED_SECRET]")
        try {
            info := ProviderResolver.Resolve("openrouter/free")
            if info.providerKey != "openrouter"
                throw Error("Expected providerKey 'openrouter', got '" info.providerKey "'")
            if info.modelName != "openrouter/free"
                throw Error("Expected API modelName 'openrouter/free', got '" info.modelName "'")
            if info.endpoint != "https://openrouter.ai/api/v1/chat/completions"
                throw Error("Unexpected OpenRouter endpoint: " info.endpoint)
            if info.apiKey != "[REDACTED_SECRET]"
                throw Error("OpenRouter API key was not read from OPENROUTER_API_KEY")
            if info.fimEndpoint != ""
                throw Error("OpenRouter Free must not advertise an FIM endpoint")
        } finally {
            EnvSet("OPENROUTER_API_KEY", "")
        }
    }

    ResolveProvider_OpenRouterNestedModelId() {
        EnvSet("OPENROUTER_API_KEY", "test-openrouter-key")
        try {
            info := ProviderResolver.Resolve("openrouter/anthropic/claude-sonnet-4")
            if info.providerKey != "openrouter"
                throw Error("Expected nested OpenRouter model to use the OpenRouter provider")
            if info.modelName != "anthropic/claude-sonnet-4"
                throw Error("Expected upstream OpenRouter slug without transport prefix, got '" info.modelName "'")

            routerInfo := ProviderResolver.Resolve("openrouter/openrouter/auto")
            if routerInfo.modelName != "openrouter/auto"
                throw Error("Expected OpenRouter auto router slug 'openrouter/auto', got '" routerInfo.modelName "'")
        } finally {
            EnvSet("OPENROUTER_API_KEY", "")
        }
    }

    ProviderResolver_AuthDiagnostic_IsRedacted() {
        p := { displayName: "OpenRouter", endpoint: "https://openrouter.ai/api/v1/chat/completions", authEnvVar: "OPENROUTER_API_KEY", authMode: "env", apiKey: "" }
        secretSentinel := "diagnostic-secret-value"
        msg := ProviderResolver._AuthDiagnostic("openrouter", "openrouter/free", p, secretSentinel)
        if InStr(msg, secretSentinel)
            throw Error("Provider auth diagnostics must not contain the API key")
        if !InStr(msg, "provider=openrouter") || !InStr(msg, "model=openrouter/free")
            throw Error("Provider auth diagnostics must identify the resolved OpenRouter model")
        if !InStr(msg, "authSource=env") || !InStr(msg, "keyPresent=true") || !InStr(msg, "keyLength=" StrLen(secretSentinel))
            throw Error("Provider auth diagnostics must report redacted env-key state: " msg)
    }

    OpenRouterFree_NormalRequest_UsesChatPath() {
        EnvSet("OPENROUTER_API_KEY", "[REDACTED_SECRET]")
        try {
            request := LLMRequestBuilder.createJSONRequest("openrouter/free", "You are helpful", "Hello", "", "", "", false, "")
            parsed := jsongo.Parse(request)
            if parsed["model"] != "openrouter/free"
                throw Error("OpenRouter request should send model 'openrouter/free'")
            if !parsed.Has("messages") || parsed.Has("prompt") || parsed.Has("suffix")
                throw Error("OpenRouter normal request must use chat message format")
            info := ProviderResolver.Resolve("openrouter/free")
            cmd := CurlBuilder.Build(info, "req.json", "out.json")
            if !InStr(cmd, "https://openrouter.ai/api/v1/chat/completions")
                throw Error("OpenRouter normal request must use the chat-completions cURL path")
        } finally {
            EnvSet("OPENROUTER_API_KEY", "")
        }
    }

    ResolveProvider_UnknownModel_FallsBackToDeepSeek() {
        info := ProviderResolver.Resolve("unknown-model-xyz")
        if info.providerKey != "deepseek"
            throw Error("Expected fallback to deepseek, got '" info.providerKey "'")
    }

    ; Regression (bug #190): the fallback must NOT be hardcoded to
    ; providers["deepseek"] - the Settings UI lets the user delete deepseek,
    ; and a missing-key Map index THROWS in AHK v2. With deepseek removed,
    ; an uncovered model must resolve to the FIRST configured provider
    ; instead of crashing the request path.
    ResolveProvider_DeletedDeepseek_FallsBackToFirstProvider() {
        global providers, providerMap
        oldProviders := providers
        oldProviderMap := providerMap
        providers := Map()
        providers["openai"] := { displayName: "OpenAI", endpoint: "https://api.openai.com/v1", fimEndpoint: "", authEnvVar: "OPENAI_API_KEY", authMode: "env", apiKey: "" }
        providerMap := Map("openai", "openai")
        try {
            info := ProviderResolver.Resolve("deepseek/deepseek-v4-flash")
            if info.providerKey != "openai"
                throw Error("uncovered model must fall back to the first configured provider (bug #190), got '" info.providerKey "'")
            if !info.endpoint
                throw Error("fallback result must carry the provider endpoint (bug #190)")
            ctrl := ProviderResolver.Resolve("openai/gpt-4")
            if ctrl.providerKey != "openai"
                throw Error("covered provider must still resolve normally, got '" ctrl.providerKey "'")
        } finally {
            providers := oldProviders
            providerMap := oldProviderMap
        }
    }

    ; ----------------------------------------------------
    ; _FixStreamBoolean tests
    ; ----------------------------------------------------

    FixStreamBoolean_FixesStreamTrue() {
        result := LLMRequestBuilder._FixStreamBoolean('{"stream":1,"model":"test"}')
        if !InStr(result, '"stream":true')
            throw Error("Expected stream:true, got: " result)
    }

    FixStreamBoolean_LargeImagePayloadUsesBoundedSerializationTime() {
        characters := 44 * 1024 * 1024
        imageData := StrReplace(Format("{:" characters "}", ""), " ", "A")
        raw := '{"messages":[{"content":"data:image/png;base64,' imageData '"}],"stream":1,"store":0}'
        started := A_TickCount
        fixed := LLMRequestBuilder._FixStreamBoolean(raw)
        elapsed := A_TickCount - started
        Log("[PERF] JSON boolean serialization of 44 MiB image data: " elapsed "ms`n")
        if elapsed > 5000
            throw Error("Boolean serialization blocked for " elapsed "ms on a large image payload")
        if !InStr(fixed, '"stream":true,"store":false')
            throw Error("Large payload boolean fields were not fixed")
        if SubStr(fixed, 1, StrLen(raw) - StrLen('"stream":1,"store":0}')) != SubStr(raw, 1, StrLen(raw) - StrLen('"stream":1,"store":0}'))
            throw Error("Image payload must remain byte-for-byte unchanged")
        spaced := LLMRequestBuilder._FixStreamBoolean('{"stream" : 1,"strict":10,"store":0,"text":"\\\"stream\\\":1"}')
        if !InStr(spaced, '"stream" : true') || !InStr(spaced, '"strict":10')
            throw Error("Rewriting must accept whitespace and preserve non-boolean numbers")
    }

    FixStreamBoolean_LargeEscapedImagePreservesSerializedBytes() {
        ; jsongo escapes every slash, including those inside real base64 images.
        ; An all-A fixture misses the regex recursion caused by these escapes.
        imageData := StrReplace(Format("{:" (32 * 1024 * 1024) "}", ""), " ", "/")
        raw := jsongo.Stringify(Map("image", "data:image/png;base64," imageData,
            "stream", true, "store", false, "text", 'Quoted "stream":1 and backslash \\'))
        started := A_TickCount
        fixed := LLMRequestBuilder._FixStreamBoolean(raw)
        if A_TickCount - started > 5000
            throw Error("Escaped image serialization must not block the UI")
        expected := StrReplace(StrReplace(raw, '"stream":1', '"stream":true'), '"store":0', '"store":false')
        if fixed != expected
            throw Error("Escaped image bytes and field-looking user text must remain unchanged")
    }

    LogRequest_LargeImageKeepsResponseDiagnosticsWithinByteCap() {
        global apiLogMaxEntries
        oldPath := ApiLogger.logFilePath, oldCap := ApiLogger.maxLogBytes, oldLimit := apiLogMaxEntries
        logPath := A_Temp "\test_image_api_log_" A_TickCount "_" Random(1000, 999999) ".json"
        ApiLogger.logFilePath := logPath
        ApiLogger.maxLogBytes := 2048
        apiLogMaxEntries := 10
        try {
          for original in [
            '{"image":"data:image/png;base64,' StrReplace(Format("{:8192}", ""), " ", "A") '"}',
            jsongo.Stringify(Map("image", "data:image/png;base64," StrReplace(Format("{:8192}", ""), " ", "/")))
          ] {
            ApiLogger.ClearLogs()
            ApiLogger.LogRequest({ request: original, response: "Terminal image error", status: "error" })
            logs := ApiLogger.ReadLogs()
            if logs.Length != 1 || logs[1]["response"] != "Terminal image error"
                throw Error("Large image requests must not discard the provider response from logs")
            if !InStr(logs[1]["request"], "image data omitted from log") || FileGetSize(logPath) > ApiLogger.maxLogBytes
                throw Error("Image data must be omitted from bounded diagnostic logs")
            if StrLen(original) < 8192
                throw Error("Logging must not change the original request payload")
          }
        } finally {
            ApiLogger.logFilePath := oldPath, ApiLogger.maxLogBytes := oldCap, apiLogMaxEntries := oldLimit
            try FileDelete(logPath)
        }
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

    ; Regression (bug #149): a SHORT model id (no provider prefix) must get the
    ; same thinking config as the full "provider/model" id - the old
    ; models.Has(APIModel) check only matched full-id keys.
    CreateJSONRequest_CommandEnabled_ShortModelId_AppliesThinking() {
        result := LLMRequestBuilder.createJSONRequest("deepseek-v4-flash", "s", "u", "", "", "", false, "enabled", "high")
        parsed := jsongo.Parse(result)
        if !parsed.Has("thinking") || !parsed["thinking"].Has("type") || parsed["thinking"]["type"] != "enabled"
            throw Error("short-id command should set thinking:{type:'enabled'}, got: " jsongo.Stringify(parsed.Has("thinking") ? parsed["thinking"] : "(absent)"))
        if !parsed.Has("reasoning_effort") || parsed["reasoning_effort"] != "high"
            throw Error("short-id command should set reasoning_effort='high', got: " jsongo.Stringify(parsed.Has("reasoning_effort") ? parsed["reasoning_effort"] : "(absent)"))
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
    ApiLogger_RetainsExactLargePayloadAndCleansUpArchive() {
        global apiLogMaxEntries
        oldPath := ApiLogger.logFilePath, oldLimit := apiLogMaxEntries
        target := A_Temp "\test_exact_log_" ChatDB._UUID() ".json"
        ApiLogger.logFilePath := target
        apiLogMaxEntries := 2
        try {
            text := ""
            loop 12000
                text .= "canonical source text "
            body := jsongo.Stringify(Map("model", "example", "messages", [Map("role", "user", "content", text)]))
            ApiLogger.LogRequest({request:body,response:"{}",endpoint:"https://example.test/inference"})
            entries := ApiLogger.ReadLogs()
            if entries.Length != 1 || !entries[1].Has("request_archive")
                throw Error("Large request was not retained separately")
            archive := entries[1]["request_archive"]
            if ApiLogBodies.Read(target, archive) != body
                throw Error("Archived request differed from the sent payload")
            if !InStr(entries[1]["request"], "omitted from preview")
                throw Error("Large log did not show a readable preview")
            blocked := false
            try ApiLogBodies.Read(target, "../other.txt")
            catch
                blocked := true
            if !blocked
                throw Error("Archived body lookup accepted an unsafe path")
            ApiLogger.ClearLogs()
            if FileExist(ApiLogBodies.directory(target) "\" archive)
                throw Error("Clearing logs left an archived payload")
        } finally {
            ApiLogger.ClearLogs()
            ApiLogger.logFilePath := oldPath
            apiLogMaxEntries := oldLimit
        }
    }

    ChatGptResponseLog_UsesFinalOutputAndMetadataInsteadOfDeltas() {
        item := Map("type", "message", "role", "assistant", "content", [Map("type", "output_text", "text", "Complete final answer")])
        response := Map("id", "response-id", "status", "completed", "model", "gpt-test", "created_at", 123, "output", [item], "usage", Map("input_tokens", 10, "output_tokens", 20), "metadata", Map("mentions", "response.output_text.delta"))
        raw := "data: " jsongo.Stringify(Map("type", "response.output_text.delta", "delta", "Partial")) "`n"
        raw .= "data: " jsongo.Stringify(Map("type", "response.completed", "response", response)) "`n"
        normalized := jsongo.Parse(ChatGptResponseLog.Normalize(raw))
        if normalized["output_text"] != "Complete final answer" || normalized["id"] != "response-id" || normalized["usage"]["output_tokens"] != 20
            throw Error("Response log lost final text or provider metadata")
        if normalized.Has("delta") || normalized.Get("type", "") = "response.output_text.delta"
            throw Error("Response log retained token deltas")
        if normalized["metadata"]["mentions"] != "response.output_text.delta"
            throw Error("Response log altered provider metadata")
        single := ChatGptResponseLog.Normalize(jsongo.Stringify(Map("type", "response.completed", "response", response)))
        if jsongo.Parse(single)["status"] != "completed" || ChatGptResponseLog.Normalize(single) != single
            throw Error("Single terminal event or already-final response was misclassified")
    }

    ChatGptResponseLog_MergesItemDoneAndMarksInterruptedTextPartial() {
        item := Map("type", "message", "role", "assistant", "content", [Map("type", "output_text", "text", "Item-done answer")])
        raw := "data: " jsongo.Stringify(Map("type", "response.output_item.done", "item", item)) "`n"
        raw .= "data: " jsongo.Stringify(Map("type", "response.completed", "response", Map("id", "empty-terminal", "status", "completed", "output", [])))
        normalized := jsongo.Parse(ChatGptResponseLog.Normalize(raw))
        if normalized["output_text"] != "Item-done answer"
            throw Error("Empty terminal output lost the assembled response")
        partial := jsongo.Parse(ChatGptResponseLog.Normalize("data: " jsongo.Stringify(Map("type", "response.output_text.delta", "delta", "Partial answer")), "error"))
        if partial["status"] != "error" || !partial["partial"] || partial["output_text"] != "Partial answer"
            throw Error("Interrupted response was presented as completed")
    }

    PublicReasoningSummary_UsesOnlyProviderPublicSummaryFields() {
        output := [Map("type", "reasoning", "encrypted_content", "PRIVATE-OPAQUE-STATE", "summary", [Map("type", "summary_text", "text", "Public final summary")])]
        if ChatGptResponsesStreamParser.PublicReasoningSummary(output) != "Public final summary"
            throw Error("Provider public summary was not recovered")
        if ChatGptResponsesStreamParser.PublicReasoningSummary([Map("type", "reasoning", "encrypted_content", "PRIVATE-OPAQUE-STATE")]) != ""
            throw Error("Opaque reasoning was exposed as a public summary")
    }

}
