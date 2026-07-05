; ----------------------------------------------------
; LLM Client (OpenAI-compatible API)
; ----------------------------------------------------

class LLMClient {
    ; Chat completions cURL template with timeout (2 min max, 30 sec connect)
    static cURLCommand :=
        'cURL.exe -s --max-time 120 --connect-timeout 30 -X POST ' APIEndpoint ' '
        . '-H "Authorization: Bearer {1}" '
        . '-H "Content-Type: application/json" '
        . '-d @"{2}" '
        . '-o "{3}"'

    ; Streaming cURL template (no --max-time, uses --no-buffer for real-time output)
    ; {4} = stderr capture file (e.g., cURLError_*.txt)
    static StreamcURLCommand :=
        'cURL.exe -s --no-buffer --connect-timeout 30 -X POST ' APIEndpoint ' '
        . '-H "Authorization: Bearer {1}" '
        . '-H "Content-Type: application/json" '
        . '-d @"{2}" '
        . '-o "{3}" '
        . '2>"{4}"'

    ; FIM (Fill In the Middle) cURL template — uses the DeepSeek beta endpoint
    static FIMcURLCommand :=
        'cURL.exe -s --max-time 120 --connect-timeout 30 -X POST ' FIMEndpoint ' '
        . '-H "Authorization: Bearer {1}" '
        . '-H "Content-Type: application/json" '
        . '-d @"{2}" '
        . '-o "{3}"'

    ; Fix jsongo boolean serialization — converts "stream":1 to "stream":true
    static _FixStreamBoolean(jsonStr) {
        jsonStr := StrReplace(jsonStr, '"stream":1', '"stream":true')
        jsonStr := StrReplace(jsonStr, '"stream":0', '"stream":false')
        return jsonStr
    }

    __New(APIKey) {
        this.APIKey := APIKey
    }

    createJSONRequest(APIModel, systemPrompt, userPrompt, temperature := "", maxTokens := "", stop := "", stream := false, thinking := "") {
        requestObj := {}
        requestObj.model := APIModel
        requestObj.messages := [{ role: "user", content: userPrompt }]
        if systemPrompt != "" {
            requestObj.messages.InsertAt(1, { role: "system", content: systemPrompt })
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
        if thinking != "" {
            requestObj.thinking := { type: thinking }
        }
        return LLMClient._FixStreamBoolean(jsongo.Stringify(requestObj))
    }

    extractJSONResponse(var) {
        response := var.Get("choices")[1].Get("message").Get("content")
        model := var.Get("model")
        usage := var.Has("usage") ? {
            promptTokens:     var["usage"]["prompt_tokens"],
            completionTokens: var["usage"]["completion_tokens"],
            totalTokens:      var["usage"]["total_tokens"],
            cachedTokens:     var["usage"].Has("prompt_cache_hit_tokens") ? var["usage"]["prompt_cache_hit_tokens"] : 0
        } : { promptTokens: 0, completionTokens: 0, totalTokens: 0, cachedTokens: 0 }
        return {
            response: response,
            model: model,
            usage: usage
        }
    }

    extractErrorResponse(var) {
        error := var.Get("error").Get("message")
        code := var.Get("error").Get("code")
        return {
            error: error,
            code: code,
        }
    }

    appendToChatHistory(role, message, &chatHistoryJSONRequest, chatHistoryJSONRequestFile) {
        obj := jsongo.Parse(chatHistoryJSONRequest)
        obj["messages"].Push({
            role: role,
            content: message
        })
        chatHistoryJSONRequest := LLMClient._FixStreamBoolean(jsongo.Stringify(obj))
        FileOpen(chatHistoryJSONRequestFile, "w", "UTF-8-RAW").Write(chatHistoryJSONRequest)
    }

    buildcURLCommand(chatHistoryJSONRequestFile, cURLOutputFile) {
        return Format(LLMClient.cURLCommand, this.APIKey, chatHistoryJSONRequestFile, cURLOutputFile)
    }

    ; Builds the streaming cURL command (no --max-time, uses --no-buffer)
    ; errorFile = path to capture stderr (e.g., cURLError_*.txt)
    buildStreamcURLCommand(chatHistoryJSONRequestFile, cURLOutputFile, errorFile) {
        return Format(LLMClient.StreamcURLCommand, this.APIKey, chatHistoryJSONRequestFile, cURLOutputFile, errorFile)
    }

    ; ----------------------------------------------------
    ; FIM-specific methods (Fill In the Middle)
    ; ----------------------------------------------------

    ; Builds the FIM JSON request: {model, prompt, suffix?, max_tokens}
    createFIMRequest(APIModel, prefix, suffix, temperature := "", maxTokens := "", stop := "") {
        maxTokens := (maxTokens != "") ? maxTokens : FIMMaxTokens
        requestObj := { model: APIModel, prompt: prefix, max_tokens: maxTokens }
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

    ; Builds the cURL command for the FIM endpoint
    buildFIMcURLCommand(chatHistoryJSONRequestFile, cURLOutputFile) {
        return Format(LLMClient.FIMcURLCommand, this.APIKey, chatHistoryJSONRequestFile, cURLOutputFile)
    }

    ; SSE parsing moved to SSEParser.ahk (SSEParser.ParseLine)
    ; Logging moved to ApiLogger.ahk (ApiLogger.LogRequest etc.)
    ; Cost calculation moved to CostCalculator.ahk (CostCalculator.ComputeTokenCosts)
}
