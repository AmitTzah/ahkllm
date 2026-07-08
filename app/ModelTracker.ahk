; ----------------------------------------------------
; Tracks active models and their state
; ----------------------------------------------------

getActiveModels() {
    static activeModels := Map()
    return activeModels
}

; ----------------------------------------------------
; Custom messages and handlers for detecting
; Response Window states
; ----------------------------------------------------

responseWindowState(uniqueID, responseWindowhWnd, state, mainScriptHiddenhWnd) {
    static responseWindowLoadingCount := 0
    static reloadScript := false

    switch state {
        case CustomMessages.WM_RESPONSE_WINDOW_LOADING_START:
            if !getActiveModels().Has(uniqueID) {
                return
            }
            getActiveModels()[uniqueID].isLoading := true
            responseWindowLoadingCount++
            if (responseWindowLoadingCount = 1) {
                manageCursorAndToolTip("Loading")
            }
            manageCursorAndToolTip("Update")

        case CustomMessages.WM_RESPONSE_WINDOW_LOADING_FINISH:
            if !getActiveModels().Has(uniqueID) {
                return
            }
            if (responseWindowLoadingCount > 0) {
                responseWindowLoadingCount--
                getActiveModels()[uniqueID].isLoading := false
                if (responseWindowLoadingCount = 0) {
                    manageCursorAndToolTip("Reset")
                } else {
                    manageCursorAndToolTip("Update")
                }
            }

        case "reloadScript": reloadScript := true

        case CustomMessages.WM_CHAT_WINDOW_OPENED:
            OnChatWindowOpened(uniqueID, responseWindowhWnd, state, mainScriptHiddenhWnd)
    }
}
