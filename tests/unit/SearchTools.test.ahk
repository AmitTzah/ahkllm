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

    ContextText_MarksSearch() {
        txt := SearchTools.BuildContextText("q", "answer")
        if SubStr(txt, 1, 15) != "[Web search: q]"
            throw Error("context marker wrong: " txt)
        if !InStr(txt, "answer")
            throw Error("context body missing: " txt)
    }
}
