;--------------------------------------------------
; cURL process management
;--------------------------------------------------

cURLState(action, data := 0) {
    static cURLPID := 0

    switch action {
        case "get": return cURLPID
        case "set": cURLPID := data
        case "close": ProcessClose(cURLPID), cURLPID := 0
    }
    return 0
}

; ----------------------------------------------------
; Post a message to the WebView
; ----------------------------------------------------

postWebMessage(target, data := unset, reqId := "") {
    global responseWindow
    if !IsSet(responseWindow) || !responseWindow {
        return
    }

    msgObj := { target: target }

    ; If data is provided, add it to the message object
    msgObj.data := IsSet(data) ? data : unset
    ; Correlation id from a WebView request (step 2 of the IPC refactor):
    ; replies echo it so the WebView can match responses to requests.
    if reqId != ""
        msgObj.reqId := reqId

    jsonStr := jsongo.Stringify(msgObj)
    try responseWindow.PostWebMessageAsJSON(jsonStr)
}

; ----------------------------------------------------
; Delete temp files
; ----------------------------------------------------

deleteTempFiles() {
    safeDelete(requestParams.Has("chatHistoryJSONRequestFile") ? requestParams["chatHistoryJSONRequestFile"] : "")
    safeDelete(requestParams.Has("cURLCommandFile") ? requestParams["cURLCommandFile"] : "")
    safeDelete(requestParams.Has("cURLOutputFile") ? requestParams["cURLOutputFile"] : "")
    safeDelete(requestParams.Has("cURLErrorFile") ? requestParams["cURLErrorFile"] : "")
}

; ----------------------------------------------------
; Start or stop loading cursor
; ----------------------------------------------------

startLoadingCursor(status) {
    global requestParams
    if !IsSet(requestParams)
        return
    status ? CustomMessages.notifyLoadingState(CustomMessages.WM_LOADING_START,
        requestParams["uniqueID"], , requestParams["mainScriptHiddenHwnd"])
            : CustomMessages.notifyLoadingState(CustomMessages.WM_LOADING_FINISH,
                requestParams["uniqueID"], , requestParams["mainScriptHiddenHwnd"])
}

; ----------------------------------------------------
; Post token usage and cost stats for the current thread
; Computes estimates from DB, sends to WebView
; ----------------------------------------------------

postThreadStats(threadId := "") {
    if !threadId
        return
    stats := ChatDB.Msg_GetThreadStats(threadId)
    ; Bug #207: scope the token-bar payload to the thread it belongs to. The
    ; WebView ignores stats for a thread that is no longer active, so a
    ; completion in thread A can never repaint thread B's header.
    stats.threadId := threadId
    postWebMessage("updateTokenUsage", stats)
}

; debugLog() is now in lib/DebugLog.ahk - included via Config.ahk

; ----------------------------------------------------
; Build structured messages array from DB path for WebView
; Used by ChatIPC, ChatCallbacks, StreamHandler - defined here
; as a shared utility rather than in a callbacks file.
; ----------------------------------------------------

buildStructuredMessagesFromPath(path, threadId := "") {
    ; Batch-load all attachments for this thread (if threadId provided)
    allAttachments := Map()
    if threadId {
        attList := ChatDB.Attachment_GetByThread(threadId)
        for att in attList {
            msgId := att.message_id
            if !allAttachments.Has(msgId)
                allAttachments[msgId] := []
            attObj := {
                id: att.id,
                attachment_type: att.attachment_type,
                file_path: att.file_path,
                mime_type: att.mime_type,
                original_filename: att.original_filename,
                file_size: att.file_size,
                extracted_text: att.extracted_text
            }
            ; Include base64 for image thumbnails in message bubbles
            if att.attachment_type = "image" {
                attObj.base64 := ImageUtils.ReadAndEncode(att.file_path)
            }
            allAttachments[msgId].Push(attObj)
        }
    }

    structuredMessages := []
    for msg in path {
        msgObj := { role: msg.role, content: msg.content, id: msg.id,
            tokenCount: msg.HasProp("token_count") ? msg.token_count : 0,
            thinkingTokens: msg.HasProp("thinking_tokens") ? msg.thinking_tokens : 0,
            cachedTokens: msg.HasProp("cached_tokens") ? msg.cached_tokens : 0,
            responseTimeMs: msg.HasProp("response_time_ms") ? msg.response_time_ms : 0,
            ttftMs: msg.HasProp("ttft_ms") ? msg.ttft_ms : 0,
            createdAt: msg.HasProp("created_at") ? msg.created_at : "" }
        if msg.role = "assistant" && msg.model
            msgObj.model := msg.model
        if msg.sibling_group {
            siblings := ChatDB.Msg_GetSiblings(msg.id)
            ; Bug #125: the branch label is the 1-based POSITION of this message
            ; among the REMAINING siblings - the raw sibling_index+1 goes stale
            ; after a sibling is deleted (B kept showing 2/2 after A vanished)
            ; and grows with every retry.
            pos := 0
            for i, sib in siblings {
                if sib.id = msg.id {
                    pos := i
                    break
                }
            }
            msgObj.siblingInfo := { index: pos ? pos : 1, total: siblings.Length }
        }
        if msg.HasProp("reasoning") && msg.reasoning
            msgObj.reasoning := msg.reasoning
        ; Include attachments for this message
        if allAttachments.Has(msg.id)
            msgObj.attachments := allAttachments[msg.id]
        structuredMessages.Push(msgObj)
    }
    return structuredMessages
}

; Load a thread into UI with full refresh. Replaces 3 duplicate call sites.
_LoadThreadAndRefreshUI(threadId, includeDropdownLabel := true) {
    global activeThreadId
    activeThreadId := threadId
    _restoreThreadSettings(activeThreadId)
    path := ChatDB.Msg_GetActivePath(activeThreadId)
    postWebMessage("initChatMode", { messages: buildStructuredMessagesFromPath(path, activeThreadId), threadId: activeThreadId })
    postWebMessage("renderChatTree", ChatDB.Msg_GetTree(activeThreadId))
    postThreadStats(activeThreadId)
    if includeDropdownLabel
        _sendDropdownLabel()
    ; Push per-thread settings (model, assistant, font size, etc.) to WebView
    postCurrentSettingsToWebView()
    ; Bug #38: keep the window title in sync with the active thread. Only
    ; renameThread updated chatWindow.Title before, so switching threads left
    ; the previously renamed thread's title in the title bar.
        threadInfo := ChatDB.db.Query("SELECT title FROM chat_threads WHERE id=?;", activeThreadId)
    if threadInfo.count
        chatWindow.Title := AppInfo.Name " - " threadInfo[1, "title"]
}

; Refresh thread list and trash list in the sidebar WebView.
; Replaces 5 duplicate call sites across Message.ahk and Sidebar.ahk.
_postThreadListRefresh() {
    threads := ChatDB.Thread_List()
    folders := _GetFolders()
    postWebMessage("threadList", { threads: threads, folders: folders })
    postWebMessage("trashList", ChatDB.Thread_List(true))
}

_GetFolders() {
    table := ChatDB.db.Query("SELECT id, name FROM chat_folders ORDER BY name;")
    folders := []
    for row in table.rows {
        folders.Push({ id: row.id, name: row.name })
    }
    return folders
}

; generateThreadTitle() is in ThreadTitleGen.ahk - included via ChatWindow.ahk
