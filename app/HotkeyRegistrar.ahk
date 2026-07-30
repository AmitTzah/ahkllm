; ======================================================
; HotkeyRegistrar.ahk — Dynamic hotkey registration
;
; Provides _registerAllHotkeys() to turn off old hotkey
; bindings and re-register with current global values.
; Called at startup and on settings update via IPC.
;
; Also provides handleHotkey() — the dispatch function
; that all registered hotkeys call, routing each action
; to the appropriate handler.
; ======================================================

global _activeHotkeys := { main: "", saveReload: "", closeWindows: "", suspend: "" }

_registerAllHotkeys() {
    global mainHotkey, saveReloadHotkey, closeWindowsHotkey, suspendHotkey, _activeHotkeys

    ; Turn off any previously registered hotkeys
    if _activeHotkeys.main
        Hotkey(_activeHotkeys.main, "Off")
    if _activeHotkeys.saveReload
        Hotkey(_activeHotkeys.saveReload, "Off")
    if _activeHotkeys.closeWindows
        Hotkey(_activeHotkeys.closeWindows, "Off")
    if _activeHotkeys.suspend
        Hotkey(_activeHotkeys.suspend, "Off")

    ; Register current hotkeys
    Hotkey(mainHotkey, (*) => handleHotkey("showCommandMenu"), "On")
    Hotkey(saveReloadHotkey, (*) => handleHotkey("saveAndReloadScript"), "On")
    Hotkey(closeWindowsHotkey, (*) => handleHotkey("closeWindows"), "On")
    Hotkey(suspendHotkey, (*) => handleHotkey("suspendHotkey"), "S On")

    ; Remember active bindings for next update
    _activeHotkeys.main := mainHotkey
    _activeHotkeys.saveReload := saveReloadHotkey
    _activeHotkeys.closeWindows := closeWindowsHotkey
    _activeHotkeys.suspend := suspendHotkey
}

; handleHotkey references global functions and objects (buildCommandMenu, toggleSuspend,
; commandInputWindow, etc.) — these are reads from the global scope, so no global declaration
; is needed (AHK v2 resolves undeclared reads to globals automatically).
handleHotkey(action) {
    try {
    switch action {
        case "showCommandMenu":
            buildCommandMenu()

        case "suspendHotkey":
            KeyWait "CapsLock", "L"
            SetCapsLockState "Off"
            toggleSuspend(A_IsSuspended)

        case "saveAndReloadScript":
            if !WinActive("UserConfig.ahk") {
                return
            }

            ; Small delay to ensure file operations are complete
            Sleep 100

            if (getActiveModels().Count > 0) {
                MsgBox("Script will automatically reload once the chat window is closed.",
                    "LLM AutoHotkey Assistant", 64)
                handleLoadingState(0, 0, "reloadScript", 0)
            } else {
                Reload()
            }

        case "closeWindows":
            switch WinActive("A") {
                case commandInputWindow.guiObj.hWnd: commandInputWindow.closeButtonAction()
            }
    }
    } catch Error as e {
        debugLog("ERROR in handleHotkey(" action "): " e.Message "`n" e.Stack, "ErrorHandler")
        ToolTip("Error: " e.Message, , , 19)
        SetTimer(() => ToolTip(, , , 19), -5000)
    }
}
