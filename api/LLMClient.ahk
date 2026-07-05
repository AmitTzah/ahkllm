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

    ; ----------------------------------------------------
    ; SSE Streaming — parses a "data: " line from the SSE stream
    ; Returns an object {type, content, model?} where type is
    ; "content", "reasoning", "model", or "done"
    ; ----------------------------------------------------

    parseSSELine(line) {
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

    ; ----------------------------------------------------
    ; API request/response logging
    ; ----------------------------------------------------
    ;
    ; Logs a single API interaction to %TEMP%\LLM_API_Log.json.
    ; The log is capped at apiLogMaxEntries entries (newest first).
    ; Set apiLogMaxEntries to 0 to disable logging entirely.
    ;
    static logFilePath := A_Temp "\LLM_API_Log.json"

    static LogRequest(entry) {
        if (apiLogMaxEntries <= 0) {
            return
        }

        logs := []
        if FileExist(this.logFilePath) {
            try {
                logs := jsongo.Parse(FileOpen(this.logFilePath, "r", "UTF-8-RAW").Read())
            }
        }

        ; Add timestamp if not already present
        if !entry.HasProp("timestamp") || entry.timestamp = "" {
            entry.timestamp := FormatTime(, "yyyy-MM-dd HH:mm:ss")
        }

        logs.InsertAt(1, entry)

        ; Trim oldest entries to stay within the configured limit
        while logs.Length > apiLogMaxEntries {
            logs.RemoveAt(logs.Length)
        }

        FileOpen(this.logFilePath, "w", "UTF-8-RAW").Write(jsongo.Stringify(logs))
    }

    ; Reads the log file and returns the entries array (newest first).
    static ReadLogs() {
        logs := []
        if FileExist(this.logFilePath) {
            try {
                logs := jsongo.Parse(FileOpen(this.logFilePath, "r", "UTF-8-RAW").Read())
            }
        }
        return logs
    }

    ; Clears the log file entirely.
    static ClearLogs() {
        if FileExist(this.logFilePath) {
            FileDelete(this.logFilePath)
        }
    }

    ; Returns the path to the log file (for reference/display).
    ; ----------------------------------------------------
    ; Token cost calculation
    ; ----------------------------------------------------
    ;
    ; Computes cost estimates for a given model and token usage.
    ; Looks up pricing from the global modelPricing map (defined in UserConfig.ahk).
    ; Returns an object with formatted cost strings, or empty strings if pricing
    ; is not available for the model.
    ;
    static ComputeTokenCosts(model, usage) {
        costs := { inputCost: "", outputCost: "", totalCost: "", contextWindow: "" }
        
        ; Handle provider/model format — use just the model part for lookup
        modelShort := model
        slashPos := InStr(model, "/")
        if slashPos > 0 {
            modelShort := SubStr(model, slashPos + 1)
        }
        
        ; Look up pricing for this model
        if modelPricing.Has(modelShort) {
            pricing := modelPricing[modelShort]
            inputPrice       := pricing.HasOwnProp("input")       ? pricing.input       : 0
            cachedInputPrice := pricing.HasOwnProp("cachedInput") ? pricing.cachedInput : (inputPrice * 0.1)
            outputPrice      := pricing.HasOwnProp("output")      ? pricing.output      : 0
            contextWin       := pricing.HasOwnProp("context")     ? pricing.context     : ""
            
            ; Determine cached token count (default to 0 if not provided)
            cachedTokens := usage.HasProp("cachedTokens") ? usage.cachedTokens : 0
            
            ; Calculate input cost: split cached vs non-cached
            if inputPrice > 0 && usage.promptTokens > 0 {
                nonCachedTokens := usage.promptTokens - cachedTokens
                nonCachedCost := nonCachedTokens * inputPrice / 1000000
                cachedCost := cachedTokens * cachedInputPrice / 1000000
                costs.inputCost := Round(nonCachedCost + cachedCost, 6)
            }
            
            ; Calculate output cost
            if outputPrice > 0 && usage.completionTokens > 0 {
                costs.outputCost := Round(usage.completionTokens * outputPrice / 1000000, 6)
            }
            
            ; Calculate total
            if (inputPrice > 0 || outputPrice > 0) && (costs.inputCost != "" || costs.outputCost != "") {
                total := (costs.inputCost != "" ? costs.inputCost : 0) + (costs.outputCost != "" ? costs.outputCost : 0)
                costs.totalCost := Round(total, 6)
            }
            if contextWin != "" {
                costs.contextWindow := contextWin
            }
        }
        
        return costs
    }

    static GetLogFilePath() {
        return this.logFilePath
    }
}
