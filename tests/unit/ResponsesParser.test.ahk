; ======================================================
; ResponsesParser.test.ahk — DeepSeek/OpenAI Responses API parser
; ======================================================

class ResponsesParserTest {

    static __New() {
        RegisterTestClass("ResponsesParserTest")
    }

    Parse_ExtractsOutputTextAndUsage() {
        raw := '{"object":"response","model":"deepseek-v4-flash","output":[{"type":"message","content":[{"type":"output_text","text":"Hello!"}]}],"usage":{"input_tokens":10,"output_tokens":5,"total_tokens":15,"input_tokens_details":{"cached_tokens":3},"output_tokens_details":{"reasoning_tokens":2}}}'
        result := ResponsesParser.Parse(jsongo.Parse(raw))
        if result.response != "Hello!"
            throw Error("response text mismatch: '" result.response "'")
        if result.model != "deepseek-v4-flash"
            throw Error("model mismatch")
        if result.usage.promptTokens != 10 || result.usage.completionTokens != 5 || result.usage.totalTokens != 15 || result.usage.cachedTokens != 3 || result.usage.thinkingTokens != 2
            throw Error("usage mapping mismatch: " jsongo.Stringify(result.usage))
    }

    Parse_EmptyOutput_ReturnsEmpty() {
        result := ResponsesParser.Parse(jsongo.Parse('{"output":[],"usage":{}}'))
        if result.response != ""
            throw Error("expected empty response")
    }

    Parse_MissingUsage_DoesNotThrow() {
        result := ResponsesParser.Parse(jsongo.Parse('{"output":[{"type":"message","content":[{"type":"output_text","text":"x"}]}]}'))
        if result.response != "x"
            throw Error("expected response text")
        if result.usage.totalTokens != 0
            throw Error("expected zeroed usage")
    }
}
