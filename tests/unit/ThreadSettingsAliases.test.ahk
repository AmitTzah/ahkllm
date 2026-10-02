; Legacy model aliases remain stored until the user selects another model.
class ThreadSettingsAliasesTest {
    static __New() {
        RegisterTestClass("ThreadSettingsAliasesTest")
    }

    LegacyAlias_SettingsFlushPreservesStoredModel() {
        global requestParams, activeThreadId
        oldParams := requestParams
        oldActive := activeThreadId
        databaseWasOpen := ChatDB.isOpen
        oldDatabasePath := databaseWasOpen ? ChatDB.dbPath : ""
        if databaseWasOpen
            ChatDB.Close()
        databasePath := A_Temp "\test_thread_aliases_" A_TickCount "_" Random(1000, 999999) ".db"
        try {
            ChatDB.Open(databasePath)
            activeThreadId := ChatDB.Thread_Create("Legacy model alias")
            ChatDB.Thread_UpdateSettings(activeThreadId, { modelOverride: "codex/gpt-5.6-luna" })
            requestParams := Map()
            ThreadSettings.RestoreIntoRequestParams(activeThreadId)
            if requestParams["singleAPIModelName"] != "chatgpt/gpt-5.6-luna"
                throw Error("Legacy model must route through the canonical runtime provider")
            handleModelSettingsUpdate(Map("model", "chatgpt/gpt-5.6-luna", "reasoning", "high"))
            saved := ChatDB.Thread_GetSettings(activeThreadId)
            if saved.modelOverride != "codex/gpt-5.6-luna" || saved.reasoningOverride != "high"
                throw Error("Settings flush must save side settings without rewriting the legacy model")
            handleModelSettingsUpdate(Map("model", "openai/gpt-5-mini"))
            if ChatDB.Thread_GetSettings(activeThreadId).modelOverride != "openai/gpt-5-mini"
                throw Error("Selecting a different model must replace the legacy override")
            requestParams["singleAPIModelName"] := "chatgpt/gpt-5.6-luna"
            newThreadId := ChatDB.Thread_Create("New canonical chat")
            _saveCurrentSettingsToThread(newThreadId)
            if ChatDB.Thread_GetSettings(newThreadId).modelOverride != "chatgpt/gpt-5.6-luna"
                throw Error("New threads must save the canonical model independently of the active thread")
        } finally {
            requestParams := oldParams
            activeThreadId := oldActive
            ChatDB.Close()
            try FileDelete(databasePath)
            if databaseWasOpen
                ChatDB.Open(oldDatabasePath)
        }
    }
}
