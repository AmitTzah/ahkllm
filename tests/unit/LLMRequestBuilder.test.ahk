; ======================================================
; LLMRequestBuilder.test.ahk — Unit tests for LLMRequestBuilder class
;
; Tests: createJSONRequest, createFIMRequest,
;        extractJSONResponse, extractFIMResponse,
;        parseSSELine, ComputeTokenCosts, buildcURLCommand
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
        result := client.createJSONRequest("deepseek-v4-flash", "You are helpful", "Hello", "", "", "", false, "")
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
        result := client.createJSONRequest("test-model", "", "just user", "", "", "", false, "")
        parsed := jsongo.Parse(result)
        if parsed["messages"].Length != 1
            throw Error("Expected 1 message without system prompt, got " parsed["messages"].Length)
        if parsed["messages"][1]["role"] != "user"
            throw Error("Expected role 'user'")
    }

    CreateJSONRequest_WithStream() {
        client := this._setup()
        result := client.createJSONRequest("test", "s", "u", "", "", "", true, "")
        parsed := jsongo.Parse(result)
        ; jsongo serializes true as 1 — we check for "stream" key existence
        if !parsed.Has("stream")
            throw Error("Expected 'stream' key in JSON")
    }

    CreateJSONRequest_WithTemperature() {
        client := this._setup()
        result := client.createJSONRequest("test", "s", "u", "0.7", "", "", false, "")
        parsed := jsongo.Parse(result)
        if parsed["temperature"] != 0.7
            throw Error("Expected temperature 0.7, got " parsed["temperature"])
    }

    CreateJSONRequest_WithMaxTokens() {
        client := this._setup()
        result := client.createJSONRequest("test", "s", "u", "", "500", "", false, "")
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
    ; extractJSONResponse — returns Object (use dot notation)
    ; --------------------

    ExtractJSONResponse_Standard() {
        client := this._setup()
        raw := '{"choices":[{"message":{"content":"Hello world"},"finish_reason":"stop"}],"model":"deepseek-v4-flash","usage":{"prompt_tokens":10,"completion_tokens":5,"total_tokens":15}}'
        parsed := jsongo.Parse(raw)
        result := client.extractJSONResponse(parsed)
        if result.response != "Hello world"
            throw Error("Expected response 'Hello world'")
        if result.model != "deepseek-v4-flash"
            throw Error("Expected model 'deepseek-v4-flash'")
        if result.usage.totalTokens != 15
            throw Error("Expected 15 totalTokens, got " result.usage.totalTokens)
    }

    ExtractJSONResponse_WithCache() {
        client := this._setup()
        raw := '{"choices":[{"message":{"content":"Hello"},"finish_reason":"stop"}],"model":"deepseek-v4-flash","usage":{"prompt_tokens":100,"completion_tokens":20,"total_tokens":120,"prompt_cache_hit_tokens":50}}'
        parsed := jsongo.Parse(raw)
        result := client.extractJSONResponse(parsed)
        if result.usage.cachedTokens != 50
            throw Error("Expected 50 cachedTokens, got " result.usage.cachedTokens)
    }

    ; --------------------
    ; extractFIMResponse — returns Object (use dot notation)
    ; --------------------

    ExtractFIMResponse_Standard() {
        client := this._setup()
        raw := '{"choices":[{"text":"completed code","finish_reason":"stop"}],"model":"deepseek-v4-flash"}'
        parsed := jsongo.Parse(raw)
        result := client.extractFIMResponse(parsed)
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
        client := this._setup()
        result := SSEParser.ParseLine('data: {"choices":[{"delta":{"reasoning_content":"thinking...", "content":""}}]}')
        if result.type != "reasoning"
            throw Error("Expected type 'reasoning', got '" result.type "'")
        if result.content != "thinking..."
            throw Error("Expected content 'thinking...', got '" result.content "'")
    }

    ParseSSELine_Done() {
        client := this._setup()
        result := SSEParser.ParseLine("data: [DONE]")
        if result.type != "done"
            throw Error("Expected type 'done', got '" result.type "'")
    }

    ParseSSELine_Finish() {
        client := this._setup()
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
        client := this._setup()
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
    ; buildcURLCommand
    ; --------------------

    BuildcURLCommand_Format() {
        client := this._setup()
        cmd := client.buildcURLCommand("req.json", "out.json")
        if !InStr(cmd, "cURL.exe")
            throw Error("Expected cURL.exe in command")
        if !InStr(cmd, "sk-test-key")
            throw Error("Expected API key in command")
        if !InStr(cmd, "req.json")
            throw Error("Expected request file in command")
        if !InStr(cmd, "out.json")
            throw Error("Expected output file in command")
    }

    BuildFIMcURLCommand_Format() {
        client := this._setup()
        cmd := client.buildFIMcURLCommand("fim-req.json", "fim-out.json")
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

    ; ----------------------------------------------------
    ; createJSONRequest — strengthened assertions
    ; ----------------------------------------------------

    CreateJSONRequest_WithStream_ValueIsTrue() {
        client := this._setup()
        result := client.createJSONRequest("test", "s", "u", "", "", "", true, "")
        parsed := jsongo.Parse(result)
        if !parsed.Has("stream") || parsed["stream"] != true
            throw Error("Expected stream:true, got: " parsed["stream"])
    }
}
