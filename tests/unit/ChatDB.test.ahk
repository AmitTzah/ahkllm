; ======================================================
; ChatDB.test.ahk — Unit tests for ChatDB class
;
; Tests: Msg_Insert, Msg_GetActivePath, Msg_HardDelete,
;        Msg_GetThreadStats, Msg_GetSiblings,
;        Msg_SetActiveLeaf, Msg_SwitchBranch, Thread_CRUD
; ======================================================

class ChatDBTest {

    static __New() {
        RegisterTestClass("ChatDBTest")
    }

    ; Each test opens its own temp DB — no shared state
    _openDb() {
        if ChatDB.isOpen {
            oldPath := ChatDB.dbPath
            ChatDB.Close()
            try FileDelete(oldPath)
        }
        ChatDB.Open(A_Temp "\test_chat_" A_TickCount ".db")
    }

    _closeDb() {
        if ChatDB.isOpen {
            dbPath := ChatDB.dbPath
            ChatDB.Close()
            try FileDelete(dbPath)
        }
    }

    _setup() {
        this._openDb()
        return ChatDB.Thread_Create("Test Thread")
    }

    _teardown() {
        this._closeDb()
    }

    ; --------------------
    ; Msg_Insert
    ; --------------------

    Insert_SystemMessage() {
        threadId := this._setup()
        id := ChatDB.Msg_Insert({thread_id: threadId, role: "system", content: "You are a helpful assistant."})
        if !id
            throw Error("Expected non-empty id")
        path := ChatDB.Msg_GetActivePath(threadId)
        if path.Length != 1
            throw Error("Expected 1 message, got " path.Length)
        if path[1].role != "system"
            throw Error("Expected role 'system', got '" path[1].role "'")
        this._teardown()
    }

    Insert_UserMessage() {
        threadId := this._setup()
        sysId := ChatDB.Msg_Insert({thread_id: threadId, role: "system", content: "system"})
        id := ChatDB.Msg_Insert({thread_id: threadId, role: "user", content: "Hello", parent_id: sysId})
        if !id
            throw Error("Expected non-empty id")
        path := ChatDB.Msg_GetActivePath(threadId)
        if path.Length != 2
            throw Error("Expected 2 messages, got " path.Length)
        if path[2].role != "user"
            throw Error("Expected role 'user', got '" path[2].role "'")
        this._teardown()
    }

    Insert_WithTokenCounts() {
        threadId := this._setup()
        ChatDB.Msg_Insert({thread_id: threadId, role: "system", content: "system"})
        ChatDB.Msg_Insert({thread_id: threadId, role: "user", content: "Hello"})
        id := ChatDB.Msg_Insert({thread_id: threadId, role: "assistant", content: "Hi there!", model: "deepseek-v4-flash", prompt_tokens: 10, completion_tokens: 5, total_tokens: 15, cached_tokens: 0})
        path := ChatDB.Msg_GetActivePath(threadId)
        if path[path.Length].total_tokens != 15
            throw Error("Expected total_tokens=15, got " path[path.Length].total_tokens)
        if path[path.Length].cached_tokens != 0
            throw Error("Expected cached_tokens=0, got " path[path.Length].cached_tokens)
        this._teardown()
    }

    ; --------------------
    ; Msg_GetActivePath
    ; --------------------

    GetActivePath_EmptyThread() {
        threadId := this._setup()
        path := ChatDB.Msg_GetActivePath(threadId)
        if path.Length != 0
            throw Error("Expected empty path for new thread, got " path.Length)
        this._teardown()
    }

    GetActivePath_MultiMessage() {
        threadId := this._setup()
        sysId := ChatDB.Msg_Insert({thread_id: threadId, role: "system", content: "s"})
        usrId := ChatDB.Msg_Insert({thread_id: threadId, role: "user", content: "u", parent_id: sysId})
        ChatDB.Msg_Insert({thread_id: threadId, role: "assistant", content: "a", parent_id: usrId})
        path := ChatDB.Msg_GetActivePath(threadId)
        if path.Length != 3
            throw Error("Expected 3 messages, got " path.Length)
        roles := ["system", "user", "assistant"]
        for i, msg in path {
            if msg.role != roles[i]
                throw Error("Message " i " expected role '" roles[i] "', got '" msg.role "'")
        }
        this._teardown()
    }

    ; --------------------
    ; Msg_HardDelete (re-parenting model)
    ; --------------------

    HardDelete_LastMessage_MovesActiveLeaf() {
        threadId := this._setup()
        u1Id := ChatDB.Msg_Insert({thread_id: threadId, role: "user", content: "u1"})
        a1Id := ChatDB.Msg_Insert({thread_id: threadId, role: "assistant", content: "a1", parent_id: u1Id})
        path := ChatDB.Msg_GetActivePath(threadId)
        if path.Length != 2
            throw Error("Expected 2 before delete, got " path.Length)

        ChatDB.Msg_HardDelete(a1Id)
        path := ChatDB.Msg_GetActivePath(threadId)
        if path.Length != 1
            throw Error("Expected 1 after deleting leaf, got " path.Length)
        ; Verify row is gone
        check := ChatDB.db.Exec("SELECT id FROM messages WHERE id='" a1Id "';")
        if check.count > 0
            throw Error("Row should have been hard-deleted")
        this._teardown()
    }

