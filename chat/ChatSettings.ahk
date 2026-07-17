; ======================================================
; ChatSettings.ahk — Thread settings + assistant/model management

_updateProviderFromModel(model) {
    parts := ModelParser.Split(model)
    if parts.provider
        requestParams["providerName"] := parts.provider
}

;
; Manages requestParams for the current thread: restore,
; save, reset, dropdown label, assistant switching,
; model settings persistence.
; ======================================================

; Clear all request-level overrides to default state.
_ClearRequestOverrides() {
    requestParams["systemOverride"] := ""
    requestParams["reasoningOverride"] := ""
    requestParams["temperatureOverride"] := ""
    if requestParams.Has("activeAssistantId")
        requestParams.Delete("activeAssistantId")
    requestParams["singleAPIModelName"] := chatDefaultModel
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
    if settings.assistantId {
        requestParams["activeAssistantId"] := settings.assistantId
        asst := ChatDB.Assistant_Get(settings.assistantId)
        if asst {
            requestParams["singleAPIModelName"] := asst.baseModel
            requestParams["systemOverride"] := asst.systemMessage
            requestParams["reasoningOverride"] := asst.reasoning
            requestParams["temperatureOverride"] := asst.temperature
        }
    }
}

; Build the settings object from current requestParams state.
_CurrentSettingsObject() {
    return {
        assistantId: requestParams.Has("activeAssistantId") ? requestParams["activeAssistantId"] : "",
        modelOverride: requestParams["singleAPIModelName"] != chatDefaultModel ? requestParams["singleAPIModelName"] : "",
        systemOverride: requestParams.Has("systemOverride") ? requestParams["systemOverride"] : "",
        reasoningOverride: requestParams.Has("reasoningOverride") ? requestParams["reasoningOverride"] : "",
        temperatureOverride: requestParams.Has("temperatureOverride") ? requestParams["temperatureOverride"] : ""
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

; Send current dropdown label to WebView (assistant name / model name / "Default Model").
_sendDropdownLabel() {
    if requestParams.Has("activeAssistantId") && requestParams["activeAssistantId"] {
        asst := ChatDB.Assistant_Get(requestParams["activeAssistantId"])
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
    postWebMessage("dropdownLabel", { text: ModelParser.StripProvider(chatDefaultModel), isAssistant: false })
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
        return
    }

    asst := ChatDB.Assistant_Get(assistantId)
    if !asst
        return

    requestParams["singleAPIModelName"] := asst.baseModel
    requestParams["systemOverride"] := asst.systemMessage
    requestParams["reasoningOverride"] := asst.reasoning
    requestParams["temperatureOverride"] := asst.temperature
    requestParams["activeAssistantId"] := assistantId

    ; Update provider tracking for API logs
    _updateProviderFromModel(asst.baseModel)

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

    ; Only clear assistant when user explicitly changes the model (non-empty).
    ; When model is empty, the user is adjusting side settings (reasoning, temperature, etc.)
    ; while an assistant is active — preserve the assistant.
    if model {
        if requestParams.Has("activeAssistantId")
            requestParams.Delete("activeAssistantId")
        requestParams["singleAPIModelName"] := model
        _updateProviderFromModel(model)
    } else if requestParams.Has("activeAssistantId") {
        ; Assistant is active — keep current model (assistant's base model)
        ; Only update reasoning/temperature/systemMessage below
    } else {
        requestParams["singleAPIModelName"] := chatDefaultModel
    }
    requestParams["systemOverride"] := systemMessage
    requestParams["reasoningOverride"] := reasoning
    requestParams["temperatureOverride"] := temperature

    ; Persist to DB
    if activeThreadId {
        ChatDB.Thread_UpdateSettings(activeThreadId, _CurrentSettingsObject())
        postThreadStats(activeThreadId)

    }

    _sendDropdownLabel()
    debugLog("[SETTINGS] Saved — thread=" activeThreadId " model=" (model ? model : chatDefaultModel) " systemMsg=" StrLen(systemMessage) "chars")
}

postCurrentSettingsToWebView() {
    model := requestParams["singleAPIModelName"]
    systemMessage := requestParams.Has("systemOverride") ? requestParams["systemOverride"] : ""
    reasoning := requestParams.Has("reasoningOverride") ? requestParams["reasoningOverride"] : ""
    temperature := requestParams.Has("temperatureOverride") ? requestParams["temperatureOverride"] : ""

    ; Include assistant metadata when active
    assistantName := ""
    assistantBaseModel := ""
    assistantDescription := ""
    if requestParams.Has("activeAssistantId") && requestParams["activeAssistantId"] {
        asst := ChatDB.Assistant_Get(requestParams["activeAssistantId"])
        if asst {
            assistantName := asst.name
            assistantBaseModel := asst.baseModel ? asst.baseModel : ""
            assistantDescription := asst.description ? asst.description : ""
        }
    }

    postWebMessage("currentSettings", {
        model: model,
        systemMessage: systemMessage,
        reasoning: reasoning,
        temperature: temperature,
        assistantName: assistantName,
        assistantBaseModel: assistantBaseModel,
        assistantDescription: assistantDescription
    })
}

postAssistantsToWebView() {
    assistants := ChatDB.Assistant_List()
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
