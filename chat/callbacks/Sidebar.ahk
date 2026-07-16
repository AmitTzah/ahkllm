; Thread list and sidebar navigation callbacks

; ----------------------------------------------------
; Sidebar actions from WebView (D6)
; ----------------------------------------------------

handleSidebarAction(params, *) {
    global activeThreadId
    subAction := params.Has("subAction") ? params["subAction"] : params["action"]
    switch subAction {
        case "loadThreadList":
            _postThreadListRefresh()
        case "loadTrashList":
            postWebMessage("trashList", ChatDB.Thread_List(true))
        case "loadTree":
            if activeThreadId
                postWebMessage("renderChatTree", ChatDB.Msg_GetTree(activeThreadId))
        case "loadThread":
            if params.Has("threadId")
                _LoadThreadAndRefreshUI(params["threadId"])
        case "navigateToMessage":
            if params.Has("messageId") && activeThreadId {
                ; Walk to the branch leaf so the full path (including children
                ; after the target message) is preserved. The JS side scrolls
                ; to the specific clicked/search node separately.
                leafId := TreeRepo._WalkToLeaf(params["messageId"])
                ChatDB.Msg_SetActiveLeaf(activeThreadId, leafId)
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
                if activeThreadId = threadId {
                    activeThreadId := ""
                    postWebMessage("loadThread", "")  ; clear JS activeThreadId + topbar
                    postWebMessage("initChatMode", [])
                }
                _postThreadListRefresh()
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
                if activeThreadId = threadId {
                    activeThreadId := ""
                    postWebMessage("loadThread", "")  ; clear JS activeThreadId + topbar
                    postWebMessage("initChatMode", [])
                }
                _postThreadListRefresh()
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
                _postThreadListRefresh()
                ; Also update window title if this is the active thread
                if activeThreadId = params["threadId"] {
                    threadInfo := ChatDB.db.Exec("SELECT title FROM chat_threads WHERE id='" params["threadId"] "';")
                    if threadInfo.count
                        chatWindow.Title := "Chat — " threadInfo[1, "title"]
                }
            }
        case "createFolder":
            if params.Has("name") {
                id := ChatDB._UUID()
                ChatDB.db.Exec("INSERT INTO chat_folders (id, name) VALUES('" id "', '" SQLite.Escape(params["name"]) "');")
                _postThreadListRefresh()
            }
        case "renameFolder":
            if params.Has("folderId") && params.Has("name") {
                ChatDB.db.Exec("UPDATE chat_folders SET name='" SQLite.Escape(params["name"]) "' WHERE id='" params["folderId"] "';")
                _postThreadListRefresh()
            }
        case "deleteFolder":
            if params.Has("folderId") {
                ChatDB.db.Exec("UPDATE chat_threads SET folder_id=NULL WHERE folder_id='" params["folderId"] "';")
                ChatDB.db.Exec("DELETE FROM chat_folders WHERE id='" params["folderId"] "';")
                _postThreadListRefresh()
            }
        case "moveToFolder":
            if params.Has("threadId") && params.Has("folderId") {
                fid := params["folderId"] = "__none__" ? "NULL" : "'" params["folderId"] "'"
                ChatDB.db.Exec("UPDATE chat_threads SET folder_id=" fid " WHERE id='" params["threadId"] "';")
                _postThreadListRefresh()
            }
    }
}

