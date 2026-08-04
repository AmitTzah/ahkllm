; ======================================================
; ChatSettings.ahk — Thread settings + assistant/model management
;
; Manages requestParams for the current thread: restore,
; save, reset, dropdown label, assistant switching,
; model settings persistence.
; ======================================================

; Update provider tracking for API logs from a model id.
_updateProviderFromModel(model) {
    parts := ModelParser.Split(model)
    if parts.provider
        requestParams["providerName"] := parts.provider
}

; Clear all request-level overrides to default state.
_ClearRequestOverrides() {
    requestParams["systemOverride"] := ""
    requestParams["reasoningOverride"] := ""
    requestParams["temperatureOverride"] := ""
    requestParams["codeExecution"] := false
    requestParams["webSearch"] := false
    if requestParams.Has("activeAssistantId")
        requestParams.Delete("activeAssistantId")
    if requestParams.Has("fontSize")
        requestParams.Delete("fontSize")
    requestParams["singleAPIModelName"] := appDefaultModel
}

; Apply saved per-thread settings from DB to requestParams.
_restoreThreadSettings(threadId) {
    ; Always clear previous overrides before loading new ones.
    ; Prevents system messages, reasoning, etc. from leaking across threads.
    _ClearRequestOverrides()

    settings := ChatDB.Thread_GetSettings(threadId)
    if !settings
        return
    if settings.modelOverride
        requestParams["singleAPIModelName"] := settings.modelOverride
    if settings.systemOverride
        requestParams["systemOverride"] := settings.systemOverride
    if settings.reasoningOverride
        requestParams["reasoningOverride"] := settings.reasoningOverride
    if settings.temperatureOverride
        requestParams["temperatureOverride"] := settings.temperatureOverride
    if settings.fontSize
        requestParams["fontSize"] := settings.fontSize
    ; Right-rail Advanced toggles (Code Execution / Web Search) — persisted stubs
    requestParams["codeExecution"] := _BoolFrom(settings.HasOwnProp("codeExecution") ? settings.codeExecution : false)
    requestParams["webSearch"] := _BoolFrom(settings.HasOwnProp("webSearch") ? settings.webSearch : false)
    if settings.assistantId {
        requestParams["activeAssistantId"] := settings.assistantId
        asst := AssistantRepo.GetFromSettings(settings.assistantId)
        if asst {
            requestParams["singleAPIModelName"] := asst.baseModel
            ; Fall back to the assistant's values ONLY where the thread has no
            ; per-thread override. Stored overrides (system prompt, reasoning,
            ; temperature) must win over the assistant defaults - otherwise a
            ; per-thread edit made while an assistant is active silently
            ; vanishes on the next reload (bug #47).
            if !settings.systemOverride
                requestParams["systemOverride"] := AssistantRepo._resolveSystemMessage(asst)
            if !settings.reasoningOverride
                requestParams["reasoningOverride"] := asst.reasoning
            if !settings.temperatureOverride
                requestParams["temperatureOverride"] := asst.temperature
        }
    }
}

; Normalize a JSON boolean / 1 / 0 / "true" / "false" value to a real boolean.
_BoolFrom(value) {
    if value = 1 || value = "1" || value = "true" || value = "on" || value = "yes"
        return true
    return false
}

; Build the settings object from current requestParams state.
_CurrentSettingsObject() {
    global responseWindowFontSize
    defaultFontSize := IsSet(responseWindowFontSize) ? responseWindowFontSize : "17"
    return {
        assistantId: requestParams.Has("activeAssistantId") ? requestParams["activeAssistantId"] : "",
        modelOverride: requestParams["singleAPIModelName"] != appDefaultModel ? requestParams["singleAPIModelName"] : "",
        systemOverride: requestParams.Has("systemOverride") ? requestParams["systemOverride"] : "",
        reasoningOverride: requestParams.Has("reasoningOverride") ? requestParams["reasoningOverride"] : "",
        temperatureOverride: requestParams.Has("temperatureOverride") ? requestParams["temperatureOverride"] : "",
        codeExecution: requestParams.Has("codeExecution") ? requestParams["codeExecution"] : false,
        webSearch: requestParams.Has("webSearch") ? requestParams["webSearch"] : false,
        fontSize: requestParams.Has("fontSize") ? requestParams["fontSize"] : defaultFontSize
    }
}

; Persist current requestParams settings to a thread (called on thread creation).
_saveCurrentSettingsToThread(threadId) {
    ChatDB.Thread_UpdateSettings(threadId, _CurrentSettingsObject())
}

; Reset settings to defaults (no assistant, default model, no overrides).
_resetToDefaultSettings() {
    _ClearRequestOverrides()
}

; Apply an assistant's settings to requestParams and mark it active.
; Shared by handleSwitchAssistant and the new-chat default resolution.
_applyAssistantToRequestParams(asst) {
    requestParams["singleAPIModelName"] := asst.baseModel
    requestParams["systemOverride"] := AssistantRepo._resolveSystemMessage(asst)
    requestParams["reasoningOverride"] := asst.reasoning
    requestParams["temperatureOverride"] := asst.temperature
    requestParams["activeAssistantId"] := asst.id
    _updateProviderFromModel(asst.baseModel)
}

; Apply the configured "new chats start with" default to requestParams.
; "" = app default model (appDefaultModel); "asst:<id>" = an assistant;
; anything else is treated as a model id. Returns true when a default applied.
_applyNewChatDefault() {
    global newChatStartsWith
    value := IsSet(newChatStartsWith) ? newChatStartsWith : ""
    if value = ""
        return false
    if SubStr(value, 1, 5) = "asst:" {
        asst := AssistantRepo.GetFromSettings(SubStr(value, 6))
        if !asst
            return false
        _applyAssistantToRequestParams(asst)
        return true
    }
    ; Model default: drop any active assistant and use the model directly.
    if requestParams.Has("activeAssistantId")
        requestParams.Delete("activeAssistantId")
    requestParams["singleAPIModelName"] := value
    _updateProviderFromModel(value)
    return true
}

; Send current dropdown label to WebView (assistant name / model name / "Default Model").
_sendDropdownLabel() {
    if requestParams.Has("activeAssistantId") && requestParams["activeAssistantId"] {
        asst := AssistantRepo.GetFromSettings(requestParams["activeAssistantId"])
        if asst {
            postWebMessage("dropdownLabel", { text: asst.name, isAssistant: true })
            return
        }
    }
    model := requestParams["singleAPIModelName"]
    if model {
        ; Always show actual model name, never "Default Model"
        displayModel := ModelParser.StripProvider(model)
        postWebMessage("dropdownLabel", { text: displayModel, isAssistant: false })
        return
    }
    postWebMessage("dropdownLabel", { text: ModelParser.StripProvider(appDefaultModel), isAssistant: false })
}

handleSwitchAssistant(parsed) {
    global activeThreadId
    assistantId := parsed.Get("assistantId", "")
    if !assistantId {
        ; User selected "Default Model" — clear assistant
        _resetToDefaultSettings()
        if activeThreadId {
            ChatDB.Thread_UpdateSettings(activeThreadId, _CurrentSettingsObject())
        }
        _sendDropdownLabel()
        postCurrentSettingsToWebView()
        return
    }

    asst := AssistantRepo.GetFromSettings(assistantId)
    if !asst
        return

    _applyAssistantToRequestParams(asst)

    ; Persist to DB
    if activeThreadId {
        ChatDB.Thread_UpdateSettings(activeThreadId, {
            assistantId: assistantId,
            modelOverride: "",
            systemOverride: "",
            reasoningOverride: "",
            temperatureOverride: ""
        })
    }

    _sendDropdownLabel()
    postCurrentSettingsToWebView()
    if activeThreadId
        postThreadStats(activeThreadId)
    debugLog("[MODEL] Switched to assistant: " asst.name " (" asst.baseModel ")")
}

handleModelSettingsUpdate(parsed) {
    global activeThreadId
    model := parsed.Get("model", "")
    systemMessage := parsed.Get("systemMessage", "")
    reasoning := parsed.Get("reasoning", "")
    temperature := parsed.Get("temperature", "")
    codeExecution := _BoolFrom(parsed.Get("codeExecution", false))
    webSearch := _BoolFrom(parsed.Get("webSearch", false))

    ; Only clear assistant when user explicitly changes the model (non-empty).
    ; When model is empty, the user is adjusting side settings (reasoning, temperature, etc.)
    ; while an assistant is active — preserve the assistant.
    if model {
        if requestParams.Has("activeAssistantId")
            requestParams.Delete("activeAssistantId")
        requestParams["singleAPIModelName"] := model
        _updateProviderFromModel(model)
    } else if !requestParams.Has("activeAssistantId") {
        ; No explicit model and no active assistant — fall back to the default.
        requestParams["singleAPIModelName"] := appDefaultModel
    }
    requestParams["systemOverride"] := systemMessage
    requestParams["reasoningOverride"] := reasoning
    requestParams["temperatureOverride"] := temperature
    requestParams["codeExecution"] := codeExecution
    requestParams["webSearch"] := webSearch

    ; Persist to DB
    if activeThreadId {
        ChatDB.Thread_UpdateSettings(activeThreadId, _CurrentSettingsObject())
        postThreadStats(activeThreadId)

    }

    _sendDropdownLabel()
    postCurrentSettingsToWebView()
    debugLog("[SETTINGS] Saved — thread=" activeThreadId " model=" (model ? model : appDefaultModel) " systemMsg=" StrLen(systemMessage) "chars")
}

postCurrentSettingsToWebView() {
    global responseWindowFontSize
    model := requestParams["singleAPIModelName"]
    systemMessage := requestParams.Has("systemOverride") ? requestParams["systemOverride"] : ""
    reasoning := requestParams.Has("reasoningOverride") ? requestParams["reasoningOverride"] : ""
    temperature := requestParams.Has("temperatureOverride") ? requestParams["temperatureOverride"] : ""
    defaultFontSize := IsSet(responseWindowFontSize) ? responseWindowFontSize : "17"
    fontSize := requestParams.Has("fontSize") ? requestParams["fontSize"] : defaultFontSize
    codeExecution := requestParams.Has("codeExecution") ? requestParams["codeExecution"] : false
    webSearch := requestParams.Has("webSearch") ? requestParams["webSearch"] : false

    ; Include assistant metadata when active
    assistantName := ""
    assistantBaseModel := ""
    assistantDescription := ""
    if requestParams.Has("activeAssistantId") && requestParams["activeAssistantId"] {
        asst := AssistantRepo.GetFromSettings(requestParams["activeAssistantId"])
        if asst {
            assistantName := asst.name
            assistantBaseModel := asst.baseModel ? asst.baseModel : ""
            assistantDescription := asst.HasOwnProp("description") ? asst.description : ""
        }
    }

    ; Build thinking level options from the current model's metadata.
    ; Raw level values only — the frontend labels and sorts them via the shared
    ; ReasoningLevels helper (single source of truth for labels/order).
    thinkingLevels := []
    global models
    if models.Has(model) {
        modelMeta := models[model]
        if modelMeta.HasOwnProp("thinkingLevelMap") && IsObject(modelMeta.thinkingLevelMap) {
            for level in modelMeta.thinkingLevelMap
                thinkingLevels.Push(level)
        }
    }

    ; Step 3 of the IPC refactor: the right-rail per-thread payload is its own
    ; message (threadSettings) — distinct from the full appSettings payload.
    postWebMessage("threadSettings", {
        model: model,
        systemMessage: systemMessage,
        reasoning: reasoning,
        temperature: temperature,
        codeExecution: codeExecution,
        webSearch: webSearch,
        fontSize: fontSize,
        assistantName: assistantName,
        assistantBaseModel: assistantBaseModel,
        assistantDescription: assistantDescription,
        thinkingLevels: thinkingLevels
    })
}

postAssistantsToWebView() {
    global assistants, models
    if !IsSet(assistants) || !IsSet(models)
        return
    postWebMessage("assistantList", assistants)

    ; Also send model list grouped by provider for the two-dropdown selector
    modelByProvider := Map()
    for modelId, modelData in models {
        parts := ModelParser.Split(modelId)
        if parts.provider {
            providerKey := parts.provider
            shortName := parts.name
            if !modelByProvider.Has(providerKey)
                modelByProvider[providerKey] := []
            modelByProvider[providerKey].Push({
                id: shortName,
                fullId: modelId,
                name: modelData.HasOwnProp("displayName") ? modelData.displayName : shortName,
                reasoning: modelData.HasOwnProp("reasoning") ? modelData.reasoning : false,
                vision: modelData.HasOwnProp("vision") ? modelData.vision : false
            })
        }
    }
    postWebMessage("modelList", modelByProvider)
}

; Delayed push: send assistant list after WebView page loads.
; Called from the main init flow with a timer to avoid race conditions.
SetTimer SendAssistantsDelayed, -500
SendAssistantsDelayed() {
    postAssistantsToWebView()
}

; Handle per-chat font size update from the header +/- buttons.
handleUpdateFontSize(parsed) {
    global activeThreadId
    fontSize := parsed.Get("fontSize", 17)
    if activeThreadId {
        requestParams["fontSize"] := fontSize
        ChatDB.Thread_UpdateSettings(activeThreadId, { fontSize: fontSize })
    }
}
