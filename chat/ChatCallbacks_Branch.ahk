; ======================================================
; ChatCallbacks_Branch.ahk — Branch navigation, fork,
; feedback, and button click (Retry) callbacks
;
; NOTE: #Include'd by ChatWindow.ahk. Has access to:
;   activeThreadId, requestParams, chatWindow, ChatDB,
;   BuildAndWriteRequestFiles, postWebMessage,
;   startLoadingCursor, sendRequestToLLM, manageState,
;   buildStructuredMessagesFromPath
; ======================================================

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
