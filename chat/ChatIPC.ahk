; ======================================================
; ChatIPC.ahk — IPC handlers + unified thread loading
;
; Handles WM_LOAD_THREAD, WM_TRIGGER_LLM, WM_NEW_CHAT
; from the main script. LoadThreadIntoUI is the unified
; entry point used by both IPC and command-line-arg paths.
; ======================================================

; Register IPC handlers for main-script commands
OnMessage(CustomMessages.WM_LOAD_THREAD, OnLoadThread)
OnMessage(CustomMessages.WM_NEW_CHAT, OnNewChat)
OnMessage(CustomMessages.WM_TRIGGER_LLM, OnTriggerLLM)

OnLoadThread(wParam, lParam, msg, hWnd) {
    ; Read threadId from temp file (set by notifyLoadThread via PostMessage)
    threadFile := A_Temp "\chat_load_thread.txt"
    if !FileExist(threadFile)
        return
    threadId := FileOpen(threadFile, "r", "UTF-8-RAW").Read()
    FileDelete(threadFile)
    if !threadId
        return
    LoadThreadIntoUI(threadId, false)
}

; Explicit trigger: fire LLM for the current thread if there's a pending user message.
; Sent by processInitialRequest after loading a command-triggered thread.
OnTriggerLLM(wParam, lParam, msg, hWnd) {
    global activeThreadId
    if !activeThreadId
        return
    path := ChatDB.Msg_GetActivePath(activeThreadId)
    if path.Length > 0 && path[path.Length].role = "user"
        _BuildAndFireRequest()
}

OnNewChat(wParam, lParam, msg, hWnd) {
    global activeThreadId
    activeThreadId := ChatDB.Thread_Create()
    _resetToDefaultSettings()
    postWebMessage("initChatMode", [])
    _sendDropdownLabel()
}

; Unified thread loader — used by both IPC path (OnLoadThread) and
; command-line-arg path (ChatWindow startup). Eliminates duplication.
LoadThreadIntoUI(threadId, autoFire := false) {
    _LoadThreadAndRefreshUI(threadId)
    ; Auto-trigger LLM when spawning fresh with a threadId (command-line-arg path).
    if autoFire {
        path := ChatDB.Msg_GetActivePath(activeThreadId)
        if path.Length > 0 && path[path.Length].role = "user"
            _BuildAndFireRequest()
    }
}
