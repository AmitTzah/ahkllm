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
        case CustomMessages.WM_RESPONSE_WINDOW_OPENED:
            getActiveModels()[uniqueID].hWnd := responseWindowhWnd

        case CustomMessages.WM_RESPONSE_WINDOW_CLOSED:
            if getActiveModels().Has(uniqueID) {
                getActiveModels().Delete(uniqueID)
                manageCursorAndToolTip("Update")
            }

            if (getActiveModels().Count = 0) && reloadScript {
                Reload()
            }
        case CustomMessages.WM_RESPONSE_WINDOW_LOADING_START:
            getActiveModels()[uniqueID].isLoading := true
            responseWindowLoadingCount++
            if (responseWindowLoadingCount = 1) {
                manageCursorAndToolTip("Loading")
            }

            manageCursorAndToolTip("Update")

        case CustomMessages.WM_RESPONSE_WINDOW_LOADING_FINISH:
            if (responseWindowLoadingCount > 0 && getActiveModels().Has(uniqueID)) {
                responseWindowLoadingCount--
                getActiveModels()[uniqueID].isLoading := false
                if (responseWindowLoadingCount = 0) {
                    manageCursorAndToolTip("Reset")
                } else {
                    manageCursorAndToolTip("Update")
                }
            }

        case "reloadScript": reloadScript := true
    }
}