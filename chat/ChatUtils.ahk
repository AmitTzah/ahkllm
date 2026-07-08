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

postWebMessage(target, data := unset) {
    msgObj := { target: target }

    ; If data is provided, add it to the message object
    msgObj.data := IsSet(data) ? data : unset

    jsonStr := jsongo.Stringify(msgObj)
    responseWindow.PostWebMessageAsJSON(jsonStr)
}

; ----------------------------------------------------
; Delete temp files
; ----------------------------------------------------

deleteTempFiles() {
    safeDelete(requestParams["chatHistoryJSONRequestFile"])
    safeDelete(requestParams["cURLCommandFile"])
    safeDelete(requestParams["cURLOutputFile"])
    safeDelete(requestParams["cURLErrorFile"])
}

; ----------------------------------------------------
; Start or stop loading cursor
; ----------------------------------------------------

startLoadingCursor(status) {
    status ? CustomMessages.notifyLoadingState(CustomMessages.WM_LOADING_START,
        requestParams["uniqueID"], , requestParams["mainScriptHiddenhWnd"])
            : CustomMessages.notifyLoadingState(CustomMessages.WM_LOADING_FINISH,
                requestParams["uniqueID"], , requestParams["mainScriptHiddenhWnd"])
}

; ----------------------------------------------------
; Post token usage and cost stats for the current thread
; Computes estimates from DB, sends to WebView
; ----------------------------------------------------

postThreadStats(threadId := "") {
    if !threadId
        return
    stats := ChatDB.Msg_GetThreadStats(threadId)
    postWebMessage("updateTokenUsage", stats)
}

; debugLog() is now in lib/DebugLog.ahk — included via Config.ahk

; ----------------------------------------------------
; Build structured messages array from DB path for WebView
; Used by ChatIPC, ChatCallbacks, StreamHandler — defined here
; as a shared utility rather than in a callbacks file.
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

; Load a thread into UI with full refresh. Replaces 3 duplicate call sites.
_LoadThreadAndRefreshUI(threadId, includeDropdownLabel := true) {
    global activeThreadId
    activeThreadId := threadId
    _restoreThreadSettings(activeThreadId)
    path := ChatDB.Msg_GetActivePath(activeThreadId)
    postWebMessage("initChatMode", buildStructuredMessagesFromPath(path))
    postWebMessage("renderChatTree", ChatDB.Msg_GetTree(activeThreadId))
    postThreadStats(activeThreadId)
    if includeDropdownLabel
        _sendDropdownLabel()
}

; generateThreadTitle() is in ThreadTitleGen.ahk — included via ChatWindow.ahk
