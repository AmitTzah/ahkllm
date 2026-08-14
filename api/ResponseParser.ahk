; ----------------------------------------------------
; ResponseParser.ahk — LLM API response extraction
;
; Parses chat completions and FIM responses from all
; providers. SSE streaming chunks are parsed by SSEParser.ahk.
; Extracted from LLMRequestBuilder.ahk.
; ----------------------------------------------------

class ResponseParser {

    ; Extracts response content from a chat completions response.
    ; Handles both DeepSeek's prompt_cache_hit_tokens and OpenAI/Gemini's
    ; prompt_tokens_details.cached_tokens formats.
    static ParseChatResponse(var) {
        message := var.Get("choices")[1].Get("message")
        response := message.Has("content") ? message["content"] : ""
        model := var.Get("model")

        ; Tool calls (web_search) — returned so the stream/single-shot loop can
        ; execute them and re-request with the results.
        toolCalls := []
        if message.Has("tool_calls") {
            for tc in message["tool_calls"] {
                fn := tc.Has("function") ? tc["function"] : ""
                toolCalls.Push({
                    id: tc.Has("id") ? tc["id"] : "",
                    name: IsObject(fn) && fn.Has("name") ? fn["name"] : "",
                    arguments: IsObject(fn) && fn.Has("arguments") ? fn["arguments"] : ""
                })
            }
        }

        usage := { promptTokens: 0, completionTokens: 0, totalTokens: 0, cachedTokens: 0, thinkingTokens: 0 }
        if var.Has("usage") {
            usageNode := var["usage"]
            usage.promptTokens := usageNode.Has("prompt_tokens") ? usageNode["prompt_tokens"] : 0
            usage.completionTokens := usageNode.Has("completion_tokens") ? usageNode["completion_tokens"] : 0
            usage.totalTokens := usageNode.Has("total_tokens") ? usageNode["total_tokens"] : 0
            ; Google: completion_tokens excludes thinking tokens.
            ; Capture original before inflating, then inflate for cost/aggregate.
            if usage.totalTokens > usage.promptTokens + usage.completionTokens {
                delta := usage.totalTokens - usage.promptTokens - usage.completionTokens
                usage.thinkingTokens := delta   ; Gemini thinking = total - prompt - visible
                usage.completionTokens := usage.totalTokens - usage.promptTokens  ; inflate to include thinking
            }

            if usageNode.Has("prompt_cache_hit_tokens") {
                usage.cachedTokens := usageNode["prompt_cache_hit_tokens"]
            } else if usageNode.Has("prompt_tokens_details") && usageNode["prompt_tokens_details"].Has("cached_tokens") {
                usage.cachedTokens := usageNode["prompt_tokens_details"]["cached_tokens"]
            }

            ; Extract thinking/reasoning tokens (OpenAI/DeepSeek format)
            if usageNode.Has("completion_tokens_details") {
                details := usageNode["completion_tokens_details"]
                if IsObject(details) && details.Has("reasoning_tokens")
                    usage.thinkingTokens := details["reasoning_tokens"]
            }
        }

        return {
            response: response,
            model: model,
            usage: usage,
            toolCalls: toolCalls
        }
    }

    ; Extracts FIM response: choices[0].text
    static ParseFIMResponse(var) {
        response := var.Get("choices")[1].Get("text")
        model := var.Get("model")
        return {
            response: response,
            model: model
        }
    }
}
