; ----------------------------------------------------
; LLM Client (OpenAI-compatible API) — Multi-Provider
; ----------------------------------------------------

class LLMClient {

    ; ----------------------------------------------------
    ; Provider Resolution
    ; ----------------------------------------------------
    ; Given a model string like "deepseek/deepseek-v4-pro" or "deepseek-v4-pro",
    ; returns { providerKey, modelName, apiKey, endpoint, fimEndpoint }.
    ; Falls back to the old format (no provider prefix) resolving through providerMap.
    static ResolveProvider(modelId) {
        ; Check if model uses "provider/model" format
        slashPos := InStr(modelId, "/")
        if slashPos > 0 {
            providerKey := SubStr(modelId, 1, slashPos - 1)
            modelName := SubStr(modelId, slashPos + 1)

            ; Validate provider exists
            if providers.Has(providerKey) {
                p := providers[providerKey]
                apiKey := EnvGet(p.authEnvVar)
                return {
                    providerKey: providerKey,
                    modelName: modelName,
                    apiKey: apiKey,
                    endpoint: p.endpoint,
                    fimEndpoint: p.fimEndpoint
                }
            }
        }
    
        ; Legacy format: no provider prefix — infer from providerMap
        ; Default to DeepSeek if no match
        providerKey := "deepseek"
        for prefix, prov in providerMap {
            if InStr(modelId, prefix) {
                providerKey := prov
                break
            }
        }
    
        ; Check if it's a known provider with that prefix
        if providers.Has(providerKey) {
            p := providers[providerKey]
            apiKey := EnvGet(p.authEnvVar)
            return {
                providerKey: providerKey,
                modelName: modelId,
                apiKey: apiKey,
                endpoint: p.endpoint,
                fimEndpoint: p.fimEndpoint
            }
        }

        ; Fallback to deepseek
        p := providers["deepseek"]
        apiKey := EnvGet(p.authEnvVar)
        return {
            providerKey: "deepseek",
            modelName: modelId,
            apiKey: apiKey,
            endpoint: p.endpoint,
            fimEndpoint: p.fimEndpoint
        }
    }

    ; ----------------------------------------------------
    ; cURL Command Builders (now per-provider)
    ; ----------------------------------------------------

    ; Build the cURL command for a non-streaming request.
    ; providerInfo from ResolveProvider(), or uses the default APIEndpoint + APIKey.
    static BuildcURLCommand(providerInfo, requestFile, outputFile) {
        endpoint := providerInfo.endpoint
        return 'cURL.exe -s --max-time 120 --connect-timeout 30 -X POST '
            . endpoint ' '
            . '-H "Authorization: Bearer ' providerInfo.apiKey '" '
            . '-H "Content-Type: application/json" '
            . '-d @"' requestFile '" '
            . '-o "' outputFile '"'
    }

    ; Build the streaming cURL command.
    ; providerInfo from ResolveProvider().
    ; errorFile = path to capture stderr (e.g., cURLError_*.txt)
    static BuildStreamcURLCommand(providerInfo, requestFile, outputFile, errorFile) {
        endpoint := providerInfo.endpoint
        return 'cURL.exe -s --no-buffer --connect-timeout 30 -X POST '
            . endpoint ' '
            . '-H "Authorization: Bearer ' providerInfo.apiKey '" '
            . '-H "Content-Type: application/json" '
            . '-d @"' requestFile '" '
            . '-o "' outputFile '" '
            . '2>"' errorFile '"'
    }

    ; Build the FIM cURL command (DeepSeek-specific, uses FIM endpoint)
    static BuildFIMcURLCommand(providerInfo, requestFile, outputFile) {
        endpoint := providerInfo.fimEndpoint
        if !endpoint {
            endpoint := providerInfo.endpoint
        }
        return 'cURL.exe -s --max-time 120 --connect-timeout 30 -X POST '
            . endpoint ' '
            . '-H "Authorization: Bearer ' providerInfo.apiKey '" '
            . '-H "Content-Type: application/json" '
            . '-d @"' requestFile '" '
            . '-o "' outputFile '"'
    }

