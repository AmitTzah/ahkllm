; ======================================================
; DeepSeekSearch.test.ahk - DeepSeek native /responses backend
; ======================================================

class DeepSeekSearchTest {

    static __New() {
        RegisterTestClass("DeepSeekSearchTest")
    }

    ; Regression (real-API report 2026-08-15): DeepSeek's /responses envelope
    ; always carries an "error" key - JSON null on success. jsongo parses
    ; null as "" (empty string), so the old `parsed.Has("error")` check
    ; treated every successful search as "Web search failed: " with no
    ; reason. The shape below is the REAL api.deepseek.com/responses success
    ; response (reasoning + web_search_call + message output items, plus
    ; error:null in the envelope).
    ExtractResult_SuccessEnvelopeWithErrorNull_ReturnsAnswer() {
        ; Apostrophes inside the JSON use the \u0027 escape (this AHK build's
        ; single-quoted string literals have no '' escape).
        raw := '{"object":"response","status":"completed","model":"deepseek-v4-pro","error":null,"output":[{"type":"reasoning","id":"r1","status":"completed","content":[{"type":"reasoning_text","text":"searching"}]},{"type":"web_search_call","id":"c1","status":"completed","action":{"type":"search","queries":["today\u0027s date"]}},{"type":"message","id":"m1","status":"completed","role":"assistant","content":[{"type":"output_text","annotations":[],"text":"Today\u0027s date is Tuesday, August 4, 2026."}]}],"usage":{"input_tokens":4750,"output_tokens":796,"total_tokens":5546,"input_tokens_details":{"cached_tokens":3456},"output_tokens_details":{"reasoning_tokens":680}}}'
        result := DeepSeekSearch.ExtractResult(jsongo.Parse(raw), "today's date")
        if result != "Today's date is Tuesday, August 4, 2026."
            throw Error("error:null success envelope must return the answer, got: '" result "'")
    }

    ; A REAL failure still surfaces a meaningful message (never a bare
    ; "Web search failed: ").
    ExtractResult_RealErrorObject_ReturnsFailureMessage() {
        raw := '{"error":{"message":"rate limit exceeded","type":"rate_limit_error"}}'
        result := DeepSeekSearch.ExtractResult(jsongo.Parse(raw))
        if !InStr(result, "Web search failed: rate limit exceeded")
            throw Error("expected rate-limit failure text, got: '" result "'")
    }

    ExtractResult_EmptyOutput_ReturnsNoAnswerFailure() {
        raw := '{"object":"response","status":"completed","error":null,"output":[]}'
        result := DeepSeekSearch.ExtractResult(jsongo.Parse(raw))
        if result != "Web search failed: DeepSeek returned no answer."
            throw Error("expected no-answer failure, got: '" result "'")
    }

    ExtractResult_MissingErrorKey_ReturnsAnswer() {
        raw := '{"object":"response","output":[{"type":"message","content":[{"type":"output_text","text":"plain answer"}]}]}'
        result := DeepSeekSearch.ExtractResult(jsongo.Parse(raw))
        if result != "plain answer"
            throw Error("missing error key must still parse the answer, got: '" result "'")
    }

    ; Key gate returns a failure without touching the network (same pattern
    ; as the Tavily key gate test).
    Run_MissingApiKey_ReturnsErrorWithoutNetwork() {
        result := DeepSeekSearch.Run("test query", { providerKey: "deepseek", modelName: "deepseek-v4-pro", apiKey: "", endpoint: "https://api.deepseek.com/chat/completions" })
        if !InStr(result, "no DeepSeek API key")
            throw Error("expected missing-key failure, got: '" result "'")
    }
}
