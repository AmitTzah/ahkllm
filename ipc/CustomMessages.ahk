; ----------------------------------------------------
; Custom messages
; ----------------------------------------------------

class CustomMessages {
    ; Loading cursor notifications (main script → tooltip + cursor)
    static WM_LOADING_START := 0x400 + 123
    static WM_LOADING_FINISH := 0x400 + 124

    ; Single-window chat model messages
    ; NOTE: Must use 0x500+ range — WebView2 uses 0x400-0x4FF for internal messages.
    ; Collision with WebView2 internal messages causes access-violation crashes.
    static WM_CHAT_WINDOW_OPENED := 0x500 + 0
    static WM_LOAD_THREAD := 0x500 + 2
    static WM_TRIGGER_LLM := 0x500 + 4
    static WM_SHOW_DASHBOARD := 0x500 + 6
    static WM_SHOW_API_LOGS := 0x500 + 7

    static registerHandlers(origin, handle) {
        switch origin {
            case "mainScript":
                for msg in [this.WM_LOADING_START,
                    this.WM_LOADING_FINISH,
                    this.WM_CHAT_WINDOW_OPENED,
                    this.WM_SHOW_API_LOGS]
                    OnMessage(msg, handle)

            case "subScript":
                for msg in [this.WM_LOAD_THREAD]
                    OnMessage(msg, handle)
        }
    }

    static notifyLoadingState(state, uniqueID, responseWindowhWnd := unset, mainScriptHiddenhWnd := unset) {
        try {
            switch state {
                case this.WM_CHAT_WINDOW_OPENED:
                    PostMessage(state, uniqueID, responseWindowhWnd, , "ahk_id " mainScriptHiddenhWnd)
                case this.WM_LOADING_START, this.WM_LOADING_FINISH:
                    PostMessage(state, uniqueID, 0, , "ahk_id " mainScriptHiddenhWnd)
            }
        }
    }

    ; --- Single-window chat IPC helpers ---

    ; Main → ChatWindow: tell it to load a different thread
    ; Uses PostMessage (async) via a temp file — avoids blocking the main script
    ; on slow WebView2 ExecuteScript calls in the ChatWindow process.
    static notifyLoadThread(threadId, chatWindowhWnd) {
        try {
            FileOpen(A_Temp "\chat_load_thread.txt", "w", "UTF-8-RAW").Write(threadId)
            PostMessage(this.WM_LOAD_THREAD, 0, 0, , "ahk_id " chatWindowhWnd)
        }
    }

    ; Main → ChatWindow: trigger LLM for the current thread (command-triggered chats)
    static notifyTriggerLLM(chatWindowhWnd) {
        try PostMessage(this.WM_TRIGGER_LLM, 0, 0, , "ahk_id " chatWindowhWnd)
    }

    ; Main → ChatWindow: show inline dashboard
    static notifyShowDashboard(chatWindowhWnd) {
        try PostMessage(this.WM_SHOW_DASHBOARD, 0, 0, , "ahk_id " chatWindowhWnd)
    }

    ; ChatWindow → Main: open API logs viewer
    static notifyShowApiLogs(mainScriptHiddenhWnd) {
        try PostMessage(this.WM_SHOW_API_LOGS, 0, 0, , "ahk_id " mainScriptHiddenhWnd)
    }
}