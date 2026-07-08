; ----------------------------------------------------
; SSEParser — Server-Sent Events streaming parser
; Parses SSE data: lines from the stream output file
; Returns an object {type, content, model?} where type is
; "content", "reasoning", "finish", or "done"
;
; NOTE: jsongo.Parse() returns Maps. Use .Has() not .HasOwnProp()
; for jsongo-parsed objects. Internal result object uses .HasOwnProp().
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
        if !choices || choices.Length = 0 {
            ; OpenAI stream_options: include_usage sends the usage object
            ; in a separate chunk with empty choices after the finish_reason
            ; chunk. Extract it here so it isn't discarded.
            if parsed.Has("usage") && IsObject(parsed["usage"]) {
                usageObj := parsed["usage"]
                result := { type: "finish" }
                if parsed.Has("model") && parsed["model"] != ""
                    result.model := parsed["model"]
                result.usage := {
                    promptTokens:     usageObj.Has("prompt_tokens") ? usageObj["prompt_tokens"] : 0,
                    completionTokens: usageObj.Has("completion_tokens") ? usageObj["completion_tokens"] : 0,
                    totalTokens:      usageObj.Has("total_tokens") ? usageObj["total_tokens"] : 0,
                    cachedTokens:     usageObj.Has("prompt_cache_hit_tokens") ? usageObj["prompt_cache_hit_tokens"] : 0
                }
                return result
            }
            return { type: "ignore" }
        }

        delta := choices[1].Has("delta") ? choices[1]["delta"] : choices[1]

        result := {}

        ; Check for reasoning_content field (DeepSeek, some OpenAI models)
        if delta.Has("reasoning_content") && delta["reasoning_content"] != "" {
            result.type := "reasoning"
            result.content := delta["reasoning_content"]
            return result
        }

        ; Check for reasoning field (alternative naming)
        if delta.Has("reasoning") && delta["reasoning"] != "" {
            result.type := "reasoning"
            result.content := delta["reasoning"]
            return result
        }

        ; Check for content (includes Gemini's <thought> tag handling)
        if delta.Has("content") && delta["content"] != "" {
            content := delta["content"]

            ; Gemini embeds thinking as <thought>...</thought> tags in the content stream,
            ; flagged by extra_content.google.thought: true
            ; jsongo returns Maps — use .Has() not .HasOwnProp()
            isGeminiThought := delta.Has("extra_content")
                && delta["extra_content"].Has("google")
                && delta["extra_content"]["google"].Has("thought")
                && delta["extra_content"]["google"]["thought"]

            if isGeminiThought {
                ; Strip <thought> and </thought> XML wrappers
                content := StrReplace(content, "<thought>", "")
                content := StrReplace(content, "</thought>", "")
                result.type := "reasoning"
                result.content := content
                return result
            }

            ; Handle </thought> closing tag before real content (Gemini final chunk)
            if InStr(content, "</thought>") {
                content := StrReplace(content, "</thought>", "")
            }

            if content != "" {
                result.type := "content"
                result.content := content
                ; Don't return yet — finish_reason + usage may also be in this chunk
            }
        }

        ; Check for finish reason (stream end)
        finish := choices[1].Has("finish_reason") ? choices[1]["finish_reason"] : ""
        if finish != "" && finish != "null" {
            ; Preserve content type if already set, otherwise mark as finish
            if !result.HasOwnProp("type") {
                result.type := "finish"
            }
            result.reason := finish

            ; Extract model name from the response
            if parsed.Has("model") && parsed["model"] != "" {
                result.model := parsed["model"]
            }

            ; Extract usage data from the stream response.
            ; Guard: jsongo.Parse converts JSON null to "" (empty string),
            ; and bracket access on "" throws "__Item" error.
            ; Also guard: Map access on missing key throws "Item has no value".
            if parsed.Has("usage") && IsObject(parsed["usage"]) {
                usageObj := parsed["usage"]
                result.usage := {
                    promptTokens:     usageObj.Has("prompt_tokens") ? usageObj["prompt_tokens"] : 0,
                    completionTokens: usageObj.Has("completion_tokens") ? usageObj["completion_tokens"] : 0,
                    totalTokens:      usageObj.Has("total_tokens") ? usageObj["total_tokens"] : 0,
                    cachedTokens:     usageObj.Has("prompt_cache_hit_tokens") ? usageObj["prompt_cache_hit_tokens"] : 0
                }
            }
            return result
        }

        ; Return content if found without finish_reason
        if result.HasOwnProp("type") {
            return result
        }

        return { type: "ignore" }
    }
}
