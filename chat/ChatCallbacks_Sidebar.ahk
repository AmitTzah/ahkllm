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
                postThreadStats(activeThreadId)
            }
        case "navigateToMessage":
            if params.Has("messageId") && activeThreadId {
                ChatDB.Msg_SetActiveLeaf(activeThreadId, params["messageId"])
                path := ChatDB.Msg_GetActivePath(activeThreadId)
                postWebMessage("initChatMode", buildStructuredMessagesFromPath(path))
                postWebMessage("renderChatTree", ChatDB.Msg_GetTree(activeThreadId))
                postThreadStats(activeThreadId)
            }
        case "newChat":
            activeThreadId := ChatDB.Thread_Create()
            postWebMessage("loadThread", activeThreadId)
            postWebMessage("threadList", ChatDB.Thread_List())
        case "deleteThread":
            if params.Has("threadId") {
                threadId := params["threadId"]
                ChatDB.Thread_SoftDelete(threadId)  ; soft-delete to trash
                if activeThreadId = threadId
                    activeThreadId := ""
                postWebMessage("threadList", ChatDB.Thread_List())
                if !activeThreadId
                    postWebMessage("initChatMode", [])
            }
        case "restoreThread":
            if params.Has("threadId") {
                ChatDB.Thread_Restore(params["threadId"])
                postWebMessage("threadList", ChatDB.Thread_List())
            }
        case "deleteThreadForever":
            if params.Has("threadId") {
                threadId := params["threadId"]
                ChatDB.Thread_Delete(threadId)  ; permanent hard delete
                if activeThreadId = threadId
                    activeThreadId := ""
                postWebMessage("threadList", ChatDB.Thread_List())
                if !activeThreadId
                    postWebMessage("initChatMode", [])
            }
        case "emptyTrash":
            ; Hard-delete ALL trashed threads permanently
            trashed := ChatDB.Thread_List(true)
            for t in trashed {
                ChatDB.Thread_Delete(t.id)
            }
            if activeThreadId {
                ; Check if active thread was among purged
                stillExists := false
                for t in ChatDB.Thread_List()
                    if t.id = activeThreadId
                        stillExists := true
                if !stillExists {
                    activeThreadId := ""
                    postWebMessage("initChatMode", [])
                }
            }
            postWebMessage("threadList", ChatDB.Thread_List())
        case "renameThread":
            if params.Has("threadId") && params.Has("title") {
                ChatDB.Thread_Update(params["threadId"], params["title"])
                postWebMessage("threadList", ChatDB.Thread_List())
                ; Also update window title if this is the active thread
                if activeThreadId = params["threadId"] {
                    threadInfo := ChatDB.db.Exec("SELECT title FROM chat_threads WHERE id='" params["threadId"] "';")
                    if threadInfo.count
                        chatWindow.Title := "Chat — " threadInfo[1, "title"]
                }
            }
    }
}
