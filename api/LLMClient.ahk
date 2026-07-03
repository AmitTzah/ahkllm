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

    createJSONRequest(APIModel, systemPrompt, userPrompt, temperature := "", maxTokens := "", stop := "") {
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
        return jsongo.Stringify(requestObj)
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
    }

    buildcURLCommand(chatHistoryJSONRequestFile, cURLOutputFile) {
        return Format(LLMClient.cURLCommand, this.APIKey, chatHistoryJSONRequestFile, cURLOutputFile)
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