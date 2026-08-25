; ======================================================
; TavilySearch.test.ahk — Tavily backend formatting + key gate
; ======================================================

class TavilySearchTest {

    static __New() {
        RegisterTestClass("TavilySearchTest")
    }

    Format_Fixture_ProducesAnswerAndLinks() {
        raw := '{"query":"ahk webview2","answer":"AutoHotkey supports WebView2.","results":[{"url":"https://example.com/a","title":"Title A","content":"Snippet A"},{"url":"https://example.com/b","title":"Title B","content":"Snippet B"}]}'
        txt := TavilySearch._Format(jsongo.Parse(raw))
        if !InStr(txt, "Answer: AutoHotkey supports WebView2.")
            throw Error("answer missing: " txt)
        if !InStr(txt, "1. Title A") || !InStr(txt, "https://example.com/a") || !InStr(txt, "Snippet A")
            throw Error("first result missing: " txt)
        if !InStr(txt, "2. Title B")
            throw Error("second result missing: " txt)
    }

    Format_TrimsLongContent() {
        long := ""
        Loop 800
            long .= "y"
        raw := '{"results":[{"url":"u","title":"t","content":"' . long . '"}]}'
        txt := TavilySearch._Format(jsongo.Parse(raw))
        if !InStr(txt, "t")
            throw Error("title missing")
        if StrLen(txt) > 900
            throw Error("long content was not trimmed: " StrLen(txt) " chars")
    }

    Run_MissingKey_ReturnsErrorWithoutNetwork() {
        global tavilyApiKey
        old := tavilyApiKey
        tavilyApiKey := ""
        EnvSet("TAVILY_API_KEY", "")
        result := TavilySearch.Run("test query")
        tavilyApiKey := old
        if !InStr(result, "Web search failed")
            throw Error("expected a failure message, got: " result)
    }

    LogPayload_ExcludesApiKeyAndKeepsQueryMetadata() {
        logged := TavilySearch._LogPayload("AutoHotkey WebView2")
        if InStr(logged, "api_key") || InStr(logged, "test-tavily-key")
            throw Error("logged Tavily payload contains credential material: " logged)
        if !InStr(logged, "AutoHotkey WebView2")
            throw Error("logged Tavily payload lost the search query: " logged)
    }
}
