class ExternalApplicationsTest {
    NullableProjection_IsWireOnlyAndRestoresRequiredNulls() {
        properties := Map("path", Map("type", ["string", "null"]), "depth", Map("type", "integer", "minimum", 1),
            "optional", Map("type", ["string", "null"]), "items", Map("type", "array", "items", Map("type", "object", "properties", Map("end", Map("type", ["integer", "null"])), "required", ["end"])))
        schema := Map("type", "object", "properties", properties, "required", ["path", "depth", "items"], "additionalProperties", false)
        definition := Map("name", "example", "strict", true, "parameters", schema)
        before := jsongo.Stringify(definition)
        wire := ApplicationNullableArguments.Definitions([definition])[1]
        if jsongo.Stringify(definition) != before || wire["strict"] || wire["parameters"]["properties"]["path"]["type"] != "string"
            throw Error("Null compatibility mutated the original schema or failed to remove null from the wire")
        if wire["parameters"]["required"].Length != 2 || wire["parameters"]["properties"]["items"]["items"]["required"].Length
            throw Error("Required nullable object properties must be optional on the provider wire")
        args := ApplicationNativeTools.Arguments(Map("arguments", '{"depth":4,"items":[{}]}'), definition, true)
        json := ApplicationArgumentJson.Serialize(args)
        if !InStr(json, '"path":null') || !InStr(json, '"end":null') || args.Has("optional")
            throw Error("Original null semantics or optional omission changed: " json)
        rejected := false
        try ApplicationNativeTools.Arguments(Map("arguments", '{"items":[{}]}'), definition, true)
        catch Error as e
            rejected := InStr(e.Message, "depth")
        if !rejected
            throw Error("Non-nullable required parameters must remain required")
    }
    StreamDiagnostics_PreserveExactCurrentRoundAndArchiveLargeBodies() {
        this._setup()
        previousLog := ApiLogger.logFilePath
        file := this.directory "\provider.txt"
        logPath := this.directory "\diagnostics.json"
        try {
            threadId := ExternalApplications.Import(this._package())
            text := ""
            loop 4000
                text .= "payload Ω quoted `"text`"`r`n"
            raw := "data: " jsongo.Stringify(Map("type", "response.output_text.delta", "delta", text)) "`r`n`r`ndata: [DONE]`r`n"
            FileOpen(file, "w", "UTF-8-RAW").Write(raw)
            stream := {threadId: threadId, transport: "http", outputFile: file}
            entry := {request: "{}", response: '{"choices":[]}', status: "success"}
            ApplicationStreamDiagnostics.Attach(entry, stream)
            if jsongo.Parse(entry.response)["_ahkllm_stream_diagnostics"]["raw_response"] != raw
                throw Error("Raw SSE capture changed Unicode, quoting, line endings, or DONE marker")
            if ChatGptResponseLog.Normalize(entry.response) != entry.response
                throw Error("Response normalization must not consume embedded SSE diagnostics")
            ApiLogger.logFilePath := logPath
            ApiLogger.LogRequest(entry)
            saved := ApiLogger.ReadLogs()[1]
            if !saved.Has("response_archive")
                throw Error("Large diagnostic body must use the existing retained-payload archive")
            if jsongo.Parse(ApiLogBodies.Read(logPath, saved["response_archive"]))["_ahkllm_stream_diagnostics"]["raw_response"] != raw
                throw Error("API logging or archiving changed the raw stream")
            FileOpen(file, "w", "UTF-8-RAW").Write("data: SECOND ROUND`n")
            ApplicationStreamDiagnostics.Attach(entry, stream)
            if jsongo.Parse(entry.response)["_ahkllm_stream_diagnostics"]["raw_response"] != "data: SECOND ROUND`n"
                throw Error("Diagnostics must not accumulate previous rounds")
            ThreadLockRepo.Set(threadId, "fixture-salt", "fixture-hash", 600000)
            entry := {request: "PRIVATE REQUEST", response: "PRIVATE RESPONSE"}
            ApplicationStreamDiagnostics.Attach(entry, stream)
            if entry.request != "<hidden: locked chat>" || entry.response != "<hidden: locked chat>"
                throw Error("Locked diagnostic capture leaked provider data")
        } finally {
            ApiLogger.logFilePath := previousLog
            this._teardown()
        }
    }
    NativeArguments_RejectScalarsMalformedJsonAndSchemaMismatches() {
        threadId := "native-validation-unit"
        definition := Map("name", "echo_text", "parameters", Map("type", "object", "properties", Map("text", Map("type", "string")), "required", ["text"], "additionalProperties", false))
        try {
            for text in ['null', '[]', '"double encoded"', '{"text":', '{"text":17}', '{"text":"ok","extra":true}'] {
                ApplicationChat.active[threadId] := Map("tools", [definition])
                calls := [Map("name", "echo_text", "call_id", "valid", "arguments", '{"text":"must not execute"}'), Map("name", "echo_text", "call_id", "invalid", "arguments", text)]
                outputs := ApplicationNativeTools.RunRound(threadId, calls, (*) => "")
                if outputs.Length != 2 || !InStr(outputs[2]["output"], "Invalid arguments for echo_text") || !InStr(outputs[1]["output"], "batch was not executed")
                    throw Error("Invalid native batch was not rejected atomically: " text)
                if outputs[2]["call_id"] != "invalid" || !InStr(outputs[2]["output"], '"ok":false')
                    throw Error("Correction feedback lost its call ID or JSON boolean")
            }
            ApplicationChat.active[threadId] := Map("tools", [definition])
            call := Map("name", "echo_text", "call_id", "retry", "arguments", '"still invalid"')
            ApplicationNativeTools.RunRound(threadId, [call], (*) => "")
            ApplicationNativeTools.RunRound(threadId, [call], (*) => "")
            rejected := false
            try ApplicationNativeTools.RunRound(threadId, [call], (*) => "")
            catch Error as e
                rejected := InStr(e.Message, "3 invalid argument rounds")
            if !rejected
                throw Error("Invalid native arguments must have a bounded correction budget")
        } finally {
            if ApplicationChat.active.Has(threadId)
                ApplicationChat.active.Delete(threadId)
        }
    }

