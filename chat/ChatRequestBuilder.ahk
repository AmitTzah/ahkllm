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

#Include ..\shared\ModelParser.ahk
#Include ..\shared\ModelResolver.ahk
#Include ..\shared\AttachmentUtils.ahk
#Include ..\shared\ImageUtils.ahk

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

    ; Bug #112: a provider with no endpoint would produce a URL-less cURL
    ; command - surface a friendly error instead of raw cURL stderr.
    if !providerInfo.endpoint {
        return _ShowEndpointError(providerInfo)
    }

    ; Build messages array from DB path
    apiMessages := _BuildApiMessagesFromPath(path)

    ; Attach every user message's own attachments to its API content part
    ; (bug #142: the old last-user-only pass silently dropped earlier attached
    ; images/files from follow-up requests, so multi-turn vision lost the
    ; image after the first exchange).
    if !_ProcessAttachmentsForPath(&apiMessages, requestParams["singleAPIModelName"])
        return ""

    ; Clean up internal _msgId fields
    _CleanApiMessages(apiMessages)

    ; Build request object and apply overrides
    requestObj := _BuildRequestObj(apiMessages, providerInfo)

    return _WriteRequestFiles(requestObj, providerInfo)
}

; Show API key error and return "" so caller aborts.
_ShowApiKeyError(providerInfo) {
    ; Bug #199: ProviderResolver can return providerKey="" when NO providers
    ; are configured - a bare providers[""] Map index THROWS in AHK v2 and
    ; crashes the error handler before the friendly message is posted.
    pInfo := ""
    if providers.Has(providerInfo.providerKey)
        pInfo := providers[providerInfo.providerKey]
    envVar := pInfo && pInfo.HasOwnProp("authEnvVar") ? pInfo.authEnvVar : providerInfo.providerKey
    errorMsg := "No API key configured for " providerInfo.providerKey ". Set " envVar " environment variable."
    postWebMessage("showError", { message: errorMsg })
    postWebMessage("setChatButtonsEnabled", true)
    startLoadingCursor(false)
    debugLog("ERROR: " errorMsg)
    return ""
}

; Show "endpoint missing" error and return "" so caller aborts (bug #112).
_ShowEndpointError(providerInfo) {
    errorMsg := "No endpoint configured for provider '" providerInfo.providerKey "'. Set it in Settings → Providers."
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

; Attach attachments for EVERY user message in apiMessages (bug #142: the
; follow-up API request must keep the earlier messages' image/file content
; parts, exactly like it keeps their text). Returns false if the vision gate
; fails (any image in the conversation on a model without vision support).
_ProcessAttachmentsForPath(&apiMessages, modelName) {
    ; Vision gate across the whole conversation: every image that would be
    ; sent counts, not just the last user message's.
    for msg in apiMessages {
        if msg.role != "user" || !msg.HasProp("_msgId") || !msg._msgId
            continue
        attachments := ChatDB.Attachment_GetByMessage(msg._msgId)
        if attachments.Length && _HasImageAttachments(attachments) && !AttachmentUtils.HasVision(modelName) {
            errorMsg := "Model '" modelName "' does not support vision. Remove images or switch models."
            postWebMessage("showError", { message: errorMsg })
            postWebMessage("setChatButtonsEnabled", true)
            startLoadingCursor(false)
            return false
        }
    }

    ; Then turn each user message with attachments into a content array
    ; (images + file contexts + the message text). Keep _msgId so the later
    ; cleanup pass can strip it from the serialized request.
    for i, msg in apiMessages {
        if msg.role != "user" || !msg.HasProp("_msgId") || !msg._msgId
            continue
        attachments := ChatDB.Attachment_GetByMessage(msg._msgId)
        if !attachments.Length
            continue

        contentArray := _BuildImageContentParts(attachments)
        fileContexts := _BuildFileContexts(attachments)
        userMsg := apiMessages[i].content

        if contentArray.Length || fileContexts {
            if fileContexts
                contentArray.InsertAt(1, { type: "text", text: RTrim(fileContexts, "`n`n") })
            if userMsg
                contentArray.Push({ type: "text", text: userMsg })
        }

        if contentArray.Length > 0 {
            apiMessages[i] := { role: "user", content: contentArray, _msgId: msg._msgId }
        }
        ; else: keep original string content (no attachable content at all)
    }

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
    ; Single lookup accepting full or short model ids (bug #43: short ids
    ; used to get an empty modelMeta, silently dropping thinking config).
    modelMeta := ModelResolver.Lookup(models, requestParams["singleAPIModelName"])

    ; Apply reasoning override via metadata-driven handler.
    ; Only send thinking config for a thinking level this model actually offers.
    ; "Model Default" (empty) — or any value the sidebar dropdown can't display
    ; (e.g. an assistant's "none" default on a model whose level list has no
    ; "none") — sends NO thinking config at all.
    reasoning := requestParams.Has("reasoningOverride") ? requestParams["reasoningOverride"] : ""
    hasLevelMap := IsObject(modelMeta) && modelMeta.HasOwnProp("thinkingLevelMap") && IsObject(modelMeta.thinkingLevelMap)
    if (reasoning != "" && hasLevelMap && modelMeta.thinkingLevelMap.Has(reasoning))
        OpenAIChatCompletions.ApplyThinking(&requestObj, modelMeta, reasoning, requestParams["singleAPIModelName"])

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
    ; Bug #203: a chat-mode command with "Stream Response" OFF must run the
    ; single-shot JSON path (CurlBuilder.Build + ResponseParser), not the SSE
    ; stream handler - otherwise a JSON-only API response is dropped as an SSE
    ; parse failure.
    if requestParams["stream"]
        sendStreamingRequest(&chatHistoryJSONRequest, initialRequest)
    else
        sendNonStreamingRequest(&chatHistoryJSONRequest)
}

; Build request, fire to LLM, handle errors. Replaces 5 duplicate call sites.
_BuildAndFireRequest() {
    try {
    chatHistoryJSONRequest := buildRequest()
    if !chatHistoryJSONRequest {
        postWebMessage("setChatButtonsEnabled", true)
        startLoadingCursor(false)
        ; Bug #211: a retry rejected before any stream (vision gate, API-key
        ; error, endpoint error) leaves pendingRetrySiblingGroup / 
        ; pendingRetryIsRoot set - clear them so the next normal response is
        ; not mis-grouped with the retried message. The deletes are INLINED
        ; (no helper call) because ChatRequestBuilder.ahk is #Included by the
        ; headless DB-audit probe WITHOUT the chat-process modules - AHK v2
        ; treats a call whose callee is only defined in a later #Include as an
        ; unassigned local variable and pops a #Warn modal that hangs the run.
        if requestParams.Has("pendingRetrySiblingGroup")
            requestParams.Delete("pendingRetrySiblingGroup")
        if requestParams.Has("pendingRetryIsRoot")
            requestParams.Delete("pendingRetryIsRoot")
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

