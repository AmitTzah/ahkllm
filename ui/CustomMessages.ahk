; ----------------------------------------------------
; Custom messages
; ----------------------------------------------------

class CustomMessages {
    static WM_RESPONSE_WINDOW_OPENED := 0x400 + 125
    static WM_RESPONSE_WINDOW_CLOSED := 0x400 + 126
    static WM_SEND_TO_ALL_MODELS := 0x400 + 127
    static WM_RESPONSE_WINDOW_LOADING_START := 0x400 + 123
    static WM_RESPONSE_WINDOW_LOADING_FINISH := 0x400 + 124

    static registerHandlers(origin, handle) {
        switch origin {
            case "mainScript":
                for msg in [this.WM_RESPONSE_WINDOW_OPENED, this.WM_RESPONSE_WINDOW_CLOSED, this.WM_RESPONSE_WINDOW_LOADING_START,
                    this.WM_RESPONSE_WINDOW_LOADING_FINISH]
                    OnMessage(msg, handle)

            case "subScript": OnMessage(this.WM_SEND_TO_ALL_MODELS, handle)
        }
    }

    static notifyResponseWindowState(state, uniqueID, responseWindowhWnd := unset, mainScriptHiddenhWnd := unset) {
        switch state {
            case this.WM_RESPONSE_WINDOW_OPENED, this.WM_RESPONSE_WINDOW_CLOSED:
                PostMessage(state, uniqueID, responseWindowhWnd, , "ahk_id " mainScriptHiddenhWnd)
            case this.WM_SEND_TO_ALL_MODELS:
                PostMessage(state, uniqueID, 0, , "ahk_id " responseWindowhWnd)
            case this.WM_RESPONSE_WINDOW_LOADING_START, this.WM_RESPONSE_WINDOW_LOADING_FINISH:
                PostMessage(state, uniqueID, 0, , "ahk_id " mainScriptHiddenhWnd)
        }
    }
}