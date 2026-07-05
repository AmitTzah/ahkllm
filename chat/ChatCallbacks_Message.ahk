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

chatSendFromWebView(message, *) {
    global activeThreadId
    if !message
        return

    ; Auto-create thread if first message (no active thread)
    if !activeThreadId {
        activeThreadId := ChatDB.Thread_Create("New Chat")
        postWebMessage("threadList", ChatDB.Thread_List())
        postWebMessage("trashList", ChatDB.Thread_List(true))
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

    ; Build API request from DB messages
    chatHistoryJSONRequest := BuildAndWriteRequestFiles()
    if !chatHistoryJSONRequest {
        postWebMessage("setChatButtonsEnabled", true)
        startLoadingCursor(false)
        return
    }

    ; Show user message bubble in WebView
    path := ChatDB.Msg_GetActivePath(activeThreadId)
    structuredMessages := buildStructuredMessagesFromPath(path)
    lastMsg := structuredMessages[structuredMessages.Length]
    postWebMessage("appendChatMessage", lastMsg)

    ; Send to LLM
    sendRequestToLLM(&chatHistoryJSONRequest)
}

; ----------------------------------------------------
; Chat mode: Handle retry request from WebView
; ----------------------------------------------------

retryFromWebView(*) {
    buttonClickAction("Retry")
}

; ----------------------------------------------------
; Build structured messages array from DB path
; ----------------------------------------------------

buildStructuredMessagesFromPath(path) {
    structuredMessages := []
    for msg in path {
        msgObj := { role: msg.role, content: msg.content, id: msg.id }
        if msg.role = "assistant" && msg.model
            msgObj.model := msg.model
        if msg.sibling_group {
            siblings := ChatDB.Msg_GetSiblings(msg.id)
            msgObj.siblingInfo := { index: msg.sibling_index + 1, total: siblings.Length }
        }
        if msg.feedback
            msgObj.feedback := msg.feedback
        if msg.HasProp("reasoning") && msg.reasoning
            msgObj.reasoning := msg.reasoning
        structuredMessages.Push(msgObj)
    }
    return structuredMessages
}
