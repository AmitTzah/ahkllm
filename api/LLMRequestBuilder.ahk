; ----------------------------------------------------
; LLMRequestBuilder.ahk — LLM API request construction
;
; Builds JSON request objects (chat, FIM), manages
; chat history, and handles per-provider thinking config.
;
; Specialized concerns extracted to their own files:
;   ProviderResolver.ahk — provider/endpoint resolution
;   CurlBuilder.ahk      — cURL command construction
;   ResponseParser.ahk   — response parsing
; ----------------------------------------------------

#Include ..\shared\ModelResolver.ahk

class LLMRequestBuilder {

    __New(APIKey) {
        this.APIKey := APIKey
    }

    ; ----------------------------------------------------
    ; Request Builders
    ; ----------------------------------------------------

    ; Builds the standard chat completions JSON request.
    ; Supports: provider/model ID, system prompt, user prompt, images, thinking.
    ; images: optional array of { data (base64), mimeType } objects
    static createJSONRequest(APIModel, systemMessage, userPrompt, temperature := "", maxTokens := "", stop := "", stream := false, reasoningEffort := "", reasoningLevel := "", images*) {
        providerInfo := ProviderResolver.Resolve(APIModel)
        modelName := providerInfo.modelName
        providerKey := providerInfo.providerKey

        requestObj := {}
        requestObj.model := modelName
        requestObj.messages := []

        if systemMessage != "" {
            requestObj.messages.Push({ role: "system", content: systemMessage })
        }

        if images.Length > 0 {
            userContent := []
            for i, img in images {
                if IsObject(img) && img.HasOwnProp("data") && img.HasOwnProp("mimeType") {
                    userContent.Push({
                        type: "image_url",
                        image_url: { url: "data:" img.mimeType ";base64," img.data }
                    })
                }
            }
            userContent.Push({ type: "text", text: userPrompt })
            requestObj.messages.Push({ role: "user", content: userContent })
        } else {
            requestObj.messages.Push({ role: "user", content: userPrompt })
        }

        if temperature != ""
            requestObj.temperature := temperature
        if maxTokens != ""
            requestObj.max_tokens := maxTokens
        if stop != "" && stop.Length > 0
            requestObj.stop := LLMRequestBuilder._normalizeStop(stop)
        if stream {
            requestObj.stream := true
        }

        ; Apply thinking parameters via metadata-driven handler.
        ; Command type "enabled" + explicit level → use the level as the
        ; reasoning value. Command type
        ; "disabled" → "none" so ApplyThinking takes its disabled branch
        ; (a raw "disabled" string would wrongly hit the enabled branch).
        ; Empty type = "Model Default" — send NO thinking config.
        effectiveReasoning := reasoningEffort
        if (reasoningEffort = "enabled" && reasoningLevel != "")
            effectiveReasoning := reasoningLevel
        else if (reasoningEffort = "disabled")
            effectiveReasoning := "none"
        global models
        ; Resolve model metadata through ModelResolver.Lookup so
        ; SHORT ids (no provider prefix, e.g. the default commands' models) get
        ; the same thinking config as full "provider/model" ids; a direct
        ; models.Has(APIModel) check would only match full-id keys and could
        ; silently drop thinking for short ids.
        modelMeta := ModelResolver.Lookup(models, APIModel)
        if (effectiveReasoning != "" && modelMeta)
            OpenAIChatCompletions.ApplyThinking(&requestObj, modelMeta, effectiveReasoning, APIModel)
        return LLMRequestBuilder._FixStreamBoolean(jsongo.Stringify(requestObj))
    }

    ; Builds the FIM JSON request: {model, prompt, suffix?, max_tokens}
    createFIMRequest(APIModel, prefix, suffix, temperature := "", maxTokens := "", stop := "") {
        modelName := ModelParser.StripProvider(APIModel)

        maxTokens := (maxTokens != "") ? maxTokens : 4000    ; default FIM max tokens
        requestObj := { model: modelName, prompt: prefix, max_tokens: maxTokens }
        if (suffix != "") {
            requestObj.suffix := suffix
        }
        if temperature != ""
            requestObj.temperature := temperature
        if stop != "" && stop.Length > 0
            requestObj.stop := LLMRequestBuilder._normalizeStop(stop)
        return jsongo.Stringify(requestObj)
    }

    ; Translates user-friendly "\n" to actual newlines in stop sequences.
    static _normalizeStop(stop) {
        result := []
        for item in stop {
            result.Push(StrReplace(item, "\n", "`n"))
        }
        return result
    }

    ; ----------------------------------------------------
    ; JSON Serialization Fix
    ; ----------------------------------------------------
    ; jsongo serializes AHK booleans (true=1/false=0) as JSON 1/0, but some
    ; APIs require real JSON booleans for stream/include_usage/include_thoughts.
    ; The rewrite is QUOTE-AWARE: it walks the JSON and only rewrites these
    ; key:value tokens outside string literals, so user content that merely
    ; contains `"stream":1` (escaped inside a string) is never corrupted
    ; without altering escaped string content.
    static _FixStreamBoolean(jsonStr) {
        fields := Map("stream", true, "include_usage", false, "include_thoughts", false,
            "store", true, "strict", true, "additionalProperties", true, "parallel_tool_calls", true)
        output := "", copiedThrough := 0, position := 1
        ; Jump between quotes in native code. Never run a recursive regex over
        ; image data: jsongo escapes base64 slashes, exhausting PCRE's limits.
        while opening := InStr(jsonStr, '"', true, position) {
            closing := LLMRequestBuilder._JsonStringEnd(jsonStr, opening)
            if !closing
                break
            if closing - opening <= 21 {
                key := SubStr(jsonStr, opening + 1, closing - opening - 1)
                ; Anchored to this string's end, so regex only reads a field's
                ; colon, numeric boolean and delimiter, never its string value.
                if fields.Has(key) && RegExMatch(jsonStr, '\G\s*:\s*\K[01](?=\s*(?:[,}\]]|$))', &value, closing + 1)
                    && (value[0] = "1" || fields[key]) {
                    output .= SubStr(jsonStr, copiedThrough + 1, value.Pos - copiedThrough - 1)
                        . (value[0] = "1" ? "true" : "false")
                    copiedThrough := value.Pos
                }
            }
            position := closing + 1
        }
        return output SubStr(jsonStr, copiedThrough + 1)
    }

    static _JsonStringEnd(jsonStr, opening) {
        closing := opening
        while closing := InStr(jsonStr, '"', true, closing + 1) {
            backslashes := 0, beforeQuote := closing - 1
            while beforeQuote > opening && SubStr(jsonStr, beforeQuote, 1) = "\" {
                backslashes++
                beforeQuote--
            }
            if Mod(backslashes, 2) = 0
                return closing
        }
        return 0
    }

    ; ----------------------------------------------------
    ; Instance Helpers (needed by llmClient in Main/ChatWindow)
    ; ----------------------------------------------------

    appendToChatHistory(role, message, &chatHistoryJSONRequest, chatHistoryJSONRequestFile) {
        obj := jsongo.Parse(chatHistoryJSONRequest)
        obj["messages"].Push({ role: role, content: message })
        chatHistoryJSONRequest := LLMRequestBuilder._FixStreamBoolean(jsongo.Stringify(obj))
        FileOpen(chatHistoryJSONRequestFile, "w", "UTF-8-RAW").Write(chatHistoryJSONRequest)
    }
}
