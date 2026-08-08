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
        ; reasoning value (the level was previously dropped). Command type
        ; "disabled" → "none" so ApplyThinking takes its disabled branch
        ; (a raw "disabled" string would wrongly hit the enabled branch).
        ; Empty type = "Model Default" — send NO thinking config.
        effectiveReasoning := reasoningEffort
        if (reasoningEffort = "enabled" && reasoningLevel != "")
            effectiveReasoning := reasoningLevel
        else if (reasoningEffort = "disabled")
            effectiveReasoning := "none"
        global models
        if (effectiveReasoning != "" && models.Has(APIModel))
            OpenAIChatCompletions.ApplyThinking(&requestObj, models[APIModel], effectiveReasoning, APIModel)
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
    ; (bug #100).
    static _FixStreamBoolean(jsonStr) {
        replacements := Map(
            '"stream":1', '"stream":true',
            '"stream":0', '"stream":false',
            '"include_usage":1', '"include_usage":true',
            '"include_thoughts":1', '"include_thoughts":true'
        )
        result := ""
        i := 1
        len := StrLen(jsonStr)
        inString := false
        while i <= len {
            ch := SubStr(jsonStr, i, 1)
            if inString {
                result .= ch
                if ch = "\" {
                    ; Escaped character - copy it and the escaped char as-is.
                    if i < len {
                        result .= SubStr(jsonStr, i + 1, 1)
                        i += 2
                        continue
                    }
                } else if ch = '"' {
                    inString := false
                }
                i += 1
                continue
            }
            if ch = '"' {
                ; Possible JSON key. Only rewrite when it is one of the target
                ; keys followed by a whole 1/0 value (the next char must be a
                ; JSON delimiter, so `"stream":10` is never mangled).
                matched := false
                for k, v in replacements {
                    if SubStr(jsonStr, i, StrLen(k)) = k {
                        after := SubStr(jsonStr, i + StrLen(k), 1)
                        if after = "" || after = "," || after = "}" || after = "]" || after = " " || after = "`n" || after = "`r" || after = "`t" {
                            result .= v
                            i += StrLen(k)
                            matched := true
                            break
                        }
                    }
                }
                if matched
                    continue
                ; Not a target key - consume the whole string value (escaped
                ; quotes included) so its contents are never rewritten.
                inString := true
                result .= ch
                i += 1
                continue
            }
            result .= ch
            i += 1
        }
        return result
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
