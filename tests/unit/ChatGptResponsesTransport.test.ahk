; ======================================================
; ChatGptResponsesTransport.test.ahk — direct ChatGPT-plan transport tests
; No network or real OAuth calls.
; ======================================================

class ChatGptResponsesTransportTest {
    static __New() {
        RegisterTestClass("ChatGptResponsesTransportTest")
    }

    BuildPayload_IsStatelessAndUsesRequiredPlanFlags() {
        request := Map(
            "model", "gpt-test",
            "messages", [
                Map("role", "system", "content", "System rule"),
                Map("role", "user", "content", "Hello"),
                Map("role", "assistant", "content", "Hi"),
                Map("role", "user", "content", "Again")
            ],
            "temperature", 0.7,
            "max_output_tokens", 1234,
            "previous_response_id", "must-not-leak"
        )
        payload := ChatGptResponsesTransport.BuildPayload(request, false, false)
        json := ChatGptResponsesTransport.Serialize(payload)

        if !InStr(json, '"store":false')
            throw Error("ChatGPT-plan payload must serialize store:false")
        if !InStr(json, '"stream":true')
            throw Error("ChatGPT-plan payload must serialize stream:true")
        if !InStr(json, '"parallel_tool_calls":false')
            throw Error("ChatGPT-plan image/function execution must be serial")
        for forbidden in ["previous_response_id", "temperature", "max_output_tokens", '"messages"'] {
            if InStr(json, forbidden)
                throw Error("Unsupported/stateful Responses field leaked into plan payload: " forbidden)
        }
        if !payload.Has("instructions") || payload["instructions"] != "System rule"
            throw Error("system messages must be lifted into Responses instructions")
        if payload["input"].Length != 3
            throw Error("user/assistant history must remain explicit Responses input")
    }

    BuildPayload_MapsImageDataAndTextToResponsesParts() {
        request := Map(
            "model", "gpt-test",
            "messages", [
                Map(
                    "role", "user",
                    "content", [
                        Map("type", "image_url", "image_url", Map("url", "data:image/png;base64,AA==")),
                        Map("type", "text", "text", "describe")
                    ]
                )
            ]
        )
        payload := ChatGptResponsesTransport.BuildPayload(request)
        parts := payload["input"][1]["content"]
        if parts.Length != 2
            throw Error("expected image and text Responses content parts")
        if parts[1]["type"] != "input_image" || parts[1]["image_url"] != "data:image/png;base64,AA=="
            throw Error("image_url content was not converted to Responses input_image")
        if parts[2]["type"] != "input_text" || parts[2]["text"] != "describe"
            throw Error("text content was not converted to Responses input_text")
    }

    BuildPayload_WebSearchAndImageToolAreExplicitToggles() {
        base := Map("model", "gpt-test", "messages", [Map("role", "user", "content", "draw a lighthouse")])
        none := ChatGptResponsesTransport.BuildPayload(base, false, false)
        if none.Has("tools")
            throw Error("tools must be absent when both right-rail toggles are off")

        search := ChatGptResponsesTransport.BuildPayload(base, true, false)
        if !search.Has("tools") || search["tools"].Length != 1 || search["tools"][1]["type"] != "web_search"
            throw Error("Web Search toggle must expose only hosted web_search")

        image := ChatGptResponsesTransport.BuildPayload(base, false, true)
        if !image.Has("tools") || image["tools"].Length != 1
            throw Error("Image Generation toggle must expose one client namespace")
        ns := image["tools"][1]
        if ns["type"] != "namespace" || ns["name"] != "ahkllm"
            throw Error("image tool must live under the ahkllm namespace")
        tool := ns["tools"][1]
        if tool["type"] != "function" || tool["name"] != "generate_image" || !tool["strict"]
            throw Error("image tool must be the strict ahkllm.generate_image function")
    }

