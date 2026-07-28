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
        global requestParams, activeThreadId, chatDefaultModel

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
        if requestParams["singleAPIModelName"] != chatDefaultModel
            throw Error("Did not revert to default model. Got: " requestParams["singleAPIModelName"] " expected: " chatDefaultModel)

        ; Assert: reasoning was updated
        if requestParams["reasoningOverride"] != "low"
            throw Error("reasoningOverride was not updated. Got: " requestParams["reasoningOverride"])

        this._closeDb()
    }
}
