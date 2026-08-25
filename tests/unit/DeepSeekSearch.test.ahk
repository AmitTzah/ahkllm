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

    ; Regression (real capture 2026-08-16): DeepSeek tags every message item
    ; "final_answer" at output_item.added time and only marks interim
    ; commentary ("Let me search...") as "commentary" at output_item.done.
    ; The streamed result must be rebuilt from the done-time phases so the
    ; tool result / search card never includes the model's interim narration,
    ; while the live card still shows everything the model streams.
    FeedFixture_MultiItemStream_UsesDoneTimePhaseForFinalAnswer() {
        streamFile := A_ScriptDir "\fixtures\responses-stream-multi-item.sse"
        if !FileExist(streamFile)
            throw Error("fixture missing: " streamFile)
        raw := FileOpen(streamFile, "r", "UTF-8-RAW").Read()
        ResponsesStreamParser.Reset()
        state := { reasoning: "", answer: "", items: Map(), itemOrder: [], searchRounds: 0, failedMsg: "", lastProgressTick: 0 }
        for line in StrSplit(raw, "`n") {
            if Trim(line) = ""
                continue
            DeepSeekSearch._FeedProgress(line, state, "test query", "")
        }
        finalAnswer := DeepSeekSearch._BuildFinalAnswer(state)
        if finalAnswer != "Here is the answer: Iran situation is tense."
            throw Error("expected only the final item in the result, got: '" finalAnswer "'")
        if InStr(state.answer, "Let me search for the latest news.") = 0
            throw Error("live card must still show the interim commentary")
        if InStr(finalAnswer, "Let me search") != 0
            throw Error("interim commentary leaked into the final result")
    }

    ; Regression (real-API report 2026-08-16 18:48): jsongo serializes AHK
    ; true as JSON 1, and DeepSeek's /responses API REJECTS "stream":1 with a
    ; 400 - every search call failed instantly and was misreported as
    ; "no answer". The wire payload must carry a real JSON boolean.
    BuildPayload_SendsRealJsonBooleanForStream() {
        payload := DeepSeekSearch._BuildPayload("latest news", { providerKey: "deepseek", modelName: "deepseek-v4-pro", apiKey: "k", endpoint: "https://api.deepseek.com/chat/completions" })
        if InStr(payload, '"stream":1') != 0
            throw Error("payload must not carry stream:1: " payload)
        if InStr(payload, '"stream":true') = 0
            throw Error("payload must carry stream:true: " payload)
        parsed := jsongo.Parse(payload)
        if !IsObject(parsed) || !parsed.Has("stream")
            throw Error("payload did not parse: " payload)
    }

    ; A 400 validation body is plain JSON (no SSE events), so the stream
    ; parser never sees it - the real API error must still surface instead of
    ; the misleading "DeepSeek returned no answer".
    ReadApiError_ExtractsMessageFromValidationBody() {
        errFile := A_Temp "\ds_err_test_" A_TickCount "_" Random(1000, 999999) ".json"
        FileOpen(errFile, "w", "UTF-8-RAW").Write('{"error":{"message":"stream: invalid type: integer 1, expected a boolean","type":"invalid_request_error"}}')
        msg := DeepSeekSearch._ReadApiError(errFile)
        try FileDelete(errFile)
        if InStr(msg, "expected a boolean") = 0
            throw Error("expected the real error message, got: '" msg "'")
    }

    ReadApiError_EmptyForNonJsonBody() {
        errFile := A_Temp "\ds_err_test2_" A_TickCount "_" Random(1000, 999999) ".txt"
        FileOpen(errFile, "w", "UTF-8-RAW").Write("not json")
        msg := DeepSeekSearch._ReadApiError(errFile)
        try FileDelete(errFile)
        if msg != ""
            throw Error("expected empty for non-JSON body, got: '" msg "'")
    }
}
