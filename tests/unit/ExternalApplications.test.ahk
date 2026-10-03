class ExternalApplicationsTest {
    static __New() => RegisterTestClass("ExternalApplicationsTest")

    _setup() {
        this.previousData := AppInfo.DataDir
        this.directory := A_Temp "\AhkLLM_External_Test_" ChatDB._UUID()
        DirCreate(this.directory)
        AppInfo.DataDir := this.directory
        if ChatDB.isOpen
            ChatDB.Close()
        ChatDB.Open(this.directory "\chat.db")
        this.profile := Map("id", "example", "name", "Example application", "command", [A_AhkPath, A_ScriptDir "\fixtures\external-application.ahk"], "timeout_seconds", 5)
        ExternalApplications.Register(this.profile, false)
    }

    _teardown() {
        ApplicationChat.active.Clear()
        ChatDB.Close()
        AppInfo.DataDir := this.previousData
        try DirDelete(this.directory, true)
    }

    _package() => Map("protocol", "ahkllm.external-applications", "version", 1, "application_id", "example", "request_id", ChatDB._UUID(), "title", "Example session", "instructions", "Example instructions", "message", "Visible task", "initial_input", "COMPLETE PRELOADED CONTEXT", "state", Map("checkpoint", 0))

    Import_IsIdempotentAndKeepsFullInitialInput() {
        this._setup()
        try {
            package := this._package()
            threadId := ExternalApplications.Import(package)
            if ExternalApplications.Import(package) != threadId
                throw Error("Duplicate launch created another thread")
            path := ChatDB.Msg_GetActivePath(threadId)
            if path.Length != 1 || path[1].content != "Visible task"
                throw Error("Initial visible message was not persisted")
            replay := ApplicationRepo.Replay(path)
            if replay[1]["content"][1]["text"] != "COMPLETE PRELOADED CONTEXT"
                throw Error("Complete initial context was lost")
        } finally this._teardown()
    }

    Import_UsesConfiguredModelWithoutChangingExistingRuntime() {
        global newChatStartsWith, requestParams
        previous := IsSet(newChatStartsWith) ? newChatStartsWith : ""
        this._setup()
        try {
            runtimeModel := requestParams["singleAPIModelName"]
            newChatStartsWith := "openai/gpt-5-mini"
            package := this._package()
            threadId := ExternalApplications.Import(package)
            settings := ChatDB.Thread_GetSettings(threadId)
            if settings.modelOverride != newChatStartsWith || settings.systemOverride != package["instructions"]
                throw Error("Imported chat lost its model default or application instructions")
            if requestParams["singleAPIModelName"] != runtimeModel
                throw Error("Import changed the currently displayed chat's runtime model")
            newChatStartsWith := "deepseek/deepseek-v4-flash"
            if ExternalApplications.Import(package) != threadId || ChatDB.Thread_GetSettings(threadId).modelOverride != "openai/gpt-5-mini"
                throw Error("Reopening a retained application chat changed its model")
        } finally {
            newChatStartsWith := previous
            this._teardown()
        }
    }

    Import_UsesConfiguredAssistantAndKeepsTaskInstructions() {
        global newChatStartsWith, assistants
        previous := IsSet(newChatStartsWith) ? newChatStartsWith : ""
        previousAssistants := assistants
        this._setup()
        try {
            assistants := [{id:"import-default",name:"Default",baseModel:"openai/gpt-5-mini",systemMessage:"Assistant prompt",reasoning:"medium",temperature:""}]
            newChatStartsWith := "asst:import-default"
            package := this._package()
            threadId := ExternalApplications.Import(package)
            settings := ChatDB.Thread_GetSettings(threadId)
            effective := ThreadSettings.ComputeEffective(settings, assistants[1])
            if settings.assistantId != "import-default" || effective.model != "openai/gpt-5-mini" || effective.reasoning != "medium"
                throw Error("Imported chat ignored the configured assistant defaults")
            if effective.systemMessage != package["instructions"]
                throw Error("Assistant prompt replaced application task instructions")
        } finally {
            assistants := previousAssistants
            newChatStartsWith := previous
            this._teardown()
        }
    }

    Fork_PreservesConnectionCheckpointsAndExactToolHistory() {
        this._setup()
        try {
            threadId := ExternalApplications.Import(this._package())
            parent := ChatDB.Msg_GetActivePath(threadId)[1].id
            assistant := ChatDB.Msg_Insert({thread_id: threadId, role: "assistant", content: "Answer", parent_id: parent})
            output := [Map("type", "function_call", "call_id", "call-1", "name", "echo_text", "arguments", "{}"), Map("type", "function_call_output", "call_id", "call-1", "output", "immutable-result"), Map("type", "message", "role", "assistant", "content", [Map("type", "output_text", "text", "Answer")])]
            ApplicationRepo.SaveNode(assistant, Map("checkpoint", 1), output)
            fork := ChatDB.Msg_ForkThread(threadId, assistant)
            if ApplicationRepo.Session(fork).application_id != "example" || ApplicationRepo.State(fork)["checkpoint"] != 1
                throw Error("Fork lost the external checkpoint")
            replay := ApplicationRepo.Replay(ChatDB.Msg_GetActivePath(fork))
            if replay.Length != 4 || replay[3]["output"] != "immutable-result"
                throw Error("Fork lost immutable tool output")
        } finally this._teardown()
    }

    EditingAuthorAction_DoesNotInheritApprovalOrDeferredContext() {
        this._setup()
        try {
            threadId := ExternalApplications.Import(this._package())
            parent := ChatDB.Msg_GetActivePath(threadId)[1].id
            action := ChatDB.Msg_Insert({thread_id: threadId, role: "user", content: "Approve", parent_id: parent})
            ApplicationRepo.SaveNode(action, Map("checkpoint", 2), [Map("role", "user", "content", [Map("type", "input_text", "text", "DEFERRED PRIVATE CONTEXT")])], "action")
            edited := ChatDB.Msg_Insert({thread_id: threadId, role: "user", content: "Actually, discuss more", parent_id: parent})
            ApplicationRepo.CopyEditedNode(action, edited, "Actually, discuss more", "user")
            if ApplicationRepo.State(threadId)["checkpoint"] != 0
                throw Error("Edited approval inherited later permissions")
            if InStr(jsongo.Stringify(ApplicationRepo.Replay(ChatDB.Msg_GetActivePath(threadId))), "DEFERRED PRIVATE CONTEXT")
                throw Error("Edited approval leaked deferred context")
        } finally this._teardown()
    }

    ProcessTransport_HandlesUnicodeAndQuotedArguments() {
        this._setup()
        try {
            text := "שלום Ω 🙂 quoted `"text`""
            response := ApplicationProcess.Call(this.profile, "echo", Map("text", text))
            if response["text"] != text
                throw Error("Subprocess transport corrupted UTF-8")
            if ApplicationProcess.Quote("C:\path with spaces\") != '"C:\path with spaces\\"'
                throw Error("Command argument quoting lost a trailing backslash")
        } finally this._teardown()
    }

    PermanentDeletion_RemovesIntegrationRecords() {
        this._setup()
        try {
            threadId := ExternalApplications.Import(this._package())
            ChatDB.Thread_Delete(threadId)
            if ChatDB.db.Query("SELECT * FROM application_sessions;").count || ChatDB.db.Query("SELECT * FROM application_nodes;").count
                throw Error("Deleted chat left stale integration records")
        } finally this._teardown()
    }

    TextSegmentation_IsByteBoundedAndLosslessForUnicode() {
        text := "prefix🙂שלום`n끝suffix"
        parts := ApplicationWire.InputParts(text, 8)
        for part in parts
            if StrPut(part["text"], "UTF-8") - 1 > 8
                throw Error("Input segment exceeded its UTF-8 bound")
        if ApplicationWire.Text(parts) != text
            throw Error("Input segmentation changed Unicode or whitespace")
    }

    AttachmentReplay_PreservesContextWithoutDuplicatesAndHonorsRemoval() {
        this._setup()
        try {
            threadId := ExternalApplications.Import(this._package())
            path := ChatDB.Msg_GetActivePath(threadId)
            input := [{role: "user", _msgId: path[1].id, content: [{type: "text", text: "Visible task"}, {type: "text", text: "EXTRACTED DOCUMENT"}, {type: "image_url", image_url: {url: "data:image/png;base64,AA=="}}]}]
            first := ApplicationRepo.Replay(path, input)
            second := ApplicationRepo.Replay(path, input)
            if first[1]["content"].Length != 3 || second[1]["content"].Length != 3
                throw Error("Attachment replay dropped or duplicated context: " jsongo.Stringify(first) " / " jsongo.Stringify(second))
            projected := ApplicationWire.ChatMessages(first)
            if !(projected[1].content is Array) || projected[1].content[3]["type"] != "image_url"
                throw Error("HTTP projection dropped an image")
            removed := ApplicationRepo.Replay(path, [{role: "user", _msgId: path[1].id, content: "Visible task"}])
            if removed[1]["content"].Length != 1 || removed[1]["content"][1]["text"] != "COMPLETE PRELOADED CONTEXT"
                throw Error("Removing attachments lost initial context or retained removed data")
        } finally this._teardown()
    }

    DeletingSourceChat_DoesNotReleaseForkCheckpoints() {
        this._setup()
        try {
            threadId := ExternalApplications.Import(this._package())
            messageId := ChatDB.Msg_GetActivePath(threadId)[1].id
            fork := ChatDB.Msg_ForkThread(threadId, messageId)
            ChatDB.Thread_Delete(threadId)
            if ChatDB.db.Query("SELECT * FROM application_release_queue;").count
                throw Error("A retained fork's checkpoint was queued for release")
            ChatDB.Thread_Delete(fork)
            if !ChatDB.db.Query("SELECT * FROM application_release_queue;").count
                throw Error("Unreferenced checkpoint was not queued for cleanup")
            ExternalApplications.FlushReleases()
            if ChatDB.db.Query("SELECT * FROM application_release_queue;").count
                throw Error("Released checkpoint stayed in the cleanup queue")
        } finally this._teardown()
    }

    ConnectionManagement_PersistsEditsAndDisconnectKeepsChatRecords() {
        this._setup()
        try {
            threadId := ExternalApplications.Import(this._package())
            updated := this.profile.Clone()
            updated["name"] := "Renamed example"
            updated["timeout_seconds"] := 45
            ExternalApplications.Register(updated, false)
            if ExternalApplications.Profiles()["example"]["name"] != "Renamed example"
                throw Error("Connection edit did not persist")
            ExternalApplications.Disconnect("example")
            if ExternalApplications.Profiles().Has("example")
                throw Error("Connection was not removed")
            if !ApplicationRepo.Session(threadId) || !ChatDB.Msg_GetActivePath(threadId).Length
                throw Error("Disconnect deleted historical chat data")
        } finally this._teardown()
    }

    ConnectionManagement_RejectsChangesDuringActiveTurn() {
        this._setup()
        try {
            threadId := ExternalApplications.Import(this._package())
            ApplicationChat.active[threadId] := Map()
            rejected := false
            try ExternalApplications.Disconnect("example")
            catch Error as e
                rejected := InStr(e.Message, "running tasks")
            if !rejected || !ExternalApplications.Profiles().Has("example")
                throw Error("Active connection was modified")
        } finally this._teardown()
    }
}
