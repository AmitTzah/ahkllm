; ======================================================
; ChatCallbacks_Branch.ahk — Branch navigation, fork,
; feedback, and button click (Retry) callbacks
;
; NOTE: #Include'd by ChatWindow.ahk. Has access to:
;   activeThreadId, requestParams, chatWindow, ChatDB,
;   BuildAndWriteRequestFiles, postWebMessage,
;   startLoadingCursor, sendRequestToLLM, cURLState,
;   buildStructuredMessagesFromPath
; ======================================================

; ----------------------------------------------------
; Switch branch from WebView (D3)
; ----------------------------------------------------

handleBranchSwitch(params, *) {
    global activeThreadId
    if !params.Has("id") || !activeThreadId
        return
    id := params["id"]
    direction := params.Has("direction") ? params["direction"] : 1
    result := ChatDB.Msg_SwitchBranch(activeThreadId, id, direction)
    postWebMessage("updateChatView", buildStructuredMessagesFromPath(result.path))
    postWebMessage("updateBranchInfo", { msgId: id, siblingInfo: result.siblingInfo })
    postThreadStats(activeThreadId)
}

; ----------------------------------------------------
; Fork/duplicate chat from WebView (D7)
; ----------------------------------------------------

handleFork(msgId, *) {
    global activeThreadId
    if !msgId || !activeThreadId
        return
    newThreadId := ChatDB.Msg_ForkThread(activeThreadId, msgId)
    if newThreadId
        postWebMessage("threadForked", { newThreadId: newThreadId })
}

; ----------------------------------------------------
; Set message feedback from WebView (D8)
; ----------------------------------------------------

handleFeedback(params, *) {
    if !params.Has("id")
        return
    ChatDB.Msg_SetFeedback(params["id"], params.Has("rating") ? params["rating"] : 0)
}

; ----------------------------------------------------
; Button click actions
; ----------------------------------------------------

retryAction(messageId := "") {
    global activeThreadId, chatWindow, requestParams
            if !activeThreadId
                return
            path := ChatDB.Msg_GetActivePath(activeThreadId)
            targetMsg := ""
            parentMsg := ""
            if messageId && path.Length {
                ; Find the specific assistant to retry (and its parent)
                for i, msg in path {
                    if msg.id = messageId && msg.role = "assistant" {
                        targetMsg := msg
                        if i > 1
                            parentMsg := path[i - 1]
                        break
                    }
                }
            }
            if targetMsg {
                ; Retry specific assistant
                siblingGroup := targetMsg.sibling_group
                if !siblingGroup {
                    siblingGroup := ChatDB._UUID()
                    ChatDB.db.Exec("UPDATE messages SET sibling_group='" siblingGroup "', sibling_index=0 WHERE id='" targetMsg.id "';")
                }
                requestParams["pendingRetrySiblingGroup"] := siblingGroup
                if parentMsg
                    ChatDB.Msg_SetActiveLeaf(activeThreadId, parentMsg.id)
            } else if path.Length && path[path.Length].role = "assistant" {
                ; Legacy: retry last assistant
                oldMsg := path[path.Length]
                siblingGroup := oldMsg.sibling_group
                if !siblingGroup {
                    siblingGroup := ChatDB._UUID()
                    ChatDB.db.Exec("UPDATE messages SET sibling_group='" siblingGroup "', sibling_index=0 WHERE id='" oldMsg.id "';")
                }
                requestParams["pendingRetrySiblingGroup"] := siblingGroup
                if path.Length > 1
                    ChatDB.Msg_SetActiveLeaf(activeThreadId, path[path.Length - 1].id)
            } else if path.Length && path[path.Length].role = "user" {
                ; Chat ends with user (e.g. assistant was deleted) — just resend
                ; the current chat. No sibling group needed since we aren't
                ; replacing an existing assistant. Clear any stale retry state.
                if requestParams.Has("pendingRetrySiblingGroup")
                    requestParams.Delete("pendingRetrySiblingGroup")
            }
            ; Send to LLM if we have a retry pending OR if chat ends with user
    if requestParams.Has("pendingRetrySiblingGroup") || (path.Length && path[path.Length].role = "user")
        _BuildAndFireRequest()
}
