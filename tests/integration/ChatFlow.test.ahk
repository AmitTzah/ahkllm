; ======================================================
; ChatFlow.test.ahk — Integration tests for full chat flow
;
; Tests: Thread create → insert messages → get path →
;        token stats → delete → stats update across branches
; ======================================================

class ChatFlowTest {

    static __New() {
        RegisterTestClass("ChatFlowTest")
    }

    _setup() {
        if ChatDB.isOpen {
            oldPath := ChatDB.dbPath
            ChatDB.Close()
            try FileDelete(oldPath)
        }
        ChatDB.Open(A_Temp "\test_flow_" A_TickCount ".db")
        return ChatDB.Thread_Create("Flow Test")
    }

    _teardown() {
        if ChatDB.isOpen {
            dbPath := ChatDB.dbPath
            ChatDB.Close()
            try FileDelete(dbPath)
        }
    }

    ; --------------------
    ; Full send→DB→path→stats pipeline
    ; --------------------

    FullPipeline_InsertPathStats() {
        threadId := this._setup()

        ; Insert messages with proper parent chain
        sysId := ChatDB.Msg_Insert({thread_id: threadId, role: "system", content: "You are helpful."})
        usr1Id := ChatDB.Msg_Insert({thread_id: threadId, role: "user", content: "Hello", parent_id: sysId})
        asst1Id := ChatDB.Msg_Insert({thread_id: threadId, role: "assistant", content: "Hi!", model: "deepseek-v4-flash", parent_id: usr1Id, token_count: 18})
        usr2Id := ChatDB.Msg_Insert({thread_id: threadId, role: "user", content: "What is 2+2?", parent_id: asst1Id})
        asst2Id := ChatDB.Msg_Insert({thread_id: threadId, role: "assistant", content: "4", model: "deepseek-v4-flash", parent_id: usr2Id, token_count: 26})

        ; Verify path length
        path := ChatDB.Msg_GetActivePath(threadId)
        if path.Length != 5
            throw Error("Expected 5 messages in path, got " path.Length)

        ; Verify message order
        expectedRoles := ["system", "user", "assistant", "user", "assistant"]
        for i, msg in path {
            if msg.role != expectedRoles[i]
                throw Error("Message " i " expected role '" expectedRoles[i] "', got '" msg.role "'")
        }

        ; Verify stats — context used should be the last assistant's total_tokens
        stats := ChatDB.Msg_GetThreadStats(threadId)
        if stats.activePathTokens <= 0
            throw Error("Expected activePathTokens > 0, got " stats.activePathTokens)
        totalTokens := stats.cumulativeInputTokens + stats.cumulativeOutputTokens
        if totalTokens <= 0
            throw Error("Expected cumulativeInput+Output > 0, got " totalTokens)
        if stats.cumulativeCachedTokens < 0
            throw Error("Expected cumulativeCachedTokens >= 0")

        this._teardown()
    }

    ; --------------------
    ; Delete → path changes
    ; --------------------

    HardDelete_ChangesPath() {
        threadId := this._setup()
        sysId := ChatDB.Msg_Insert({thread_id: threadId, role: "system", content: "s"})
        usrId := ChatDB.Msg_Insert({thread_id: threadId, role: "user", content: "u", parent_id: sysId})
        asstId := ChatDB.Msg_Insert({thread_id: threadId, role: "assistant", content: "a", parent_id: usrId})

        ChatDB.Msg_HardDelete(asstId)
        path := ChatDB.Msg_GetActivePath(threadId)
        if path.Length != 2
            throw Error("Expected 2 after delete, got " path.Length)
        if path[path.Length].role != "user"
            throw Error("Expected last role 'user' after delete")

        this._teardown()
    }

    ; --------------------
    ; Branch → siblings → stats
    ; --------------------

    Branch_BadgeInfo() {
        threadId := this._setup()
        usrId := ChatDB.Msg_Insert({thread_id: threadId, role: "user", content: "u1"})
        a1Id := ChatDB.Msg_Insert({thread_id: threadId, role: "assistant", content: "a1", parent_id: usrId})
        ; Create a sibling via retry-like flow
        sg := ChatDB._UUID()
        ChatDB.db.Exec("UPDATE messages SET sibling_group='" sg "', sibling_index=0 WHERE id='" a1Id "';")
        ChatDB.Msg_Insert({thread_id: threadId, role: "assistant", content: "a2", parent_id: usrId, sibling_group: sg, sibling_index: 1})

        ; Get sibling info
        sibs := ChatDB.Msg_GetSiblings(a1Id)
        if sibs.Length != 2
            throw Error("Expected 2 siblings, got " sibs.Length)
        if sibs[1].sibling_index != 0
            throw Error("Expected first sibling index 0")
        if sibs[2].sibling_index != 1
            throw Error("Expected second sibling index 1")

        ; Switch branch
        result := ChatDB.Msg_SwitchBranch(threadId, a1Id, 1)
        if result.siblingInfo.total != 2
            throw Error("Expected sibling total 2 after switch, got " result.siblingInfo.total)
        if result.path[result.path.Length].content != "a2"
            throw Error("Expected last message content 'a2' after branch switch")

        this._teardown()
    }

    ; --------------------
    ; Fork → verify copied messages
    ; --------------------

    ForkThread_MaintainsCount() {
        threadId := this._setup()
        sysId := ChatDB.Msg_Insert({thread_id: threadId, role: "system", content: "system"})
        usrId := ChatDB.Msg_Insert({thread_id: threadId, role: "user", content: "user msg", parent_id: sysId})
        ChatDB.Msg_Insert({thread_id: threadId, role: "assistant", content: "asst response", model: "deepseek-v4-flash", parent_id: usrId, token_count: 15})

        newThreadId := ChatDB.Msg_ForkThread(threadId, usrId)
        if !newThreadId
            throw Error("Fork returned empty thread id")

        path := ChatDB.Msg_GetActivePath(newThreadId)
        if path.Length != 2
            throw Error("Expected 2 messages in forked thread, got " path.Length)
        if path[1].content != "system"
            throw Error("Expected first forked message 'system'")
        if path[2].content != "user msg"
            throw Error("Expected second forked message 'user msg'")

        ChatDB.Thread_Delete(newThreadId)
        this._teardown()
    }
}