    ; ----------------------------------------------------
    ; Backward Compatible Instance Methods
    ; ----------------------------------------------------
    ; These use the old signature for existing code that hasn't been updated yet.
    ; New code should use the static methods above.

    __New(APIKey) {
        this.APIKey := APIKey
    }

    buildcURLCommand(chatHistoryJSONRequestFile, cURLOutputFile) {
        ; Use global APIEndpoint and this.APIKey
        return 'cURL.exe -s --max-time 120 --connect-timeout 30 -X POST '
            . APIEndpoint ' '
            . '-H "Authorization: Bearer ' this.APIKey '" '
            . '-H "Content-Type: application/json" '
            . '-d @"' chatHistoryJSONRequestFile '" '
            . '-o "' cURLOutputFile '"'
    }

    buildStreamcURLCommand(chatHistoryJSONRequestFile, cURLOutputFile, errorFile) {
        return 'cURL.exe -s --no-buffer --connect-timeout 30 -X POST '
            . APIEndpoint ' '
            . '-H "Authorization: Bearer ' this.APIKey '" '
            . '-H "Content-Type: application/json" '
            . '-d @"' chatHistoryJSONRequestFile '" '
            . '-o "' cURLOutputFile '" '
            . '2>"' errorFile '"'
    }

    buildFIMcURLCommand(chatHistoryJSONRequestFile, cURLOutputFile) {
        return 'cURL.exe -s --max-time 120 --connect-timeout 30 -X POST '
            . FIMEndpoint ' '
            . '-H "Authorization: Bearer ' this.APIKey '" '
            . '-H "Content-Type: application/json" '
            . '-d @"' chatHistoryJSONRequestFile '" '
            . '-o "' cURLOutputFile '"'
    }

    ; Fix jsongo boolean serialization — AHK true/false serialize as 1/0, JSON needs true/false
    static _FixStreamBoolean(jsonStr) {
        jsonStr := StrReplace(jsonStr, '"stream":1', '"stream":true')
        jsonStr := StrReplace(jsonStr, '"stream":0', '"stream":false')
        jsonStr := StrReplace(jsonStr, '"include_usage":1', '"include_usage":true')
        jsonStr := StrReplace(jsonStr, '"include_thoughts":1', '"include_thoughts":true')
        return jsonStr
    }

    ; ----------------------------------------------------
    ; JSON Request Builders
    ; ----------------------------------------------------

