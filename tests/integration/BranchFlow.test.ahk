; ======================================================
; BranchFlow.test.ahk — Integration tests for branching
;
; Tests: Edit → branch → multiple siblings → navigate →
;        edit overwrite → undo pattern
; ======================================================

class BranchFlowTest {

    static __New() {
        RegisterTestClass("BranchFlowTest")
    }

    _setup() {
        if ChatDB.isOpen {
            oldPath := ChatDB.dbPath
            ChatDB.Close()
            try FileDelete(oldPath)
        }
        ChatDB.Open(A_Temp "\test_branch_" A_TickCount ".db")
        return ChatDB.Thread_Create("Branch Test")
    }

    _teardown() {
        if ChatDB.isOpen {
            dbPath := ChatDB.dbPath
            ChatDB.Close()
            try FileDelete(dbPath)
        }
    }

    ; --------------------
    ; Create branch via retry mechanism
    ; --------------------

    RetryCreatesSibling() {
        threadId := this._setup()
        usrId := ChatDB.Msg_Insert({thread_id: threadId, role: "user", content: "u1"})
        a1Id := ChatDB.Msg_Insert({thread_id: threadId, role: "assistant", content: "a1", parent_id: usrId})

        ; Simulate retry: assign sibling_group to existing assistant
        sg := ChatDB._UUID()
        ChatDB.db.Exec("UPDATE messages SET sibling_group='" sg "', sibling_index=0 WHERE id='" a1Id "';")

        ; Insert new sibling (like retry would)
        a2Id := ChatDB.Msg_Insert({thread_id: threadId, role: "assistant", content: "a2", parent_id: usrId, sibling_group: sg, sibling_index: 1})

        ; Verify siblings
        sibs := ChatDB.Msg_GetSiblings(a1Id)
        if sibs.Length != 2
            throw Error("Expected 2 siblings after retry, got " sibs.Length)

        ; Verify GetSiblings works for both messages
        sibs2 := ChatDB.Msg_GetSiblings(a2Id)
        if sibs2.Length != 2
            throw Error("Expected 2 siblings from a2, got " sibs2.Length)

        this._teardown()
    }

    ; --------------------
    ; Switch between branches
    ; --------------------

    SwitchBranches_ChangesContent() {
        threadId := this._setup()
        usrId := ChatDB.Msg_Insert({thread_id: threadId, role: "user", content: "Tell me a joke"})
        a1Id := ChatDB.Msg_Insert({thread_id: threadId, role: "assistant", content: "Why did the chicken cross the road?", parent_id: usrId})

        ; Create sibling branch
        sg := ChatDB._UUID()
        ChatDB.db.Exec("UPDATE messages SET sibling_group='" sg "', sibling_index=0 WHERE id='" a1Id "';")
        ChatDB.Msg_Insert({thread_id: threadId, role: "assistant", content: "What do you call a fish with no eyes?", parent_id: usrId, sibling_group: sg, sibling_index: 1})

        ; Switch to sibling
        result := ChatDB.Msg_SwitchBranch(threadId, a1Id, 1)
        lastContent := result.path[result.path.Length].content
        if lastContent != "What do you call a fish with no eyes?"
            throw Error("Expected 'fish' joke after switch, got '" lastContent "'")

        ; Switch back
        result2 := ChatDB.Msg_SwitchBranch(threadId, result.path[result.path.Length].id, -1)
        lastContent2 := result2.path[result2.path.Length].content
        if lastContent2 != "Why did the chicken cross the road?"
            throw Error("Expected 'chicken' joke after switch back, got '" lastContent2 "'")

        this._teardown()
    }

    ; --------------------
    ; Edit overwrite then verify content
    ; --------------------

    EditOverwrite_UpdatesContent() {
        threadId := this._setup()
        id := ChatDB.Msg_Insert({thread_id: threadId, role: "user", content: "original text"})
        ChatDB.Msg_Edit(id, "edited text")
        path := ChatDB.Msg_GetActivePath(threadId)
        if path[path.Length].content != "edited text"
            throw Error("Expected 'edited text', got '" path[path.Length].content "'")
        this._teardown()
    }

    ; --------------------
    ; Multiple messages → stats update
    ; --------------------

    MultiMessage_StatsAccurate() {
        threadId := this._setup()
        sysId := ChatDB.Msg_Insert({thread_id: threadId, role: "system", content: "short sys"})
        usrId := ChatDB.Msg_Insert({thread_id: threadId, role: "user", content: "short user", parent_id: sysId})
        a1Id := ChatDB.Msg_Insert({thread_id: threadId, role: "assistant", content: "short asst", model: "deepseek-v4-flash", parent_id: usrId, prompt_tokens: 20, completion_tokens: 5, total_tokens: 25})

        ; Create sibling with different tokens
        sg := ChatDB._UUID()
        ChatDB.db.Exec("UPDATE messages SET sibling_group='" sg "', sibling_index=0 WHERE id='" a1Id "';")
        ChatDB.Msg_Insert({thread_id: threadId, role: "assistant", content: "longer assistant response with more tokens", model: "deepseek-v4-flash", parent_id: usrId, sibling_group: sg, sibling_index: 1, prompt_tokens: 20, completion_tokens: 10, total_tokens: 30})

        ; Stats for active path (first sibling)
        stats := ChatDB.Msg_GetThreadStats(threadId)
        ; Context used should be last assistant's total_tokens
        if stats.activePathTokens <= 0
            throw Error("Expected activePathTokens > 0")
        ; Cumulative cost should be > 0
        if stats.cumulativeCost <= 0
            throw Error("Expected cumulativeCost > 0")
        ; Cumulative tokens should include both paths
        if stats.cumulativeTotalTokens <= 0
            throw Error("Expected cumulativeTotalTokens > 0")

        this._teardown()
    }
}
