; ======================================================
; SearchToolExecutor.test.ahk — web_search tool execution + follow-up staging
; ======================================================

class SearchToolExecutorTest {

    static __New() {
        RegisterTestClass("SearchToolExecutorTest")
    }

    _setupDb() {
        if ChatDB.isOpen {
            oldPath := ChatDB.dbPath
            ChatDB.Close()
            try FileDelete(oldPath)
        }
        ChatDB.Open(A_Temp "\test_ste_" A_TickCount "_" Random(1000, 999999) ".db")
    }

    _teardownDb() {
        if ChatDB.isOpen {
            dbPath := ChatDB.dbPath
            ChatDB.Close()
            try FileDelete(dbPath)
        }
    }

    Execute_BuildsAssistantAndToolMessages() {
        providerInfo := { providerKey: "openai", modelName: "gpt-5-mini", apiKey: "k", endpoint: "http://x/chat/completions" }
        toolCalls := [{
            id: "call_1",
            name: "web_search",
            arguments: "{`"query`":`"latest news`"}"
        }]
        ; Inject a test runner so no network call happens in the unit test.
        exec := SearchToolExecutor.Execute(toolCalls, providerInfo, (q) => "answer for " . q)

        if exec.toolMessages.Length != 2
            throw Error("expected assistant + tool messages, got " exec.toolMessages.Length)
        asst := exec.toolMessages[1]
        toolMsg := exec.toolMessages[2]
        if asst.role != "assistant" || asst.tool_calls.Length != 1
            throw Error("assistant tool_calls message wrong")
        if asst.tool_calls[1].function.name != "web_search" || asst.tool_calls[1].id != "call_1"
            throw Error("tool call payload wrong")
        if toolMsg.role != "tool" || toolMsg.tool_call_id != "call_1"
            throw Error("tool result message wrong")
        if !InStr(toolMsg.content, "answer for latest news")
            throw Error("tool result missing injected answer: " toolMsg.content)
        if !InStr(exec.contextText, "[Web search: latest news]")
            throw Error("context text missing marker: " exec.contextText)
    }

    Execute_UnknownTool_ReturnsErrorResult() {
        providerInfo := { providerKey: "openai", modelName: "gpt-5-mini", apiKey: "k", endpoint: "http://x/chat/completions" }
        toolCalls := [{ id: "call_x", name: "delete_all_files", arguments: "{}" }]
        exec := SearchToolExecutor.Execute(toolCalls, providerInfo)
        if !InStr(exec.toolMessages[2].content, "not available")
            throw Error("expected unavailable-tool error: " exec.toolMessages[2].content)
    }

    QueueFollowUp_InsertsContextAndStagesMessages() {
        global requestParams, activeThreadId
        this._setupDb()
        ChatDB.Thread_Create("Queue")
        threads := ChatDB.Thread_List()
        activeThreadId := threads[threads.Length].id
        u1Id := ChatDB.Msg_Insert({ thread_id: activeThreadId, role: "user", content: "q" })

        requestParams := Map()
        exec := {
            toolMessages: [{ role: "assistant", content: "", tool_calls: [] }],
            contextText: "[Web search: x]`n`nresults"
        }
        ctxId := SearchToolExecutor.QueueFollowUp(exec, activeThreadId, u1Id, 1)
        if !ctxId
            throw Error("expected a context message id")
        path := ChatDB.Msg_GetActivePath(activeThreadId)
        if path.Length != 2 || path[2].role != "user" || path[2].id != ctxId
            throw Error("search context not chained after the user message")
        if requestParams["_toolLoopCount"] != 1
            throw Error("tool loop count not staged")
        if requestParams["_pendingToolMessages"].Length != 1
            throw Error("pending tool messages not staged")

        activeThreadId := ""
        this._teardownDb()
    }
}
