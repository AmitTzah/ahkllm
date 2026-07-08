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
        this._curl := CurlBuilder(APIKey)
    }

    ; ----------------------------------------------------
    ; Request Builders
    ; ----------------------------------------------------

    ; Builds the standard chat completions JSON request.
    ; Supports: provider/model ID, system prompt, user prompt, images, thinking.
    ; images: optional array of { data (base64), mimeType } objects
    createJSONRequest(APIModel, systemMessage, userPrompt, temperature := "", maxTokens := "", stop := "", stream := false, reasoningEffort := "", images*) {
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
            requestObj.stop := stop
        if stream {
            requestObj.stream := true
        }

        LLMRequestBuilder.ApplyThinkingOverride(&requestObj, providerKey, modelName, reasoningEffort)
        return LLMRequestBuilder._FixStreamBoolean(jsongo.Stringify(requestObj))
    }

    ; Builds the FIM JSON request: {model, prompt, suffix?, max_tokens}
    createFIMRequest(APIModel, prefix, suffix, temperature := "", maxTokens := "", stop := "") {
        modelName := ModelParser.StripProvider(APIModel)

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

    ; ----------------------------------------------------
    ; Thinking Configuration
    ; ----------------------------------------------------
    ; Applies per-provider thinking parameters to a request object.
    ; Called by createJSONRequest and BuildAndWriteRequestFiles (chat flow).
    ;
    ; Provider behavior:
    ;   DeepSeek: thinking toggle + reasoning_effort
    ;   OpenAI:   reasoning_effort
    ;   Google 2.5: reasoning_effort; Google 3.x: extra_body with thinking_level
    static ApplyThinkingOverride(&requestObj, providerKey, modelName, reasoningVal) {
        if reasoningVal = ""
            return

        if reasoningVal = "none" {
            if providerKey = "deepseek" {
                requestObj.thinking := { type: "disabled" }
            } else {
                ; OpenAI + Google: reasoning_effort: "none" disables thinking.
                ; Google docs: "For Gemini 2.5 models, thinking can be disabled
                ; by setting reasoning_effort to 'none'."
                ; For models that can't disable, the API error surfaces in chat UI.
                requestObj.reasoning_effort := "none"
            }
            return
        }

        if providerKey = "google" {
            ; Known Gemini families use extra_body for thought summaries:
            ;   3.x models → thinking_level (string)
            ;   2.5 models → thinking_budget (numeric)
            ; Other Google models (Gemma, etc.) → reasoning_effort (safe default)
            isGemini3x := InStr(modelName, "3.") > 0 || InStr(modelName, "gemini-3") > 0
            isGemini25 := InStr(modelName, "2.5") > 0 || InStr(modelName, "gemini-2") > 0

            if isGemini3x || isGemini25 {
                tc := { include_thoughts: true }
                if isGemini3x {
                    tc.thinking_level := reasoningVal
                } else {
                    budgetMap := Map("minimal", 1024, "low", 4096, "medium", 8192, "high", 16384, "xhigh", 24576)
                    if budgetMap.Has(reasoningVal)
                        tc.thinking_budget := budgetMap[reasoningVal]
                }
                requestObj.extra_body := { google: { thinking_config: tc } }
            } else {
                ; Gemma and other Google models: use reasoning_effort
                requestObj.reasoning_effort := reasoningVal
            }
        } else {
            requestObj.reasoning_effort := reasoningVal
            if providerKey = "deepseek" {
                requestObj.thinking := { type: "enabled" }
            }
        }
    }

    ; ----------------------------------------------------
    ; JSON Serialization Fix
    ; ----------------------------------------------------
    static _FixStreamBoolean(jsonStr) {
        jsonStr := StrReplace(jsonStr, '"stream":1', '"stream":true')
        jsonStr := StrReplace(jsonStr, '"stream":0', '"stream":false')
        jsonStr := StrReplace(jsonStr, '"include_usage":1', '"include_usage":true')
        jsonStr := StrReplace(jsonStr, '"include_thoughts":1', '"include_thoughts":true')
        return jsonStr
    }

    ; ----------------------------------------------------
    ; Instance Helpers (needed by llmClient in Main/ChatWindow)
    ; ----------------------------------------------------

    buildcURLCommand(requestFile, outputFile) {
        return this._curl.buildcURLCommand(requestFile, outputFile)
    }

    buildFIMcURLCommand(requestFile, outputFile) {
        return this._curl.buildFIMcURLCommand(requestFile, outputFile)
    }

    extractJSONResponse(var) {
        return ResponseParser.ParseChatResponse(var)
    }

    extractFIMResponse(var) {
        return ResponseParser.ParseFIMResponse(var)
    }

    appendToChatHistory(role, message, &chatHistoryJSONRequest, chatHistoryJSONRequestFile) {
        obj := jsongo.Parse(chatHistoryJSONRequest)
        obj["messages"].Push({ role: role, content: message })
        chatHistoryJSONRequest := LLMRequestBuilder._FixStreamBoolean(jsongo.Stringify(obj))
        FileOpen(chatHistoryJSONRequestFile, "w", "UTF-8-RAW").Write(chatHistoryJSONRequest)
    }
}
