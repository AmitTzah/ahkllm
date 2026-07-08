; ======================================================
; ChatCallbacks_Edit.ahk — Edit and delete callbacks
;
; NOTE: #Include'd by ChatWindow.ahk. Has access to:
;   activeThreadId, requestParams, ChatDB,
;   BuildAndWriteRequestFiles, postWebMessage,
;   startLoadingCursor, sendRequestToLLM,
;   buildStructuredMessagesFromPath
; ======================================================

; ----------------------------------------------------
; Edit message from WebView (D1)
; ----------------------------------------------------

handleEdit(params, *) {
    global activeThreadId
    if !params.Has("id") || !params.Has("content") || !activeThreadId
        return

    id := params["id"]
    content := params["content"]
    mode := params.Has("mode") ? params["mode"] : "overwrite"

    if mode = "branch" {
        path := ChatDB.Msg_GetActivePath(activeThreadId)
        parentId := ""
        siblingGroup := ""
        siblingIndex := 0
        role := "assistant"
        for i, msg in path {
            if msg.id = id {
                parentId := msg.parent_id
                role := msg.role
                if msg.sibling_group {
                    siblingGroup := msg.sibling_group
                } else {
                    siblingGroup := ChatDB._UUID()
                    ChatDB.db.Exec("UPDATE messages SET sibling_group='" siblingGroup "', sibling_index=0 WHERE id='" id "';")
                }
                siblingIndex := MessageRepo.GetMaxSiblingIndex(siblingGroup) + 1
                break
            }
        }
        ChatDB.Msg_Insert({ thread_id: activeThreadId, role: role, content: content, model: "", parent_id: parentId, sibling_group: siblingGroup, sibling_index: siblingIndex })
        ; Trigger LLM request for the new branch (same as Retry flow)
        path := ChatDB.Msg_GetActivePath(activeThreadId)
        postWebMessage("updateChatView", buildStructuredMessagesFromPath(path))
        postThreadStats(activeThreadId)  ; refresh token/cost bar after branch edit
        _BuildAndFireRequest()
    } else {
        ChatDB.Msg_Edit(id, content)
        path := ChatDB.Msg_GetActivePath(activeThreadId)
        postWebMessage("updateChatView", buildStructuredMessagesFromPath(path))
        postThreadStats(activeThreadId)  ; refresh token/cost bar after edit
    }
}

; ----------------------------------------------------
; Delete message from WebView (D2) — hard-delete with re-parenting
; ----------------------------------------------------

handleDelete(msgId, *) {
    global activeThreadId
    if !msgId || !activeThreadId
        return
    
    ; Msg_HardDelete handles re-parenting and active_leaf_id internally.
    ; No need to manually find parent or update active leaf — the method
    ; re-parents children to the deleted message's parent and only moves
    ; active_leaf_id if the deleted message was the leaf itself.
    ChatDB.Msg_HardDelete(msgId)
    
    path := ChatDB.Msg_GetActivePath(activeThreadId)
    postWebMessage("updateChatView", buildStructuredMessagesFromPath(path))
    postThreadStats(activeThreadId)  ; refresh token/cost bar after deletion
}
