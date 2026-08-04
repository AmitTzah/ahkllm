; ======================================================
; ChatSettings.test.ahk — Unit tests for ChatSettings module
;
; Tests: handleModelSettingsUpdate preserves assistant
;        when only side settings change (thinking level, etc.)
; ======================================================

class ChatSettingsTest {

    static __New() {
        RegisterTestClass("ChatSettingsTest")
    }

    _openDb() {
        if ChatDB.isOpen {
            oldPath := ChatDB.dbPath
            ChatDB.Close()
            try FileDelete(oldPath)
        }
        ChatDB.Open(A_Temp "\test_chat_settings_" A_TickCount ".db")
    }

    _closeDb() {
        if ChatDB.isOpen {
            dbPath := ChatDB.dbPath
            ChatDB.Close()
            try FileDelete(dbPath)
        }
    }

    test_preservesAssistant_whenOnlyReasoningChanges() {
        global requestParams, activeThreadId, assistants

        this._openDb()

        ; Stub assistants global (no DB seeding needed)
        assistants := [{id: "asst-1", name: "Test Asst", baseModel: "deepseek/test", systemMessage: "Hello", reasoning: "", temperature: "", isDefault: true}]
        asst := assistants[1]

        ; Set up requestParams with an active assistant
        requestParams["activeAssistantId"] := asst.id
        requestParams["singleAPIModelName"] := asst.baseModel
        requestParams["systemOverride"] := asst.systemMessage
        requestParams["reasoningOverride"] := ""
        requestParams["temperatureOverride"] := ""

        ; Simulate user changing thinking level from right sidebar
        ; (model="" because assistant mode doesn't populate model field)
        parsed := jsongo.Parse('{"model":"","systemMessage":"","reasoning":"high","temperature":""}')
        handleModelSettingsUpdate(parsed)

        ; Assert: assistant should still be active
        if !requestParams.Has("activeAssistantId") || !requestParams["activeAssistantId"]
            throw Error("activeAssistantId was cleared when only reasoning changed")
        if requestParams["activeAssistantId"] != asst.id
            throw Error("activeAssistantId changed to different assistant")

        ; Assert: reasoning was updated
        if requestParams["reasoningOverride"] != "high"
            throw Error("reasoningOverride was not updated. Got: " requestParams["reasoningOverride"])

        ; Assert: model was not changed
        if requestParams["singleAPIModelName"] != asst.baseModel
            throw Error("singleAPIModelName was changed. Got: " requestParams["singleAPIModelName"] " expected: " asst.baseModel)

        this._closeDb()
    }

    test_clearsAssistant_whenModelExplicitlyChanged() {
        global requestParams, activeThreadId, assistants

        this._openDb()

        assistants := [{id: "asst-1", name: "Test Asst", baseModel: "deepseek/test", systemMessage: "Hello", reasoning: "", temperature: "", isDefault: true}]
        asst := assistants[1]

        ; Set up requestParams with an active assistant
        requestParams["activeAssistantId"] := asst.id
        requestParams["singleAPIModelName"] := asst.baseModel
        requestParams["systemOverride"] := asst.systemMessage
        requestParams["reasoningOverride"] := ""
        requestParams["temperatureOverride"] := ""

        ; Simulate user explicitly picking a model (non-empty model field)
        parsed := jsongo.Parse('{"model":"deepseek/deepseek-v4-flash","systemMessage":"","reasoning":"","temperature":""}')
        handleModelSettingsUpdate(parsed)

        ; Assert: assistant should be cleared
        if requestParams.Has("activeAssistantId")
            throw Error("activeAssistantId was NOT cleared when model explicitly changed")

        ; Assert: model was updated
        if requestParams["singleAPIModelName"] != "deepseek/deepseek-v4-flash"
            throw Error("singleAPIModelName was not updated. Got: " requestParams["singleAPIModelName"])

        this._closeDb()
    }

    test_revertsToDefaultModel_whenNoAssistantAndNoModel() {
        global requestParams, activeThreadId, appDefaultModel

        this._openDb()

        ; Clean state — no assistant, no model override
        requestParams.Delete("activeAssistantId")
        requestParams["singleAPIModelName"] := "some-other-model"
        requestParams["systemOverride"] := ""
        requestParams["reasoningOverride"] := ""
        requestParams["temperatureOverride"] := ""

        ; Simulate settings change with empty model and no assistant
        parsed := jsongo.Parse('{"model":"","systemMessage":"","reasoning":"low","temperature":""}')
        handleModelSettingsUpdate(parsed)

        ; Assert: reverts to default model
        if requestParams["singleAPIModelName"] != appDefaultModel
            throw Error("Did not revert to default model. Got: " requestParams["singleAPIModelName"] " expected: " appDefaultModel)

        ; Assert: reasoning was updated
        if requestParams["reasoningOverride"] != "low"
            throw Error("reasoningOverride was not updated. Got: " requestParams["reasoningOverride"])

        this._closeDb()
    }

    ; Regression: right-rail Advanced toggles (Code Execution / Web Search)
    ; used to do nothing — only a CSS class changed. They must be stored,
    ; round-tripped, and persisted with the thread as stubs.
    test_advancedToggles_storedAndPersisted() {
        global requestParams, activeThreadId, assistants

        this._openDb()

        assistants := [{id: "asst-1", name: "Test Asst", baseModel: "deepseek/test", systemMessage: "Hello", reasoning: "", temperature: "", isDefault: true}]
        if requestParams.Has("activeAssistantId")
            requestParams.Delete("activeAssistantId")
        requestParams["singleAPIModelName"] := "deepseek/deepseek-v4-flash"

        ChatDB.Thread_Create("Toggle Thread")
        threads := ChatDB.Thread_List()
        activeThreadId := threads[threads.Length].id

        parsed := jsongo.Parse('{"model":"deepseek/deepseek-v4-flash","systemMessage":"","reasoning":"","temperature":"","codeExecution":false,"webSearch":true}')
        handleModelSettingsUpdate(parsed)

        ; In-memory flags
        if requestParams["codeExecution"] != false
            throw Error("codeExecution should be false in requestParams")
        if requestParams["webSearch"] != true
            throw Error("webSearch was not stored in requestParams")

        ; Round-trip through the settings object
        obj := _CurrentSettingsObject()
        if obj.codeExecution != false || obj.webSearch != true
            throw Error("_CurrentSettingsObject does not carry the advanced toggles")

        ; Persisted to the thread and restored by Thread_GetSettings
        saved := ChatDB.Thread_GetSettings(activeThreadId)
        if saved.codeExecution != false || saved.webSearch != true
            throw Error("advanced toggles did not persist to the thread: " jsongo.Stringify(saved))

        activeThreadId := ""
        this._closeDb()
    }

    test_applyNewChatDefault_appDefault_keepsChatDefaultModel() {
        global newChatStartsWith, requestParams, assistants, appDefaultModel

        oldDefault := newChatStartsWith
        oldAsst := assistants
        oldModel := requestParams["singleAPIModelName"]
        assistants := []
        newChatStartsWith := ""
        try {
            applied := _applyNewChatDefault()
            if applied
                throw Error("App default should not apply an assistant/model")
            if requestParams["singleAPIModelName"] != oldModel
                throw Error("App default must leave the current default model intact")
        } finally {
            newChatStartsWith := oldDefault
            assistants := oldAsst
            requestParams["singleAPIModelName"] := oldModel
        }
    }

    test_applyNewChatDefault_assistant_applies() {
        global newChatStartsWith, requestParams, assistants

        oldDefault := newChatStartsWith
        oldAsst := assistants
        oldModel := requestParams["singleAPIModelName"]
        oldAsstId := requestParams.Has("activeAssistantId") ? requestParams["activeAssistantId"] : ""
        assistants := [{ id: "asst-9", name: "Nine", baseModel: "openai/gpt-5-mini", systemMessage: "sys", reasoning: "low", temperature: "0.7" }]
        newChatStartsWith := "asst:asst-9"
        try {
            applied := _applyNewChatDefault()
            if !applied
                throw Error("Assistant default should apply")
            if requestParams["activeAssistantId"] != "asst-9"
                throw Error("Assistant default should mark the assistant active")
            if requestParams["singleAPIModelName"] != "openai/gpt-5-mini"
                throw Error("Assistant default should apply its base model")
            if requestParams["systemOverride"] != "sys"
                throw Error("Assistant default should apply its system message")
            if requestParams["temperatureOverride"] != "0.7"
                throw Error("Assistant default should apply its temperature")
        } finally {
            newChatStartsWith := oldDefault
            assistants := oldAsst
            requestParams["singleAPIModelName"] := oldModel
            if oldAsstId = ""
                requestParams.Delete("activeAssistantId")
            else
                requestParams["activeAssistantId"] := oldAsstId
            requestParams["systemOverride"] := ""
            requestParams["temperatureOverride"] := ""
        }
    }

    test_applyNewChatDefault_model_applies_andClearsAssistant() {
        global newChatStartsWith, requestParams, assistants

        oldDefault := newChatStartsWith
        oldAsst := assistants
        oldModel := requestParams["singleAPIModelName"]
        requestParams["activeAssistantId"] := "asst-stale"
        assistants := [{ id: "asst-1", name: "One", baseModel: "deepseek/deepseek-v4-flash", systemMessage: "", reasoning: "", temperature: "" }]
        newChatStartsWith := "openai/gpt-5-mini"
        try {
            applied := _applyNewChatDefault()
            if !applied
                throw Error("Model default should apply")
            if requestParams["singleAPIModelName"] != "openai/gpt-5-mini"
                throw Error("Model default should set the model, got '" requestParams["singleAPIModelName"] "'")
            if requestParams.Has("activeAssistantId")
                throw Error("Model default should clear any active assistant")
        } finally {
            newChatStartsWith := oldDefault
            assistants := oldAsst
            requestParams["singleAPIModelName"] := oldModel
            if requestParams.Has("activeAssistantId")
                requestParams.Delete("activeAssistantId")
        }
    }

    ; Regression (bug #47): per-thread overrides must survive a reload even
    ; when an assistant is active. _restoreThreadSettings used to apply the
    ; stored overrides and THEN overwrite all three with the assistant's
    ; values, so any per-thread edit (system prompt, thinking, temperature)
    ; made while an assistant was active silently vanished on the next load.
    test_restoreThreadSettings_keepsPerThreadOverrides_whenAssistantActive() {
        global requestParams, activeThreadId, assistants

        this._openDb()

        assistants := [{
            id: "asst-47", name: "Test Asst", baseModel: "deepseek/test",
            systemMessage: "assistant system", systemMessageFile: "",
            reasoning: "high", temperature: "0.3"
        }]

        threadId := ChatDB.Thread_Create("Override Thread")
        ChatDB.Thread_UpdateSettings(threadId, {
            assistantId: "asst-47",
            systemOverride: "user override",
            reasoningOverride: "low",
            temperatureOverride: "0.9"
        })

        _restoreThreadSettings(threadId)

        if !requestParams.Has("activeAssistantId") || requestParams["activeAssistantId"] != "asst-47"
            throw Error("assistant should stay active")
        if requestParams["systemOverride"] != "user override"
            throw Error("systemOverride was overwritten by the assistant: " requestParams["systemOverride"])
        if requestParams["reasoningOverride"] != "low"
            throw Error("reasoningOverride was overwritten by the assistant: " requestParams["reasoningOverride"])
        if requestParams["temperatureOverride"] != "0.9"
            throw Error("temperatureOverride was overwritten by the assistant: " requestParams["temperatureOverride"])

        this._closeDb()
    }

    ; The fallback must stay intact: with NO per-thread overrides, the
    ; assistant's values (system message, reasoning, temperature) still apply
    ; when the thread reloads.
    test_restoreThreadSettings_fallsBackToAssistantDefaults() {
        global requestParams, activeThreadId, assistants

        this._openDb()

        assistants := [{
            id: "asst-47b", name: "Test Asst", baseModel: "deepseek/test",
            systemMessage: "assistant system", systemMessageFile: "",
            reasoning: "high", temperature: "0.3"
        }]

        threadId := ChatDB.Thread_Create("Assistant Thread")
        ChatDB.Thread_UpdateSettings(threadId, { assistantId: "asst-47b" })

        _restoreThreadSettings(threadId)

        if !requestParams.Has("activeAssistantId") || requestParams["activeAssistantId"] != "asst-47b"
            throw Error("assistant should be active")
        if requestParams["systemOverride"] != "assistant system"
            throw Error("assistant system message should apply when no override: " requestParams["systemOverride"])
        if requestParams["reasoningOverride"] != "high"
            throw Error("assistant reasoning should apply when no override: " requestParams["reasoningOverride"])
        if requestParams["temperatureOverride"] != "0.3"
            throw Error("assistant temperature should apply when no override: " requestParams["temperatureOverride"])

        this._closeDb()
    }
}
