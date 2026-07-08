; ======================================================
; ChatSettings.ahk — Thread settings + assistant/model management
;
; Manages requestParams for the current thread: restore,
; save, reset, dropdown label, assistant switching,
; model settings persistence.
; ======================================================

; Apply saved per-thread settings from DB to requestParams.
_restoreThreadSettings(threadId) {
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

; Persist current requestParams settings to a thread (called on thread creation).
_saveCurrentSettingsToThread(threadId) {
    ChatDB.Thread_UpdateSettings(threadId, {
        assistantId: requestParams.Has("activeAssistantId") ? requestParams["activeAssistantId"] : "",
        modelOverride: requestParams["singleAPIModelName"] != chatDefaultModel ? requestParams["singleAPIModelName"] : "",
        systemOverride: requestParams.Has("systemOverride") ? requestParams["systemOverride"] : "",
        reasoningOverride: requestParams.Has("reasoningOverride") ? requestParams["reasoningOverride"] : "",
        temperatureOverride: requestParams.Has("temperatureOverride") ? requestParams["temperatureOverride"] : ""
    })
}

; Reset settings to defaults (no assistant, default model, no overrides).
_resetToDefaultSettings() {
    requestParams["singleAPIModelName"] := chatDefaultModel
    if requestParams.Has("systemOverride")
        requestParams.Delete("systemOverride")
    if requestParams.Has("reasoningOverride")
        requestParams.Delete("reasoningOverride")
    if requestParams.Has("temperatureOverride")
        requestParams.Delete("temperatureOverride")
    if requestParams.Has("activeAssistantId")
        requestParams.Delete("activeAssistantId")
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
    if model && model != chatDefaultModel {
        ; Show model name without provider prefix
        slashPos := InStr(model, "/")
        displayModel := slashPos > 0 ? SubStr(model, slashPos + 1) : model
        postWebMessage("dropdownLabel", { text: displayModel, isAssistant: false })
        return
    }
    postWebMessage("dropdownLabel", { text: "Default Model", isAssistant: false })
}

switchAssistantFromWebView(parsed) {
    global activeThreadId
    assistantId := parsed.Get("assistantId", "")
    if !assistantId {
        ; User selected "Default Model" — clear assistant
        _resetToDefaultSettings()
        if activeThreadId {
            ChatDB.Thread_UpdateSettings(activeThreadId, {
                assistantId: "",
                modelOverride: "",
                systemOverride: "",
                reasoningOverride: "",
                temperatureOverride: ""
            })
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
    slashPos := InStr(asst.baseModel, "/")
    if slashPos > 0 {
        requestParams["providerName"] := SubStr(asst.baseModel, 1, slashPos - 1)
    }

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
    debugLog("Switched to assistant: " asst.name " (" asst.baseModel ")")
}

updateModelSettingsFromWebView(parsed) {
    model := parsed.Get("model", "")
    systemMessage := parsed.Get("systemMessage", "")
    reasoning := parsed.Get("reasoning", "")
    temperature := parsed.Get("temperature", "")

    ; Clear assistant when user manually changes settings via gear
    if requestParams.Has("activeAssistantId")
        requestParams.Delete("activeAssistantId")

    if model {
        requestParams["singleAPIModelName"] := model
        slashPos := InStr(model, "/")
        if slashPos > 0 {
            requestParams["providerName"] := SubStr(model, 1, slashPos - 1)
        }
    } else {
        requestParams["singleAPIModelName"] := chatDefaultModel
    }
    requestParams["systemOverride"] := systemMessage
    requestParams["reasoningOverride"] := reasoning
    requestParams["temperatureOverride"] := temperature

    ; Persist to DB
    if activeThreadId {
        ChatDB.Thread_UpdateSettings(activeThreadId, {
            assistantId: "",
            modelOverride: requestParams["singleAPIModelName"] != chatDefaultModel ? requestParams["singleAPIModelName"] : "",
            systemOverride: systemMessage,
            reasoningOverride: reasoning,
            temperatureOverride: temperature
        })
    }

    _sendDropdownLabel()
    debugLog("Model settings updated: model=" (model ? model : chatDefaultModel "(default)"))
}

postCurrentSettingsToWebView() {
    model := requestParams["singleAPIModelName"]
    systemMessage := requestParams.Has("systemOverride") ? requestParams["systemOverride"] : ""
    reasoning := requestParams.Has("reasoningOverride") ? requestParams["reasoningOverride"] : ""
    temperature := requestParams.Has("temperatureOverride") ? requestParams["temperatureOverride"] : ""
    isReadOnly := requestParams.Has("activeAssistantId") && requestParams["activeAssistantId"] != ""
    postWebMessage("currentSettings", {
        model: model,
        systemMessage: systemMessage,
        reasoning: reasoning,
        temperature: temperature,
        readOnly: isReadOnly
    })
}

postAssistantsToWebView() {
    assistants := ChatDB.Assistant_List()
    postWebMessage("assistantList", assistants)

    ; Also send model list grouped by provider for the two-dropdown selector
    modelByProvider := Map()
    for modelId, modelData in models {
        slashPos := InStr(modelId, "/")
        if slashPos > 0 {
            providerKey := SubStr(modelId, 1, slashPos - 1)
            shortName := SubStr(modelId, slashPos + 1)
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
