; ======================================================
; HotkeyRegistrar.ahk - Dynamic hotkey registration
; ======================================================

global _activeHotkeys := { main: "", reload: "", closeWindows: "", suspend: "" }
global _hotkeyRegistrationErrors := []

_registerAllHotkeys(showErrors := false) {
    global mainHotkey, reloadHotkey, closeWindowsHotkey, suspendHotkey
    global _activeHotkeys, _hotkeyRegistrationErrors
    _hotkeyRegistrationErrors := []

    ; Parallel E2E workers must not register system-wide shortcuts. The suite
    ; drives the app through CDP/IPC and verifies hotkey wiring separately.
    if EnvGet("AHKLLM_E2E_WORKER") != "" {
        _activeHotkeys := { main: "", reload: "", closeWindows: "", suspend: "" }
        return
    }

    _HotkeyOff(_activeHotkeys.main)
    _HotkeyOff(_activeHotkeys.reload)
    _HotkeyOff(_activeHotkeys.closeWindows)
    _HotkeyOff(_activeHotkeys.suspend)

    _activeHotkeys.main := _HotkeyOn(_NormalizeHotkeyKey(mainHotkey), (*) => handleHotkey("showCommandMenu"), "On", "Main Hotkey", mainHotkey)
    _activeHotkeys.reload := _HotkeyOn(_NormalizeHotkeyKey(reloadHotkey), (*) => handleHotkey("reloadScript"), "On", "Reload Script", reloadHotkey)
    _activeHotkeys.closeWindows := _HotkeyOn(_NormalizeHotkeyKey(closeWindowsHotkey), (*) => handleHotkey("closeWindows"), "On", "Close Windows", closeWindowsHotkey)
    _activeHotkeys.suspend := _HotkeyOn(_NormalizeHotkeyKey(suspendHotkey), (*) => handleHotkey("suspendHotkey"), "S On", "Suspend Toggle", suspendHotkey)

    if showErrors && _hotkeyRegistrationErrors.Length
        _ShowHotkeyRegistrationErrors()
}

_NormalizeHotkeyKey(key) {
    if !key
        return ""
    return StrReplace(key, "``", "SC029")
}

_HotkeyOn(key, callback, options := "On", label := "", displayKey := "") {
    global _hotkeyRegistrationErrors
    if !key
        return ""
    try {
        Hotkey(key, callback, options)
        return key
    } catch Error as e {
        debugLog("Hotkey registration failed for '" key "': " e.Message, "HotkeyRegistrar")
        _hotkeyRegistrationErrors.Push({ label: label != "" ? label : "Hotkey", key: displayKey != "" ? displayKey : key, message: e.Message })
        return ""
    }
}

_ShowHotkeyRegistrationErrors() {
    global _hotkeyRegistrationErrors
    if !_hotkeyRegistrationErrors.Length
        return
    message := "Some hotkeys could not be applied:"
    for _, item in _hotkeyRegistrationErrors {
        message .= "`n`n" item.label ": " item.key
        if item.message != ""
            message .= "`n" item.message
    }
    ToolTip(message, , , 18)
    SetTimer(() => ToolTip(, , , 18), -7000)
}

_HotkeyOff(key) {
    if !key
        return
    try Hotkey(key, "Off")
    catch Error as e
        debugLog("Hotkey unregister failed for '" key "': " e.Message, "HotkeyRegistrar")
}

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
