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

handleSidebarAction(params, *) {
    global activeThreadId
    subAction := params.Has("subAction") ? params["subAction"] : params["action"]
    switch subAction {
        case "loadThreadList":
            postWebMessage("threadList", ChatDB.Thread_List())
        case "loadTrashList":
            postWebMessage("trashList", ChatDB.Thread_List(true))
        case "loadThread":
            if params.Has("threadId")
                _LoadThreadAndRefreshUI(params["threadId"])
        case "navigateToMessage":
            if params.Has("messageId") && activeThreadId {
                ChatDB.Msg_SetActiveLeaf(activeThreadId, params["messageId"])
                _LoadThreadAndRefreshUI(activeThreadId, false)
            }
        case "newChat":
            activeThreadId := ChatDB.Thread_Create()
            _resetToDefaultSettings()
            postWebMessage("loadThread", activeThreadId)
            _postThreadListRefresh()
        case "deleteThread":
            if params.Has("threadId") {
                threadId := params["threadId"]
                ChatDB.Thread_SoftDelete(threadId)  ; soft-delete to trash
                if activeThreadId = threadId
                    activeThreadId := ""
                _postThreadListRefresh()
                if !activeThreadId
                    postWebMessage("initChatMode", [])
            }
        case "restoreThread":
            if params.Has("threadId") {
                ChatDB.Thread_Restore(params["threadId"])
                _postThreadListRefresh()
            }
        case "deleteThreadForever":
            if params.Has("threadId") {
                threadId := params["threadId"]
                ChatDB.Thread_Delete(threadId)  ; permanent hard delete
                if activeThreadId = threadId
                    activeThreadId := ""
                _postThreadListRefresh()
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
            _postThreadListRefresh()
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
