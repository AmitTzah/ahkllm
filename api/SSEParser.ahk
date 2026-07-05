; ----------------------------------------------------
; SSEParser — Server-Sent Events streaming parser
; Parses SSE data: lines from the stream output file
; Returns an object {type, content, model?} where type is
; "content", "reasoning", "finish", or "done"
; ----------------------------------------------------

class SSEParser {
    ; Parses a single "data: " line from the SSE stream.
    ; Returns an object with {type, content, model?, usage?}
    static ParseLine(line) {
        if !InStr(line, "data: ")
            return { type: "ignore" }

        data := SubStr(line, InStr(line, "data: ") + 6)

        if data = "[DONE]"
            return { type: "done" }

        try {
            parsed := jsongo.Parse(data)
        } catch {
            return { type: "ignore" }
        }

        choices := parsed["choices"]
        if !choices || choices.Length = 0
            return { type: "ignore" }

        delta := choices[1].Has("delta") ? choices[1]["delta"] : choices[1]

        result := {}

        ; Check for reasoning content (DeepSeek thinking blocks)
        if delta.Has("reasoning_content") && delta["reasoning_content"] != "" {
            result.type := "reasoning"
            result.content := delta["reasoning_content"]
            return result
        }

        ; Check for regular content
        if delta.Has("content") && delta["content"] != "" {
            result.type := "content"
            result.content := delta["content"]
            return result
        }

        ; Check for finish reason (stream end)
        finish := choices[1].Has("finish_reason") ? choices[1]["finish_reason"] : ""
        if finish != "" && finish != "null" {
            result.type := "finish"
            result.reason := finish

            ; Extract model name from the response
            if parsed.Has("model") && parsed["model"] != "" {
                result.model := parsed["model"]
            }

            ; Extract usage data from the stream response
            if parsed.Has("usage") {
                result.usage := {
                    promptTokens:     parsed["usage"]["prompt_tokens"],
                    completionTokens: parsed["usage"]["completion_tokens"],
                    totalTokens:      parsed["usage"]["total_tokens"],
                    cachedTokens:     parsed["usage"].Has("prompt_cache_hit_tokens") ? parsed["usage"]["prompt_cache_hit_tokens"] : 0
                }
            }
            return result
        }

        return { type: "ignore" }
    }
}