    HardDelete_MiddleMessage_ReparentsChildren() {
        threadId := this._setup()
        u1Id := ChatDB.Msg_Insert({thread_id: threadId, role: "user", content: "u1"})
        a1Id := ChatDB.Msg_Insert({thread_id: threadId, role: "assistant", content: "a1", parent_id: u1Id})
        u2Id := ChatDB.Msg_Insert({thread_id: threadId, role: "user", content: "u2", parent_id: a1Id})
        a2Id := ChatDB.Msg_Insert({thread_id: threadId, role: "assistant", content: "a2", parent_id: u2Id})
        path := ChatDB.Msg_GetActivePath(threadId)
        if path.Length != 4
            throw Error("Expected 4 before delete, got " path.Length)

        ; Delete middle message (a1Id) — children should be re-parented to u1Id
        ChatDB.Msg_HardDelete(a1Id)
        path := ChatDB.Msg_GetActivePath(threadId)
        if path.Length != 3
            throw Error("Expected 3 after re-parent, got " path.Length)
        ; Verify u2 now has parent u1 (not a1 which is deleted)
        checkParent := ChatDB.db.Exec("SELECT parent_id FROM messages WHERE id='" u2Id "';")
        if checkParent.count && checkParent[1, "parent_id"] != u1Id
            throw Error("u2 should be re-parented to u1Id, got " checkParent[1, "parent_id"])
        this._teardown()
    }

    HardDelete_RootMessage_ReparentsToNull() {
        threadId := this._setup()
        rootId := ChatDB.Msg_Insert({thread_id: threadId, role: "system", content: "sys"})
        u1Id := ChatDB.Msg_Insert({thread_id: threadId, role: "user", content: "u1", parent_id: rootId})
        ; Delete root — children should get parent_id=NULL
        ChatDB.Msg_HardDelete(rootId)
        path := ChatDB.Msg_GetActivePath(threadId)
        if path.Length < 1
            throw Error("Expected path with user message after root delete, got " path.Length)
        ; Verify u1 has NULL parent_id
        check := ChatDB.db.Exec("SELECT parent_id FROM messages WHERE id='" u1Id "';")
        if check.count && check[1, "parent_id"] != ""
            throw Error("Child should have NULL parent after root delete")
        this._teardown()
    }

    ; --------------------
    ; Msg_GetThreadStats
    ; --------------------

    GetThreadStats_Empty() {
        threadId := this._setup()
        stats := ChatDB.Msg_GetThreadStats(threadId)
        if stats.activePathTokens != 0
            throw Error("Expected 0 activePathTokens, got " stats.activePathTokens)
        if stats.cumulativeTotalTokens != 0
            throw Error("Expected 0 cumulativeTotalTokens, got " stats.cumulativeTotalTokens)
        this._teardown()
    }

    GetThreadStats_WithApiTokens() {
        threadId := this._setup()
        ChatDB.Msg_Insert({thread_id: threadId, role: "system", content: "system"})
        ChatDB.Msg_Insert({thread_id: threadId, role: "user", content: "user message"})
        ChatDB.Msg_Insert({thread_id: threadId, role: "assistant", content: "response", model: "deepseek-v4-flash", prompt_tokens: 15, completion_tokens: 5, total_tokens: 20})
        stats := ChatDB.Msg_GetThreadStats(threadId)
        if stats.activePathTokens <= 0
            throw Error("Expected activePathTokens > 0, got " stats.activePathTokens)
        if stats.cumulativeTotalTokens <= 0
            throw Error("Expected cumulativeTotalTokens > 0, got " stats.cumulativeTotalTokens)
        this._teardown()
    }

    ; --------------------
    ; Msg_GetSiblings
    ; --------------------

    GetSiblings_NoSiblings() {
        threadId := this._setup()
        id := ChatDB.Msg_Insert({thread_id: threadId, role: "user", content: "u1"})
        sibs := ChatDB.Msg_GetSiblings(id)
        if sibs.Length != 0
            throw Error("Expected 0 siblings for single message, got " sibs.Length)
        this._teardown()
    }

    GetSiblings_WithBranch() {
        threadId := this._setup()
        id1 := ChatDB.Msg_Insert({thread_id: threadId, role: "user", content: "u1"})
        ChatDB.Msg_Insert({thread_id: threadId, role: "assistant", content: "a1", parent_id: id1})
        sg := "test-group"
        id3 := ChatDB.Msg_Insert({thread_id: threadId, role: "assistant", content: "a2", parent_id: id1, sibling_group: sg, sibling_index: 1})
        sibs := ChatDB.Msg_GetSiblings(id3)
        if sibs.Length < 1
            throw Error("Expected at least 1 sibling, got " sibs.Length)
        this._teardown()
    }

