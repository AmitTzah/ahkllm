; Edit and delete callbacks

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
    attachments := params.Has("attachments") ? params["attachments"] : []
    removedIds := params.Has("removedAttachmentIds") ? params["removedAttachmentIds"] : []

    ; Delete attachments explicitly removed during edit (deferred deletion)
    for removedId in removedIds {
        ChatDB.Attachment_DeleteOne(removedId)
    }

    if mode = "branch" {
        path := ChatDB.Msg_GetActivePath(activeThreadId)
        parentId := ""
        siblingGroup := ""
        siblingIndex := 0
        role := "assistant"
        model := ""
        tokenCount := 0, promptTokens := 0, thinkingTokens := 0, cachedTokens := 0, activePathTokens := 0
        for i, msg in path {
            if msg.id = id {
                parentId := msg.parent_id
                role := msg.role
                model := msg.model
                if msg.sibling_group {
                    siblingGroup := msg.sibling_group
                } else {
                    siblingGroup := ChatDB._UUID()
                    ChatDB.db.Exec("UPDATE messages SET sibling_group='" SQLite.Escape(siblingGroup) "', sibling_index=0 WHERE id='" SQLite.Escape(id) "';")
                }
                siblingIndex := MessageRepo.GetMaxSiblingIndex(siblingGroup) + 1
                ; Bug #123: capture the source message's token metadata inside
                ; the loop (the for-loop variable is not valid after it exits).
                tokenCount := msg.HasProp("token_count") ? msg.token_count : 0
                promptTokens := msg.HasProp("prompt_tokens") ? msg.prompt_tokens : 0
                thinkingTokens := msg.HasProp("thinking_tokens") ? msg.thinking_tokens : 0
                cachedTokens := msg.HasProp("cached_tokens") ? msg.cached_tokens : 0
                activePathTokens := msg.HasProp("active_path_tokens") && msg.active_path_tokens != "" ? msg.active_path_tokens : 0
                break
            }
        }
        ; Bug #118: this is a LOCAL DB copy - no API call happened, so Insert
        ; must not upsert chat_usage or re-charge the cumulative counters.
        ; Bug #123: carry the source message's token metadata (token_count,
        ; prompt_tokens, thinking, cached, active_path_tokens) so the branch
        ; copy's Context Used and token popover stay faithful to the original.
        newMsgId := ChatDB.Msg_Insert({
            thread_id: activeThreadId, role: role, content: content, model: model,
            parent_id: parentId, sibling_group: siblingGroup, sibling_index: siblingIndex,
            token_count: tokenCount,
            prompt_tokens: promptTokens,
            thinking_tokens: thinkingTokens,
            cached_tokens: cachedTokens,
            active_path_tokens: activePathTokens,
            local_copy: true
        })
        ; Copy attachments from old message to new branch message
        ChatDB.Attachment_CopyForMessage(id, newMsgId)
        ; Save new attachments from edit (skip if already present on message)
        for att in attachments {
            if !IsObject(att)
                continue
            attBase64 := att.Has("base64") ? att["base64"] : ""
            if attBase64 {
                attFilename := att.Has("filename") ? att["filename"] : "unknown"
                attHash := att.Has("contentHash") ? att["contentHash"] : ""
                filePath := ImageUtils.SaveBase64ToFile(attBase64, newMsgId, attFilename, attHash)
                if filePath && !_AttachmentExistsOnMessage(newMsgId, filePath)
                    ChatDB.Attachment_Save(newMsgId, att)
            }
        }
        ; Trigger LLM request for the new branch (same as Retry flow)
        ; Only auto-fire when branching a user message — branching an assistant
        ; message just creates a sibling and updates the view.
        path := ChatDB.Msg_GetActivePath(activeThreadId)
        postWebMessage("updateChatView", buildStructuredMessagesFromPath(path, activeThreadId))
        postThreadStats(activeThreadId)  ; refresh token/cost bar after branch edit
        if (role = "user") {
            _BuildAndFireRequest()
        }
    } else {
        ; Append any new attachments — never delete existing ones (× button handles removal)
        for att in attachments {
            if !IsObject(att)
                continue
            attBase64 := att.Has("base64") ? att["base64"] : ""
            if attBase64 {
                attFilename := att.Has("filename") ? att["filename"] : "unknown"
                attHash := att.Has("contentHash") ? att["contentHash"] : ""
                filePath := ImageUtils.SaveBase64ToFile(attBase64, id, attFilename, attHash)
                if filePath && !_AttachmentExistsOnMessage(id, filePath)
                    ChatDB.Attachment_Save(id, att)
            }
        }
        ChatDB.Msg_Edit(id, content)
        debugLog("[EDIT] Message — id=" id " thread=" activeThreadId)
        path := ChatDB.Msg_GetActivePath(activeThreadId)
        postWebMessage("updateChatView", buildStructuredMessagesFromPath(path, activeThreadId))
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
    debugLog("[DELETE] Message — id=" msgId " thread=" activeThreadId)
    
    path := ChatDB.Msg_GetActivePath(activeThreadId)
    postWebMessage("updateChatView", buildStructuredMessagesFromPath(path, activeThreadId))
    postThreadStats(activeThreadId)  ; refresh token/cost bar after deletion
}

; ----------------------------------------------------
; Helper: check if an attachment with given file_path already exists on a message
; ----------------------------------------------------

_AttachmentExistsOnMessage(msgId, filePath) {
    safeMsgId := SQLite.Escape(msgId)
    safePath := SQLite.Escape(filePath)
    result := ChatDB.db.Exec("SELECT COUNT(*) AS cnt FROM message_attachments WHERE message_id='" safeMsgId "' AND file_path='" safePath "';")
    return result.count && result[1, "cnt"] > 0
}
