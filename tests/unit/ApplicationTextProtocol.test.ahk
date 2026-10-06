class ApplicationTextProtocolTest {
    static __New() => RegisterTestClass("ApplicationTextProtocolTest")

    _tools() => [Map("name", "echo_text", "parameters", Map("type", "object", "properties", Map("text", Map("type", "string")), "required", ["text"], "additionalProperties", false))]

    Parse_ValidCallsAndFinalAnswers() {
        calls := Map("kind", "tool_calls", "calls", [Map("name", "echo_text", "arguments", Map("text", "Hello Ω"))])
        parsed := ApplicationTextProtocol.Parse(ApplicationTextProtocol.Envelope(calls), this._tools())
        if parsed.calls.Length != 1 || parsed.calls[1]["name"] != "echo_text" || parsed.calls[1]["call_id"] = ""
            throw Error("Valid advertised call was not normalized")
        if jsongo.Parse(parsed.calls[1]["arguments"])["text"] != "Hello Ω"
            throw Error("UTF-8 tool arguments changed")
        literal := 'A literal example: {"kind":"tool_calls"}'
        final := ApplicationTextProtocol.Parse(ApplicationTextProtocol.Envelope(Map("kind", "final", "content", literal)), this._tools())
        if final.content != literal || final.calls.Length
            throw Error("Final examples must remain inert text")
        plain := ApplicationTextProtocol.Parse(literal, this._tools())
        if plain.calls.Length || plain.content != literal
            throw Error("Unmarked JSON must never invoke a tool")
        lowerMarker := StrLower(ApplicationTextProtocol.MARKER) "`n" jsongo.Stringify(calls)
        if ApplicationTextProtocol.Parse(lowerMarker, this._tools()).calls.Length
            throw Error("A different marker spelling must remain inert text")
    }

    Parse_RejectsMalformedUnknownAndInvalidArgumentsBeforeExecution() {
        invalid := [
            ApplicationTextProtocol.MARKER "`n" '{"kind":"tool_calls","calls":[',
            ApplicationTextProtocol.Envelope(Map("kind", "tool_calls", "calls", [Map("name", "unadvertised", "arguments", Map())])),
            ApplicationTextProtocol.Envelope(Map("kind", "tool_calls", "calls", [Map("name", "ECHO_TEXT", "arguments", Map("text", "ok"))])),
            ApplicationTextProtocol.Envelope(Map("kind", "tool_calls", "calls", [Map("name", "echo_text", "arguments", Map("text", 42))])),
            ApplicationTextProtocol.Envelope(Map("kind", "tool_calls", "calls", [Map("name", "echo_text", "arguments", Map())])),
            ApplicationTextProtocol.Envelope(Map("kind", "tool_calls", "calls", [Map("name", "echo_text", "arguments", Map("text", "ok", "unexpected", true))])),
            ApplicationTextProtocol.Envelope(Map("kind", "final", "content", "ok")) " trailing prose"
        ]
        for text in invalid {
            rejected := false
            try ApplicationTextProtocol.Parse(text, this._tools())
            catch
                rejected := true
            if !rejected
                throw Error("Unsafe or malformed application reply was accepted")
        }
    }

    Messages_ReplayToolExchangeWithoutNativeToolRoles() {
        input := [Map("type", "function_call", "call_id", "one", "name", "echo_text", "arguments", '{"text":"hello"}'),
            Map("type", "function_call_output", "call_id", "one", "output", "exact result")]
        messages := ApplicationTextProtocol.Messages(input)
        if messages[1].role != "assistant" || !InStr(messages[1].content, ApplicationTextProtocol.MARKER)
            || messages[2].role != "user" || !InStr(messages[2].content, "exact result")
            throw Error("Text replay lost call/result identity")
    }

    Parse_PreservesBooleanAndNullTypesAndRejectsTypeConfusion() {
        tools := [Map("name", "typed", "parameters", Map("type", "object", "properties", Map(
            "flag", Map("type", "boolean"), "optional", Map("type", ["string", "null"]), "line", Map("type", "integer")
        ), "required", ["flag", "optional", "line"], "additionalProperties", false))]
        text := ApplicationTextProtocol.MARKER "`n" '{"kind":"tool_calls","calls":[{"name":"typed","arguments":{"flag":true,"optional":null,"line":1}}]}'
        parsed := ApplicationTextProtocol.Parse(text, tools)
        args := parsed.calls[1]["arguments"]
        if !InStr(args, '"flag":true') || !InStr(args, '"optional":null')
            throw Error("Text arguments lost their JSON literal types")
        for invalid in [StrReplace(text, '"line":1', '"line":true'), StrReplace(text, '"flag":true', '"flag":1')] {
            rejected := false
            try ApplicationTextProtocol.Parse(invalid, tools)
            catch
                rejected := true
            if !rejected
                throw Error("Boolean and integer arguments must not be interchangeable")
        }
        nullText := ApplicationTextProtocol.MARKER "`n" '{"kind":"tool_calls","calls":[{"name":"echo_text","arguments":{"text":null}}]}'
        rejected := false
        try ApplicationTextProtocol.Parse(nullText, this._tools())
        catch
            rejected := true
        if !rejected
            throw Error("Null must not be accepted as an empty string argument")
    }

    ApplyRequest_IsGenericAndOnlyAddsAdvertisedToolInstructions() {
        request := {messages: [{role: "system", content: "Task instructions"}], tools: [Map("type", "function")], external_input: []}
        input := [Map("role", "user", "content", [Map("type", "input_text", "text", "Prepared context")])]
        ApplicationTextProtocol.ApplyRequest(request, input, this._tools())
        if request.HasOwnProp("tools") || request.HasOwnProp("external_input")
            || !InStr(request.messages[1].content, "echo_text") || request.messages[2].content != "Task instructions"
            || request.messages[3].content != "Prepared context"
            throw Error("Text mode did not preserve context and replace native schemas")
    }
}
