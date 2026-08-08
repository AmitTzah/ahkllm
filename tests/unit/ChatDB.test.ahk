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
        id := ChatDB.Msg_Insert({thread_id: threadId, role: "assistant", content: "Hi there!", model: "deepseek-v4-flash", token_count: 15, cached_tokens: 0})
        path := ChatDB.Msg_GetActivePath(threadId)
        if path[path.Length].token_count != 15
            throw Error("Expected token_count=15, got " path[path.Length].token_count)
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
        if stats.cumulativeInputTokens != 0
            throw Error("Expected 0 cumulativeInputTokens, got " stats.cumulativeInputTokens)
        if stats.cumulativeOutputTokens != 0
            throw Error("Expected 0 cumulativeOutputTokens, got " stats.cumulativeOutputTokens)
        this._teardown()
    }

    GetThreadStats_WithApiTokens() {
        threadId := this._setup()
        ChatDB.Msg_Insert({thread_id: threadId, role: "system", content: "system"})
        ChatDB.Msg_Insert({thread_id: threadId, role: "user", content: "user message"})
        ChatDB.Msg_Insert({thread_id: threadId, role: "assistant", content: "response", model: "deepseek-v4-flash", token_count: 20})
        stats := ChatDB.Msg_GetThreadStats(threadId)
        if stats.activePathTokens <= 0
            throw Error("Expected activePathTokens > 0, got " stats.activePathTokens)
        if stats.cumulativeOutputTokens <= 0
            throw Error("Expected cumulativeOutputTokens > 0, got " stats.cumulativeOutputTokens)
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

    SwitchBranch_UpdatesActivePathTokens() {
        threadId := this._setup()
        u1Id := ChatDB.Msg_Insert({thread_id: threadId, role: "user", content: "hello"})
        ; Two sibling assistants — token_count = visible output
        a1Id := ChatDB.Msg_Insert({thread_id: threadId, role: "assistant", content: "short reply", parent_id: u1Id, sibling_group: "test-sg", sibling_index: 0, model: "deepseek-v4-flash", token_count: 5, cached_tokens: 0})
        a2Id := ChatDB.Msg_Insert({thread_id: threadId, role: "assistant", content: "longer detailed response", parent_id: u1Id, sibling_group: "test-sg", sibling_index: 1, model: "deepseek-v4-flash", token_count: 10, cached_tokens: 0})
        ; After insert, active_path_tokens = token_count of last assistant (10)
        stats := ChatDB.Msg_GetThreadStats(threadId)
        if stats.activePathTokens != 10
            throw Error("Expected active_path_tokens=10 for a2, got " stats.activePathTokens)

        ; Switch to a1 branch — _SyncActivePathTokens sums token_count: a1(5) = 5
        result := ChatDB.Msg_SwitchBranch(threadId, a2Id, -1)
        if result.siblingInfo.index != 1
            throw Error("Expected sibling index 1 after switching, got " result.siblingInfo.index)

        stats := ChatDB.Msg_GetThreadStats(threadId)
        if stats.activePathTokens != 5
            throw Error("Expected active_path_tokens=5 for a1 branch after switch, got " stats.activePathTokens)

        ; Switch back to a2 — token_count sum: a2(10) = 10
        ChatDB.Msg_SwitchBranch(threadId, a1Id, 1)
        stats := ChatDB.Msg_GetThreadStats(threadId)
        if stats.activePathTokens != 10
            throw Error("Expected active_path_tokens=10 for a2 branch after switch back, got " stats.activePathTokens)
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

    ; Regression: Fork copies attachments
    ForkThread_CopiesAttachments() {
        threadId := this._setup()
        u1Id := ChatDB.Msg_Insert({thread_id: threadId, role: "user", content: "u1 with file"})
        ChatDB.Attachment_Insert(u1Id, {
            attachment_type: "pdf",
            file_path: "attachments\test_fork.pdf",
            mime_type: "application/pdf",
            original_filename: "test.pdf",
            file_size: 500,
            extracted_text: "fork test"
        })
        a1Id := ChatDB.Msg_Insert({thread_id: threadId, role: "assistant", content: "a1", parent_id: u1Id})

        newId := ChatDB.Msg_ForkThread(threadId, a1Id)
        if !newId
            throw Error("Expected new thread id from fork")

        ; Get forked message and check its attachments
        path := ChatDB.Msg_GetActivePath(newId)
        if path.Length != 2
            throw Error("Expected 2 messages in forked thread")

        atts := ChatDB.Attachment_GetByMessage(path[1].id)
        if atts.Length != 1
            throw Error("Expected 1 copied attachment after fork, got " atts.Length)
        if atts[1].attachment_type != "pdf"
            throw Error("Expected pdf attachment type after fork copy")

        ChatDB.Thread_Delete(newId)
        this._teardown()
    }

    ; Regression: Fork copies per-thread font_size and Advanced toggles (bug #44)
    ForkThread_CopiesPerThreadSettings() {
        threadId := this._setup()
        togglesJson := jsongo.Stringify(Map("codeExecution", true, "webSearch", true))
        ChatDB.db.Exec("UPDATE chat_threads SET font_size=20, advanced_toggles='" SQLite.Escape(togglesJson) "' WHERE id='" threadId "';")
        u1Id := ChatDB.Msg_Insert({thread_id: threadId, role: "user", content: "u1"})
        a1Id := ChatDB.Msg_Insert({thread_id: threadId, role: "assistant", content: "a1", parent_id: u1Id})
        newId := ChatDB.Msg_ForkThread(threadId, a1Id)
        if !newId
            throw Error("Expected new thread id from fork (per-thread settings)")
        row := ChatDB.db.Exec("SELECT font_size, advanced_toggles FROM chat_threads WHERE id='" newId "';")
        if !row.count || Integer(row[1, "font_size"]) != 20
            throw Error("Expected forked thread font_size=20, got " (row.count ? row[1, "font_size"] : "none"))
        if !InStr(row[1, "advanced_toggles"], "codeExecution")
            throw Error("Expected forked thread advanced_toggles to contain codeExecution, got " row[1, "advanced_toggles"])
        if !InStr(row[1, "advanced_toggles"], "webSearch")
            throw Error("Expected forked thread advanced_toggles to contain webSearch")
        ChatDB.Thread_Delete(newId)
        this._teardown()
    }

    ; Regression (bug #48): a fork must carry the token/cost stats - the
    ; per-message active_path_tokens (context used) and the thread's
    ; cumulative counters - so the fork's token bar does not reset to zero.
    ForkThread_CopiesTokenStats() {
        threadId := this._setup()
        ChatDB.db.Exec("UPDATE chat_threads SET cumulative_input_tokens=10, cumulative_output_tokens=20, cumulative_cached_tokens=2, cumulative_cost=0.5, cumulative_input_cost=0.3, cumulative_cached_input_cost=0.01, cumulative_output_cost=0.2 WHERE id='" threadId "';")
        u1Id := ChatDB.Msg_Insert({thread_id: threadId, role: "user", content: "u1", token_count: 10})
        a1Id := ChatDB.Msg_Insert({thread_id: threadId, role: "assistant", content: "a1", parent_id: u1Id, token_count: 20})
        newId := ChatDB.Msg_ForkThread(threadId, u1Id)
        if !newId
            throw Error("Expected new thread id from fork (token stats)")
        row := ChatDB.db.Exec("SELECT cumulative_input_tokens, cumulative_output_tokens, cumulative_cost, active_leaf_id FROM chat_threads WHERE id='" newId "';")
        if !row.count
            throw Error("fork thread row missing")
        if Integer(row[1, "cumulative_input_tokens"]) != 10
            throw Error("fork should inherit cumulative_input_tokens=10, got " row[1, "cumulative_input_tokens"])
        if Number(row[1, "cumulative_cost"]) != 0.5
            throw Error("fork should inherit cumulative_cost=0.5, got " row[1, "cumulative_cost"])
        leaf := ChatDB.db.Exec("SELECT active_path_tokens FROM messages WHERE id='" row[1, "active_leaf_id"] "';")
        if !leaf.count || Integer(leaf[1, "active_path_tokens"]) != 10
            throw Error("fork leaf should keep active_path_tokens=10, got " (leaf.count ? leaf[1, "active_path_tokens"] : "none"))
        ChatDB.Thread_Delete(newId)
        this._teardown()
    }

    ; Regression (bug #58): a fork must land in the source thread's folder.
    ForkThread_CopiesFolder() {
        threadId := this._setup()
        ChatDB.db.Exec("UPDATE chat_threads SET folder_id='f-58' WHERE id='" threadId "';")
        u1Id := ChatDB.Msg_Insert({thread_id: threadId, role: "user", content: "u1"})
        a1Id := ChatDB.Msg_Insert({thread_id: threadId, role: "assistant", content: "a1", parent_id: u1Id})
        newId := ChatDB.Msg_ForkThread(threadId, a1Id)
        if !newId
            throw Error("Expected new thread id from fork (folder)")
        row := ChatDB.db.Exec("SELECT folder_id FROM chat_threads WHERE id='" newId "';")
        if !row.count || row[1, "folder_id"] != "f-58"
            throw Error("Expected forked thread folder_id=f-58, got " (row.count ? row[1, "folder_id"] : "none"))
        ChatDB.Thread_Delete(newId)
        this._teardown()
    }

    ; Regression (bug #62): a fork must inherit a temperature override of 0
    ; (AHK treats 0 as falsy, so the old truthiness check dropped it).
    ForkThread_CopiesTemperatureZero() {
        threadId := this._setup()
        u1Id := ChatDB.Msg_Insert({thread_id: threadId, role: "user", content: "u1"})
        a1Id := ChatDB.Msg_Insert({thread_id: threadId, role: "assistant", content: "a1", parent_id: u1Id})
        ChatDB.Thread_UpdateSettings(threadId, { temperatureOverride: 0 })
        newId := ChatDB.Msg_ForkThread(threadId, a1Id)
        if !newId
            throw Error("Expected new thread id from fork (temp 0)")
        s := ChatDB.Thread_GetSettings(newId)
        if s.temperatureOverride = "" || s.temperatureOverride != 0
            throw Error("fork should inherit temperature override 0, got '" s.temperatureOverride "'")
        ChatDB.Thread_Delete(newId)
        this._teardown()
    }

    ; Regression (bug #69): the LIKE fallback must escape %/_/\\ so searching for
    ; a literal % does not match every message.
    SearchMessages_LikeEscapesWildcards() {
        threadId := this._setup()
        ChatDB.Msg_Insert({thread_id: threadId, role: "user", content: "50% done"})
        ChatDB.Msg_Insert({thread_id: threadId, role: "user", content: "plain text here"})
        results := ChatDB.SearchMessages("%", threadId)
        if results.Length != 1
            throw Error("searching for % should match only the message containing it, got " results.Length)
        if !InStr(results[1].contentPreview, "50% done")
            throw Error("expected the %-containing message, got '" results[1].contentPreview "'")
        this._teardown()
    }

    ; Regression (bug #80, security): thread mutators must escape threadId - a
    ; crafted id with a single quote must not break or inject SQL.
    ThreadMutators_EscapeThreadId() {
        threadId := this._setup()
        crafted := "bad'id"
        ChatDB.db.Exec("INSERT INTO chat_threads (id, title) VALUES('bad''id', 'Crafted');")
        try {
            ChatDB.Thread_SoftDelete(crafted)
            row := ChatDB.db.Exec("SELECT is_deleted FROM chat_threads WHERE id='bad''id';")
            if !row.count || Integer(row[1, "is_deleted"]) != 1
                throw Error("SoftDelete should target the crafted id literally")
            ChatDB.Thread_Restore(crafted)
            row := ChatDB.db.Exec("SELECT is_deleted FROM chat_threads WHERE id='bad''id';")
            if !row.count || Integer(row[1, "is_deleted"]) != 0
                throw Error("Restore should target the crafted id literally")
            ChatDB.Thread_Update(crafted, "Renamed")
            row := ChatDB.db.Exec("SELECT title FROM chat_threads WHERE id='bad''id';")
            if row[1, "title"] != "Renamed"
                throw Error("Update should target the crafted id literally")
            ChatDB.Thread_Delete(crafted)
            row := ChatDB.db.Exec("SELECT COUNT(*) AS c FROM chat_threads WHERE id='bad''id';")
            if Integer(row[1, "c"]) != 0
                throw Error("Delete should target the crafted id literally")
        } finally {
            this._teardown()
        }
    }

    ; Regression (bug #96, security): AttachmentRepo must escape msgId/threadId
    ; and ChatDB FTS_Sync/FTS_Remove the same way - a crafted id with a single
    ; quote must not break or inject SQL.
    AttachmentRepo_EscapesMsgId() {
        threadId := this._setup()
        craftedMsgId := "bad'id"
        ChatDB.db.Exec("INSERT INTO messages (id, thread_id, role, content) VALUES('bad''id', '" threadId "', 'user', 'attached content');")
        try {
            attId := ChatDB.Attachment_Insert(craftedMsgId, {
                attachment_type: "text_file",
                file_path: "tmp/nonexistent.bin",
                mime_type: "text/plain",
                original_filename: "note.txt",
                file_size: 12,
                extracted_text: "hello"
            })
            if !attId
                throw Error("Attachment_Insert should return an id for a crafted msgId")
            rows := ChatDB.Attachment_GetByMessage(craftedMsgId)
            if rows.Length != 1 || rows[1].original_filename != "note.txt"
                throw Error("GetByMessage should find the crafted-id attachment, got " rows.Length " rows")
            ChatDB.Attachment_DeleteByMessage(craftedMsgId)
            rows := ChatDB.Attachment_GetByMessage(craftedMsgId)
            if rows.Length != 0
                throw Error("DeleteByMessage should remove the crafted-id attachment, got " rows.Length " rows")

            ; FTS sync/remove must also escape msgId (bug #96).
            ChatDB.FTS_Sync(craftedMsgId, "content with a quote ' here")
            ftsRow := ChatDB.db.Exec("SELECT COUNT(*) AS c FROM messages_fts WHERE msg_id='bad''id';")
            if !ftsRow.count || Integer(ftsRow[1, "c"]) != 1
                throw Error("FTS_Sync should index the crafted-id message, got " (ftsRow.count ? ftsRow[1, "c"] : "none"))
            ChatDB.FTS_Remove(craftedMsgId)
            ftsRow := ChatDB.db.Exec("SELECT COUNT(*) AS c FROM messages_fts WHERE msg_id='bad''id';")
            if !ftsRow.count || Integer(ftsRow[1, "c"]) != 0
                throw Error("FTS_Remove should remove the crafted-id message, got " (ftsRow.count ? ftsRow[1, "c"] : "none"))
        } finally {
            this._teardown()
        }
    }

    ; Regression (bug #99, security): MessageRepo.Insert must escape parent_id
    ; and sibling_group - a crafted id with a single quote must not break or
    ; inject SQL (same class as #80/#81/#96).
    Insert_EscapesParentIdAndSiblingGroup() {
        threadId := this._setup()
        craftedParent := "bad'parent"
        craftedGroup := "sib'group"
        try {
            parentId := ChatDB.Msg_Insert({thread_id: threadId, role: "user", content: "parent", parent_id: craftedParent, sibling_group: craftedGroup})
            if !parentId
                throw Error("Msg_Insert should accept a crafted parent_id/sibling_group")
            row := ChatDB.db.Exec("SELECT parent_id, sibling_group FROM messages WHERE id='" parentId "';")
            if !row.count || row[1, "parent_id"] != craftedParent || row[1, "sibling_group"] != craftedGroup
                throw Error("crafted parent_id/sibling_group should round-trip literally, got " (row.count ? row[1, "parent_id"] " / " row[1, "sibling_group"] : "none"))
            ; A child with a crafted parent hits the active-path lookup too.
            childId := ChatDB.Msg_Insert({thread_id: threadId, role: "user", content: "child", parent_id: craftedParent})
            if !childId
                throw Error("Msg_Insert child with crafted parent_id should succeed")
            childRow := ChatDB.db.Exec("SELECT parent_id FROM messages WHERE id='" childId "';")
            if !childRow.count || childRow[1, "parent_id"] != craftedParent
                throw Error("child parent_id should round-trip literally")
        } finally {
            this._teardown()
        }
    }

    ; Regression (bug #81, security): _setupSiblingGroup must escape msg.id.
    Branch_SetupSiblingGroup_EscapesMsgId() {
        srcPath := A_ScriptDir "\..\chat\callbacks\Branch.ahk"
        src := FileRead(srcPath)
        block := SubStr(src, InStr(src, "_setupSiblingGroup(msg) {"), 500)
        if !InStr(block, "SQLite.Escape(msg.id)")
            throw Error("_setupSiblingGroup must escape msg.id (bug #81)")
    }

    ; Regression (bug #70): FTS5 MATCH must quote terms so special characters
    ; (e.g. C++) do not produce a syntax error / empty results.
    SearchMessages_FTS5EscapesSpecialChars() {
        threadId := this._setup()
        ChatDB.Msg_Insert({thread_id: threadId, role: "user", content: "I code C++ daily"})
        ChatDB.Msg_Insert({thread_id: threadId, role: "user", content: "plain text"})
        results := ChatDB.SearchMessages("C++", threadId)
        if results.Length = 0
            throw Error("searching for C++ should return the C++ message, got 0 results")
        found := false
        for r in results {
            if InStr(r.contentPreview, "C++")
                found := true
        }
        if !found
            throw Error("the C++ message was not found among the results")
        this._teardown()
    }

    ; Regression (bug #63): a model with cachedInput="" must fall back to 10%
    ; of the input price instead of showing 0 in the token-bar pricing unit.
    GetThreadStats_CachedInputEmpty_FallsBackToTenPercent() {
        global models, requestParams
        threadId := this._setup()
        testModel := "deepseek/test-empty-cached"
        models[testModel] := {
            provider: "deepseek", api: "openai-completions",
            compat: Map("thinkingFormat", "deepseek", "supportsReasoningEffort", true, "supportsUsageInStreaming", true, "maxTokensField", "max_tokens"),
            thinkingLevelMap: Map("none", "none", "low", "low", "high", "high", "max", "max"),
            thinkingOff: "disabled",
            input: 1, cachedInput: "", output: 2, context: 1000000, reasoning: true, vision: false
        }
        ; Bug #103: pricing resolves from the ACTIVE model (request model
        ; first) - make the test model active so its pricing drives the unit.
        oldModel := requestParams["singleAPIModelName"]
        try {
            requestParams["singleAPIModelName"] := testModel
            ChatDB.Msg_Insert({thread_id: threadId, role: "assistant", content: "hi", model: testModel})
            stats := ChatDB.Msg_GetThreadStats(threadId)
            if Number(stats.pricingUnit.cachedInput) != 0.1
                throw Error("cachedInput fallback should be 10% of input (0.1), got " stats.pricingUnit.cachedInput)
        } finally {
            requestParams["singleAPIModelName"] := oldModel
            models.Delete(testModel)
            this._teardown()
        }
    }

    ; Regression (bug #64): active_path_tokens must include thinking tokens so
    ; the header "Context Used" reflects the full context-window usage.
    ActivePathTokens_IncludesThinkingTokens() {
        threadId := this._setup()
        uId := ChatDB.Msg_Insert({thread_id: threadId, role: "user", content: "hello", token_count: 10})
        aId := ChatDB.Msg_Insert({thread_id: threadId, role: "assistant", content: "answer", parent_id: uId, prompt_tokens: 20, token_count: 5, thinking_tokens: 7})
        leaf := ChatDB.db.Exec("SELECT active_path_tokens FROM messages WHERE id='" aId "';")
        if !leaf.count || Integer(leaf[1, "active_path_tokens"]) != 32
            throw Error("expected active_path_tokens = prompt(20) + visible(5) + thinking(7) = 32, got " (leaf.count ? leaf[1, "active_path_tokens"] : "none"))
        this._teardown()
    }

    ; Regression (bug #107): _RecomputeActivePath must keep an assistant's API
    ; ground truth (prompt + visible + thinking) instead of reducing it to a
    ; pure prefix sum of visible tokens.
    RecomputeActivePath_PreservesAssistantPromptTokens() {
        threadId := this._setup()
        uId := ChatDB.Msg_Insert({thread_id: threadId, role: "user", content: "hello", token_count: 10})
        aId := ChatDB.Msg_Insert({thread_id: threadId, role: "assistant", content: "answer", parent_id: uId, prompt_tokens: 100, token_count: 20})
        leaf := ChatDB.db.Exec("SELECT active_path_tokens, prompt_tokens FROM messages WHERE id='" aId "';")
        if !leaf.count || Integer(leaf[1, "active_path_tokens"]) != 120
            throw Error("setup: assistant active_path should be prompt(100)+visible(20)=120, got " (leaf.count ? leaf[1, "active_path_tokens"] : "none"))
        if !leaf.count || Integer(leaf[1, "prompt_tokens"]) != 100
            throw Error("setup: assistant prompt_tokens should be persisted (bug #107), got " (leaf.count ? leaf[1, "prompt_tokens"] : "none"))
        ; Simulate the structural-change recompute (delete/edit path).
        TreeRepo._RecomputeActivePath(threadId)
        leaf := ChatDB.db.Exec("SELECT active_path_tokens FROM messages WHERE id='" aId "';")
        if !leaf.count || Integer(leaf[1, "active_path_tokens"]) != 120
            throw Error("recompute must keep prompt+visible (120), got " (leaf.count ? leaf[1, "active_path_tokens"] : "none"))
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

    ; Trash lifecycle
    ; --------------------

    Thread_SoftDelete_HidesFromList() {
        threadId := this._setup()
        ChatDB.Thread_SoftDelete(threadId)
        threads := ChatDB.Thread_List()
        for t in threads {
            if t.id = threadId
                throw Error("Soft-deleted thread should not appear in normal list")
        }
        ; Should appear in trash
        trashed := ChatDB.Thread_List(true)
        found := false
        for t in trashed {
            if t.id = threadId
                found := true
        }
        if !found
            throw Error("Soft-deleted thread should appear in trash list")
        this._teardown()
    }

    Thread_Restore_Reappears() {
        threadId := this._setup()
        ChatDB.Thread_SoftDelete(threadId)
        ChatDB.Thread_Restore(threadId)
        threads := ChatDB.Thread_List()
        found := false
        for t in threads {
            if t.id = threadId
                found := true
        }
        if !found
            throw Error("Restored thread should appear in list")
        this._teardown()
    }

    ; ----------------------------------------------------
    ; Regression: Thread_PurgeExpired must permanently delete trashed threads
    ; past the retention period (previously nothing called it, so trash never
    ; auto-purged). Expired threads go; recent ones survive.
    ; ----------------------------------------------------
    Thread_PurgeExpired_DeletesExpiredKeepsRecent() {
        global trashRetentionDays
        oldRetention := trashRetentionDays
        trashRetentionDays := 1
        try {
            this._setup()
            expiredId := ChatDB.Thread_Create("Expired Trash")
            recentId  := ChatDB.Thread_Create("Recent Trash")

            ChatDB.Thread_SoftDelete(expiredId)
            ChatDB.Thread_SoftDelete(recentId)

            ; Age the expired thread past the 1-day retention window.
            ChatDB.db.Exec("UPDATE chat_threads SET deleted_at=datetime('now', '-2 days') WHERE id='" expiredId "';")

            ChatDB.Thread_PurgeExpired()

            recentSurvived := false
            for t in ChatDB.Thread_List(true) {
                if t.id = expiredId
                    throw Error("Expired trashed thread survived PurgeExpired")
                if t.id = recentId
                    recentSurvived := true
            }
            if !recentSurvived
                throw Error("Recent trashed thread was purged before its retention period")
        } finally {
            trashRetentionDays := oldRetention
            this._teardown()
        }
    }

    ; --------------------
    ; Cumulative counter persistence
    ; --------------------

    ; Regression (bug #65): hard-deleting a message must decrement the thread's
    ; cumulative counters (they used to stay stale and forever inflated).
    HardDelete_DecrementsCumulativeCounters() {
        threadId := this._setup()
        ChatDB.Msg_Insert({thread_id: threadId, role: "system", content: "sys"})
        ChatDB.Msg_Insert({thread_id: threadId, role: "user", content: "Hello"})
        a1Id := ChatDB.Msg_Insert({thread_id: threadId, role: "assistant", content: "Hi!", model: "deepseek-v4-flash", token_count: 15, cached_tokens: 0})
        threadRow := ChatDB.db.Exec("SELECT cumulative_output_tokens FROM chat_threads WHERE id='" threadId "';")
        beforeOut := Integer(threadRow[1, "cumulative_output_tokens"])
        if beforeOut != 15
            throw Error("Expected cumulative output 15 before delete, got " beforeOut)

        ChatDB.Msg_HardDelete(a1Id)

        threadRow := ChatDB.db.Exec("SELECT cumulative_input_tokens, cumulative_output_tokens, cumulative_cached_tokens FROM chat_threads WHERE id='" threadId "';")
        afterIn := Integer(threadRow[1, "cumulative_input_tokens"])
        afterOut := Integer(threadRow[1, "cumulative_output_tokens"])
        afterCached := Integer(threadRow[1, "cumulative_cached_tokens"])
        if afterOut != 0
            throw Error("Cumulative output_tokens should drop to 0 after delete, got " afterOut)
        if afterIn != 0 || afterCached != 0
            throw Error("Cumulative input/cached should be 0 after delete, got in=" afterIn " cached=" afterCached)
        this._teardown()
    }

    ; --------------------
    ; Msg_Edit active_path_tokens recalculation
    ; --------------------

    Edit_AdjustsActivePathTokens() {
        threadId := this._setup()
        ChatDB.Msg_Insert({thread_id: threadId, role: "system", content: "sys"})
        ChatDB.Msg_Insert({thread_id: threadId, role: "user", content: "Very long original message to edit"})
        aId := ChatDB.Msg_Insert({thread_id: threadId, role: "assistant", content: "response", model: "deepseek-v4-flash", token_count: 10, cached_tokens: 0})
        ; After insert, active_path_tokens = prefix sum (0+0+10=10)
        stats := ChatDB.Msg_GetThreadStats(threadId)
        if stats.activePathTokens != 10
            throw Error("Expected activePathTokens=10 baseline, got " stats.activePathTokens)

        ; Edit the assistant message — _RecomputeActivePath recalculates from token_count (still 10)
        ChatDB.Msg_Edit(aId, "ok")

        stats2 := ChatDB.Msg_GetThreadStats(threadId)
        if stats2.activePathTokens != 10
            throw Error("Expected activePathTokens=10 after edit, got " stats2.activePathTokens)
        this._teardown()
    }

    ; ----------------------------------------------------
    ; Assistant CRUD tests
    ; ----------------------------------------------------

    ; AssistantRepo.GetFromSettings tests — assistants now come from global array, not DB
    GetFromSettings_ReturnsCorrectAssistant() {
        global assistants
        assistants := [{id: "a1", name: "Test Asst", baseModel: "deepseek/test", isDefault: true}]

        asst := AssistantRepo.GetFromSettings("a1")
        if !asst
            throw Error("GetFromSettings returned empty for valid ID")
        if asst.name != "Test Asst"
            throw Error("GetFromSettings returned wrong name: " asst.name)
        if asst.id != "a1"
            throw Error("GetFromSettings returned wrong ID")
    }

    GetFromSettings_UnknownId_ReturnsEmpty() {
        global assistants
        assistants := [{id: "a1", name: "Test", baseModel: "m", isDefault: true}]

        result := AssistantRepo.GetFromSettings("nonexistent-id")
        if result != ""
            throw Error("Expected empty string for unknown ID, got: " (IsObject(result) ? result.name : String(result)))
    }

    GetFromSettings_UnsetGlobal_ReturnsEmpty() {
        global assistants
        assistants := unset

        result := AssistantRepo.GetFromSettings("any-id")
        if result != ""
            throw Error("Expected empty string when assistants global is unset")
    }

    ; ----------------------------------------------------
    ; Thread settings persistence tests
    ; ----------------------------------------------------

    Thread_UpdateSettings_SavesModelOverride() {
        this._openDb()
        threadId := ChatDB.Thread_Create("Test")

        ChatDB.Thread_UpdateSettings(threadId, { modelOverride: "openai/gpt-4.1" })
        settings := ChatDB.Thread_GetSettings(threadId)

        if !settings || settings.modelOverride != "openai/gpt-4.1"
            throw Error("Expected modelOverride 'openai/gpt-4.1', got: " (settings ? settings.modelOverride : "NULL"))
        this._closeDb()
    }

    Thread_UpdateSettings_ClearsModelOverride() {
        this._openDb()
        threadId := ChatDB.Thread_Create("Test")

        ChatDB.Thread_UpdateSettings(threadId, { modelOverride: "openai/gpt-4.1" })
        ChatDB.Thread_UpdateSettings(threadId, { modelOverride: "" })
        settings := ChatDB.Thread_GetSettings(threadId)

        if settings.modelOverride != ""
            throw Error("Expected empty modelOverride after clear, got: " settings.modelOverride)
        this._closeDb()
    }

    Thread_UpdateSettings_SavesAssistantId() {
        global assistants
        assistants := [{id: "asst-test-1", name: "Test", baseModel: "deepseek/test", isDefault: true}]
        this._openDb()
        threadId := ChatDB.Thread_Create("Test")

        ChatDB.Thread_UpdateSettings(threadId, { assistantId: "asst-test-1" })
        settings := ChatDB.Thread_GetSettings(threadId)

        if !settings || settings.assistantId != "asst-test-1"
            throw Error("Expected assistantId to match, got: " (settings ? settings.assistantId : "NULL"))
        this._closeDb()
    }

    Thread_UpdateSettings_SavesAllFields() {
        this._openDb()
        threadId := ChatDB.Thread_Create("Test")

        ChatDB.Thread_UpdateSettings(threadId, {
            modelOverride: "openai/gpt-4.1",
            systemOverride: "You are helpful",
            reasoningOverride: "none",
            temperatureOverride: 0.7
        })
        settings := ChatDB.Thread_GetSettings(threadId)

        if settings.systemOverride != "You are helpful"
            throw Error("Expected systemOverride, got: " settings.systemOverride)
        if settings.reasoningOverride != "none"
            throw Error("Expected reasoningOverride 'none', got: " settings.reasoningOverride)
        if settings.temperatureOverride != "0.7"
            throw Error("Expected temperatureOverride '0.7', got: " settings.temperatureOverride)
        this._closeDb()
    }

    Thread_GetSettings_EmptyThread_ReturnsEmpty() {
        this._openDb()
        threadId := ChatDB.Thread_Create("Test")

        settings := ChatDB.Thread_GetSettings(threadId)

        if settings.modelOverride || settings.systemOverride || settings.reasoningOverride || settings.temperatureOverride
            throw Error("Expected all overrides to be empty for new thread")
        this._closeDb()
    }

    ; ----------------------------------------------------
    ; Usage_Query — now queries chat_usage table
    ; ----------------------------------------------------

    UsageQuery_AcceptsMapInput() {
        this._openDb()

        ; Populate chat_usage directly (same as real inserts would)
        ChatDB.ChatUsage_Upsert({date: FormatTime(, "yyyy-MM-dd"), model: "deepseek-v4-flash", provider: "deepseek",
            prompt_tokens: 30, completion_tokens: 60, thinking_tokens: 10, thinking_tokens: 0, cached_tokens: 5, input_cost: 0.0000042, cached_input_cost: 0.000000014, output_cost: 0.0000168, total_cost: 0.0000210})

        ChatDB.ChatUsage_Upsert({date: FormatTime(, "yyyy-MM-dd"), model: "deepseek-v4-flash", provider: "deepseek",
            prompt_tokens: 20, completion_tokens: 30, thinking_tokens: 0, thinking_tokens: 0, cached_tokens: 0, input_cost: 0.0000028, output_cost: 0.0000084, total_cost: 0.0000112})

        ; Simulate jsongo.Parse() returning a Map (bracket-only access)
        filters := Map("timeRange", "all", "model", "", "type", "all")
        result := ChatDB.Usage_Query(filters)

        if result.chat.Length = 0
            throw Error("Expected chat rows > 0 with Map input, got " result.chat.Length)
        if result.models.Length = 0
            throw Error("Expected at least 1 model, got " result.models.Length)

        ; Verify chat row has aggregated values: call_count=2, prompt=50, comp=90
        first := result.chat[1]
        if first.input_tokens != 50
            throw Error("Expected input_tokens=50, got " first.input_tokens)
        if first.output_tokens != 90
            throw Error("Expected output_tokens=90, got " first.output_tokens)
        if first.message_count != 2
            throw Error("Expected 2 calls grouped, got " first.message_count)

        this._closeDb()
    }

    UsageQuery_RespectsTimeRangeFilter() {
        this._openDb()

        ; Insert today's chat usage
        ChatDB.ChatUsage_Upsert({date: FormatTime(, "yyyy-MM-dd"), model: "deepseek-v4-flash", provider: "deepseek",
            prompt_tokens: 10, completion_tokens: 20, thinking_tokens: 0, cached_tokens: 0, input_cost: 0.0000014, output_cost: 0.0000056, total_cost: 0.0000070})

        ; "day" filter should return today's data
        filters := Map("timeRange", "day", "model", "", "type", "all")
        result := ChatDB.Usage_Query(filters)
        if result.chat.Length = 0
            throw Error("Expected chat rows with 'day' filter, got 0")

        ; "month" filter should also return today's data
        filtersMonth := Map("timeRange", "month", "model", "", "type", "all")
        resultMonth := ChatDB.Usage_Query(filtersMonth)
        if resultMonth.chat.Length = 0
            throw Error("Expected chat rows with 'month' filter, got 0")

        this._closeDb()
    }

    ; ----------------------------------------------------
    ; chat_usage — ChatUsage_Upsert
    ; ----------------------------------------------------

    ChatUsage_Upsert_InsertsNewRow() {
        this._openDb()
        ChatDB.ChatUsage_Upsert({date: FormatTime(, "yyyy-MM-dd"), model: "deepseek-v4-flash", provider: "deepseek",
            prompt_tokens: 10, completion_tokens: 20, thinking_tokens: 0, thinking_tokens: 0, cached_tokens: 0, input_cost: 0.0000014, output_cost: 0.0000056, total_cost: 0.0000070, response_time_ms: 1200})

        row := ChatDB.db.Exec("SELECT * FROM chat_usage WHERE date='" FormatTime(, "yyyy-MM-dd") "' AND model='deepseek-v4-flash'")
        if row.count != 1
            throw Error("Expected 1 row, got " row.count)
        if Integer(row[1,"call_count"]) != 1
            throw Error("Expected call_count=1, got " row[1,"call_count"])
        if Integer(row[1,"prompt_tokens"]) != 10
            throw Error("Expected prompt_tokens=10, got " row[1,"prompt_tokens"])
        this._closeDb()
    }

    ChatUsage_Upsert_UpdatesExistingRow() {
        this._openDb()
        date := FormatTime(, "yyyy-MM-dd")
        ChatDB.ChatUsage_Upsert({date: date, model: "deepseek-v4-flash", provider: "deepseek",
            prompt_tokens: 10, completion_tokens: 20, thinking_tokens: 0, cached_tokens: 0, input_cost: 0.0000014, output_cost: 0.0000056, total_cost: 0.0000070})
        ChatDB.ChatUsage_Upsert({date: date, model: "deepseek-v4-flash", provider: "deepseek",
            prompt_tokens: 15, completion_tokens: 25, thinking_tokens: 0, cached_tokens: 5, input_cost: 0.0000021, cached_input_cost: 0.000000014, output_cost: 0.0000070, total_cost: 0.0000091})

        row := ChatDB.db.Exec("SELECT * FROM chat_usage WHERE date='" date "' AND model='deepseek-v4-flash'")
        if row.count != 1
            throw Error("Expected 1 row (UPSERT), got " row.count)
        if Integer(row[1,"call_count"]) != 2
            throw Error("Expected call_count=2, got " row[1,"call_count"])
        if Integer(row[1,"prompt_tokens"]) != 25
            throw Error("Expected prompt_tokens=25, got " row[1,"prompt_tokens"])
        if Integer(row[1,"completion_tokens"]) != 45
            throw Error("Expected completion_tokens=45, got " row[1,"completion_tokens"])
        this._closeDb()
    }

    ChatUsage_Upsert_TracksCachedInputCost() {
        this._openDb()
        ChatDB.ChatUsage_Upsert({date: FormatTime(, "yyyy-MM-dd"), model: "deepseek-v4-flash", provider: "deepseek",
            prompt_tokens: 100, completion_tokens: 50, thinking_tokens: 0, cached_tokens: 40, input_cost: 0.000014, cached_input_cost: 0.000000112, output_cost: 0.000014, total_cost: 0.000028})

        row := ChatDB.db.Exec("SELECT * FROM chat_usage WHERE date='" FormatTime(, "yyyy-MM-dd") "' AND model='deepseek-v4-flash'")
        if Number(row[1,"cached_input_cost"]) != 0.000000112
            throw Error("Expected cached_input_cost=0.000000112, got " row[1,"cached_input_cost"])
        if Number(row[1,"input_cost"]) != 0.000014
            throw Error("Expected input_cost=0.000014, got " row[1,"input_cost"])
        this._closeDb()
    }

    ; ----------------------------------------------------
    ; Usage_Query — type filter
    ; ----------------------------------------------------

    UsageQuery_TypeFilter_ChatOnly() {
        this._openDb()
        ChatDB.ChatUsage_Upsert({date: FormatTime(, "yyyy-MM-dd"), model: "deepseek-v4-flash", provider: "deepseek",
            prompt_tokens: 10, completion_tokens: 20, thinking_tokens: 0, cached_tokens: 0, input_cost: 0.0000014, output_cost: 0.0000056, total_cost: 0.0000070})
        ChatDB.CommandUsage_Upsert({date: FormatTime(, "yyyy-MM-dd"), model: "deepseek-v4-flash", provider: "deepseek", command_name: "Refine",
            prompt_tokens: 50, completion_tokens: 30, thinking_tokens: 0, cached_tokens: 0, input_cost: 0.000007, output_cost: 0.0000084, total_cost: 0.0000154})

        filters := Map("timeRange", "all", "model", "", "type", "chat")
        result := ChatDB.Usage_Query(filters)
        if result.chat.Length != 1
            throw Error("Expected 1 chat row with type=chat, got " result.chat.Length)
        if result.commands.Length != 0
            throw Error("Expected 0 command rows with type=chat, got " result.commands.Length)
        this._closeDb()
    }

    UsageQuery_TypeFilter_CommandOnly() {
        this._openDb()
        ChatDB.ChatUsage_Upsert({date: FormatTime(, "yyyy-MM-dd"), model: "deepseek-v4-flash", provider: "deepseek",
            prompt_tokens: 10, completion_tokens: 20, thinking_tokens: 0, cached_tokens: 0, input_cost: 0.0000014, output_cost: 0.0000056, total_cost: 0.0000070})
        ChatDB.CommandUsage_Upsert({date: FormatTime(, "yyyy-MM-dd"), model: "deepseek-v4-flash", provider: "deepseek", command_name: "Refine",
            prompt_tokens: 50, completion_tokens: 30, thinking_tokens: 0, cached_tokens: 0, input_cost: 0.000007, output_cost: 0.0000084, total_cost: 0.0000154})

        filters := Map("timeRange", "all", "model", "", "type", "command")
        result := ChatDB.Usage_Query(filters)
        if result.chat.Length != 0
            throw Error("Expected 0 chat rows with type=command, got " result.chat.Length)
        if result.commands.Length != 1
            throw Error("Expected 1 command row with type=command, got " result.commands.Length)
        this._closeDb()
    }

    UsageQuery_ProviderFilter_ChatOnly() {
        this._openDb()
        ChatDB.ChatUsage_Upsert({date: FormatTime(, "yyyy-MM-dd"), model: "deepseek/deepseek-v4-flash", provider: "deepseek",
            prompt_tokens: 10, completion_tokens: 20, thinking_tokens: 0, cached_tokens: 0, input_cost: 0.0000014, output_cost: 0.0000056, total_cost: 0.0000070})
        ChatDB.ChatUsage_Upsert({date: FormatTime(, "yyyy-MM-dd"), model: "google/gemini-2.5-flash", provider: "google",
            prompt_tokens: 30, completion_tokens: 40, thinking_tokens: 0, cached_tokens: 0, input_cost: 0.000009, output_cost: 0.000100, total_cost: 0.000109})

        filters := Map("timeRange", "all", "model", "", "provider", "deepseek", "type", "all")
        result := ChatDB.Usage_Query(filters)
        if result.chat.Length != 1
            throw Error("Expected 1 chat row with provider=deepseek, got " result.chat.Length)
        if result.chat[1].input_tokens != 10
            throw Error("Expected deepseek input_tokens=10, got " result.chat[1].input_tokens)
        this._closeDb()
    }

    ; ----------------------------------------------------
    ; chat_usage — TTFT tracking
    ; ----------------------------------------------------

    ChatUsage_Upsert_TracksTTFT() {
        this._openDb()
        date := FormatTime(, "yyyy-MM-dd")
        ; Insert with ttft_ms — should persist to total_ttft_ms
        ChatDB.ChatUsage_Upsert({date: date, model: "deepseek-v4-flash", provider: "deepseek",
            prompt_tokens: 10, completion_tokens: 20, thinking_tokens: 0, cached_tokens: 0,
            input_cost: 0.0000014, output_cost: 0.0000056, total_cost: 0.0000070,
            response_time_ms: 1200, ttft_ms: 350})
        row := ChatDB.db.Exec("SELECT total_ttft_ms, call_count FROM chat_usage WHERE date='" date "' AND model='deepseek-v4-flash'")
        if Integer(row[1,"total_ttft_ms"]) != 350
            throw Error("Expected total_ttft_ms=350 on INSERT, got " row[1,"total_ttft_ms"])

        ; Second upsert — should accumulate ttft_ms
        ChatDB.ChatUsage_Upsert({date: date, model: "deepseek-v4-flash", provider: "deepseek",
            prompt_tokens: 5, completion_tokens: 10, thinking_tokens: 0, cached_tokens: 0,
            input_cost: 0.0000007, output_cost: 0.0000028, total_cost: 0.0000035,
            response_time_ms: 800, ttft_ms: 200})
        row2 := ChatDB.db.Exec("SELECT total_ttft_ms, call_count FROM chat_usage WHERE date='" date "' AND model='deepseek-v4-flash'")
        if Integer(row2[1,"total_ttft_ms"]) != 550
            throw Error("Expected total_ttft_ms=550 on UPDATE (350+200), got " row2[1,"total_ttft_ms"])
        if Integer(row2[1,"call_count"]) != 2
            throw Error("Expected call_count=2, got " row2[1,"call_count"])
        this._closeDb()
    }

    ; ----------------------------------------------------
    ; command_usage — TTFT tracking
    ; ----------------------------------------------------

    CommandUsage_Upsert_TracksTTFT() {
        this._openDb()
        date := FormatTime(, "yyyy-MM-dd")
        ; Insert with ttft_ms
        ChatDB.CommandUsage_Upsert({date: date, model: "deepseek-v4-flash", provider: "deepseek", command_name: "Summarize",
            prompt_tokens: 50, completion_tokens: 100, thinking_tokens: 0, cached_tokens: 0,
            input_cost: 0.000007, output_cost: 0.000028, total_cost: 0.000035,
            response_time_ms: 2500, ttft_ms: 800})
        row := ChatDB.db.Exec("SELECT total_ttft_ms FROM command_usage WHERE date='" date "' AND model='deepseek-v4-flash' AND command_name='Summarize'")
        if Integer(row[1,"total_ttft_ms"]) != 800
            throw Error("Expected total_ttft_ms=800, got " row[1,"total_ttft_ms"])

        ; Accumulate
        ChatDB.CommandUsage_Upsert({date: date, model: "deepseek-v4-flash", provider: "deepseek", command_name: "Summarize",
            prompt_tokens: 30, completion_tokens: 50, thinking_tokens: 0, cached_tokens: 0,
            input_cost: 0.0000042, output_cost: 0.000014, total_cost: 0.0000182,
            response_time_ms: 1200, ttft_ms: 400})
        row2 := ChatDB.db.Exec("SELECT total_ttft_ms, call_count FROM command_usage WHERE date='" date "' AND model='deepseek-v4-flash' AND command_name='Summarize'")
        if Integer(row2[1,"total_ttft_ms"]) != 1200
            throw Error("Expected total_ttft_ms=1200 on UPSERT (800+400), got " row2[1,"total_ttft_ms"])
        if Integer(row2[1,"call_count"]) != 2
            throw Error("Expected call_count=2, got " row2[1,"call_count"])
        this._closeDb()
    }

    ; ----------------------------------------------------
    ; Usage_Query — total_ttft_ms in chat results
    ; ----------------------------------------------------

    UsageQuery_IncludesTTFT_Chat() {
        this._openDb()
        ChatDB.ChatUsage_Upsert({date: FormatTime(, "yyyy-MM-dd"), model: "deepseek-v4-flash", provider: "deepseek",
            prompt_tokens: 10, completion_tokens: 20, thinking_tokens: 5, cached_tokens: 0,
            input_cost: 0.0000014, output_cost: 0.0000056, total_cost: 0.0000070,
            response_time_ms: 900, ttft_ms: 300})
        filters := Map("timeRange", "all", "model", "", "type", "all")
        result := ChatDB.Usage_Query(filters)
        if result.chat.Length != 1
            throw Error("Expected 1 chat row, got " result.chat.Length)
        if result.chat[1].total_ttft_ms != 300
            throw Error("Expected total_ttft_ms=300 in query result, got " result.chat[1].total_ttft_ms)
        if result.chat[1].total_response_time_ms != 900
            throw Error("Expected total_response_time_ms=900 in query result, got " result.chat[1].total_response_time_ms)
        this._closeDb()
    }

    ; ----------------------------------------------------
    ; Usage_Query — total_ttft_ms in command results
    ; ----------------------------------------------------

    UsageQuery_IncludesTTFT_Command() {
        this._openDb()
        ChatDB.CommandUsage_Upsert({date: FormatTime(, "yyyy-MM-dd"), model: "deepseek-v4-flash", provider: "deepseek", command_name: "Refine",
            prompt_tokens: 50, completion_tokens: 30, thinking_tokens: 0, cached_tokens: 0,
            input_cost: 0.000007, output_cost: 0.0000084, total_cost: 0.0000154,
            response_time_ms: 1500, ttft_ms: 500})
        filters := Map("timeRange", "all", "model", "", "type", "all")
        result := ChatDB.Usage_Query(filters)
        if result.commands.Length != 1
            throw Error("Expected 1 command row, got " result.commands.Length)
        if result.commands[1].total_ttft_ms != 500
            throw Error("Expected total_ttft_ms=500 in query result, got " result.commands[1].total_ttft_ms)
        this._closeDb()
        ; ----------------------------------------------------
        ; Usage_Query — output_tokens is the total (includes thinking),
        ; so JS must NOT add thinking_tokens again for speed calc.
        ; Bug: dashboard double-counted thinking, inflating tok/s.
        ; ----------------------------------------------------
    
        UsageQuery_OutputTokensIncludesThinking() {
            this._openDb()
            ; completion_tokens=50 is the TOTAL (visible 40 + thinking 10)
            ChatDB.ChatUsage_Upsert({date: FormatTime(, "yyyy-MM-dd"), model: "deepseek-v4-flash", provider: "deepseek",
                prompt_tokens: 100, completion_tokens: 50, thinking_tokens: 10, cached_tokens: 0,
                input_cost: 0.000014, output_cost: 0.000014, total_cost: 0.000028,
                response_time_ms: 500, ttft_ms: 150})
            filters := Map("timeRange", "all", "model", "", "type", "all")
            result := ChatDB.Usage_Query(filters)
            ; output_tokens = completion_tokens = 50 (already includes the 10 thinking tokens)
            if result.chat[1].output_tokens != 50
                throw Error("Expected output_tokens=50 (total completion), got " result.chat[1].output_tokens)
            ; thinking_tokens is separate metadata — adding it again would double-count
            if result.chat[1].thinking_tokens != 10
                throw Error("Expected thinking_tokens=10, got " result.chat[1].thinking_tokens)
            ; The correct output for speed = output_tokens (50), NOT output_tokens + thinking_tokens (60)
            this._closeDb()
        }
    
    }

    ; ----------------------------------------------------
    ; chat_usage — TTFT defaults to 0 when not provided
    ; ----------------------------------------------------

    ChatUsage_Upsert_TTFT_DefaultsToZero() {
        this._openDb()
        date := FormatTime(, "yyyy-MM-dd")
        ; Insert without ttft_ms — should default to 0
        ChatDB.ChatUsage_Upsert({date: date, model: "deepseek-v4-flash", provider: "deepseek",
            prompt_tokens: 10, completion_tokens: 20, thinking_tokens: 0, cached_tokens: 0,
            input_cost: 0.0000014, output_cost: 0.0000056, total_cost: 0.0000070,
            response_time_ms: 500})
        row := ChatDB.db.Exec("SELECT total_ttft_ms FROM chat_usage WHERE date='" date "' AND model='deepseek-v4-flash'")
        if Integer(row[1,"total_ttft_ms"]) != 0
            throw Error("Expected total_ttft_ms=0 when not provided, got " row[1,"total_ttft_ms"])
        this._closeDb()
    }

    ; ----------------------------------------------------
    ; SearchMessages — full-text message search
    ; ----------------------------------------------------

    SearchMessages_MatchesContent() {
        threadId := this._setup()
        ChatDB.Msg_Insert({thread_id: threadId, role: "user", content: "hello world testing"})
        ChatDB.Msg_Insert({thread_id: threadId, role: "assistant", content: "response here"})
        results := ChatDB.SearchMessages("hello", threadId)
        if results.Length != 1
            throw Error("Expected 1 match for 'hello', got " results.Length)
        if results[1].messageId = ""
            throw Error("Expected non-empty messageId")
        if results[1].role != "user"
            throw Error("Expected role 'user', got '" results[1].role "'")
        if results[1].contentPreview != "hello world testing"
            throw Error("Expected contentPreview 'hello world testing', got '" results[1].contentPreview "'")
        if results[1].threadTitle != "Test Thread"
            throw Error("Expected threadTitle 'Test Thread', got '" results[1].threadTitle "'")
        this._teardown()
    }

    SearchMessages_NoMatches() {
        threadId := this._setup()
        ChatDB.Msg_Insert({thread_id: threadId, role: "user", content: "hello"})
        results := ChatDB.SearchMessages("xyznonexistent", threadId)
        if results.Length != 0
            throw Error("Expected 0 matches for nonexistent term, got " results.Length)
        this._teardown()
    }

    SearchMessages_ScopedToThread() {
        this._openDb()
        thread1 := ChatDB.Thread_Create("Thread 1")
        thread2 := ChatDB.Thread_Create("Thread 2")
        ChatDB.Msg_Insert({thread_id: thread1, role: "user", content: "unique phrase alpha"})
        ChatDB.Msg_Insert({thread_id: thread2, role: "user", content: "completely different beta"})

        ; Scoped to thread1 — should only find thread1's message
        results := ChatDB.SearchMessages("unique", thread1)
        if results.Length != 1
            throw Error("Expected 1 match scoped to thread1, got " results.Length)
        if results[1].threadId != thread1
            throw Error("Expected threadId to be thread1, got " results[1].threadId)

        ; Scoped to thread2 — should NOT find thread1's message
        results2 := ChatDB.SearchMessages("unique", thread2)
        if results2.Length != 0
            throw Error("Expected 0 matches for 'unique' scoped to thread2, got " results2.Length)

        ; Unscoped (global) — should find the message from thread1
        results3 := ChatDB.SearchMessages("unique")
        if results3.Length != 1
            throw Error("Expected 1 global match for 'unique', got " results3.Length)

        ChatDB.Thread_Delete(thread1)
        ChatDB.Thread_Delete(thread2)
        this._closeDb()
    }

    SearchMessages_ExcludesDeletedThreads() {
        this._openDb()
        thread1 := ChatDB.Thread_Create("Active Thread")
        thread2 := ChatDB.Thread_Create("Deleted Thread")
        ChatDB.Msg_Insert({thread_id: thread1, role: "user", content: "visible message"})
        ChatDB.Msg_Insert({thread_id: thread2, role: "user", content: "hidden message"})

        ; Before soft-delete — both visible
        results := ChatDB.SearchMessages("message")
        if results.Length != 2
            throw Error("Expected 2 matches before delete, got " results.Length)

        ; Soft-delete thread2
        ChatDB.Thread_SoftDelete(thread2)

        ; After soft-delete — only thread1 visible
        results2 := ChatDB.SearchMessages("message")
        if results2.Length != 1
            throw Error("Expected 1 match after delete (deleted thread excluded), got " results2.Length)
        if results2[1].threadId != thread1
            throw Error("Expected remaining result from active thread, got threadId=" results2[1].threadId)

        ChatDB.Thread_Delete(thread1)
        ChatDB.Thread_Delete(thread2)
        this._closeDb()
    }

    SearchMessages_SafeWithSpecialCharacters() {
        threadId := this._setup()
        ; Insert message with SQL-significant chars in content (but search term is safe due to SQLite.Escape)
        ChatDB.Msg_Insert({thread_id: threadId, role: "user", content: "test with apostrophe's and quotes"})
        ; Search for a term containing apostrophe — should be safe due to SQLite.Escape
        results := ChatDB.SearchMessages("apostrophe's")
        if results.Length != 1
            throw Error("Expected 1 match for term with apostrophe, got " results.Length)
        ; Search for % sign — SQL LIKE wildcard, should be escaped
        ChatDB.Msg_Insert({thread_id: threadId, role: "user", content: "50% discount"})
        results2 := ChatDB.SearchMessages("50%")
        if results2.Length != 1
            throw Error("Expected 1 match for term with percent sign, got " results2.Length)
        this._teardown()
    }

    SearchMessages_LimitEnforced() {
        this._openDb()
        threadId := ChatDB.Thread_Create("Bulk Thread")
        ; Insert 25 messages with the same keyword
        loop 25 {
            ChatDB.Msg_Insert({thread_id: threadId, role: "user", content: "keyword match " A_Index})
        }
        results := ChatDB.SearchMessages("keyword", threadId)
        if results.Length > 20
            throw Error("Expected at most 20 results (LIMIT), got " results.Length)
        if results.Length < 2
            throw Error("Expected at least some results, got " results.Length)
        ChatDB.Thread_Delete(threadId)
        this._closeDb()
    }

    ; Case-insensitive: SQLite LIKE is case-insensitive for ASCII by default
    SearchMessages_CaseInsensitive() {
        threadId := this._setup()
        ChatDB.Msg_Insert({thread_id: threadId, role: "user", content: "This is an Error message"})
        ; Search in uppercase — FTS5 matches case-insensitively
        results := ChatDB.SearchMessages("ERROR", threadId)
        if results.Length != 1
            throw Error("Expected 1 case-insensitive match for 'ERROR', got " results.Length)
        ; Search in mixed case
        results2 := ChatDB.SearchMessages("ErRoR", threadId)
        if results2.Length != 1
            throw Error("Expected 1 match for mixed-case 'ErRoR', got " results2.Length)
        this._teardown()
    }

    ; Substring match: LIKE finds mid-word substrings
    SearchMessages_Substring() {
        threadId := this._setup()
        ; "err" is a substring of "error" — LIKE finds it
        ChatDB.Msg_Insert({thread_id: threadId, role: "user", content: "error occurred"})
        results := ChatDB.SearchMessages("err", threadId)
        if results.Length != 1
            throw Error("Expected 1 LIKE fallback match for substring 'err', got " results.Length)
        this._teardown()
    }

    ; Title search: global (un-scoped) search also matches thread titles
    SearchMessages_TitleMatch() {
        this._openDb()
        threadId := ChatDB.Thread_Create("Python Debugging Guide")
        ChatDB.Msg_Insert({thread_id: threadId, role: "user", content: "how do I fix this bug"})

        ; Search for "Python" — title matches, but no message content has "Python"
        results := ChatDB.SearchMessages("Python")
        ; Should find at least the title match
        found := false
        for r in results {
            if r.threadId = threadId && r.messageId = ""
                found := true
        if !found
            throw Error("Expected title match for 'Python' in 'Python Debugging Guide'")
        ; Title result should have empty messageId and role='system'
        for r in results {
            if r.threadId = threadId && r.messageId = "" {
                if r.role != "system"
                    throw Error("Expected title result role='system', got '" r.role "'")
                if r.threadTitle != "Python Debugging Guide"
                    throw Error("Expected threadTitle 'Python Debugging Guide', got '" r.threadTitle "'")
            }
        }

        ChatDB.Thread_Delete(threadId)
        this._closeDb()
    }

    ; Regression: _WalkToLeaf finds the branch leaf, not the given message itself.
    ; When navigateToMessage is called with a user message that has assistant
    ; children, the active leaf must be the last child, not the user message.
    NavigateToMessage_WalksToLeaf() {
        threadId := this._setup()
        uId := ChatDB.Msg_Insert({thread_id: threadId, role: "user", content: "hello"})
        aId := ChatDB.Msg_Insert({thread_id: threadId, role: "assistant", content: "response", parent_id: uId})

        ; Walk from user message — should find assistant as the leaf
        leafId := TreeRepo._WalkToLeaf(uId)
        if leafId != aId
            throw Error("Expected _WalkToLeaf to find assistant (" aId ") as leaf, got " leafId)

        ; Walk from assistant — should return itself (no children)
        leafId2 := TreeRepo._WalkToLeaf(aId)
        if leafId2 != aId
            throw Error("Expected _WalkToLeaf to return assistant itself, got " leafId2)

        ; Set active leaf and verify path includes both messages
        ChatDB.Msg_SetActiveLeaf(threadId, leafId)
        path := ChatDB.Msg_GetActivePath(threadId)
        if path.Length != 2
            throw Error("Expected path length 2 after navigating to user message, got " path.Length)
        if path[1].role != "user" || path[2].role != "assistant"
            throw Error("Expected path: [user, assistant], got: [" path[1].role ", " path[2].role "]")

        this._teardown()

    ; Regression (bug #55): _WalkToLeaf must descend to the NEWEST continuation
    ; (the leaf the tree modal's _findDefaultLeaf picks), not the oldest child.
    WalkToLeaf_PicksNewestContinuation() {
        threadId := this._setup()
        uId := ChatDB.Msg_Insert({thread_id: threadId, role: "user", content: "hello"})
        aId := ChatDB.Msg_Insert({thread_id: threadId, role: "assistant", content: "response", parent_id: uId})
        oldId := ChatDB.Msg_Insert({thread_id: threadId, role: "user", content: "old follow-up", parent_id: aId})
        oldLeaf := ChatDB.Msg_Insert({thread_id: threadId, role: "assistant", content: "old answer", parent_id: oldId})
        newId := ChatDB.Msg_Insert({thread_id: threadId, role: "user", content: "new follow-up", parent_id: aId})
        newLeaf := ChatDB.Msg_Insert({thread_id: threadId, role: "assistant", content: "new answer", parent_id: newId})

        leafId := TreeRepo._WalkToLeaf(aId)
        if leafId != newLeaf
            throw Error("Expected _WalkToLeaf to pick the NEWEST continuation (" newLeaf "), got " leafId)

        ChatDB.Thread_Delete(threadId)
        this._teardown()
    }

        ; Verify FTS5 works independently (not just LIKE fallback).
        ; FTS5 finds whole-word matches; LIKE finds substrings.
        ; Test: search for a whole word → FTS5 should find it.
        ; Then search for a substring → LIKE fallback should find it.
    SearchMessages_FTS5_DirectMatch() {
            threadId := this._setup()
            ChatDB.Msg_Insert({thread_id: threadId, role: "user", content: "the zebra crossed the road"})
    
            ; Whole-word search — FTS5 should find "zebra"
            results := ChatDB.SearchMessages("zebra", threadId)
            if results.Length != 1
                throw Error("Expected 1 FTS5 match for whole word 'zebra', got " results.Length)
    
            ; Substring search — LIKE fallback should find "oss" in "crossed"
            results2 := ChatDB.SearchMessages("oss", threadId)
            if results2.Length != 1
                throw Error("Expected 1 LIKE fallback match for substring 'oss', got " results2.Length)
    
        this._teardown()
    }

        ; Regression: FTS5 MATCH must use proper quoting ('term' not bare term).
        ; SQLite.Escape escapes internal quotes but does NOT wrap in quotes.
        ; If we used SQLite.Escape directly, MATCH would see bare words as column names.
        SearchMessages_FTS5_WithApostrophe() {
            threadId := this._setup()
            ; Content with apostrophe: "user's" — FTS5 should match the word
            ChatDB.Msg_Insert({thread_id: threadId, role: "user", content: "the user's input was helpful"})
    
            ; Search for "user's" — FTS5 tokenizes on apostrophe, matches "user"
            results := ChatDB.SearchMessages("user", threadId)
            if results.Length != 1
                throw Error("Expected 1 FTS5 match for 'user' in 'user''s', got " results.Length)
    
            ; Search for exact word "input" — should definitely match
            results2 := ChatDB.SearchMessages("input", threadId)
            if results2.Length != 1
                throw Error("Expected 1 FTS5 match for 'input', got " results2.Length)
    
            this._teardown()
        }
    
        ; Regression: FTS5 sync must handle content with single quotes.
        ; SQLite.Escape doubles internal quotes (' → '') but does NOT wrap in quotes.
        ; The caller must add wrapping quotes: '" SQLite.Escape(val) "'
        SearchMessages_FTS5_SyncWithQuotes() {
            threadId := this._setup()
            ; Content with apostrophe/single quote — must survive FTS sync round-trip
            ChatDB.Msg_Insert({thread_id: threadId, role: "user", content: "it's working"})
            ChatDB.Msg_Insert({thread_id: threadId, role: "assistant", content: "don't panic"})
    
            ; FTS5 should find "it's" content (tokenized as "it" and "s")
            results := ChatDB.SearchMessages("working", threadId)
            if results.Length != 1
                throw Error("Expected 1 FTS5 match for 'working' after quote content sync, got " results.Length)
    
            ; FTS5 should find "don't" content
            results2 := ChatDB.SearchMessages("panic", threadId)
            if results2.Length != 1
                throw Error("Expected 1 FTS5 match for 'panic' after quote content sync, got " results2.Length)
    
            this._teardown()
        }
    
    }
    
    }

}
