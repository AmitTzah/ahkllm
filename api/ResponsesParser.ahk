; ======================================================
; ResponsesParser.ahk — DeepSeek/OpenAI Responses API (non-streaming) parser
;
; Used by DeepSeekSearch.ahk to extract the answer text from a single
; POST /responses call that carries the server-side web_search tool.
; Usage is mapped into the app's standard {prompt, completion, cached,
; thinking, total} shape so cost/usage accounting needs no special cases.
; ======================================================

class ResponsesParser {

    ; Parse a non-streaming Responses JSON object (jsongo-parsed Map).
    static Parse(var) {
        text := ""
        if var.Has("output") {
            for item in var["output"] {
                if !IsObject(item) || !item.Has("type") || item["type"] != "message"
                    continue
                if !item.Has("content")
                    continue
                for part in item["content"] {
                    if IsObject(part) && part.Has("type") && part["type"] = "output_text" && part.Has("text")
                        text .= part["text"]
                }
            }
        }

        model := var.Has("model") ? var["model"] : ""
        usage := { promptTokens: 0, completionTokens: 0, totalTokens: 0, cachedTokens: 0, thinkingTokens: 0 }
        if var.Has("usage") && IsObject(var["usage"]) {
            u := var["usage"]
            usage.promptTokens := u.Has("input_tokens") ? u["input_tokens"] : 0
            usage.completionTokens := u.Has("output_tokens") ? u["output_tokens"] : 0
            usage.totalTokens := u.Has("total_tokens") ? u["total_tokens"] : 0
            if u.Has("input_tokens_details") && IsObject(u["input_tokens_details"]) && u["input_tokens_details"].Has("cached_tokens")
                usage.cachedTokens := u["input_tokens_details"]["cached_tokens"]
            if u.Has("output_tokens_details") && IsObject(u["output_tokens_details"]) && u["output_tokens_details"].Has("reasoning_tokens")
                usage.thinkingTokens := u["output_tokens_details"]["reasoning_tokens"]
        }

        return { response: text, model: model, usage: usage }
    }
}
