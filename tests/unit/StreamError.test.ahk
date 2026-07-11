; ======================================================
; StreamError.test.ahk — Regression tests for StreamError.ahk
;
; Tests: cancel preserves pendingRetrySiblingGroup
; Bug: _handleStreamCancelled saved with sibling_group="" ignoring pendingRetrySiblingGroup
; ======================================================

class StreamErrorTest {

    static __New() {
        RegisterTestClass("StreamErrorTest")
    }

    _setup() {
        if ChatDB.isOpen {
            oldPath := ChatDB.dbPath
            ChatDB.Close()
            try FileDelete(oldPath)
        }
        ChatDB.Open(A_Temp "\test_streamerr_" A_TickCount ".db")
        return ChatDB.Thread_Create("StreamError Test")
    }

    _teardown() {
        if ChatDB.isOpen {
            dbPath := ChatDB.dbPath
            ChatDB.Close()
            try FileDelete(dbPath)
        }
    }

    ; ----------------------------------------------------
    ; Regression: Cancelled retry uses pendingRetrySiblingGroup
    ; ----------------------------------------------------
    CancelRetry_PreservesSiblingGroup() {
        threadId := this._setup()

        ; Create a message with existing sibling group (2 siblings)
        usrId := ChatDB.Msg_Insert({thread_id: threadId, role: "user", content: "q"})
        sg := ChatDB._UUID()
        ChatDB.Msg_Insert({thread_id: threadId, role: "assistant", content: "a1", parent_id: usrId, sibling_group: sg, sibling_index: 0})
        a2Id := ChatDB.Msg_Insert({thread_id: threadId, role: "assistant", content: "a2", parent_id: usrId, sibling_group: sg, sibling_index: 1})

        ; Simulate retry: set pendingRetrySiblingGroup and active leaf to parent
        global requestParams
        requestParams["pendingRetrySiblingGroup"] := sg
        ChatDB.Msg_SetActiveLeaf(threadId, usrId)

        ; Simulate what _handleStreamCancelled does: insert cancelled message with sibling_group
        cancelledId := ChatDB.Msg_Insert({
            thread_id: threadId, role: "assistant",
            content: "partial response...",
            model: "test-model",
            parent_id: usrId,
            sibling_group: sg,  ; <-- THE FIX: should be sg, not ""
            sibling_index: ChatDB.Msg_GetSiblings(a2Id).Length + 1  ; should be index 2
        })

        ; Verify the cancelled message has a sibling_group
        path := ChatDB.Msg_GetActivePath(threadId)
        lastMsg := path[path.Length]
        if !lastMsg.sibling_group
            throw Error("Cancelled message should have sibling_group, got empty")
        if lastMsg.sibling_group != sg
            throw Error("Cancelled message should have same sibling_group '" sg "', got '" lastMsg.sibling_group "'")

        ; Verify there are now 3 siblings in the group
        sibs := ChatDB.Msg_GetSiblings(cancelledId)
        if sibs.Length < 3
            throw Error("Expected at least 3 siblings after cancel-retry, got " sibs.Length)

        this._teardown()
    }

    ; ----------------------------------------------------
    ; Regression: Cancel without retry (no pendingRetrySiblingGroup) uses empty sibling_group
    ; ----------------------------------------------------
    CancelNoRetry_EmptySiblingGroup() {
        threadId := this._setup()

        usrId := ChatDB.Msg_Insert({thread_id: threadId, role: "user", content: "q"})

        ; Cancel without retry — no pendingRetrySiblingGroup
        global requestParams
        if requestParams.Has("pendingRetrySiblingGroup")
            requestParams.Delete("pendingRetrySiblingGroup")

        cancelledId := ChatDB.Msg_Insert({
            thread_id: threadId, role: "assistant",
            content: "partial...",
            model: "test",
            parent_id: usrId,
            sibling_group: "", sibling_index: 0
        })

        path := ChatDB.Msg_GetActivePath(threadId)
        lastMsg := path[path.Length]
        if lastMsg.sibling_group
            throw Error("Non-retry cancel should have empty sibling_group, got '" lastMsg.sibling_group "'")

        this._teardown()
    }
}