    ; Builds the standard chat completions JSON request.
    ; Supports: provider/model ID, system prompt, user prompt, images, thinking, etc.
    ; images: optional array of { data (base64), mimeType } objects
    createJSONRequest(APIModel, systemPrompt, userPrompt, temperature := "", maxTokens := "", stop := "", stream := false, reasoningEffort := "", images*) {
        ; Resolve model name (strip provider prefix if present)
        modelName := APIModel
        slashPos := InStr(APIModel, "/")
        if slashPos > 0 {
            modelName := SubStr(APIModel, slashPos + 1)
        }

        requestObj := {}
        requestObj.model := modelName
        requestObj.messages := []

        if systemPrompt != "" {
            requestObj.messages.Push({ role: "system", content: systemPrompt })
        }

        ; Build user message content (text + optional images)
        ; images is variadic — may contain empty strings from callers that
        ; don't use the feature. Filter those out.
        if images.Length > 0 {
            userContent := []
            ; Include images
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
            requestObj.stop := stop
        if stream {
            requestObj.stream := true
        }

        ; Handle thinking/reasoning — all OpenAI-compatible providers use reasoning_effort.
        ; Per-provider disambiguation (DeepSeek thinking:{type:"disabled"}) is handled
        ; in BuildAndWriteRequestFiles for the chat flow; this method is for non-chat prompts.
        if reasoningEffort != "" {
            requestObj.reasoning_effort := reasoningEffort
        }

        return LLMClient._FixStreamBoolean(jsongo.Stringify(requestObj))
    }

    ; ----------------------------------------------------
    ; Response Extraction
    ; ----------------------------------------------------

    ; Extracts response content from a chat completions response.
    ; Handles both DeepSeek's prompt_cache_hit_tokens and OpenAI/Gemini's
    ; prompt_tokens_details.cached_tokens formats.
    extractJSONResponse(var) {
        response := var.Get("choices")[1].Get("message").Get("content")
        model := var.Get("model")

        usage := { promptTokens: 0, completionTokens: 0, totalTokens: 0, cachedTokens: 0 }
        if var.Has("usage") {
            usageNode := var["usage"]

            ; Prompt tokens — standard across all providers
            usage.promptTokens := usageNode.Has("prompt_tokens") ? usageNode["prompt_tokens"] : 0
            usage.completionTokens := usageNode.Has("completion_tokens") ? usageNode["completion_tokens"] : 0
            usage.totalTokens := usageNode.Has("total_tokens") ? usageNode["total_tokens"] : 0

            ; Cached tokens — different field per provider
            if usageNode.Has("prompt_cache_hit_tokens") {
                ; DeepSeek: top-level field
                usage.cachedTokens := usageNode["prompt_cache_hit_tokens"]
            } else if usageNode.Has("prompt_tokens_details") && usageNode["prompt_tokens_details"].Has("cached_tokens") {
                ; OpenAI / Gemini: nested in prompt_tokens_details
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
    extractStreamChunk(var) {
        if !var.Has("choices") || var["choices"].Length = 0 {
            return { type: "done", content: "", model: "", usage: {} }
        }

        choice := var["choices"][1]
        delta := choice.Has("delta") ? choice["delta"] : {}

        ; Check finish reason
        if choice.Has("finish_reason") && choice["finish_reason"] != "" && choice["finish_reason"] != "null" {
            result := { type: "finish", content: "", model: "", usage: {} }
            if var.Has("model") {
                result.model := var["model"]
            }
            ; Capture usage from the final chunk
            if var.Has("usage") {
                result.usage := var["usage"]
            }
            return result
        }

        ; Extract reasoning content if present (DeepSeek streaming)
        if delta.Has("reasoning_content") && delta["reasoning_content"] {
            return { type: "reasoning", content: delta["reasoning_content"], model: "", usage: {} }
        }

        ; Standard content delta
        content := delta.Has("content") ? delta["content"] : ""
        return { type: "content", content: content, model: "", usage: {} }
    }

    ; Extracts error response
    extractErrorResponse(var) {
        error := var.Get("error").Get("message")
        code := var.Get("error").Get("code")
        return {
            error: error,
            code: code,
        }
    }

    ; ----------------------------------------------------
    ; Chat History Management
    ; ----------------------------------------------------

    appendToChatHistory(role, message, &chatHistoryJSONRequest, chatHistoryJSONRequestFile) {
        obj := jsongo.Parse(chatHistoryJSONRequest)
        obj["messages"].Push({
            role: role,
            content: message
        })
        chatHistoryJSONRequest := LLMClient._FixStreamBoolean(jsongo.Stringify(obj))
        FileOpen(chatHistoryJSONRequestFile, "w", "UTF-8-RAW").Write(chatHistoryJSONRequest)
    }

    ; ----------------------------------------------------
    ; FIM-specific methods (Fill In the Middle)
    ; ----------------------------------------------------

    ; Builds the FIM JSON request: {model, prompt, suffix?, max_tokens}
    createFIMRequest(APIModel, prefix, suffix, temperature := "", maxTokens := "", stop := "") {
        ; Resolve model name
        modelName := APIModel
        slashPos := InStr(APIModel, "/")
        if slashPos > 0 {
            modelName := SubStr(APIModel, slashPos + 1)
        }

        maxTokens := (maxTokens != "") ? maxTokens : FIMMaxTokens
        requestObj := { model: modelName, prompt: prefix, max_tokens: maxTokens }
        if (suffix != "") {
            requestObj.suffix := suffix
        }
        if temperature != ""
            requestObj.temperature := temperature
        if stop != "" && stop.Length > 0
            requestObj.stop := stop
        return jsongo.Stringify(requestObj)
    }

    ; Extracts FIM response: choices[0].text
    extractFIMResponse(var) {
        response := var.Get("choices")[1].Get("text")
        model := var.Get("model")
        return {
            response: response,
            model: model
        }
    }
}
