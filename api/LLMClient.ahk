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
        result := jsongo.Stringify(requestObj)
        ; jsongo serializes AHK v2 true/false (integers 1/0) as "stream":1 instead of "stream":true.
        ; The DeepSeek API requires boolean values for the stream field. Fix it post-hoc.
        result := StrReplace(result, '"stream":1', '"stream":true')
        result := StrReplace(result, '"stream":0', '"stream":false')
        return result
    }

    extractJSONResponse(var) {
        response := var.Get("choices")[1].Get("message").Get("content")
        model := var.Get("model")
        return {
            response: response,
            model: model
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
        chatHistoryJSONRequest := jsongo.Stringify(obj)
        ; jsongo serializes AHK v2 true/false as integers 1/0.
        ; The DeepSeek API requires boolean values. Fix it post-hoc.
        chatHistoryJSONRequest := StrReplace(chatHistoryJSONRequest, '"stream":1', '"stream":true')
        chatHistoryJSONRequest := StrReplace(chatHistoryJSONRequest, '"stream":0', '"stream":false')
        FileOpen(chatHistoryJSONRequestFile, "w", "UTF-8-RAW").Write(chatHistoryJSONRequest)
    }

    getMessages(obj) {
        messages := []
        for i in obj["messages"] {
            messages.Push({
                role: i["role"],
                content: i["content"]
            })
        }
        return messages
    }

    removeLastAssistantMessage(&chatHistoryJSONRequest) {
        obj := jsongo.Parse(chatHistoryJSONRequest)
        messagesArray := obj["messages"]
        lastIndex := messagesArray.Length
        if (messagesArray[lastIndex]["role"] = "assistant") {
            messagesArray.RemoveAt(lastIndex)
        }
        chatHistoryJSONRequest := jsongo.Stringify(obj)
        ; jsongo serializes AHK v2 true/false as integers 1/0 — fix for DeepSeek API
        chatHistoryJSONRequest := StrReplace(chatHistoryJSONRequest, '"stream":1', '"stream":true')
        chatHistoryJSONRequest := StrReplace(chatHistoryJSONRequest, '"stream":0', '"stream":false')
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
    static GetLogFilePath() {
        return this.logFilePath
    }
}