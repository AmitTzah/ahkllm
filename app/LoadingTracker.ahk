; ----------------------------------------------------
; Tracks active models and their state
; ----------------------------------------------------

getActiveModels() {
    static activeModels := Map()
    return activeModels
}

; ----------------------------------------------------
; Custom messages and handlers for detecting
; chat window states
; ----------------------------------------------------

handleLoadingState(uniqueID, responseWindowhWnd, state, mainScriptHiddenhWnd) {
    static loadingCount := 0
    static pendingReload := false

    switch state {
        case CustomMessages.WM_LOADING_START:
            if !getActiveModels().Has(uniqueID)
                return
            getActiveModels()[uniqueID].isLoading := true
            loadingCount++
            if (loadingCount = 1)
                updateLoadingUI("Loading")
            updateLoadingUI("Update")

        case CustomMessages.WM_LOADING_FINISH:
            if !getActiveModels().Has(uniqueID)
                return
            if (loadingCount > 0) {
                loadingCount--
                getActiveModels()[uniqueID].isLoading := false
                if (loadingCount = 0) {
                    updateLoadingUI("Reset")
                    if pendingReload
                        Reload()
                } else {
                    updateLoadingUI("Update")
                }
            }

        case "reloadScript": pendingReload := true

        case CustomMessages.WM_CHAT_WINDOW_OPENED:
            onChatWindowOpened(uniqueID, responseWindowhWnd, state, mainScriptHiddenhWnd)

        case CustomMessages.WM_SHOW_API_LOGS:
            ShowApiLogs()
    }
}
