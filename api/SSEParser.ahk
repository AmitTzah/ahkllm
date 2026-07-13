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
            return SSEParser._handleUsageOnlyChunk(parsed)
        }

        delta := choices[1].Has("delta") ? choices[1]["delta"] : choices[1]
        result := SSEParser._parseDeltaContent(delta)

        ; Check for finish reason (stream end) — may coexist with content
        finish := choices[1].Has("finish_reason") ? choices[1]["finish_reason"] : ""
        if finish != "" && finish != "null" {
            if !result.HasOwnProp("type")
                result.type := "finish"
            result.reason := finish
            if parsed.Has("model") && parsed["model"] != ""
                result.model := parsed["model"]
            if parsed.Has("usage") && IsObject(parsed["usage"])
                result.usage := SSEParser._buildUsageObject(parsed["usage"])
            return result
        }

        if result.HasOwnProp("type")
            return result
        return { type: "ignore" }
    }

    ; Handle the usage-only chunk (stream_options: include_usage sends usage
    ; in a separate chunk with empty choices after finish_reason).
    static _handleUsageOnlyChunk(parsed) {
        if parsed.Has("usage") && IsObject(parsed["usage"]) {
            result := { type: "finish" }
            if parsed.Has("model") && parsed["model"] != ""
                result.model := parsed["model"]
            result.usage := SSEParser._buildUsageObject(parsed["usage"])
            return result
        }
        return { type: "ignore" }
    }

    ; Parse delta content — detect reasoning vs visible content.
    ; Returns {type?, content?} — may be empty if no recognized content.
    static _parseDeltaContent(delta) {
        result := {}

        ; reasoning_content (DeepSeek, some OpenAI models)
        if delta.Has("reasoning_content") && delta["reasoning_content"] != "" {
            result.type := "reasoning"
            result.content := delta["reasoning_content"]
            return result
        }

        ; reasoning field (alternative naming)
        if delta.Has("reasoning") && delta["reasoning"] != "" {
            result.type := "reasoning"
            result.content := delta["reasoning"]
            return result
        }

        ; content — may include Gemini <thought> tags
        if delta.Has("content") && delta["content"] != "" {
            content := delta["content"]

            ; Gemini embeds thinking as <thought>...</thought> with extra_content flag
            isGeminiThought := delta.Has("extra_content")
                && delta["extra_content"].Has("google")
                && delta["extra_content"]["google"].Has("thought")
                && delta["extra_content"]["google"]["thought"]

            if isGeminiThought {
                content := StrReplace(content, "<thought>", "")
                content := StrReplace(content, "</thought>", "")
                result.type := "reasoning"
                result.content := content
                return result
            }

            ; Strip lingering </thought> closing tag
            content := StrReplace(content, "</thought>", "")

            if content != "" {
                result.type := "content"
                result.content := content
            }
        }

        return result
    }

    ; Build a standardized usage object from a jsongo-parsed usage Map.
    static _buildUsageObject(usageObj) {
        cachedTokens := 0
        if usageObj.Has("prompt_cache_hit_tokens") {
            cachedTokens := usageObj["prompt_cache_hit_tokens"]
        } else if usageObj.Has("prompt_tokens_details") {
            details := usageObj["prompt_tokens_details"]
            if IsObject(details) && details.Has("cached_tokens")
                cachedTokens := details["cached_tokens"]
        }
        return {
            promptTokens:     usageObj.Has("prompt_tokens") ? usageObj["prompt_tokens"] : 0,
            completionTokens: _computeCompletion(usageObj),
            totalTokens:      usageObj.Has("total_tokens") ? usageObj["total_tokens"] : 0,
            cachedTokens:     cachedTokens,
            thinkingTokens:   _extractThinkingTokens(usageObj)
        }
    }
}

; Google: completion_tokens excludes thinking tokens.
; Use total - prompt for the real output count (visible + thinking).
_computeCompletion(usageObj) {
    prompt := usageObj.Has("prompt_tokens") ? usageObj["prompt_tokens"] : 0
    completion := usageObj.Has("completion_tokens") ? usageObj["completion_tokens"] : 0
    total := usageObj.Has("total_tokens") ? usageObj["total_tokens"] : 0
    if total > prompt + completion
        return total - prompt
    return completion
}

; Extract reasoning/thinking tokens from the usage object.
; Checks completion_tokens_details.reasoning_tokens (OpenAI/DeepSeek format).
; Falls back to total - prompt - completion for Gemini (doesn't report thinking separately).
_extractThinkingTokens(usageObj) {
    if usageObj.Has("completion_tokens_details") {
        details := usageObj["completion_tokens_details"]
        if IsObject(details) && details.Has("reasoning_tokens")
            return details["reasoning_tokens"]
    }
    ; Gemini fallback: thinking = total_tokens - prompt_tokens - completion_tokens
    prompt := usageObj.Has("prompt_tokens") ? usageObj["prompt_tokens"] : 0
    completion := usageObj.Has("completion_tokens") ? usageObj["completion_tokens"] : 0
    total := usageObj.Has("total_tokens") ? usageObj["total_tokens"] : 0
    if total > prompt + completion
        return total - prompt - completion
    return 0
}
