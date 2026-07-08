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

    ; --------------------
    ; Retry middle assistant — set active leaf to its parent
    ; This tests the DB-level logic behind buttonClickAction("Retry", messageId)
    ; for a targeted retry on an assistant that is NOT the last message.
    ; --------------------

    RetryMiddleAssistant_TargetsCorrectPath() {
        threadId := this._setup()

        ; Create 4-message path: user1 → assistant1 → user2 → assistant2
        usr1Id := ChatDB.Msg_Insert({thread_id: threadId, role: "user", content: "u1"})
        a1Id := ChatDB.Msg_Insert({thread_id: threadId, role: "assistant", content: "a1", parent_id: usr1Id})
        usr2Id := ChatDB.Msg_Insert({thread_id: threadId, role: "user", content: "u2", parent_id: a1Id})
        asst2Id := ChatDB.Msg_Insert({thread_id: threadId, role: "assistant", content: "a2", parent_id: usr2Id})

        ; Verify full path before retry
        path := ChatDB.Msg_GetActivePath(threadId)
        if path.Length != 4
            throw Error("Expected 4 messages before retry, got " path.Length)

        ; Simulate retry on assistant1:
        ; 1. Assign sibling_group to assistant1 (so new response becomes a sibling)
        sg := ChatDB._UUID()
        ChatDB.db.Exec("UPDATE messages SET sibling_group='" sg "', sibling_index=0 WHERE id='" a1Id "';")

        ; 2. Set active leaf to assistant1's parent (user1)
        ChatDB.Msg_SetActiveLeaf(threadId, usr1Id)

        ; 3. Verify active path is now [user1] only
        path2 := ChatDB.Msg_GetActivePath(threadId)
        if path2.Length != 1
            throw Error("Expected 1 message after targeted retry, got " path2.Length)
        if path2[1].id != usr1Id
            throw Error("Expected path to contain user1 after retry, got id=" path2[1].id)
        if path2[1].role != "user"
            throw Error("Expected path to end with 'user' after retry, got '" path2[1].role "'")

        ; 4. Simulate LLM response: insert new assistant with sibling_group
        ;    (matching what saveStreamResponse does)
        a3Id := ChatDB.Msg_Insert({thread_id: threadId, role: "assistant", content: "a3_retried", parent_id: usr1Id, sibling_group: sg, sibling_index: 1})

        ; 5. Set active leaf to the new response
        ChatDB.Msg_SetActiveLeaf(threadId, a3Id)

        ; 6. Verify path is now [user1, a3_retried]
        path3 := ChatDB.Msg_GetActivePath(threadId)
        if path3.Length != 2
            throw Error("Expected 2 messages after retry response, got " path3.Length)
        if path3[2].content != "a3_retried"
            throw Error("Expected 'a3_retried' after retry, got '" path3[2].content "'")

        ; 7. Verify both siblings exist
        sibs := ChatDB.Msg_GetSiblings(a1Id)
        if sibs.Length != 2
            throw Error("Expected 2 siblings after retry, got " sibs.Length)

        this._teardown()
    }

    ; --------------------
    ; buildStructuredMessagesFromPath includes siblingInfo and reasoning
    ; --------------------

    BuildStructuredMessages_IncludesMetadata() {
        threadId := this._setup()

        ; Create path with a message that has reasoning
        usrId := ChatDB.Msg_Insert({thread_id: threadId, role: "user", content: "Think step by step"})
        a1Id := ChatDB.Msg_Insert({thread_id: threadId, role: "assistant", content: "Final answer: 42", model: "deepseek-v4-flash", parent_id: usrId, reasoning: "Let me think...\nStep 1: x = 1\nStep 2: answer = 42"})

        ; Check structured output without siblingInfo
        path1 := ChatDB.Msg_GetActivePath(threadId)
        struct1 := buildStructuredMessagesFromPath(path1)
        if struct1.Length != 2
            throw Error("Expected 2 structured messages, got " struct1.Length)
        if !struct1[2].HasOwnProp("reasoning")
            throw Error("Expected reasoning field on assistant message")
        if struct1[2].reasoning != "Let me think...\nStep 1: x = 1\nStep 2: answer = 42"
            throw Error("Reasoning content mismatch, got '" struct1[2].reasoning "'")
        if struct1[2].model != "deepseek-v4-flash"
            throw Error("Expected model field, got '" struct1[2].model "'")

        ; Now add a sibling and verify siblingInfo appears in structured output
        sg := ChatDB._UUID()
        ChatDB.db.Exec("UPDATE messages SET sibling_group='" sg "', sibling_index=0 WHERE id='" a1Id "';")
        a2Id := ChatDB.Msg_Insert({thread_id: threadId, role: "assistant", content: "Alternative: 7", model: "deepseek-v4-flash", parent_id: usrId, sibling_group: sg, sibling_index: 1})

        ; Switch to the sibling to get siblingInfo in the path
        result := ChatDB.Msg_SwitchBranch(threadId, a1Id, 1)

        path2 := ChatDB.Msg_GetActivePath(threadId)
        struct2 := buildStructuredMessagesFromPath(path2)
        if struct2.Length != 2
            throw Error("Expected 2 structured messages with sibling, got " struct2.Length)

        ; The new active path has the second sibling (a2Id, sibling_index=1 → 1-based display = 2)
        if !struct2[2].HasOwnProp("siblingInfo")
            throw Error("Expected siblingInfo on message with sibling_group")
        if struct2[2].siblingInfo.index != 2
            throw Error("Expected siblingInfo.index = 2, got " struct2[2].siblingInfo.index)
        if struct2[2].siblingInfo.total != 2
            throw Error("Expected siblingInfo.total = 2, got " struct2[2].siblingInfo.total)

        this._teardown()
    }

    ; --------------------
    ; Regression: Retry when path ends with user (assistant was deleted).
    ; Verifies that after hard-deleting an assistant, inserting a new
    ; assistant response (without sibling_group) produces the correct path.
    ; This is the DB-level precondition for the empty-input retry flow
    ; where onChatSend() sends {action:'retry'} and buttonClickAction("Retry")
    ; detects path ends with user → builds request without sibling_group.
    ; --------------------

    RetryAfterAssistantDeleted_InsertsWithoutSiblingGroup() {
        threadId := this._setup()

        ; Create: user → assistant
        usrId := ChatDB.Msg_Insert({thread_id: threadId, role: "user", content: "Hello"})
        asstId := ChatDB.Msg_Insert({thread_id: threadId, role: "assistant", content: "Hi there!", model: "deepseek-v4-flash", parent_id: usrId})

        ; Delete the assistant (simulates user clicking delete on assistant bubble)
        ChatDB.Msg_HardDelete(asstId)
        path := ChatDB.Msg_GetActivePath(threadId)
        if path.Length != 1
            throw Error("Expected 1 message after delete, got " path.Length)
        if path[path.Length].role != "user"
            throw Error("Expected path to end with user after assistant deletion, got '" path[path.Length].role "'")

        ; Simulate LLM response to the "resend": insert new assistant
        ; No sibling_group — this is a fresh response, not a retry replacement
        newAsstId := ChatDB.Msg_Insert({
            thread_id: threadId, role: "assistant",
            content: "New response after resend",
            model: "deepseek-v4-flash",
            parent_id: usrId
        })

        ; Verify path is: user → new_assistant
        path2 := ChatDB.Msg_GetActivePath(threadId)
        if path2.Length != 2
            throw Error("Expected 2 messages after resend response, got " path2.Length)
        if path2[1].id != usrId
            throw Error("Expected first message to be original user")
        if path2[2].id != newAsstId
            throw Error("Expected second message to be new assistant response")
        if path2[2].content != "New response after resend"
            throw Error("Expected new assistant content, got '" path2[2].content "'")

        this._teardown()
    }

    ; --------------------
    ; Regression: HardDelete assistant → path ends with user →
    ; buildStructuredMessagesFromPath returns only user messages.
    ; This validates the JS-side precondition: after deletion,
    ; updateChatView sends only the user message to the WebView,
    ; so onChatSend() correctly identifies role='user' as last.
    ; --------------------

    BuildStructuredMessages_AfterDelete_EndsWithUser() {
        threadId := this._setup()

        ; Create: user → assistant
        usrId := ChatDB.Msg_Insert({thread_id: threadId, role: "user", content: "Query"})
        asstId := ChatDB.Msg_Insert({thread_id: threadId, role: "assistant", content: "Answer", model: "deepseek-v4-flash", parent_id: usrId})

        ; Delete assistant
        ChatDB.Msg_HardDelete(asstId)
        path := ChatDB.Msg_GetActivePath(threadId)
        struct := buildStructuredMessagesFromPath(path)

        if struct.Length != 1
            throw Error("Expected 1 structured message after delete, got " struct.Length)
        if struct[1].role != "user"
            throw Error("Expected structured message role='user', got '" struct[1].role "'")
        if struct[1].content != "Query"
            throw Error("Expected structured message content='Query', got '" struct[1].content "'")

        this._teardown()
    }
}
