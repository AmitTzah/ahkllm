; ======================================================
; ChatRequestBuilder.ahk — LLM request pipeline
;
; BuildAndWriteRequestFiles has 3 responsibilities:
;   1. VALIDATE — check API key is configured for the provider
;   2. BUILD — construct the JSON request from DB messages + overrides
;   3. WRITE — persist request + cURL command to temp files
; These are kept together because they share intermediate state
; (providerInfo, apiMessages, requestObj) that would be awkward
; to pass between separate functions.
;
; Also: sendRequestToLLM (thin wrapper) and cancelStreamFromWebView.
; ======================================================

BuildAndWriteRequestFiles() {
    if !activeThreadId
        return ""
    path := ChatDB.Msg_GetActivePath(activeThreadId)
    if !path.Length
        return ""

    ; Resolve provider once — used for validation, cURL building, and provider-specific request fields
    providerInfo := LLMClient.ResolveProvider(requestParams["singleAPIModelName"])

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

    ; Strip provider prefix from model name for API call (e.g. "deepseek/deepseek-v4-flash" → "deepseek-v4-flash")
    apiModelName := requestParams["singleAPIModelName"]
    slashPos := InStr(apiModelName, "/")
    if slashPos > 0 {
        apiModelName := SubStr(apiModelName, slashPos + 1)
    }
    requestObj := { model: apiModelName, messages: apiMessages }

    ; Apply reasoning override with per-provider thinking control.
    ; Each provider has different mechanisms for enabling/disabling thinking.
    if requestParams.Has("reasoningOverride") && requestParams["reasoningOverride"] != "" {
        reasoningVal := requestParams["reasoningOverride"]

        if reasoningVal = "none" {
            ; User wants thinking disabled — use provider-specific mechanism
            if providerInfo.providerKey = "deepseek" {
                ; DeepSeek V4: thinking:disabled is the only way to disable.
                ; Do NOT send reasoning_effort at all — DeepSeek rejects "none".
                requestObj.thinking := { type: "disabled" }
            } else {
                ; OpenAI GPT-5.1+ / Gemini Flash: reasoning_effort: "none" works
                ; For models that can't disable (GPT-5, Gemini Pro), this is silently ignored
                requestObj.reasoning_effort := "none"
            }
        } else {
            ; Specific reasoning level (low/medium/high/xhigh)
            requestObj.reasoning_effort := reasoningVal
        }
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

    ; Gemini-specific: request thinking (thought summaries) via extra_body
    if providerInfo.providerKey = "google" {
        requestObj.extra_body := {
            google: {
                thinking_config: {
                    include_thoughts: true
                }
            }
        }
    }

    payload := LLMClient._FixStreamBoolean(jsongo.Stringify(requestObj))

    uniqueID := A_TickCount
    requestFile := A_Temp "\ChatWindow_Req_" uniqueID ".json"
    cURLFile := A_Temp "\ChatWindow_cURL_" uniqueID ".txt"
    outputFile := A_Temp "\ChatWindow_Out_" uniqueID ".json"
    errorFile := A_Temp "\ChatWindow_Err_" uniqueID ".txt"

    FileOpen(requestFile, "w", "UTF-8-RAW").Write(payload)
    if requestParams["stream"] {
        cURLCommand := LLMClient.BuildStreamcURLCommand(providerInfo, requestFile, outputFile, errorFile)
    } else {
        cURLCommand := LLMClient.BuildcURLCommand(providerInfo, requestFile, outputFile)
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

cancelStreamFromWebView() {
    ; Directly kill the cURL process without going through ChatHotkeys("Esc").
    ; ChatHotkeys("Esc") has window-hiding logic (hides window when no cURL is running),
    ; which is wrong for the Stop button — the Stop button should only cancel streaming,
    ; never hide the window.
    curlPID := cURLState("get")
    if curlPID && ProcessExist(curlPID) {
        cURLState("close")
        requestParams["_streamCancelled"] := true
        postWebMessage("setChatButtonsEnabled", true)
    }
}