    ToolContinuation_ReplaysExactOutputItemsAndCallResult() {
        original := Map(
            "model", "gpt-test",
            "input", [Map("type", "message", "role", "user", "content", [Map("type", "input_text", "text", "draw")])],
            "store", false,
            "stream", true
        )
        reasoning := Map("type", "reasoning", "id", "rs_1", "encrypted_content", "opaque")
        call := Map(
            "type", "function_call",
            "id", "fc_1",
            "call_id", "call_1",
            "namespace", "ahkllm",
            "name", "generate_image",
            "arguments", '{"prompt":"a lighthouse"}'
        )
        output := Map("type", "function_call_output", "call_id", "call_1", "output", '{"status":"success"}')

        next := ChatGptResponsesTransport.BuildToolContinuation(original, [reasoning, call], [output])
        if next["input"].Length != 4
            throw Error("tool continuation must contain original input + every output item + function output")
        if next["input"][2]["encrypted_content"] != "opaque"
            throw Error("reasoning output item must be replayed exactly")
        if next["input"][3]["call_id"] != "call_1" || next["input"][4]["call_id"] != "call_1"
            throw Error("function call/output correlation must use call_id")
        if next.Has("previous_response_id")
            throw Error("HTTP plan continuation must not use previous_response_id")
    }

    BufferedParser_RequiresResponseCompleted() {
        partial := 'data: {"type":"response.output_text.delta","delta":"partial"}' Chr(10) Chr(10)
        failed := ChatGptResponsesTransport.ParseBuffered(partial)
        if failed.success
            throw Error("partial Responses stream must never be treated as successful")
        if !InStr(failed.error, "response.completed")
            throw Error("partial stream failure must identify the missing terminal event")

        complete := partial
            . 'data: {"type":"response.completed","response":{"model":"gpt-test","output":[],"usage":{"input_tokens":10,"output_tokens":2,"total_tokens":12,"input_tokens_details":{"cached_tokens":3},"output_tokens_details":{"reasoning_tokens":1}}}}'
            . Chr(10) Chr(10)
        ok := ChatGptResponsesTransport.ParseBuffered(complete)
        if !ok.success || ok.response.response != "partial"
            throw Error("completed Responses stream must return the buffered answer")
        if ok.response.usage.promptTokens != 10 || ok.response.usage.cachedTokens != 3 || ok.response.usage.thinkingTokens != 1
            throw Error("Responses usage fields were not normalized")
    }

    BufferedParser_SurfacesPreStreamAdmissionJson() {
        detail := ChatGptResponsesTransport.ParseBuffered('{"detail":"ChatGPT plan usage is unavailable for this account."}')
        if detail.success || detail.error != "ChatGPT plan usage is unavailable for this account."
            throw Error("pre-stream detail errors must surface their server diagnostic")

        nested := ChatGptResponsesTransport.ParseBuffered('{"error":{"message":"OAuth token is no longer valid."}}')
        if nested.success || nested.error != "OAuth token is no longer valid."
            throw Error("pre-stream error.message must surface its server diagnostic")

        limited := ChatGptResponsesTransport.ParseBuffered('{"error":{"code":"subscription_sharing_usage_limit_exceeded","message":"Usage limit reached."}}')
        if limited.success || !limited.HasOwnProp("errorCode") || limited.errorCode != "subscription_sharing_usage_limit_exceeded"
            throw Error("pre-stream admission error code must be preserved")
    }

    BufferedParser_PreservesUsageLimitErrorCode() {
        failed := ChatGptResponsesTransport.ParseBuffered(
            'data: {"type":"response.failed","response":{"error":{"code":"subscription_sharing_usage_limit_exceeded","message":"Usage limit reached.","param":null}}}' Chr(10) Chr(10)
        )
        if failed.success
            throw Error("response.failed must not be treated as success")
        if !failed.HasOwnProp("errorCode") || failed.errorCode != "subscription_sharing_usage_limit_exceeded"
            throw Error("structured Responses error code was not preserved")
        if failed.error != "Usage limit reached."
            throw Error("structured Responses error message was not preserved")
    }

