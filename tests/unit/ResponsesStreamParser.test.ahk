; ======================================================
; ResponsesStreamParser.test.ahk - DeepSeek /responses SSE stream parser
; ======================================================

class ResponsesStreamParserTest {

    static __New() {
        RegisterTestClass("ResponsesStreamParserTest")
    }

    ParseLine_ReasoningDelta() {
        result := ResponsesStreamParser.ParseLine('data: {"type":"response.reasoning_text.delta","content_index":0,"delta":"The","item_id":"r1","output_index":0}')
        if result.type != "reasoning" || result.content != "The"
            throw Error("expected reasoning delta, got: " jsongo.Stringify(result))
    }

    ; The message phase is only on output_item.added; the parser must track it
    ; per item id so output_text deltas can be attributed to final vs
    ; commentary.
    ParseLine_OutputTextDelta_AttributesFinalAnswerPhase() {
        ResponsesStreamParser.Reset()
        ResponsesStreamParser.ParseLine('data: {"type":"response.output_item.added","item":{"type":"message","id":"m1","status":"in_progress","content":[],"phase":"final_answer","role":"assistant"},"output_index":2}')
        result := ResponsesStreamParser.ParseLine('data: {"type":"response.output_text.delta","content_index":0,"delta":"Hello","item_id":"m1","output_index":2}')
        if result.type != "answer" || result.content != "Hello" || result.phase != "final_answer"
            throw Error("expected final_answer delta, got: " jsongo.Stringify(result))
    }

    ParseLine_CommentaryPhase_NotFinalAnswer() {
        ResponsesStreamParser.Reset()
        ResponsesStreamParser.ParseLine('data: {"type":"response.output_item.added","item":{"type":"message","id":"c1","status":"in_progress","content":[],"phase":"commentary","role":"assistant"},"output_index":1}')
        result := ResponsesStreamParser.ParseLine('data: {"type":"response.output_text.delta","content_index":0,"delta":"Let me dig","item_id":"c1","output_index":1}')
        if result.type != "answer" || result.phase != "commentary"
            throw Error("expected commentary delta, got: " jsongo.Stringify(result))
    }

    ParseLine_UnknownItemId_HasEmptyPhase() {
        ResponsesStreamParser.Reset()
        result := ResponsesStreamParser.ParseLine('data: {"type":"response.output_text.delta","delta":"x","item_id":"unknown"}')
        if result.type != "answer" || result.phase != ""
            throw Error("expected empty phase for unknown item, got: " jsongo.Stringify(result))
    }

    ParseLine_SearchAndLifecycleEvents() {
        result := ResponsesStreamParser.ParseLine('data: {"type":"response.web_search_call.searching","item_id":"call_1","output_index":1}')
        if result.type != "search"
            throw Error("expected search event, got: " jsongo.Stringify(result))
        result2 := ResponsesStreamParser.ParseLine('data: {"type":"response.web_search_call.completed","item_id":"call_1","output_index":1}')
        if result2.type != "search_done"
            throw Error("expected search_done event, got: " jsongo.Stringify(result2))
        result3 := ResponsesStreamParser.ParseLine('data: {"type":"response.completed","response":{}}')
        if result3.type != "done"
            throw Error("expected done event, got: " jsongo.Stringify(result3))
    }

    ParseLine_IgnoresNonDataLines() {
        if ResponsesStreamParser.ParseLine("event: response.created").type != "ignore"
            throw Error("event-only lines must be ignored")
        if ResponsesStreamParser.ParseLine("").type != "ignore"
            throw Error("empty lines must be ignored")
        if ResponsesStreamParser.ParseLine("data: not json").type != "ignore"
            throw Error("unparseable data must be ignored")
    }
}
