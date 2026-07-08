; ======================================================
; ChatRequestBuilder.ahk — LLM request pipeline
;
; buildRequest has 3 responsibilities:
;   1. VALIDATE — check API key is configured for the provider
;   2. BUILD — construct the JSON request from DB messages + overrides
;   3. WRITE — persist request + cURL command to temp files
; These are kept together because they share intermediate state
; (providerInfo, apiMessages, requestObj) that would be awkward
; to pass between separate functions.
;
; Also: sendRequestToLLM (thin wrapper) and handleCancelStream.
; ======================================================

buildRequest() {
    if !activeThreadId
        return ""
    path := ChatDB.Msg_GetActivePath(activeThreadId)
    if !path.Length
        return ""

    ; Resolve provider once — used for validation, cURL building, and provider-specific request fields
    providerInfo := ProviderResolver.Resolve(requestParams["singleAPIModelName"])

    ; Validate: check API key is available for the selected provider
    if !providerInfo.apiKey {
        pInfo := providers[providerInfo.providerKey]
        envVar := pInfo ? pInfo.authEnvVar : providerInfo.providerKey
        errorMsg := "No API key configured for " providerInfo.providerKey ". Set " envVar " environment variable."
        postWebMessage("showError", { message: errorMsg })
        postWebMessage("setChatButtonsEnabled", true)
        startLoadingCursor(false)
        debugLog("ERROR: " errorMsg)
        return ""
    }

    ; Build messages array as AHK objects for safe JSON serialization
    apiMessages := []
    for msg in path {
        apiMessages.Push({ role: msg.role, content: msg.content })
    }

    ; Apply system message override if set via Settings modal
    if requestParams.Has("systemOverride") && requestParams["systemOverride"] {
        found := false
        for i, m in apiMessages {
            if m.role = "system" {
                apiMessages[i].content := requestParams["systemOverride"]
                found := true
                break
            }
        }
        ; If no system message exists (e.g. thread started with empty system message),
        ; prepend one so the override takes effect.
        if !found {
            apiMessages.InsertAt(1, { role: "system", content: requestParams["systemOverride"] })
        }
    }

    ; Strip provider prefix from model name for API call
    apiModelName := ModelParser.StripProvider(requestParams["singleAPIModelName"])
    requestObj := { model: apiModelName, messages: apiMessages }

    ; Apply reasoning override with per-provider thinking control.
    ; Delegates to shared LLMRequestBuilder.ApplyThinkingOverride for consistency
    ; with the menu command flow (createJSONRequest).
    if requestParams.Has("reasoningOverride") && requestParams["reasoningOverride"] != "" {
        LLMRequestBuilder.ApplyThinkingOverride(&requestObj, providerInfo.providerKey, providerInfo.modelName, requestParams["reasoningOverride"])
    }

    ; Apply temperature override if set (use != "" not truthiness — "0" is falsy in AHK)
    if requestParams.Has("temperatureOverride") && requestParams["temperatureOverride"] != "" {
        try {
            requestObj.temperature := Float(requestParams["temperatureOverride"])
        } catch {
            debugLog("WARNING: invalid temperature value: " requestParams["temperatureOverride"])
        }
    }

    if requestParams["stream"] {
        requestObj.stream := true
        ; stream_options tells OpenAI-compatible APIs to include usage in the final SSE chunk
        requestObj.stream_options := { include_usage: true }
    }

    ; Gemini-specific: when no reasoning override, request thought summaries
    ; via extra_body at the model's default thinking level.
    ; When an override IS set, the block above already sets extra_body with
    ; the specific thinking_level + include_thoughts.
    if providerInfo.providerKey = "google" && (!requestParams.Has("reasoningOverride") || requestParams["reasoningOverride"] = "") {
        requestObj.extra_body := {
            google: {
                thinking_config: {
                    include_thoughts: true
                }
            }
        }
    }

    payload := LLMRequestBuilder._FixStreamBoolean(jsongo.Stringify(requestObj))

    uniqueID := A_TickCount
    requestFile := A_Temp "\ChatWindow_Req_" uniqueID ".json"
    cURLFile := A_Temp "\ChatWindow_cURL_" uniqueID ".txt"
    outputFile := A_Temp "\ChatWindow_Out_" uniqueID ".json"
    errorFile := A_Temp "\ChatWindow_Err_" uniqueID ".txt"

    FileOpen(requestFile, "w", "UTF-8-RAW").Write(payload)
    if requestParams["stream"] {
        cURLCommand := CurlBuilder.BuildStream(providerInfo, requestFile, outputFile, errorFile)
    } else {
        cURLCommand := CurlBuilder.Build(providerInfo, requestFile, outputFile)
    }
    FileOpen(cURLFile, "w", "UTF-8-RAW").Write(cURLCommand)

    requestParams["chatHistoryJSONRequestFile"] := requestFile
    requestParams["cURLCommandFile"] := cURLFile
    requestParams["cURLOutputFile"] := outputFile
    requestParams["cURLErrorFile"] := errorFile

    return payload
}

sendRequestToLLM(&chatHistoryJSONRequest, initialRequest := false) {
    sendStreamingRequest(&chatHistoryJSONRequest, initialRequest)
}

; Build request, fire to LLM, handle errors. Replaces 5 duplicate call sites.
_BuildAndFireRequest() {
    chatHistoryJSONRequest := buildRequest()
    if !chatHistoryJSONRequest {
        postWebMessage("setChatButtonsEnabled", true)
        startLoadingCursor(false)
        return false
    }
    postWebMessage("setChatButtonsEnabled", false)
    startLoadingCursor(true)
    sendRequestToLLM(&chatHistoryJSONRequest)
    return true
}

handleCancelStream() {
    ; Kill cURL to stop generation server-side (closing TCP connection).
    ; Usage data is lost (only in final SSE chunk), but we avoid billing
    ; for un-displayed tokens. Token estimates are computed from what we captured.
    curlPID := cURLState("get")
    if curlPID && ProcessExist(curlPID) {
        cURLState("close")
    }
    requestParams["_streamCancelled"] := true
    postWebMessage("setChatButtonsEnabled", true)
}
