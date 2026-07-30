; ======================================================
; HotkeyRegistrar.ahk — Dynamic hotkey registration
;
; Provides _registerAllHotkeys() to turn off old hotkey
; bindings and re-register with current global values.
; Called at startup and on settings update via IPC.
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