    StreamParser_RendersWebCitationsAsClickableMarkdown() {
        output := [
            Map(
                "type", "message",
                "role", "assistant",
                "content", [
                    Map(
                        "type", "output_text",
                        "text", "Alpha fact. Beta fact.",
                        "annotations", [
                            Map(
                                "type", "url_citation",
                                "start_index", 0,
                                "end_index", 11,
                                "url", "https://example.test/alpha",
                                "title", "Alpha source"
                            ),
                            Map(
                                "type", "url_citation",
                                "start_index", 12,
                                "end_index", 22,
                                "url", "https://example.test/beta",
                                "title", "Beta source"
                            )
                        ]
                    )
                ]
            )
        ]
        text := ChatGptResponsesStreamParser.FinalTextWithCitations(output)
        if !InStr(text, "Alpha fact. [source](<https://example.test/alpha>)")
            throw Error("first web citation was not made clickable inline")
        if !InStr(text, "Beta fact. [source](<https://example.test/beta>)")
            throw Error("second web citation was not made clickable inline")
    }

    StreamParser_ExtractsNamespacedFunctionCallFromCompletedOutput() {
        line := 'data: {"type":"response.completed","response":{"model":"gpt-test","output":[{"type":"reasoning","id":"rs1"},{"type":"function_call","id":"fc1","call_id":"call1","namespace":"ahkllm","name":"generate_image","arguments":"{\"prompt\":\"x\"}"}],"usage":{"input_tokens":1,"output_tokens":1,"total_tokens":2}}}'
        chunk := ChatGptResponsesStreamParser.ParseLine(line)
        if chunk.type != "finish" || !chunk.completed
            throw Error("response.completed must be the terminal success event")
        if chunk.functionCalls.Length != 1
            throw Error("expected one function call from response.output")
        call := chunk.functionCalls[1]
        if call["namespace"] != "ahkllm" || call["name"] != "generate_image" || call["call_id"] != "call1"
            throw Error("completed function-call metadata was not preserved")
    }


    StreamParser_ItemDoneToolSurvivesEmptyCompletedOutput() {
        state := {transport:"chatgpt-responses",responseOutput:[],responsesToolCalls:[],responsesCompleted:false,
            content:"",reasoning:"",firstTokenTime:0,usage:{promptTokens:0,completionTokens:0,cachedTokens:0,thinkingTokens:0,totalTokens:0}}
        call := Map("type","function_call","id","fc-fixture","call_id","call-fixture",
            "namespace","ahkllm","name","generate_image","arguments",'{"prompt":"Alternative cover"}')
        events := [
            Map("type","response.output_item.done","output_index",0,"item",Map("type","reasoning","id","rs-fixture","encrypted_content","opaque-fixture","summary",[])),
            Map("type","response.function_call_arguments.done","item_id","fc-fixture","output_index",1,"arguments",call["arguments"]),
            Map("type","response.output_item.done","output_index",1,"item",call)
        ]
        for event in events
            _processChunk(state, ChatGptResponsesStreamParser.ParseLine("data: " jsongo.Stringify(event)), false)
        if state.responsesCompleted
            throw Error("Item completion must not mark the whole response completed")
        _processChunk(state, ChatGptResponsesStreamParser.ParseLine('data: {"type":"response.completed","response":{"status":"completed","output":[]}}'), false)
        if !state.responsesCompleted || state.responseOutput.Length != 2 || state.responsesToolCalls.Length != 1
            throw Error("Empty terminal output must preserve completed streamed items and the image call")
        saved := state.responsesToolCalls[1]
        if saved["call_id"] != "call-fixture" || saved["namespace"] != "ahkllm" || saved["name"] != "generate_image" || saved["arguments"] != call["arguments"]
            throw Error("The full item-done metadata must replace the metadata-free arguments event")
        if state.content != "" || state.reasoning != ""
            throw Error("Opaque reasoning must never be rendered as text")
    }

