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
        newMsgId := ChatDB.Msg_Insert({ thread_id: activeThreadId, role: role, content: content, model: "", parent_id: parentId, sibling_group: siblingGroup, sibling_index: siblingIndex })
        ; Copy attachments from old message to new branch message
        ChatDB.Attachment_CopyForMessage(id, newMsgId)
        ; Save new attachments from edit
        for att in attachments {
            if !IsObject(att)
                continue
            attType := att.Has("type") ? att["type"] : "text_file"
            attMime := att.Has("mimeType") ? att["mimeType"] : ""
            attFilename := att.Has("filename") ? att["filename"] : "unknown"
            attBase64 := att.Has("base64") ? att["base64"] : ""
            attSize := att.Has("size") ? att["size"] : 0
            attExtracted := att.Has("extractedText") ? att["extractedText"] : ""
            attHash := att.Has("contentHash") ? att["contentHash"] : ""
            if attBase64 {
                filePath := ImageUtils.SaveBase64ToFile(attBase64, newMsgId, attFilename, attHash)
                if filePath && !_AttachmentExistsOnMessage(newMsgId, filePath)
                    ChatDB.Attachment_Insert(newMsgId, { attachment_type: attType, file_path: filePath, mime_type: attMime, original_filename: attFilename, file_size: attSize, extracted_text: attExtracted })
            }
        }
        ; Trigger LLM request for the new branch (same as Retry flow)
        path := ChatDB.Msg_GetActivePath(activeThreadId)
        postWebMessage("updateChatView", buildStructuredMessagesFromPath(path, activeThreadId))
        postThreadStats(activeThreadId)  ; refresh token/cost bar after branch edit
        _BuildAndFireRequest()
    } else {
        ; Append any new attachments — never delete existing ones (× button handles removal)
        for att in attachments {
            if !IsObject(att)
                continue
            attType := att.Has("type") ? att["type"] : "text_file"
            attFilename := att.Has("filename") ? att["filename"] : "unknown"
            attBase64 := att.Has("base64") ? att["base64"] : ""
            attSize := att.Has("size") ? att["size"] : 0
            attExtracted := att.Has("extractedText") ? att["extractedText"] : ""
            attHash := att.Has("contentHash") ? att["contentHash"] : ""
            if attBase64 {
                filePath := ImageUtils.SaveBase64ToFile(attBase64, id, attFilename, attHash)
                if filePath && !_AttachmentExistsOnMessage(id, filePath)
                    ChatDB.Attachment_Insert(id, { attachment_type: attType, file_path: filePath, mime_type: att.Has("mimeType") ? att["mimeType"] : "", original_filename: attFilename, file_size: attSize, extracted_text: attExtracted })
            }
        }
        ChatDB.Msg_Edit(id, content)
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
