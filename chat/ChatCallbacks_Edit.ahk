; ======================================================
; ChatCallbacks_Edit.ahk — Edit, undelete, and delete callbacks
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

editMessageFromWebView(params, *) {
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
                sibTable := ChatDB.db.Exec("SELECT MAX(sibling_index) as max_idx FROM messages WHERE sibling_group='" siblingGroup "';")
                siblingIndex := sibTable.count ? Integer(sibTable[1, "max_idx"]) + 1 : 1
                break
            }
        }
        ChatDB.Msg_Insert({ thread_id: activeThreadId, role: role, content: content, model: "", parent_id: parentId, sibling_group: siblingGroup, sibling_index: siblingIndex })
        ; Trigger LLM request for the new branch (same as Retry flow)
        path := ChatDB.Msg_GetActivePath(activeThreadId)
        postWebMessage("initChatMode", buildStructuredMessagesFromPath(path))
        chatHistoryJSONRequest := BuildAndWriteRequestFiles()
        postWebMessage("setChatButtonsEnabled", false)
        startLoadingCursor(true)
        sendRequestToLLM(&chatHistoryJSONRequest)
    } else {
        ChatDB.Msg_Edit(id, content)
        path := ChatDB.Msg_GetActivePath(activeThreadId)
        postWebMessage("initChatMode", buildStructuredMessagesFromPath(path))
    }
}

; ----------------------------------------------------
; Undelete message from WebView (undo delete)
; ----------------------------------------------------

undeleteMessageFromWebView(msgId, *) {
    global activeThreadId
    if !msgId || !activeThreadId
        return
    ChatDB.Msg_Undelete(msgId)
    path := ChatDB.Msg_GetActivePath(activeThreadId)
    postWebMessage("initChatMode", buildStructuredMessagesFromPath(path))
}

; ----------------------------------------------------
; Delete message from WebView (D2)
; ----------------------------------------------------

deleteMessageFromWebView(msgId, *) {
    global activeThreadId
    if !msgId || !activeThreadId
        return
    
    ; Find parent before soft-deleting so we can update the active leaf
    currentPath := ChatDB.Msg_GetActivePath(activeThreadId)
    parentId := ""
    for msg in currentPath {
        if msg.id = msgId {
            ; parent is the previous message in the path (if any)
            break
        }
        parentId := msg.id
    }
    
    ChatDB.Msg_SoftDelete(msgId)
    
    ; Update active leaf — if parent exists, navigate there; otherwise set to NULL
    if parentId
        ChatDB.Msg_SetActiveLeaf(activeThreadId, parentId)
    else
        ChatDB.db.Exec("UPDATE chat_threads SET active_leaf_id=NULL, updated_at=datetime('now') WHERE id='" activeThreadId "';")
    
    path := ChatDB.Msg_GetActivePath(activeThreadId)
    postWebMessage("initChatMode", buildStructuredMessagesFromPath(path))
}