    StreamParser_RepeatedTerminalItemsAreDeduplicatedAndEnriched() {
        first := Map("id","fc-fixture","type","function_call","call_id","call-fixture","namespace","ahkllm","name","generate_image","arguments",'{"prompt":"first"}')
        latest := first.Clone()
        latest["arguments"] := '{"prompt":"final"}'
        merged := ChatGptResponsesStreamParser.MergeOutput([first],[latest])
        if merged.Length != 1 || merged[1]["arguments"] != latest["arguments"]
            throw Error("Terminal items must enrich the existing ID instead of invoking tools twice")
    }

    BufferedParser_ItemDoneTextSurvivesEmptyCompletedOutput() {
        raw := 'data: {"type":"response.output_item.done","item":{"type":"message","id":"msg-fixture","role":"assistant","content":[{"type":"output_text","text":"Completed item text"}]}}' Chr(10)
            . 'data: {"type":"response.completed","response":{"status":"completed","output":[]}}' Chr(10)
        result := ChatGptResponsesTransport.ParseBuffered(raw)
        if !result.success || result.content != "Completed item text" || result.responseOutput.Length != 1
            throw Error("Buffered Responses must preserve item-done text when terminal output is empty")
    }

    Serialize_LargeImageBytesArePreservedWithoutSlashEscaping() {
        image := "data:image/png;base64," StrReplace(Format("{:" (32 * 1024 * 1024) "}", ""), " ", "/")
        original := Map("model","gpt-test","input",[Map("role","user","content",[Map("type","input_image","image_url",image)])],"stream",true,"store",false)
        started := A_TickCount
        json := ChatGptResponsesTransport.Serialize(original)
        elapsed := A_TickCount - started
        Log("[PERF] Original 32 MiB base64 image serialization: " elapsed "ms`n")
        if elapsed > 5000 || InStr(json, "\/")
            throw Error("Large image JSON must avoid repeated slash escaping")
        parsed := jsongo.Parse(json)
        if parsed["input"][1]["content"][1]["image_url"] != image || original["input"][1]["content"][1]["image_url"] != image
            throw Error("Serialization must preserve the exact full-resolution image and the caller's payload")
        if !InStr(json, '"stream":true') || !InStr(json, '"store":false') || InStr(json,"AhkLLM_image_")
            throw Error("Boolean flags must remain correct and internal markers must not escape")
    }

    Serialize_UnsafeImageLookingStringsStayEscaped() {
        prefix := "data:image/png;base64," StrReplace(Format("{:8192}", ""), " ", "A")
        for suffix in ['"injected":true',Chr(10),"\",Chr(9)] {
            value := prefix suffix
            parsed := jsongo.Parse(ChatGptResponsesTransport.Serialize(Map("input",[Map("type","input_image","image_url",value)])))
            if parsed["input"][1]["image_url"] != value
                throw Error("Unsafe or malformed data URLs must use normal JSON escaping")
        }
    }

    BuildPayload_AllowsHistoryBeyondFormerCodexCharacterCeiling() {
        chunk := "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
        large := ""
        Loop 10000
            large .= chunk
        request := Map(
            "model", "gpt-test",
            "messages", [
                Map("role", "user", "content", large),
                Map("role", "assistant", "content", large),
                Map("role", "user", "content", "continue")
            ]
        )
        payload := ChatGptResponsesTransport.BuildPayload(request)
        json := ChatGptResponsesTransport.Serialize(payload)
        if StrLen(json) <= 1048576
            throw Error("fixture must exceed the former Codex turn/start 1,048,576-character ceiling")
        if payload["input"].Length != 3
            throw Error("large accumulated history must remain explicit Responses input without compaction")
        if !InStr(json, '"store":false') || !InStr(json, '"stream":true')
            throw Error("large history must still use the required stateless ChatGPT-plan flags")
    }

    SecureCurlCommand_DoesNotContainBearerToken() {
        src := FileRead(A_ScriptDir "\..\api\ChatGptResponsesTransport.ahk")
        if !InStr(src, 'curl.exe --no-buffer --silent --show-error --fail-with-body --config -')
            throw Error("Responses transport must feed curl config through stdin")
        if InStr(src, 'Authorization: Bearer " accessToken') && InStr(src, "commandLine .=")
            throw Error("bearer token must never be appended to the process command line")
    }
}
