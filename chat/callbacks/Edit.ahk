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
    ; The visible-thread gate protects the callback, but IDs are globally
    ; unique and can be stale. Validate ownership before any attachment
    ; mutation or branch/source lookup can touch another thread.
    ownership := ChatDB.db.Query("SELECT id FROM messages WHERE id=? AND thread_id=?;", id, activeThreadId)
    if !ownership.count
        return
    mode := params.Has("mode") ? params["mode"] : "overwrite"
    attachments := params.Has("attachments") ? params["attachments"] : []
    removedIds := params.Has("removedAttachmentIds") ? params["removedAttachmentIds"] : []

    if mode = "branch" {
        transactionStarted := false
        try {
        ChatDB.BeginTransaction()
        transactionStarted := true
        path := ChatDB.Msg_GetActivePath(activeThreadId)
        parentId := ""
        siblingGroup := ""
        siblingIndex := 0
        role := "assistant"
        model := ""
        tokenCount := 0, promptTokens := 0, thinkingTokens := 0, cachedTokens := 0, activePathTokens := 0
        reasoning := ""
        found := false
        for i, msg in path {
            if msg.id = id {
                found := true
                parentId := msg.parent_id
                role := msg.role
                model := msg.model
                if msg.sibling_group {
                    siblingGroup := msg.sibling_group
                } else {
                    siblingGroup := ChatDB._UUID()
                    ChatDB.db.Query("UPDATE messages SET sibling_group=?, sibling_index=0 WHERE id=?;", siblingGroup, id)
                }
                siblingIndex := MessageRepo.GetMaxSiblingIndex(siblingGroup) + 1
                ; Bug #123: capture the source message's token metadata inside
                ; the loop (the for-loop variable is not valid after it exits).
                tokenCount := msg.HasProp("token_count") ? msg.token_count : 0
                promptTokens := msg.HasProp("prompt_tokens") ? msg.prompt_tokens : 0
                thinkingTokens := msg.HasProp("thinking_tokens") ? msg.thinking_tokens : 0
                cachedTokens := msg.HasProp("cached_tokens") ? msg.cached_tokens : 0
                activePathTokens := msg.HasProp("active_path_tokens") && msg.active_path_tokens != "" ? msg.active_path_tokens : 0
                ; Bug #154: the branch copy must carry the source's reasoning/
                ; thinking CONTENT too - the Thought Process block and the
                ; thinking tokens must stay together (fork copies already do).
                reasoning := msg.HasProp("reasoning") ? msg.reasoning : ""
                break
            }
        }
        ; Branching is only valid from a message on the current active path.
        ; Never let the default assistant/root metadata below turn a missing
        ; or off-path source into a durable bogus root.
        if !found {
            ChatDB.RollbackTransaction()
            transactionStarted := false
            return
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
            reasoning: reasoning,
            local_copy: true
        })
        ; Bug #146: copy the source message's attachments EXCEPT the ones the
        ; user removed during the edit - the ORIGINAL message keeps its
        ; attachment (it stays in the tree with its original content), while
        ; the new branch is created without the removed one.
        ChatDB.Attachment_CopyForMessage(id, newMsgId, removedIds)
        ; Save new attachments from edit as part of the same transaction.
        _SaveEditAttachments(newMsgId, attachments)
        ChatDB.CommitTransaction()
        transactionStarted := false
        } catch Error as e {
            if transactionStarted
                ChatDB.RollbackTransaction()
            postWebMessage("showError", { message: "Edit failed: " e.Message })
            return
        }
        ; Trigger LLM request for the new branch (same as Retry flow)
        ; Only auto-fire when branching a user message - branching an assistant
        ; message just creates a sibling and updates the view.
        path := ChatDB.Msg_GetActivePath(activeThreadId)
        postWebMessage("updateChatView", buildStructuredMessagesFromPath(path, activeThreadId))
        postThreadStats(activeThreadId)  ; refresh token/cost bar after branch edit
        if (role = "user") {
            ; Bug #203: branch-edit auto-fire is a normal chat exchange - stream.
            requestParams["stream"] := true
            _BuildAndFireRequest()
        }
    } else {
        transactionStarted := false
        try {
        ChatDB.BeginTransaction()
        transactionStarted := true
        ; Overwrite mode: delete attachments explicitly removed during edit
        ; (deferred deletion) - the original message IS being rewritten, so the
        ; removal applies to it.
        for removedId in removedIds {
            ChatDB.Attachment_DeleteOne(removedId, activeThreadId)
        }
        ; Append any new attachments - never delete existing ones (× button handles removal)
        _SaveEditAttachments(id, attachments)
        ChatDB.Msg_Edit(id, content, activeThreadId)
        ChatDB.CommitTransaction()
        transactionStarted := false
        } catch Error as e {
            if transactionStarted
                ChatDB.RollbackTransaction()
            postWebMessage("showError", { message: "Edit failed: " e.Message })
            return
        }
        debugLog("[EDIT] Message - id=" id " thread=" activeThreadId)
        path := ChatDB.Msg_GetActivePath(activeThreadId)
        postWebMessage("updateChatView", buildStructuredMessagesFromPath(path, activeThreadId))
        postThreadStats(activeThreadId)  ; refresh token/cost bar after edit
    }
}

; Save every submitted attachment as part of the caller's transaction.
_SaveEditAttachments(msgId, attachments) {
    for att in attachments {
        if !IsObject(att)
            throw Error("Attachment could not be saved.")
        if !ChatDB.Attachment_Save(msgId, att)
            throw Error("Attachment could not be saved.")
    }
}

; ----------------------------------------------------
; Delete message from WebView (D2) - hard-delete with re-parenting
; ----------------------------------------------------

handleDelete(msgId, *) {
    global activeThreadId
    if !msgId || !activeThreadId
        return
    
    ; Msg_HardDelete handles re-parenting and active_leaf_id internally.
    ; No need to manually find parent or update active leaf - the method
    ; re-parents children to the deleted message's parent and only moves
    ; active_leaf_id if the deleted message was the leaf itself.
    ChatDB.Msg_HardDelete(msgId, activeThreadId)
    debugLog("[DELETE] Message - id=" msgId " thread=" activeThreadId)
    
    path := ChatDB.Msg_GetActivePath(activeThreadId)
    postWebMessage("updateChatView", buildStructuredMessagesFromPath(path, activeThreadId))
    postThreadStats(activeThreadId)  ; refresh token/cost bar after deletion
}

; ----------------------------------------------------
; Helper: check if an attachment with given file_path already exists on a message
; ----------------------------------------------------

_AttachmentExistsOnMessage(msgId, filePath) {
    result := ChatDB.db.Query("SELECT COUNT(*) AS cnt FROM message_attachments WHERE message_id=? AND file_path=?;", msgId, filePath)
    return result.count && result[1, "cnt"] > 0
}
