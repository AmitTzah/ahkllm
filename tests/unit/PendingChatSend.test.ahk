; Persistence failures must be correlated to the optimistic client message.
class PendingChatSendTest {
    static __New() {
        RegisterTestClass("PendingChatSendTest")
    }

    AttachmentSaveFailure_RollsBackAndReportsCorrelatedMessage() {
        this._VerifyFailedSend(false)
    }

    ChangedThread_RejectsSendWithoutPersistingIntoAnotherChat() {
        this._VerifyFailedSend(true)
    }

    _VerifyFailedSend(changedThread) {
        global requestParams, responseWindow, activeThreadId
        oldParams := requestParams, oldWindow := responseWindow, oldThread := activeThreadId
        wasOpen := ChatDB.isOpen
        oldDbPath := wasOpen ? ChatDB.dbPath : ""
        if wasOpen
            ChatDB.Close()
        databasePath := A_Temp "\test_pending_send_" A_TickCount "_" Random(1000, 999999) ".db"
        captured := []
        try {
            ChatDB.Open(databasePath)
            activeThreadId := ChatDB.Thread_Create("Pending send")
            requestParams := Map("uniqueID", "fixture", "mainScriptHiddenHwnd", "0x0")
            responseWindow := { PostWebMessageAsJSON: (obj, json) => captured.Push(json) }
            handleChatSend(Map("message", "Pending image", "clientMessageId", "fixture-request",
                "threadId", changedThread ? "other-thread" : activeThreadId,
                "attachments", [Map("type", "image", "filename", "cover.png", "base64", "")]))
            if ChatDB.Msg_GetActivePath(activeThreadId).Length
                throw Error("Rejected sends must not persist a user message")
            correlated := false
            for json in captured {
                parsed := jsongo.Parse(json)
                if parsed["target"] = "chatMessageSaved" || parsed["target"] = "appendChatMessage"
                    throw Error("Rejected sends must not be acknowledged as saved")
                if parsed["target"] = "chatMessageSaveFailed" {
                    if parsed["data"]["clientMessageId"] != "fixture-request" || parsed["data"]["threadId"] != (changedThread ? "other-thread" : activeThreadId)
                        throw Error("Persistence failure lost its request/thread correlation")
                    correlated := true
                }
            }
            if !correlated
                throw Error("Persistence failure must notify the pending-message UI")
        } finally {
            requestParams := oldParams, responseWindow := oldWindow, activeThreadId := oldThread
            ChatDB.Close()
            try FileDelete(databasePath)
            if wasOpen
                ChatDB.Open(oldDbPath)
        }
    }
}
