; ----------------------------------------------------
; ResponseParser.ahk — LLM API response extraction
;
; Parses chat completions, streaming SSE, FIM, and error
; responses from all providers. Extracted from LLMRequestBuilder.ahk.
; ----------------------------------------------------

class ResponseParser {

    ; Extracts response content from a chat completions response.
    ; Handles both DeepSeek's prompt_cache_hit_tokens and OpenAI/Gemini's
    ; prompt_tokens_details.cached_tokens formats.
    static ParseChatResponse(var) {
        response := var.Get("choices")[1].Get("message").Get("content")
        model := var.Get("model")

        usage := { promptTokens: 0, completionTokens: 0, totalTokens: 0, cachedTokens: 0 }
        if var.Has("usage") {
            usageNode := var["usage"]
            usage.promptTokens := usageNode.Has("prompt_tokens") ? usageNode["prompt_tokens"] : 0
            usage.completionTokens := usageNode.Has("completion_tokens") ? usageNode["completion_tokens"] : 0
            usage.totalTokens := usageNode.Has("total_tokens") ? usageNode["total_tokens"] : 0
            ; Google: completion_tokens excludes thinking tokens. Use total - prompt for real output.
            if usage.totalTokens > usage.promptTokens + usage.completionTokens
                usage.completionTokens := usage.totalTokens - usage.promptTokens

            if usageNode.Has("prompt_cache_hit_tokens") {
                usage.cachedTokens := usageNode["prompt_cache_hit_tokens"]
            } else if usageNode.Has("prompt_tokens_details") && usageNode["prompt_tokens_details"].Has("cached_tokens") {
                usage.cachedTokens := usageNode["prompt_tokens_details"]["cached_tokens"]
            }
        }

        return {
            response: response,
            model: model,
            usage: usage
        }
    }

    ; Extracts streaming chunk content from an SSE chunk
    static ParseStreamChunk(var) {
        if !var.Has("choices") || var["choices"].Length = 0 {
            return { type: "done", content: "", model: "", usage: {} }
        }

        choice := var["choices"][1]
        delta := choice.Has("delta") ? choice["delta"] : {}

        if choice.Has("finish_reason") && choice["finish_reason"] != "" && choice["finish_reason"] != "null" {
            result := { type: "finish", content: "", model: "", usage: {} }
            if var.Has("model")
                result.model := var["model"]
            if var.Has("usage")
                result.usage := var["usage"]
            return result
        }

        if delta.Has("reasoning_content") && delta["reasoning_content"] {
            return { type: "reasoning", content: delta["reasoning_content"], model: "", usage: {} }
        }

        content := delta.Has("content") ? delta["content"] : ""
        return { type: "content", content: content, model: "", usage: {} }
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
