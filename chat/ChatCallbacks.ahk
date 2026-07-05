; ======================================================
; ChatCallbacks.ahk — JS → AHK callbacks (via postMessage)
;
; Handles every user action from the WebView: send, retry,
; edit, delete, branch switch, fork, feedback, sidebar actions.
;
; NOTE: This file is #Include'd by ChatWindow.ahk. It has access to:
;   activeThreadId, requestParams, router, responseWindow, chatWindow,
;   ChatDB, BuildAndWriteRequestFiles, postWebMessage, manageState,
;   startLoadingCursor, debugLog, deleteTempFiles
; ======================================================

; ----------------------------------------------------
; Chat mode: Handle messages sent from the inline chat input
; ----------------------------------------------------

chatSendFromWebView(message, *) {
    global activeThreadId
    if !message
        return

    ; Auto-create thread if first message
    if !activeThreadId
        activeThreadId := ChatDB.Thread_Create("New Chat")

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

; ----------------------------------------------------
; Switch branch from WebView (D3)
; ----------------------------------------------------

switchBranchFromWebView(params, *) {
    global activeThreadId
    if !params.Has("id") || !activeThreadId
        return
    id := params["id"]
    direction := params.Has("direction") ? params["direction"] : 1
    result := ChatDB.Msg_SwitchBranch(activeThreadId, id, direction)
    postWebMessage("initChatMode", buildStructuredMessagesFromPath(result.path))
    postWebMessage("updateBranchInfo", { msgId: id, siblingInfo: result.siblingInfo })
}

; ----------------------------------------------------
; Fork/duplicate chat from WebView (D7)
; ----------------------------------------------------

forkChatFromWebView(msgId, *) {
    global activeThreadId
    if !msgId || !activeThreadId
        return
    newThreadId := ChatDB.Msg_ForkThread(activeThreadId, msgId)
    if newThreadId
        postWebMessage("threadForked", { newThreadId: newThreadId })
}

; ----------------------------------------------------
; Set message feedback from WebView (D8)
; ----------------------------------------------------

setFeedbackFromWebView(params, *) {
    if !params.Has("id")
        return
    ChatDB.Msg_SetFeedback(params["id"], params.Has("rating") ? params["rating"] : 0)
}

; ----------------------------------------------------
; Sidebar actions from WebView (D6)
; ----------------------------------------------------

sidebarActionFromWebView(params, *) {
    global activeThreadId
    subAction := params.Has("subAction") ? params["subAction"] : params["action"]
    switch subAction {
        case "loadThreadList":
            postWebMessage("threadList", ChatDB.Thread_List())
        case "loadThread":
            if params.Has("threadId") {
                activeThreadId := params["threadId"]
                path := ChatDB.Msg_GetActivePath(activeThreadId)
                postWebMessage("initChatMode", buildStructuredMessagesFromPath(path))
                postWebMessage("renderChatTree", ChatDB.Msg_GetTree(activeThreadId))
            }
        case "navigateToMessage":
            if params.Has("messageId") && activeThreadId {
                ChatDB.Msg_SetActiveLeaf(activeThreadId, params["messageId"])
                path := ChatDB.Msg_GetActivePath(activeThreadId)
                postWebMessage("initChatMode", buildStructuredMessagesFromPath(path))
                postWebMessage("renderChatTree", ChatDB.Msg_GetTree(activeThreadId))
            }
        case "newChat":
            activeThreadId := ChatDB.Thread_Create()
            postWebMessage("loadThread", activeThreadId)
            postWebMessage("threadList", ChatDB.Thread_List())
        case "deleteThread":
            if params.Has("threadId") {
                threadId := params["threadId"]
                ChatDB.Thread_Delete(threadId)
                if activeThreadId = threadId
                    activeThreadId := ""
                postWebMessage("threadList", ChatDB.Thread_List())
                if !activeThreadId
                    postWebMessage("initChatMode", [])
            }
    }
}

; ----------------------------------------------------
; Button click actions
; ----------------------------------------------------

buttonClickAction(action) {
    global activeThreadId, chatWindow, requestParams
    switch action {
        case "Retry":
            if !activeThreadId
                return
            path := ChatDB.Msg_GetActivePath(activeThreadId)
            if path.Length && path[path.Length].role = "assistant" {
                oldMsg := path[path.Length]
                ; Ensure old message has a sibling_group for branch navigation
                siblingGroup := oldMsg.sibling_group
                if !siblingGroup {
                    siblingGroup := ChatDB._UUID()
                    ChatDB.db.Exec("UPDATE messages SET sibling_group='" siblingGroup "', sibling_index=0 WHERE id='" oldMsg.id "';")
                } else {
                    ; Already has sibling_group — find max sibling_index for the new response
                    sibTable := ChatDB.db.Exec("SELECT MAX(sibling_index) as max_idx FROM messages WHERE sibling_group='" siblingGroup "';")
                    ; We'll set the new index in saveStreamResponse
                }
                ; Store pending sibling_group for the new response
                requestParams["pendingRetrySiblingGroup"] := siblingGroup
                if path.Length > 1
                    ChatDB.Msg_SetActiveLeaf(activeThreadId, path[path.Length - 1].id)
            }
            chatHistoryJSONRequest := BuildAndWriteRequestFiles()
            postWebMessage("setChatButtonsEnabled", false)
            startLoadingCursor(true)
            sendRequestToLLM(&chatHistoryJSONRequest)
    }
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
