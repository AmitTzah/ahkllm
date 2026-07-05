; ======================================================
; ChatCallbacks_Sidebar.ahk — Thread list and sidebar
; navigation callbacks (D6)
;
; NOTE: #Include'd by ChatWindow.ahk. Has access to:
;   activeThreadId, ChatDB, postWebMessage,
;   buildStructuredMessagesFromPath
; ======================================================

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
