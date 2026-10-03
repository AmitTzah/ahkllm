; ======================================================
; ChatGptResponsesStreamParser.ahk — OpenAI Responses SSE parser
;
; Parses the typed event stream used by direct ChatGPT-plan /v1/responses
; requests. A request is successful only after response.completed.
; ======================================================

class ChatGptResponsesStreamParser {
    static ParseLine(line) {
        pos := InStr(line, "data: ")
        if !pos
            return { type: "ignore" }

        data := SubStr(line, pos + 6)
        if data = "[DONE]"
            return { type: "transport_done" }

        try parsed := jsongo.Parse(data)
        catch
            return { type: "ignore" }
        if Type(parsed) != "Map"
            return { type: "ignore" }

        if !parsed.Has("type") {
            if parsed.Has("error")
                return ChatGptResponsesStreamParser._ErrorChunk(parsed["error"], "The ChatGPT Responses request failed.")
            return { type: "ignore" }
        }

        eventType := String(parsed["type"])

        if eventType = "response.output_text.delta" {
            return {
                type: "content",
                content: parsed.Has("delta") ? String(parsed["delta"]) : ""
            }
        }

        if eventType = "response.refusal.delta" {
            return {
                type: "content",
                content: parsed.Has("delta") ? String(parsed["delta"]) : ""
            }
        }

        ; Public reasoning summaries are safe to render. Never expose encrypted
        ; reasoning content or infer private chain-of-thought from other items.
        if InStr(eventType, "response.reasoning_summary") && InStr(eventType, ".delta") {
            return {
                type: "reasoning",
                content: parsed.Has("delta") ? String(parsed["delta"]) : ""
            }
        }

        if eventType = "response.web_search_call.in_progress"
            || eventType = "response.web_search_call.searching" {
            return { type: "activity", content: "Searching the web..." }
        }

        if eventType = "response.web_search_call.completed"
            return { type: "activity", content: "Web search completed." }

        if eventType = "response.output_item.done" {
            if parsed.Has("item") && parsed["item"] is Map
                return { type: "responses_output_item", item: parsed["item"] }
            return { type: "ignore" }
        }

        if eventType = "response.function_call_arguments.done" {
            call := Map()
            if parsed.Has("item") && IsObject(parsed["item"]) {
                item := parsed["item"]
                call["id"] := item.Has("id") ? item["id"] : ""
                call["call_id"] := item.Has("call_id") ? item["call_id"] : call["id"]
                call["name"] := item.Has("name") ? item["name"] : ""
                call["arguments"] := item.Has("arguments") ? item["arguments"] : ""
            } else {
                call["id"] := parsed.Has("item_id") ? parsed["item_id"] : ""
                call["call_id"] := parsed.Has("call_id") ? parsed["call_id"] : call["id"]
                call["name"] := parsed.Has("name") ? parsed["name"] : ""
                call["arguments"] := parsed.Has("arguments") ? parsed["arguments"] : ""
            }
            call["namespace"] := parsed.Has("namespace") ? parsed["namespace"] : ""
            call["output_index"] := parsed.Has("output_index") ? parsed["output_index"] : 0
            return { type: "responses_tool_call", call: call }
        }

        if eventType = "response.completed" {
            if !parsed.Has("response") || !IsObject(parsed["response"])
                return { type: "error", message: "ChatGPT sent response.completed without a response payload." }
            response := parsed["response"]
            responseOutput := response.Has("output") && IsObject(response["output"]) ? response["output"] : []
            finalText := ChatGptResponsesStreamParser.FinalTextWithCitations(responseOutput)
            result := {
                type: "finish",
                completed: true,
                responseOutput: responseOutput,
                finalText: finalText,
                functionCalls: ChatGptResponsesStreamParser.ExtractFunctionCalls(responseOutput),
                rawResponse: response
            }
            if response.Has("model") && response["model"] != ""
                result.model := response["model"]
            if response.Has("usage") && IsObject(response["usage"])
                result.usage := ChatGptResponsesStreamParser.Usage(response["usage"])
            return result
        }

        if eventType = "response.failed" {
            if parsed.Has("response") && IsObject(parsed["response"]) {
                response := parsed["response"]
                if response.Has("error")
                    return ChatGptResponsesStreamParser._ErrorChunk(response["error"], "The ChatGPT Responses request failed.")
            }
            return { type: "error", message: "The ChatGPT Responses request failed." }
        }

        if eventType = "response.incomplete" {
            message := "The ChatGPT response ended before completion."
            if parsed.Has("response") && IsObject(parsed["response"]) {
                response := parsed["response"]
                if response.Has("incomplete_details") && IsObject(response["incomplete_details"]) {
                    details := response["incomplete_details"]
                    if details.Has("reason") && details["reason"] != ""
                        message .= " Reason: " details["reason"]
                }
            }
            return { type: "error", message: message, incomplete: true }
        }

        if eventType = "error" || eventType = "response.error" {
            if parsed.Has("error")
                return ChatGptResponsesStreamParser._ErrorChunk(parsed["error"], "The ChatGPT Responses stream failed.")
            return ChatGptResponsesStreamParser._ErrorChunk(parsed, "The ChatGPT Responses stream failed.")
        }

        return { type: "ignore" }
    }

    ; Item-done events are authoritative even when completion omits output.
    ; Replace matching IDs when completion repeats/enriches those items.
    static MergeOutput(streamed, completed) {
        merged := [], positions := Map()
        for collection in [streamed, completed] {
            if !(collection is Array)
                continue
            for item in collection {
                if !(item is Map)
                    continue
                id := item.Get("id", "")
                if id != "" && positions.Has(id)
                    merged[positions[id]] := item
                else {
                    merged.Push(item)
                    if id != ""
                        positions[id] := merged.Length
                }
            }
        }
        return merged
    }

