; ======================================================
; ChatCallbacks_Message.ahk — Send and retry callbacks
; ======================================================

handleChatSend(params, *) {
    global activeThreadId
    try {
    message := params.Has("message") ? params["message"] : ""
    attachments := params.Has("attachments") ? params["attachments"] : []

    if !message && !attachments.Length
        return

    ; Auto-create thread if first message
    if !activeThreadId {
        activeThreadId := ChatDB.Thread_Create("New Chat")
        postWebMessage("loadThread", activeThreadId)
        debugLog("[THREAD] Created — id=" activeThreadId " title=New Chat")
        ; Start new chats with the configured default assistant/model ONLY when
        ; the user has not already configured the right rail before the first
        ; send (bug #212): an unconditional apply overwrote a pre-send
        ; assistant pick / typed system prompt / temperature / model with the
        ; default, so the request carried the default's system message instead
        ; of what the user chose.
        if _RequestParamsAreDefault()
            _applyNewChatDefault()
        _saveCurrentSettingsToThread(activeThreadId)
        _postThreadListRefresh()
    }

    startLoadingCursor(true)
    postWebMessage("setChatButtonsEnabled", false)

    path := ChatDB.Msg_GetActivePath(activeThreadId)
    lastMsgId := path.Length ? path[path.Length].id : ""

    msgId := ChatDB.Msg_Insert({
        thread_id: activeThreadId,
        role: "user",
        content: message,
        parent_id: lastMsgId,
        sibling_group: "",
        sibling_index: 0
    })

    ; Save attachments using shared helper
    imageCount := 0
    docCount := 0
    for att in attachments {
        if !IsObject(att)
            continue
        attType := att.Has("type") ? att["type"] : "text_file"
        if attType = "image"
            imageCount++
        else
            docCount++
        ChatDB.Attachment_Save(msgId, att)
    }
    if (imageCount > 0 || docCount > 0)
        debugLog("[ATTACH] Sent — " (imageCount + docCount) " files (image=" imageCount " doc=" docCount ")")

    path := ChatDB.Msg_GetActivePath(activeThreadId)
    structuredMessages := buildStructuredMessagesFromPath(path, activeThreadId)
    lastMsg := structuredMessages[structuredMessages.Length]
    postWebMessage("appendChatMessage", lastMsg)

    ; Bug #203: normal chat sends always stream; the command-triggered path
    ; sets this flag via OnTriggerLLM's wParam.
    requestParams["stream"] := true
    _BuildAndFireRequest()

    } catch Error as e {
        debugLog("[ATTACH] CRASH in handleChatSend: " e.Message " at line " e.Line "`n" e.Stack, "ErrorHandler")
        postWebMessage("setChatButtonsEnabled", true)
        startLoadingCursor(false)
        postWebMessage("showError", { message: "Attachment processing failed: " e.Message })
    }
}

handleRetry(params := "") {
    retryAction(params && params.Has("messageId") ? params["messageId"] : "")
}

handleDeleteAttachment(params) {
    global activeThreadId
    attId := params.Has("id") ? params["id"] : ""
    if !attId || !activeThreadId
        return
    ChatDB.Attachment_DeleteOne(attId, activeThreadId)
    if activeThreadId {
        path := ChatDB.Msg_GetActivePath(activeThreadId)
        structuredMessages := buildStructuredMessagesFromPath(path, activeThreadId)
        postWebMessage("updateChatView", structuredMessages)
    }
}
