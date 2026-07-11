; ======================================================
; ChatCallbacks_Message.ahk — Send and retry callbacks
; ======================================================

handleChatSend(params, *) {
    global activeThreadId
    try {
    debugLog("[ATTACH] handleChatSend ENTER — activeThreadId=" activeThreadId, "AttachPipeline")
    message := params.Has("message") ? params["message"] : ""
    attachments := params.Has("attachments") ? params["attachments"] : []
    debugLog("[ATTACH] message='" message "' attachments.Length=" attachments.Length, "AttachPipeline")

    if !message && !attachments.Length {
        debugLog("[ATTACH] ABORT: no message and no attachments", "AttachPipeline")
        return
    }

    ; Log each attachment
    try {
        debugLog("[ATTACH] About to iterate attachments, type=" Type(attachments), "AttachPipeline")
        for i, att in attachments {
            if IsObject(att) {
                attType := att.Has("type") ? att["type"] : "?"
                attFname := att.Has("filename") ? att["filename"] : "?"
                attB64Len := att.Has("base64") ? StrLen(att["base64"]) : 0
                attExtLen := att.Has("extractedText") ? StrLen(att["extractedText"]) : 0
                debugLog("[ATTACH] attachment[" i "]: type=" attType " file=" attFname " base64Len=" attB64Len " extractedLen=" attExtLen, "AttachPipeline")
            }
        }
    } catch Error as e {
        debugLog("[ATTACH] ERROR iterating attachments: " e.Message " at line " e.Line, "AttachPipeline")
    }

    ; Auto-create thread if first message
    if !activeThreadId {
        debugLog("[ATTACH] Creating new thread (no activeThreadId)", "AttachPipeline")
        activeThreadId := ChatDB.Thread_Create("New Chat")
        _saveCurrentSettingsToThread(activeThreadId)
        _postThreadListRefresh()
    }

    startLoadingCursor(true)
    postWebMessage("setChatButtonsEnabled", false)

    path := ChatDB.Msg_GetActivePath(activeThreadId)
    lastMsgId := path.Length ? path[path.Length].id : ""
    debugLog("[ATTACH] activePath length=" path.Length " lastMsgId=" lastMsgId, "AttachPipeline")

    msgId := ChatDB.Msg_Insert({
        thread_id: activeThreadId,
        role: "user",
        content: message,
        parent_id: lastMsgId,
        sibling_group: "",
        sibling_index: 0
    })
    debugLog("[ATTACH] user message inserted msgId=" msgId, "AttachPipeline")

    ; Process attachments
    for att in attachments {
        if !IsObject(att) {
            debugLog("[ATTACH] SKIP non-object attachment", "AttachPipeline")
            continue
        }
        attType := att.Has("type") ? att["type"] : "text_file"
        attMime := att.Has("mimeType") ? att["mimeType"] : ""
        attFilename := att.Has("filename") ? att["filename"] : "unknown"
        attBase64 := att.Has("base64") ? att["base64"] : ""
        attSize := att.Has("size") ? att["size"] : 0
        attExtracted := att.Has("extractedText") ? att["extractedText"] : ""
        attHash := att.Has("contentHash") ? att["contentHash"] : ""

        debugLog("[ATTACH] processing: type=" attType " file=" attFilename " size=" attSize " base64Len=" StrLen(attBase64) " hash=" (attHash ? SubStr(attHash, 1, 8) "..." : "none"), "AttachPipeline")

        if attBase64 {
            filePath := ImageUtils.SaveBase64ToFile(attBase64, msgId, attFilename, attHash)
            debugLog("[ATTACH] SaveBase64ToFile result: " filePath, "AttachPipeline")
            if filePath {
                attId := ChatDB.Attachment_Insert(msgId, {
                    attachment_type: attType,
                    file_path: filePath,
                    mime_type: attMime,
                    original_filename: attFilename,
                    file_size: attSize,
                    extracted_text: attExtracted
                })
                debugLog("[ATTACH] Attachment_Insert done attId=" attId, "AttachPipeline")
            } else {
                debugLog("[ATTACH] WARNING: SaveBase64ToFile returned empty for " attFilename, "AttachPipeline")
            }
        } else {
            debugLog("[ATTACH] WARNING: attBase64 is empty, skipping save for " attFilename, "AttachPipeline")
        }
    }

    debugLog("[ATTACH] Building structured messages for UI...", "AttachPipeline")
    path := ChatDB.Msg_GetActivePath(activeThreadId)
    structuredMessages := buildStructuredMessagesFromPath(path, activeThreadId)
    debugLog("[ATTACH] structuredMessages built, length=" structuredMessages.Length, "AttachPipeline")
    lastMsg := structuredMessages[structuredMessages.Length]
    postWebMessage("appendChatMessage", lastMsg)
    debugLog("[ATTACH] appendChatMessage posted", "AttachPipeline")

    debugLog("[ATTACH] Calling _BuildAndFireRequest...", "AttachPipeline")
    _BuildAndFireRequest()
    debugLog("[ATTACH] _BuildAndFireRequest returned", "AttachPipeline")

    } catch Error as e {
        debugLog("[ATTACH] CRASH in handleChatSend: " e.Message " at line " e.Line "`n" e.Stack, "AttachPipeline")
        postWebMessage("setChatButtonsEnabled", true)
        startLoadingCursor(false)
        postWebMessage("showError", { message: "Attachment processing failed: " e.Message })
    }
}

handleRetry(params := "") {
    retryAction(params && params.Has("messageId") ? params["messageId"] : "")
}

handleDeleteAttachment(params) {
    debugLog("[ATTACH] handleDeleteAttachment ENTER", "AttachPipeline")
    attId := params.Has("id") ? params["id"] : ""
    debugLog("[ATTACH] deleteAttachment attId=" attId, "AttachPipeline")
    if !attId
        return
    ChatDB.Attachment_DeleteOne(attId)
    debugLog("[ATTACH] DeleteOne done for " attId, "AttachPipeline")
    global activeThreadId
    if activeThreadId {
        path := ChatDB.Msg_GetActivePath(activeThreadId)
        structuredMessages := buildStructuredMessagesFromPath(path, activeThreadId)
        postWebMessage("updateChatView", structuredMessages)
    }
}
