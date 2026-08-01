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

global _activeHotkeys := { main: "", reload: "", closeWindows: "", suspend: "" }

_registerAllHotkeys() {
    global mainHotkey, reloadHotkey, closeWindowsHotkey, suspendHotkey, _activeHotkeys

    ; Turn off any previously registered hotkeys
    if _activeHotkeys.main
        Hotkey(_activeHotkeys.main, "Off")
    if _activeHotkeys.reload
        Hotkey(_activeHotkeys.reload, "Off")
    if _activeHotkeys.closeWindows
        Hotkey(_activeHotkeys.closeWindows, "Off")
    if _activeHotkeys.suspend
        Hotkey(_activeHotkeys.suspend, "Off")

    ; Register current hotkeys. An empty value means the hotkey is disabled —
    ; skip registration so the old binding is not re-armed after the Off above.
    if mainHotkey
        Hotkey(mainHotkey, (*) => handleHotkey("showCommandMenu"), "On")
    if reloadHotkey
        Hotkey(reloadHotkey, (*) => handleHotkey("reloadScript"), "On")
    if closeWindowsHotkey
        Hotkey(closeWindowsHotkey, (*) => handleHotkey("closeWindows"), "On")
    if suspendHotkey
        Hotkey(suspendHotkey, (*) => handleHotkey("suspendHotkey"), "S On")

    ; Remember active bindings for next update
    _activeHotkeys.main := mainHotkey
    _activeHotkeys.reload := reloadHotkey
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

        case "reloadScript":
            Reload()

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
