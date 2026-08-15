; ======================================================
; SearchTools.ahk — Web-search tool definition + shared helpers
;
; AhkLLM's only tool is web search. The per-thread right-rail toggle
; (requestParams.webSearch, default off) decides whether the model sees the
; tool at all. When it calls web_search:
;   - DeepSeek models search natively via DeepSeek's Responses API
;     (POST /responses with the server-side web_search tool).
;   - Every other provider falls back to Tavily (plain REST, no model
;     function-calling requirements beyond the standard tools array).
; ======================================================

class SearchTools {

    static TOOL_NAME := "web_search"
    static MAX_TOOL_ITERATIONS := 6

    ; OpenAI-compatible function-tool definition sent to every provider when
    ; the per-thread Web Search toggle is on.
    static Definition() {
        return {
            type: "function",
            function: {
                name: SearchTools.TOOL_NAME,
                description: "Search the web for current, factual, or URL-specific information. Returns an answer with source links.",
                parameters: {
                    type: "object",
                    properties: { query: { type: "string", description: "The search query." } },
                    required: ["query"]
                    ; NOTE: do NOT add additionalProperties here. AHK has no
                    ; boolean type — `false` IS 0, and jsongo serializes it as
                    ; "additionalProperties":0, which DeepSeek's JSON-Schema
                    ; validator rejects ("0 is not of types boolean, object").
                    ; The field is optional in JSON Schema, so omitting it is
                    ; both valid and provider-safe.
                }
            }
        }
    }

    ; Is the per-thread Web Search toggle on?
    static Enabled() {
        global requestParams
        return requestParams.Has("webSearch") && requestParams["webSearch"]
    }

    ; DeepSeek models search natively (their /responses API); everything else
    ; uses Tavily as the fallback backend.
    static IsNativeDeepSeek(providerKey) {
        return providerKey = "deepseek"
    }

    ; Tavily key: explicit setting wins, environment variable is the fallback
    ; (mirrors ProviderResolver._getApiKey for model providers).
    static TavilyKey() {
        global tavilyApiKey
        if IsSet(tavilyApiKey) && tavilyApiKey != ""
            return tavilyApiKey
        return EnvGet("TAVILY_API_KEY")
    }

    static TavilyEndpoint() {
        global tavilyEndpoint
        return IsSet(tavilyEndpoint) && tavilyEndpoint != "" ? tavilyEndpoint : "https://api.tavily.com/search"
    }

    ; Derive a Responses-API endpoint from a chat-completions endpoint:
    ;   https://api.deepseek.com/chat/completions  -> https://api.deepseek.com/responses
    ;   http://127.0.0.1:PORT/v1/chat/completions  -> http://127.0.0.1:PORT/v1/responses
    static ResponsesEndpoint(chatEndpoint) {
        marker := "/chat/completions"
        pos := InStr(chatEndpoint, marker)
        if pos {
            return SubStr(chatEndpoint, 1, pos - 1) . "/responses"
        }
        v1Pos := InStr(chatEndpoint, "/v1")
        if v1Pos {
            return SubStr(chatEndpoint, 1, v1Pos + 2) . "/responses"
        }
        return RTrim(chatEndpoint, "/") . "/responses"
    }

    ; Human-readable search context persisted as a user-role message so
    ; follow-up turns keep the results in API history (no schema change:
    ; it is a plain text message).
    static BuildContextText(query, resultText) {
        return "[Web search: " query "]`n`n" resultText
    }
}
