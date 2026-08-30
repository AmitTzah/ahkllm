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
    _HotkeyOff(_activeHotkeys.main)
    _HotkeyOff(_activeHotkeys.reload)
    _HotkeyOff(_activeHotkeys.closeWindows)
    _HotkeyOff(_activeHotkeys.suspend)

    ; Register current hotkeys. An empty value means the hotkey is disabled —
    ; skip registration so the old binding is not re-armed after the Off above.
    ; Each registration is guarded: a rejected key name (e.g. a lone backtick
    ; that AHK intermittently refuses) must not crash the app at startup. Only
    ; keys that actually registered are remembered for the next Off pass.
    _activeHotkeys.main := _HotkeyOn(_NormalizeHotkeyKey(mainHotkey), (*) => handleHotkey("showCommandMenu"))
    _activeHotkeys.reload := _HotkeyOn(_NormalizeHotkeyKey(reloadHotkey), (*) => handleHotkey("reloadScript"))
    _activeHotkeys.closeWindows := _HotkeyOn(_NormalizeHotkeyKey(closeWindowsHotkey), (*) => handleHotkey("closeWindows"))
    _activeHotkeys.suspend := _HotkeyOn(_NormalizeHotkeyKey(suspendHotkey), (*) => handleHotkey("suspendHotkey"), "S On")
}

; Register one hotkey. Returns the key when it registered, "" when disabled or
; rejected (so _activeHotkeys only tracks keys that are actually active).
; Dynamic Hotkey() can reject a literal backtick key name on some systems.
; Register that physical key by scan code instead, while keeping the saved/UI
; value as ` so existing settings remain readable. Modifiers/custom combos are
; preserved, e.g. ^` -> ^SC029 and CapsLock & ` -> CapsLock & SC029.
_NormalizeHotkeyKey(key) {
    if !key
        return ""
    return StrReplace(key, "``", "SC029")
}

_HotkeyOn(key, callback, options := "On") {
    if !key
        return ""
    try {
        Hotkey(key, callback, options)
        return key
    } catch Error as e {
        debugLog("Hotkey registration failed for '" key "': " e.Message, "HotkeyRegistrar")
        return ""
    }
}

; Turn off one previously registered hotkey (best effort — a key that failed to
; register has no binding to remove).
_HotkeyOff(key) {
    if !key
        return
    try Hotkey(key, "Off")
    catch Error as e
        debugLog("Hotkey unregister failed for '" key "': " e.Message, "HotkeyRegistrar")
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
