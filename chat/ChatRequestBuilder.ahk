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
    debugLog("[BUILDREQ] ENTER activeThreadId=" activeThreadId, "AttachPipeline")
    if !activeThreadId {
        debugLog("[BUILDREQ] ABORT: no activeThreadId", "AttachPipeline")
        return ""
    }
    path := ChatDB.Msg_GetActivePath(activeThreadId)
    if !path.Length {
        debugLog("[BUILDREQ] ABORT: empty path", "AttachPipeline")
        return ""
    }
    debugLog("[BUILDREQ] path length=" path.Length, "AttachPipeline")

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
        apiMessages.Push({ role: msg.role, content: msg.content, _msgId: msg.id })
    }

    ; Find last user message and load its attachments
    lastUserMsgId := ""
    lastUserIdx := 0
    Loop apiMessages.Length {
        i := apiMessages.Length - A_Index + 1
        if apiMessages[i].role = "user" {
            lastUserMsgId := apiMessages[i]._msgId
            lastUserIdx := i
            break
        }
    }

    debugLog("[BUILDREQ] lastUserMsgId=" lastUserMsgId " lastUserIdx=" lastUserIdx, "AttachPipeline")
    if lastUserMsgId {
        attachments := ChatDB.Attachment_GetByMessage(lastUserMsgId)
        debugLog("[BUILDREQ] attachments loaded from DB: count=" attachments.Length, "AttachPipeline")
        if attachments.Length > 0 {
            ; Vision gating: check for images
            hasImages := false
            for att in attachments {
                if att.attachment_type = "image" {
                    hasImages := true
                    break
                }
            }
            if hasImages && !AttachmentUtils.HasVision(requestParams["singleAPIModelName"]) {
                errorMsg := "Model '" requestParams["singleAPIModelName"] "' does not support vision. Remove images or switch models."
                postWebMessage("showError", { message: errorMsg })
                postWebMessage("setChatButtonsEnabled", true)
                startLoadingCursor(false)
                return ""
            }

            if lastUserIdx > 0 {
                contentArray := []
                ; Add image content parts
                for att in attachments {
                    debugLog("[BUILDREQ] att type=" att.attachment_type " file_path=" att.file_path, "AttachPipeline")
                    if att.attachment_type = "image" {
                        base64Data := ImageUtils.ReadAndEncode(att.file_path)
                        debugLog("[BUILDREQ] ReadAndEncode returned len=" (base64Data ? StrLen(base64Data) : 0), "AttachPipeline")
                        if base64Data {
                            contentArray.Push({
                                type: "image_url",
                                image_url: { url: "data:" att.mime_type ";base64," base64Data }
                            })
                            debugLog("[BUILDREQ] added image_url to contentArray", "AttachPipeline")
                        } else {
                            debugLog("[BUILDREQ] WARNING: ReadAndEncode returned empty for " att.file_path, "AttachPipeline")
                        }
                    }
                }
                debugLog("[BUILDREQ] contentArray length=" contentArray.Length, "AttachPipeline")
                ; Build content array with separate text parts for file content and user message.
                ; Follows OpenAI ChatCompletionContentPart spec: each text block is distinct.
                userMsg := apiMessages[lastUserIdx].content
                fileContexts := ""
                for att in attachments {
                    if att.attachment_type != "image" {
                        typeLabel := "File"
                        if att.attachment_type = "pdf"
                            typeLabel := "PDF"
                        else if att.attachment_type = "docx"
                            typeLabel := "DOCX"
                        if att.extracted_text {
                            fileContexts .= "[Attached " typeLabel ": " att.original_filename "]`n`n" att.extracted_text "`n`n"
                        }
                    }
                }
                ; Build content as array with separate text parts
                textContent := ""
                if !contentArray.Length && !fileContexts {
                    ; No images and no file contexts — keep as plain string content
                    textContent := userMsg
                } else {
                    ; Use content array: file contexts as separate text blocks, then user message
                    if fileContexts
                        contentArray.InsertAt(1, { type: "text", text: RTrim(fileContexts, "`n`n") })
                    if userMsg
                        contentArray.Push({ type: "text", text: userMsg })
                }
                if contentArray.Length > 0 {
                    apiMessages[lastUserIdx] := { role: "user", content: contentArray }
                }
                ; else: keep original string content (no attachments at all)
            }
        }
    }

    ; Clean up internal _msgId fields
    for msg in apiMessages
        if msg.HasProp("_msgId")
            msg.DeleteProp("_msgId")

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
    try {
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
    } catch Error as e {
        debugLog("_BuildAndFireRequest error: " e.Message "`n" e.Stack, "ErrorHandler")
        postWebMessage("showError", { message: "Request failed: " e.Message })
        postWebMessage("setChatButtonsEnabled", true)
        startLoadingCursor(false)
        return false
    }
}

handleCancelStream() {
    try {
    ; Kill cURL to stop generation server-side (closing TCP connection).
    ; Usage data is lost (only in final SSE chunk), but we avoid billing
    ; for un-displayed tokens. Token estimates are computed from what we captured.
    curlPID := cURLState("get")
    if curlPID && ProcessExist(curlPID) {
        cURLState("close")
    }
    requestParams["_streamCancelled"] := true
    postWebMessage("setChatButtonsEnabled", true)
    } catch Error as e {
        debugLog("handleCancelStream error: " e.Message "`n" e.Stack, "ErrorHandler")
        postWebMessage("setChatButtonsEnabled", true)
    }
}
