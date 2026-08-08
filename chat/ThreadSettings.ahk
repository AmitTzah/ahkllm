; ======================================================
; ThreadSettings.ahk - single source of truth for a
; thread's effective per-thread settings.
;
; Step 4 of the architecture refactor: the precedence
; rules (per-thread override > assistant default), the
; thread-restore logic, the DB serialization, and the
; right-rail message previously lived in ChatSettings.ahk
; as separate implementations that could drift (bug #47:
; the restore path overwrote the edit path's overrides).
; They now live here:
;   ComputeEffective          - precedence, one place
;   RestoreIntoRequestParams  - thread load
;   ToDbObject                - persistence shape
;   ToThreadSettingsMessage   - right-rail payload
; ======================================================

#Include ..\shared\ModelResolver.ahk
#Include db\AssistantRepo.ahk

class ThreadSettings {

    ; Effective settings for a thread from a DB row (Thread_GetSettings
    ; shape) + optional assistant. Per-thread overrides win; the assistant's
    ; values are the fallback.
    static ComputeEffective(row, asst := "") {
        eff := {
            assistantId: row.HasOwnProp("assistantId") ? row.assistantId : "",
            model: "",
            systemMessage: "",
            reasoning: "",
            temperature: "",
            codeExecution: row.HasOwnProp("codeExecution") ? row.codeExecution : false,
            webSearch: row.HasOwnProp("webSearch") ? row.webSearch : false,
            fontSize: (row.HasOwnProp("fontSize") && row.fontSize) ? row.fontSize : 17,
            assistantName: "",
            assistantBaseModel: "",
            assistantDescription: ""
        }
        hasTemperatureOverride := false
        if row.HasOwnProp("modelOverride") && row.modelOverride
            eff.model := row.modelOverride
        if row.HasOwnProp("systemOverride") && row.systemOverride
            eff.systemMessage := row.systemOverride
        if row.HasOwnProp("reasoningOverride") && row.reasoningOverride
            eff.reasoning := row.reasoningOverride
        ; Temperature 0 is a valid override (bug #35): AHK treats the numeric
        ; 0 as falsy, so only NULL/empty string means "no override".
        if row.HasOwnProp("temperatureOverride") && row.temperatureOverride != "" {
            eff.temperature := row.temperatureOverride
            hasTemperatureOverride := true
        }
        if eff.assistantId && asst {
            if !eff.model
                eff.model := asst.baseModel
            if !eff.systemMessage
                eff.systemMessage := AssistantRepo._resolveSystemMessage(asst)
            if !eff.reasoning
                eff.reasoning := asst.reasoning
            if !hasTemperatureOverride
                eff.temperature := asst.temperature
            eff.assistantName := asst.HasOwnProp("name") ? asst.name : ""
            eff.assistantBaseModel := asst.baseModel
            eff.assistantDescription := asst.HasOwnProp("description") ? asst.description : ""
        }
        return eff
    }

    ; Restore a thread's settings into requestParams (thread load path).
    ; Previously _restoreThreadSettings in ChatSettings.ahk.
    static RestoreIntoRequestParams(threadId) {
        global requestParams, appDefaultModel
        ThreadSettings._ClearOverrides()
        settings := ChatDB.Thread_GetSettings(threadId)
        if !settings
            return
        asst := settings.assistantId ? AssistantRepo.GetFromSettings(settings.assistantId) : ""
        eff := ThreadSettings.ComputeEffective(settings, asst)
        requestParams["singleAPIModelName"] := eff.model != "" ? eff.model : appDefaultModel
        requestParams["systemOverride"] := eff.systemMessage
        requestParams["reasoningOverride"] := eff.reasoning
        requestParams["temperatureOverride"] := eff.temperature
        requestParams["fontSize"] := eff.fontSize
        requestParams["codeExecution"] := eff.codeExecution
        requestParams["webSearch"] := eff.webSearch
        if eff.assistantId
            requestParams["activeAssistantId"] := eff.assistantId
    }

    ; Clear all request-level overrides to default state.
    ; Previously _ClearRequestOverrides in ChatSettings.ahk.
    static _ClearOverrides() {
        global requestParams, appDefaultModel
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

    ; Serialize the current requestParams to the DB settings shape.
    ; Previously _CurrentSettingsObject in ChatSettings.ahk.
    static ToDbObject() {
        global requestParams, responseWindowFontSize, appDefaultModel
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

    ; Right-rail message payload from the current requestParams.
    ; Previously the body of postCurrentSettingsToWebView in ChatSettings.ahk.
    static ToThreadSettingsMessage() {
        global requestParams, responseWindowFontSize, models
        model := requestParams["singleAPIModelName"]
        systemMessage := requestParams.Has("systemOverride") ? requestParams["systemOverride"] : ""
        reasoning := requestParams.Has("reasoningOverride") ? requestParams["reasoningOverride"] : ""
        temperature := requestParams.Has("temperatureOverride") ? requestParams["temperatureOverride"] : ""
        defaultFontSize := IsSet(responseWindowFontSize) ? responseWindowFontSize : "17"
        fontSize := requestParams.Has("fontSize") ? requestParams["fontSize"] : defaultFontSize
        codeExecution := requestParams.Has("codeExecution") ? requestParams["codeExecution"] : false
        webSearch := requestParams.Has("webSearch") ? requestParams["webSearch"] : false

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

        thinkingLevels := []
        ; Single lookup accepting full or short model ids (the short-form id
        ; used to get no thinking levels in the right rail).
        modelMeta := ModelResolver.Lookup(models, model)
        if IsObject(modelMeta) && modelMeta.HasOwnProp("thinkingLevelMap") && IsObject(modelMeta.thinkingLevelMap) {
            for level in modelMeta.thinkingLevelMap
                thinkingLevels.Push(level)
        }

        return {
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
        }
    }
}
