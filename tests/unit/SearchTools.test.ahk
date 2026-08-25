; ======================================================
; SearchTools.test.ahk — web-search tool definition + helpers
; ======================================================

class SearchToolsTest {

    static __New() {
        RegisterTestClass("SearchToolsTest")
    }

    ResponsesEndpoint_ReplacesChatCompletionsSuffix() {
        if SearchTools.ResponsesEndpoint("https://api.deepseek.com/chat/completions") != "https://api.deepseek.com/responses"
            throw Error("deepseek endpoint derivation failed")
        if SearchTools.ResponsesEndpoint("http://127.0.0.1:1234/v1/chat/completions") != "http://127.0.0.1:1234/v1/responses"
            throw Error("mock endpoint derivation failed")
        if SearchTools.ResponsesEndpoint("https://host.example/base") != "https://host.example/base/responses"
            throw Error("fallback endpoint derivation failed")
    }

    TavilyKey_SettingWins_EnvFallback() {
        global tavilyApiKey
        old := tavilyApiKey
        tavilyApiKey := ""
        EnvSet("TAVILY_API_KEY", "env-key-test")
        if SearchTools.TavilyKey() != "env-key-test"
            throw Error("expected env fallback")
        tavilyApiKey := "direct-key-test"
        if SearchTools.TavilyKey() != "direct-key-test"
            throw Error("expected direct setting to win")
        tavilyApiKey := old
    }

    ToolDefinition_DeclaresWebSearch() {
        def := SearchTools.Definition()
        if def.type != "function" || def.function.name != "web_search"
            throw Error("tool definition shape wrong")
        if !def.function.parameters.properties.HasOwnProp("query")
            throw Error("missing query property")
        if !def.function.parameters.HasOwnProp("required")
            throw Error("missing required array")
    }

    ; Regression (real-API report): AHK has no boolean type — `false` IS 0,
    ; so jsongo serialized the old additionalProperties:false as
    ; "additionalProperties":0. DeepSeek's JSON-Schema validator rejects that
    ; with "Invalid schema for function 'web_search': 0 is not of types
    ; boolean, object". The serialized tool definition must therefore contain
    ; no additionalProperties key at all (the field is optional in JSON
    ; Schema, so omitting it is valid and provider-safe).
    ToolDefinition_SerializedJson_HasNoAdditionalProperties() {
        serialized := jsongo.Stringify(SearchTools.Definition())
        if InStr(serialized, "additionalProperties")
            throw Error("tool schema must not carry additionalProperties (jsongo serializes AHK false as 0, which real APIs reject): " serialized)
        if InStr(serialized, "0}")
            throw Error("tool schema unexpectedly contains a bare 0 value: " serialized)
        if !InStr(serialized, '"name":"web_search"')
            throw Error("serialized tool lost its name: " serialized)
        if !InStr(serialized, '"required":["query"]')
            throw Error("serialized tool lost its required query: " serialized)
    }

    ContextText_MarksSearch() {
        txt := SearchTools.BuildContextText("q", "answer")
        if SubStr(txt, 1, 15) != "[Web search: q]"
            throw Error("context marker wrong: " txt)
        if !InStr(txt, "answer")
            throw Error("context body missing: " txt)
    }

    SearchProcessState_RegistersAndCancelsWithoutGlobalParams() {
        state := { searchPid: 0, cancelled: false }
        SearchTools.RegisterProcess(state, 0)
        if state.searchPid != 0 || SearchTools.IsCancelled(state)
            throw Error("search process state was not registered independently")
        ; Never pass a guessed PID to production CancelProcess: clear the
        ; registration first so this unit test cannot kill an unrelated tree.
        SearchTools.RegisterProcess(state, 12345)
        SearchTools.ClearProcess(state, 12345)
        SearchTools.CancelProcess(state)
        if !state.cancelled || state.searchPid != 0
            throw Error("search cancellation state was not cleaned idempotently")
        SearchTools.ClearProcess(state, 12345)
        if state.searchPid != 0
            throw Error("clearing an already-cancelled search changed state")
    }
}
