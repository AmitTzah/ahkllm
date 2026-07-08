; ----------------------------------------------------
; Cursor and Tooltip management
; ----------------------------------------------------

updateLoadingUI(action) {
    switch action {
        case "Update":
            activeCount := 0
            for key, data in getActiveModels() {
                if data.isLoading {
                    activeCount++
                }
            }

            if (activeCount = 0) {
                ToolTip
                return
            }

            toolTipMessage := "Retrieving response for the following prompt"

            ; Singular and plural forms of the word "model"
            if (activeCount > 1) {
                toolTipMessage .= "s"
            }

            toolTipMessage .= " (Press ESC to cancel):"
            for key, data in getActiveModels() {
                if (data.isLoading) {
                    toolTipMessage .= "`n- " data.commandName " [" data.name "]"
                }
            }

            ToolTipEX(toolTipMessage, 0)

        case "Loading":
            ; Change default arrow cursor (32512) to "working in background" cursor (32650)
            ; Ensure that other cursors remain unchanged to preserve their functionality
            Cursor := DllCall("LoadCursor", "uint", 0, "uint", 32650)
            DllCall("SetSystemCursor", "Ptr", Cursor, "UInt", 32512)

        case "Reset":
            ToolTip
            DllCall("SystemParametersInfo", "UInt", 0x57, "UInt", 0, "Ptr", 0, "UInt", 0)
    }
}

; ----------------------------------------------------
; Toggle Suspend
; ----------------------------------------------------

toggleSuspend(*) {
    Suspend -1
    if (A_IsSuspended) {
        TraySetIcon(iconOff, , 1)
        A_IconTip := "LLM AutoHotkey Assistant - Suspended"

        ; Show GUI at the bottom, centered
        suspendBanner.Show("AutoSize x" (A_ScreenWidth - suspendBannerWidth) / 2 " y" (A_ScreenHeight - 80) " NA")
    } else {
        TraySetIcon(iconOn)
        A_IconTip := "LLM AutoHotkey Assistant"
        suspendBanner.Hide()
    }
}