    ; --------------------
    ; Thread CRUD
    ; --------------------

    Thread_CreateAndList() {
        this._setup()
        id1 := ChatDB.Thread_Create("Chat 1")
        id2 := ChatDB.Thread_Create("Chat 2")
        threads := ChatDB.Thread_List()
        found := 0
        for t in threads {
            if t.id = id1 || t.id = id2
                found++
        }
        if found != 2
            throw Error("Expected 2 threads in list, found " found)
        ChatDB.Thread_Delete(id1)
        ChatDB.Thread_Delete(id2)
        this._teardown()
    }

    Thread_Delete_Cascades() {
        threadId := this._setup()
        ChatDB.Msg_Insert({thread_id: threadId, role: "user", content: "u1"})
        ChatDB.Msg_Insert({thread_id: threadId, role: "assistant", content: "a1"})
        ChatDB.Thread_Delete(threadId)
        path := ChatDB.Msg_GetActivePath(threadId)
        if path.Length != 0
            throw Error("Expected empty path after thread delete, got " path.Length)
        this._teardown()
    }

    ; --------------------
    ; Msg_SetActiveLeaf
    ; --------------------

    SetActiveLeaf_ChangesPath() {
        threadId := this._setup()
        u1Id := ChatDB.Msg_Insert({thread_id: threadId, role: "user", content: "u1"})
        a1Id := ChatDB.Msg_Insert({thread_id: threadId, role: "assistant", content: "a1", parent_id: u1Id})
        ChatDB.Msg_Insert({thread_id: threadId, role: "user", content: "u2", parent_id: a1Id})
        ChatDB.Msg_SetActiveLeaf(threadId, a1Id)
        path := ChatDB.Msg_GetActivePath(threadId)
        if path.Length != 2
            throw Error("Expected path length 2 after SetActiveLeaf, got " path.Length)
        if path[path.Length].id != a1Id
            throw Error("Expected last message id to be " a1Id ", got " path[path.Length].id)
        this._teardown()
    }

    ; --------------------
    ; Msg_SwitchBranch
    ; --------------------

    SwitchBranch_NoSiblings() {
        threadId := this._setup()
        u1Id := ChatDB.Msg_Insert({thread_id: threadId, role: "user", content: "u1"})
        id := ChatDB.Msg_Insert({thread_id: threadId, role: "assistant", content: "a1", parent_id: u1Id})
        result := ChatDB.Msg_SwitchBranch(threadId, id, 1)
        if result.siblingInfo.total != 1
            throw Error("Expected sibling total 1, got " result.siblingInfo.total)
        if result.path.Length != 2
            throw Error("Expected path length 2, got " result.path.Length)
        this._teardown()
    }

    ; --------------------
    ; Msg_ForkThread
    ; --------------------

    ForkThread_CreatesNewThread() {
        threadId := this._setup()
        u1Id := ChatDB.Msg_Insert({thread_id: threadId, role: "user", content: "u1"})
        a1Id := ChatDB.Msg_Insert({thread_id: threadId, role: "assistant", content: "a1", parent_id: u1Id})
        newId := ChatDB.Msg_ForkThread(threadId, a1Id)
        if !newId
            throw Error("Expected new thread id from fork")
        path := ChatDB.Msg_GetActivePath(newId)
        if path.Length != 2
            throw Error("Expected 2 messages in forked thread, got " path.Length)
        ChatDB.Thread_Delete(newId)
        this._teardown()
    }

    ; --------------------
    ; Msg_Edit
    ; --------------------

    Edit_OverwritesContent() {
        threadId := this._setup()
        id := ChatDB.Msg_Insert({thread_id: threadId, role: "user", content: "original"})
        ChatDB.Msg_Edit(id, "edited")
        path := ChatDB.Msg_GetActivePath(threadId)
        if path[path.Length].content != "edited"
            throw Error("Expected content 'edited', got '" path[path.Length].content "'")
        this._teardown()
    }

    ; --------------------
    ; Msg_SetFeedback
    ; --------------------

    SetFeedback_StoresRating() {
        threadId := this._setup()
        id := ChatDB.Msg_Insert({thread_id: threadId, role: "user", content: "u1"})
        ChatDB.Msg_SetFeedback(id, 1)
        ; Verify via DB query
        table := ChatDB.db.Exec("SELECT feedback FROM messages WHERE id='" id "';")
        if table.count && table[1, "feedback"] != 1
            throw Error("Expected feedback=1, got " table[1, "feedback"])
        ChatDB.Msg_SetFeedback(id, -1)
        table := ChatDB.db.Exec("SELECT feedback FROM messages WHERE id='" id "';")
        if table.count && table[1, "feedback"] != -1
            throw Error("Expected feedback=-1, got " table[1, "feedback"])
        ChatDB.Msg_SetFeedback(id, 0)
        table := ChatDB.db.Exec("SELECT feedback FROM messages WHERE id='" id "';")
        if table.count && table[1, "feedback"] != ""
            throw Error("Expected feedback=NULL after clear, got " table[1, "feedback"])
        this._teardown()
    }
}
