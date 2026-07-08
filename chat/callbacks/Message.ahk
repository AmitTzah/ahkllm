; ======================================================
; ChatCallbacks_Message.ahk — Send and retry callbacks
;
; NOTE: #Include'd by ChatWindow.ahk. Has access to:
;   activeThreadId, requestParams, ChatDB,
;   BuildAndWriteRequestFiles, postWebMessage,
;   startLoadingCursor, sendRequestToLLM
; ======================================================

; ----------------------------------------------------
; Chat mode: Handle messages sent from the inline chat input
; ----------------------------------------------------

handleChatSend(message, *) {
    global activeThreadId
    if !message
        return

    ; Auto-create thread if first message (no active thread)
    if !activeThreadId {
        activeThreadId := ChatDB.Thread_Create("New Chat")
        _saveCurrentSettingsToThread(activeThreadId)
        _postThreadListRefresh()
    }

    startLoadingCursor(true)
    postWebMessage("setChatButtonsEnabled", false)

    ; Find parent ID from active path
    path := ChatDB.Msg_GetActivePath(activeThreadId)
    lastMsgId := path.Length ? path[path.Length].id : ""

    ; Insert user message into DB
    ChatDB.Msg_Insert({
        thread_id: activeThreadId,
        role: "user",
        content: message,
        parent_id: lastMsgId,
        sibling_group: "",
        sibling_index: 0
    })

    ; Show user message bubble in WebView before firing
    path := ChatDB.Msg_GetActivePath(activeThreadId)
    structuredMessages := buildStructuredMessagesFromPath(path)
    lastMsg := structuredMessages[structuredMessages.Length]
    postWebMessage("appendChatMessage", lastMsg)

    ; Build and fire
    _BuildAndFireRequest()
}

; ----------------------------------------------------
; Chat mode: Handle retry request from WebView
; ----------------------------------------------------

handleRetry(params := "") {
    retryAction(params && params.Has("messageId") ? params["messageId"] : "")
}

