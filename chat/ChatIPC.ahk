; ======================================================
; ChatIPC.ahk — IPC handlers + unified thread loading
;
; Handles WM_LOAD_THREAD and WM_TRIGGER_LLM from the main
; script. LoadThreadIntoUI is the unified entry point used
; by both IPC and command-line-arg paths.
; ======================================================

; Register IPC handlers for main-script commands
OnMessage(CustomMessages.WM_LOAD_THREAD, OnLoadThread)
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
    ; Bug #203: honor the command's Stream Response toggle (wParam=1 stream,
    ; wParam=0 single-shot JSON) instead of always streaming.
    requestParams["stream"] := wParam ? true : false
    path := ChatDB.Msg_GetActivePath(activeThreadId)
    if path.Length > 0 && path[path.Length].role = "user"
        _BuildAndFireRequest()
}

; Unified thread loader — used by both IPC path (OnLoadThread) and
; command-line-arg path (ChatWindow startup). Eliminates duplication.
LoadThreadIntoUI(threadId, autoFire := false) {
    ; Bug #41: threads created outside the sidebar newChat action (tray "New
    ; Chat", command-line spawn) have no settings yet; give them the configured
    ; "New Chats Start With" default before the UI loads them.
    _applyNewChatDefaultToFreshThread(threadId)
    _LoadThreadAndRefreshUI(threadId)
    ; Auto-trigger LLM when spawning fresh with a threadId (command-line-arg path).
    if autoFire {
        requestParams["stream"] := true
        path := ChatDB.Msg_GetActivePath(activeThreadId)
        if path.Length > 0 && path[path.Length].role = "user"
            _BuildAndFireRequest()
    }
}