    static CompleteOutput(chunk, streamedOutput) {
        chunk.responseOutput := ChatGptResponsesStreamParser.MergeOutput(streamedOutput, chunk.responseOutput)
        chunk.functionCalls := ChatGptResponsesStreamParser.ExtractFunctionCalls(chunk.responseOutput)
        chunk.finalText := ChatGptResponsesStreamParser.FinalTextWithCitations(chunk.responseOutput)
    }

    static PublicReasoningSummary(output) {
        parts := []
        for item in output {
            if !(item is Map) || item.Get("type", "") != "reasoning"
                continue
            for summary in item.Get("summary", [])
                if summary is Map && summary.Get("type", "") = "summary_text" && summary.Get("text", "") != ""
                    parts.Push(summary["text"])
        }
        text := ""
        for part in parts
            text .= (text != "" ? "`n" : "") part
        return text
    }

    static FinalTextWithCitations(output) {
        if !IsObject(output) || !(output is Array)
            return ""
        result := ""
        for item in output {
            if !IsObject(item) || !item.Has("type") || item["type"] != "message"
                continue
            if item.Has("role") && item["role"] != "assistant"
                continue
            if !item.Has("content") || !(item["content"] is Array)
                continue
            for part in item["content"] {
                if !IsObject(part) || !part.Has("type")
                    continue
                if part["type"] = "output_text" {
                    text := part.Has("text") ? String(part["text"]) : ""
                    annotations := part.Has("annotations") && part["annotations"] is Array
                        ? part["annotations"] : []
                    result .= ChatGptResponsesStreamParser._AddUrlCitations(text, annotations)
                } else if part["type"] = "refusal" && part.Has("refusal") {
                    result .= String(part["refusal"])
                }
            }
        }
        return result
    }

    static _AddUrlCitations(text, annotations) {
        inserts := []
        seen := Map()
        for annotation in annotations {
            if !IsObject(annotation) || !annotation.Has("type") || annotation["type"] != "url_citation"
                continue
            if !annotation.Has("url") || annotation["url"] = "" || !annotation.Has("end_index")
                continue
            endIndex := Integer(annotation["end_index"])
            if endIndex < 0 || endIndex > StrLen(text)
                continue
            url := String(annotation["url"])
            key := endIndex "|" url
            if seen.Has(key)
                continue
            seen[key] := true
            inserts.Push({ endIndex: endIndex, url: url })
        }

        ; Insert from right to left so earlier annotation offsets remain valid.
        Loop inserts.Length {
            maxPos := A_Index
            j := A_Index + 1
            while j <= inserts.Length {
                if inserts[j].endIndex > inserts[maxPos].endIndex
                    maxPos := j
                j++
            }
            if maxPos != A_Index {
                tmp := inserts[A_Index]
                inserts[A_Index] := inserts[maxPos]
                inserts[maxPos] := tmp
            }
        }

        for citation in inserts {
            safeUrl := StrReplace(citation.url, ">", "%3E")
            marker := " [source](<" safeUrl ">)"
            text := SubStr(text, 1, citation.endIndex) marker SubStr(text, citation.endIndex + 1)
        }
        return text
    }

    static ExtractFunctionCalls(output) {
        calls := []
        if !IsObject(output) || !(output is Array)
            return calls
        for item in output {
            if !IsObject(item) || !item.Has("type") || item["type"] != "function_call"
                continue
            calls.Push(Map(
                "id", item.Has("id") ? item["id"] : "",
                "call_id", item.Has("call_id") ? item["call_id"] : (item.Has("id") ? item["id"] : ""),
                "name", item.Has("name") ? item["name"] : "",
                "namespace", item.Has("namespace") ? item["namespace"] : "",
                "arguments", item.Has("arguments") ? item["arguments"] : ""
            ))
        }
        return calls
    }

    static Usage(usage) {
        cached := 0
        thinking := 0
        if usage.Has("input_tokens_details") && IsObject(usage["input_tokens_details"]) {
            details := usage["input_tokens_details"]
            if details.Has("cached_tokens") && details["cached_tokens"] != ""
                cached := Integer(details["cached_tokens"])
        }
        if usage.Has("output_tokens_details") && IsObject(usage["output_tokens_details"]) {
            details := usage["output_tokens_details"]
            if details.Has("reasoning_tokens") && details["reasoning_tokens"] != ""
                thinking := Integer(details["reasoning_tokens"])
        }
        return {
            promptTokens: usage.Has("input_tokens") ? Integer(usage["input_tokens"]) : 0,
            completionTokens: usage.Has("output_tokens") ? Integer(usage["output_tokens"]) : 0,
            totalTokens: usage.Has("total_tokens") ? Integer(usage["total_tokens"]) : 0,
            cachedTokens: cached,
            thinkingTokens: thinking
        }
    }

    static _ErrorChunk(errorValue, fallback) {
        message := fallback
        code := ""
        param := ""
        if IsObject(errorValue) {
            if errorValue.Has("message") && errorValue["message"] != ""
                message := String(errorValue["message"])
            if errorValue.Has("code") && errorValue["code"] != ""
                code := String(errorValue["code"])
            if errorValue.Has("param") && errorValue["param"] != ""
                param := String(errorValue["param"])
        } else if errorValue != "" {
            message := String(errorValue)
        }
        result := { type: "error", message: message }
        if code != ""
            result.code := code
        if param != ""
            result.param := param
        return result
    }
}
