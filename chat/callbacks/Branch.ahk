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
    debugLog("[BRANCH] Switch — thread=" activeThreadId " leaf=" id)
    postWebMessage("updateChatView", buildStructuredMessagesFromPath(result.path, activeThreadId))
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
    debugLog("[THREAD] Forked — id=" newThreadId " from=" activeThreadId)
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

; Find which message to retry: specific assistant by id, or last assistant in path.
; Returns { targetMsg, parentMsg } — both empty if no retry target found.
_findRetryTarget(path, messageId) {
    if messageId && path.Length {
        for i, msg in path {
            if msg.id = messageId && msg.role = "assistant" {
                parentMsg := i > 1 ? path[i - 1] : ""
                return { targetMsg: msg, parentMsg: parentMsg }
            }
        }
    }
    if path.Length && path[path.Length].role = "assistant" {
        parentMsg := path.Length > 1 ? path[path.Length - 1] : ""
        return { targetMsg: path[path.Length], parentMsg: parentMsg }
    }
    return { targetMsg: "", parentMsg: "" }
}

; Ensure the message has a sibling_group, creating one if needed.
; Sets sibling_index=0 on the message. Returns the sibling group UUID.
_setupSiblingGroup(msg) {
    sg := msg.sibling_group
    if !sg {
        sg := ChatDB._UUID()
        ChatDB.db.Exec("UPDATE messages SET sibling_group='" sg "', sibling_index=0 WHERE id='" msg.id "';")
    }
    return sg
}

retryAction(messageId := "") {
    global activeThreadId, requestParams
    if !activeThreadId
        return
    path := ChatDB.Msg_GetActivePath(activeThreadId)
    target := _findRetryTarget(path, messageId)

    if target.targetMsg {
        requestParams["pendingRetrySiblingGroup"] := _setupSiblingGroup(target.targetMsg)
        if target.parentMsg
            ChatDB.Msg_SetActiveLeaf(activeThreadId, target.parentMsg.id)
    } else if path.Length && path[path.Length].role = "user" {
        ; Chat ends with user (e.g. assistant was deleted). Clear stale retry state.
        if requestParams.Has("pendingRetrySiblingGroup")
            requestParams.Delete("pendingRetrySiblingGroup")
    }

    if requestParams.Has("pendingRetrySiblingGroup") || (path.Length && path[path.Length].role = "user")
        _BuildAndFireRequest()
}
