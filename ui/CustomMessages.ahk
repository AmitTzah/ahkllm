; ----------------------------------------------------
; Custom messages
; ----------------------------------------------------

class CustomMessages {
    static WM_RESPONSE_WINDOW_OPENED := 0x400 + 125
    static WM_RESPONSE_WINDOW_CLOSED := 0x400 + 126
    static WM_SEND_TO_ALL_MODELS := 0x400 + 127
    static WM_RESPONSE_WINDOW_LOADING_START := 0x400 + 123
    static WM_RESPONSE_WINDOW_LOADING_FINISH := 0x400 + 124

    ; Single-window chat model messages
    ; NOTE: Must use 0x500+ range — WebView2 uses 0x400-0x4FF for internal messages.
    ; Collision with WebView2 internal messages causes access-violation crashes.
    static WM_CHAT_WINDOW_OPENED := 0x500 + 0
    static WM_CHAT_WINDOW_CLOSED := 0x500 + 1
    static WM_LOAD_THREAD := 0x500 + 2
    static WM_NEW_CHAT := 0x500 + 3

    static registerHandlers(origin, handle) {
        switch origin {
            case "mainScript":
                for msg in [this.WM_RESPONSE_WINDOW_OPENED, this.WM_RESPONSE_WINDOW_CLOSED, this.WM_RESPONSE_WINDOW_LOADING_START,
                    this.WM_RESPONSE_WINDOW_LOADING_FINISH,
                    this.WM_CHAT_WINDOW_OPENED, this.WM_CHAT_WINDOW_CLOSED]
                    OnMessage(msg, handle)

            case "subScript":
                for msg in [this.WM_SEND_TO_ALL_MODELS, this.WM_LOAD_THREAD, this.WM_NEW_CHAT]
                    OnMessage(msg, handle)
        }
    }

    static notifyResponseWindowState(state, uniqueID, responseWindowhWnd := unset, mainScriptHiddenhWnd := unset) {
        try {
            switch state {
                case this.WM_RESPONSE_WINDOW_OPENED, this.WM_RESPONSE_WINDOW_CLOSED,
                     this.WM_CHAT_WINDOW_OPENED, this.WM_CHAT_WINDOW_CLOSED:
                    PostMessage(state, uniqueID, responseWindowhWnd, , "ahk_id " mainScriptHiddenhWnd)
                case this.WM_SEND_TO_ALL_MODELS:
                    PostMessage(state, uniqueID, 0, , "ahk_id " responseWindowhWnd)
                case this.WM_RESPONSE_WINDOW_LOADING_START, this.WM_RESPONSE_WINDOW_LOADING_FINISH:
                    PostMessage(state, uniqueID, 0, , "ahk_id " mainScriptHiddenhWnd)
            }
        }
    }

    ; --- Single-window chat IPC helpers ---

    ; Main → ChatWindow: tell it to load a different thread
    ; Uses SendMessage (synchronous) so the StrPtr is still valid when the handler reads it
    static notifyLoadThread(threadId, chatWindowhWnd) {
        try SendMessage(this.WM_LOAD_THREAD, StrPtr(threadId), 0, , "ahk_id " chatWindowhWnd)
    }

    ; Main → ChatWindow: tell it to start a new chat
    static notifyNewChat(chatWindowhWnd) {
        try PostMessage(this.WM_NEW_CHAT, 0, 0, , "ahk_id " chatWindowhWnd)
    }
}