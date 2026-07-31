; ======================================================
; ChatRequestBuilder.ahk — LLM request pipeline
;
; buildRequest has 3 responsibilities:
;   1. VALIDATE — check API key is configured for the provider
;   2. BUILD — construct the JSON request from DB messages + overrides
;   3. WRITE — persist request + cURL command to temp files
;
; Also: sendRequestToLLM (thin wrapper).
; ======================================================

buildRequest() {
    if !activeThreadId {
        return ""
    }
    path := ChatDB.Msg_GetActivePath(activeThreadId)
    if !path.Length {
        return ""
    }
    modelName := requestParams["singleAPIModelName"]
    debugLog("[API] Chat send — model=" modelName " thread=" activeThreadId " pathLen=" path.Length)

    ; Resolve provider once — used for validation, cURL building, and provider-specific request fields
    providerInfo := ProviderResolver.Resolve(requestParams["singleAPIModelName"])

    ; Validate: check API key is available for the selected provider
    if !providerInfo.apiKey {
        return _ShowApiKeyError(providerInfo)
    }

    ; Build messages array from DB path
    apiMessages := _BuildApiMessagesFromPath(path)

    ; Process last user message's attachments
    if !_ProcessAttachmentsForLastUser(&apiMessages, requestParams["singleAPIModelName"])
        return ""

    ; Clean up internal _msgId fields
    _CleanApiMessages(apiMessages)

    ; Build request object and apply overrides
    requestObj := _BuildRequestObj(apiMessages, providerInfo)

    return _WriteRequestFiles(requestObj, providerInfo)
}

; Show API key error and return "" so caller aborts.
_ShowApiKeyError(providerInfo) {
    pInfo := providers[providerInfo.providerKey]
    envVar := pInfo ? pInfo.authEnvVar : providerInfo.providerKey
    errorMsg := "No API key configured for " providerInfo.providerKey ". Set " envVar " environment variable."
    postWebMessage("showError", { message: errorMsg })
    postWebMessage("setChatButtonsEnabled", true)
    startLoadingCursor(false)
    debugLog("ERROR: " errorMsg)
    return ""
}

; Build a plain {role, content, _msgId} array from the DB path.
_BuildApiMessagesFromPath(path) {
    apiMessages := []
    for msg in path {
        apiMessages.Push({ role: msg.role, content: msg.content, _msgId: msg.id })
    }
    return apiMessages
}

; Remove internal _msgId fields before serializing to JSON.
_CleanApiMessages(apiMessages) {
    for msg in apiMessages
        if msg.HasProp("_msgId")
            msg.DeleteProp("_msgId")
}

; Process attachments for the last user message in apiMessages.
; Returns false if vision gate fails (model doesn't support images).
_ProcessAttachmentsForLastUser(&apiMessages, modelName) {
    ; Find last user message
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
    if !lastUserMsgId || !lastUserIdx
        return true

    attachments := ChatDB.Attachment_GetByMessage(lastUserMsgId)
    if !attachments.Length
        return true

    ; Vision gating: check for images
    if _HasImageAttachments(attachments) && !AttachmentUtils.HasVision(modelName) {
        errorMsg := "Model '" modelName "' does not support vision. Remove images or switch models."
        postWebMessage("showError", { message: errorMsg })
        postWebMessage("setChatButtonsEnabled", true)
        startLoadingCursor(false)
        return false
    }

    contentArray := _BuildImageContentParts(attachments)

    userMsg := apiMessages[lastUserIdx].content
    fileContexts := _BuildFileContexts(attachments)

    if contentArray.Length || fileContexts {
        if fileContexts
            contentArray.InsertAt(1, { type: "text", text: RTrim(fileContexts, "`n`n") })
        if userMsg
            contentArray.Push({ type: "text", text: userMsg })
    }

    if contentArray.Length > 0 {
        apiMessages[lastUserIdx] := { role: "user", content: contentArray }
    }
    ; else: keep original string content (no attachments at all)

    return true
}

; Check if any attachment is an image.
_HasImageAttachments(attachments) {
    for att in attachments {
        if att.attachment_type = "image"
            return true
    }
    return false
}

; Build image_url content parts from attachments.
_BuildImageContentParts(attachments) {
    contentArray := []
    for att in attachments {
        if att.attachment_type = "image" {
            base64Data := ImageUtils.ReadAndEncode(att.file_path)
            if base64Data {
                contentArray.Push({
                    type: "image_url",
                    image_url: { url: "data:" att.mime_type ";base64," base64Data }
                })
            }
        }
    }
    return contentArray
}

; Build file context text from non-image attachments.
_BuildFileContexts(attachments) {
    fileContexts := ""
    for att in attachments {
        if att.attachment_type != "image" {
            typeLabel := att.attachment_type = "pdf" ? "PDF"
                      : att.attachment_type = "docx" ? "DOCX"
                      : "File"
            if att.extracted_text {
                fileContexts .= "[Attached " typeLabel ": " att.original_filename "]`n`n" att.extracted_text "`n`n"
            }
        }
    }
    return fileContexts
}

; Build the request object and apply all overrides (system, reasoning, temperature, stream, provider defaults).
_BuildRequestObj(apiMessages, providerInfo) {
    ; Apply system message override
    _ApplySystemOverride(apiMessages)

    ; Strip provider prefix from model name for API call
    apiModelName := ModelParser.StripProvider(requestParams["singleAPIModelName"])
    requestObj := { model: apiModelName, messages: apiMessages }

    ; Look up model metadata for thinking/compat
    global models
    modelMeta := models.Has(requestParams["singleAPIModelName"])
        ? models[requestParams["singleAPIModelName"]] : ""

    ; Apply reasoning override via metadata-driven handler
    if requestParams.Has("reasoningOverride") && requestParams["reasoningOverride"] != "" {
        if IsObject(modelMeta)
            OpenAIChatCompletions.ApplyThinking(&requestObj, modelMeta, requestParams["reasoningOverride"], requestParams["singleAPIModelName"])
    } else {
        ; No reasoning override — apply provider-level defaults (e.g. Google include_thoughts)
        if IsObject(modelMeta)
            OpenAIChatCompletions.ApplyDefaults(&requestObj, modelMeta)
    }

    ; Apply temperature override (use != "" not truthiness — "0" is falsy in AHK)
    if requestParams.Has("temperatureOverride") && requestParams["temperatureOverride"] != "" {
        try {
            requestObj.temperature := Float(requestParams["temperatureOverride"])
        } catch {
            debugLog("WARNING: invalid temperature value: " requestParams["temperatureOverride"])
        }
    }

    if requestParams["stream"] {
        requestObj.stream := true
        requestObj.stream_options := { include_usage: true }
    }

    return requestObj
}

; Apply system message override from requestParams or prepend one if missing.
_ApplySystemOverride(apiMessages) {
    if !requestParams.Has("systemOverride") || !requestParams["systemOverride"]
        return

    found := false
    for i, m in apiMessages {
        if m.role = "system" {
            apiMessages[i].content := requestParams["systemOverride"]
            found := true
            break
        }
    }
    if !found {
        apiMessages.InsertAt(1, { role: "system", content: requestParams["systemOverride"] })
    }
}

; Serialize request to JSON, write to temp files, store paths in requestParams.
_WriteRequestFiles(requestObj, providerInfo) {
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

