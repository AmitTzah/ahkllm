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
    global chatWindow
    ; Read threadId from the target ChatWindow's private handoff file. The
    ; receiving window handle prevents another AhkLLM instance (or a headless
    ; runner) from consuming this process's load request.
    threadFile := A_Temp "\chat_load_thread_" hWnd ".txt"
    if !FileExist(threadFile)
        return
    threadId := FileOpen(threadFile, "r", "UTF-8-RAW").Read()
    FileDelete(threadFile)
    if !threadId
        return
    LoadThreadIntoUI(threadId, false)
    ; Main hides the persistent window before requesting a thread switch. Do
    ; not reveal it until LoadThreadIntoUI has posted the new thread state, or
    ; the previous chat is briefly visible during command navigation.
    ; Background loads show without activating. User-facing opens pass
    ; activate=1 so the new chat receives focus only after it is loaded. The
    ; headless probe uses 2: keep the render window off-screen as well as
    ; non-activating, because Gui.Show("NA") alone preserves the default
    ; on-screen position.
    headless := wParam = 2
    activate := wParam = 1
    chatWindow.Show(headless ? "x-20000 y-20000 NA" : (activate ? "" : "NA"))
    if activate
        WinActivate("ahk_id " chatWindow.hWnd)
    if requestParams["mainScriptHiddenHwnd"]
        CustomMessages.notifyThreadLoaded(requestParams["mainScriptHiddenHwnd"])
}

; Explicit trigger: fire LLM for the current thread if there's a pending user message.
; Sent by processInitialRequest after loading a command-triggered thread.
OnTriggerLLM(wParam, lParam, msg, hWnd) {
    global activeThreadId
    if !activeThreadId
        return
    ; Honor the command's Stream Response toggle (wParam=1 stream,
    ; wParam=0 single-shot JSON) instead of always streaming.
    requestParams["stream"] := wParam ? true : false
    path := ChatDB.Msg_GetActivePath(activeThreadId)
    if path.Length > 0 && path[path.Length].role = "user"
        _BuildAndFireRequest()
}

; Unified thread loader — used by both IPC path (OnLoadThread) and
; command-line-arg path (ChatWindow startup). Eliminates duplication.
LoadThreadIntoUI(threadId, autoFire := false) {
    ; Threads created outside the sidebar newChat action (tray "New
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