    NativeArguments_PreserveBooleanNullAndNestedTypes() {
        definition := Map("parameters", Map("type", "object", "properties", Map("flag", Map("type", "boolean"), "optional", Map("type", ["string", "null"])), "required", ["flag", "optional"], "additionalProperties", false))
        args := ApplicationNativeTools.Arguments(Map("arguments", '{"flag":false,"optional":null}'), definition)
        serialized := ApplicationArgumentJson.Serialize(args)
        if serialized != '{"flag":false,"optional":null}'
            throw Error("Native RPC boolean/null types were changed: " serialized)
        definition := Map("parameters", Map("type", "object", "properties", Map("items", Map("type", "array", "items", Map("type", "object", "properties", Map("path", Map("type", "string")), "required", ["path"])))))
        rejected := false
        try ApplicationNativeTools.Arguments(Map("arguments", '{"items":["bad"]}'), definition)
        catch Error as e
            rejected := InStr(e.Message, "arguments.items[1]")
        if !rejected
            throw Error("Native nested arrays must reject strings where FWB expects objects")
    }
    HttpReplay_PreservesReasoningWithParallelToolCalls() {
        items := [Map("type", "message", "role", "assistant", "content", [Map("type", "output_text", "text", "public text")], "reasoning_content", "exact provider reasoning"),
            Map("type", "function_call", "call_id", "a", "name", "first", "arguments", "{}"),
            Map("type", "function_call", "call_id", "b", "name", "second", "arguments", "{}"),
            Map("type", "function_call_output", "call_id", "a", "output", "first result"),
            Map("type", "function_call_output", "call_id", "b", "output", "second result")]
        messages := ApplicationWire.ChatMessages(items)
        if messages.Length != 3 || messages[1].tool_calls.Length != 2 || messages[1].reasoning_content != "exact provider reasoning" || messages[1].content != "public text"
            throw Error("Reasoning, public content, or parallel native calls were lost")
        responses := ApplicationWire.ResponsesInput(items)
        if responses[1].Has("reasoning_content") || !items[1].Has("reasoning_content") || responses[2]["call_id"] != "a"
            throw Error("Switching to Responses must strip HTTP-only fields without altering durable history")
    }
    HttpContinuation_LogsCurlRelaunchBoundary() {
        source := FileRead(A_ScriptDir "\..\chat\applications\ApplicationHttpTools.ahk")
        launching := InStr(source, "[STREAM] Application HTTP continuation launching")
        runCall := InStr(source, 'Run(command, , "Hide", &pid)')
        failed := InStr(source, "[STREAM] Application HTTP continuation launch failed")
        started := InStr(source, "[STREAM] Application HTTP continuation started")
        if !launching || !runCall || !failed || !started || !(launching < runCall && runCall < failed && failed < started)
            throw Error("Application HTTP continuation must trace launch, launch failure, and successful PID assignment around cURL Run()")
    }

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

    AwaitFirstMessage_PersistsEmptyChatAndAttachesContextOnce() {
        this._setup()
        try {
            package := this._package()
            package["await_first_message"] := true
            threadId := ExternalApplications.Import(package)
            if ChatDB.Msg_GetActivePath(threadId).Length
                throw Error("Prepared chat fabricated a user message")
            ChatDB.Close()
            ChatDB.Open(this.directory "\chat.db")
            if ExternalApplications.Import(package) != threadId || ApplicationRepo.Session(threadId).initial_input != package["initial_input"]
                throw Error("Empty prepared chat did not survive reopening")
            text := "First paragraph.`n`nSecond paragraph."
            first := ChatDB.Msg_Insert({thread_id: threadId, role: "user", content: text})
            path := ChatDB.Msg_GetActivePath(threadId)
            replay := ApplicationRepo.Replay(path)
            if path.Length != 1 || path[1].content != text || !InStr(replay[1]["content"][1]["text"], package["initial_input"])
                throw Error("First request lost author paragraphs or prepared context")
            ChatDB.Msg_Insert({thread_id: threadId, role: "user", content: "Follow-up", parent_id: first})
            replay := ApplicationRepo.Replay(ChatDB.Msg_GetActivePath(threadId))
            if replay.Length != 2 || InStr(replay[2]["content"][1]["text"], package["initial_input"])
                throw Error("Prepared context was repeated on a follow-up")
            fork := ChatDB.Msg_ForkThread(threadId, first)
            if ApplicationRepo.Session(fork).initial_input != package["initial_input"]
                throw Error("Fork lost prepared session context")
        } finally this._teardown()
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
