; ======================================================
; HotkeyRegistrar.test.ahk — Unit tests for app/HotkeyRegistrar.ahk
;
; HotkeyRegistrar is only #Included by Main.ahk, so the test harness
; never loaded it before. These tests exercise _registerAllHotkeys()
; and handleHotkey() with script-level mocks for the AutoHotkey
; built-ins the module calls (Hotkey, KeyWait, SetCapsLockState,
; Reload, ToolTip, SetTimer, WinActive) and for the app functions it
; dispatches to (buildCommandMenu, toggleSuspend, commandInputWindow).
; ======================================================

#Include ..\..\app\HotkeyRegistrar.ahk

; --- Script-level mocks for built-ins used by the module ---
Hotkey(key, callback := "", options := "") {
    global _mockHotkeyCalls
    ; The built-in accepts "On"/"Off"/"Toggle" as the Action argument with no
    ; Options argument; normalize so the recorder sees the mode in `options`.
    if callback = "On" || callback = "Off" || callback = "Toggle" {
        _mockHotkeyCalls.Push({ key: key, callback: "", options: callback })
    } else {
        _mockHotkeyCalls.Push({ key: key, callback: callback, options: options })
    }
}

KeyWait(key := "", options := "") {
    global _mockKeyWaitCalls
    _mockKeyWaitCalls.Push(key)
}

SetCapsLockState(state := "Off") {
    global _mockCapsLockCalls
    _mockCapsLockCalls.Push(state)
}

Reload() {
    global _mockReloadCalls
    _mockReloadCalls += 1
}

ToolTip(text := "", x := "", y := "", which := "") {
    global _mockToolTipCalls
    _mockToolTipCalls.Push(text)
}

SetTimer(callback := "", period := "") {
    global _mockSetTimerCalls
    _mockSetTimerCalls.Push({ callback: callback, period: period })
}

WinActive(title := "") {
    global _mockWinActiveResult
    return _mockWinActiveResult
}

toggleSuspend(suspended) {
    global _mockToggleSuspendCalls
    _mockToggleSuspendCalls.Push(suspended)
}

_mockCloseWindowAction(args*) {
    global _mockCloseWindowCalls
    _mockCloseWindowCalls += 1
}
global commandInputWindow := { guiObj: { hWnd: 424242 }, closeButtonAction: _mockCloseWindowAction }

class HotkeyRegistrarTest {

    static __New() {
        RegisterTestClass("HotkeyRegistrarTest")
    }

    Register_RegistersCurrentBindings() {
        global mainHotkey, reloadHotkey, closeWindowsHotkey, suspendHotkey
        global _activeHotkeys, _mockHotkeyCalls, _mockReloadCalls
        mainHotkey := "^!m"
        reloadHotkey := "^!r"
        closeWindowsHotkey := "^!w"
        suspendHotkey := "CapsLock & x"
        _activeHotkeys := { main: "", reload: "", closeWindows: "", suspend: "" }
        _mockHotkeyCalls := []

        _registerAllHotkeys()

        if _mockHotkeyCalls.Length != 4
            throw Error("Expected 4 Hotkey() registrations, got " _mockHotkeyCalls.Length)
        if _mockHotkeyCalls[1].key != "^!m" || _mockHotkeyCalls[1].options != "On"
            throw Error("Main hotkey not registered: " _mockHotkeyCalls[1].key " / " _mockHotkeyCalls[1].options)
        if _mockHotkeyCalls[2].key != "^!r" || _mockHotkeyCalls[3].key != "^!w"
            throw Error("Reload/close hotkeys not registered")
        if _mockHotkeyCalls[4].key != "CapsLock & x" || _mockHotkeyCalls[4].options != "S On"
            throw Error("Suspend hotkey should use S On")

        ; The main hotkey callback must route through handleHotkey("showCommandMenu")
        if Type(_mockHotkeyCalls[1].callback) != "Func"
            throw Error("Main hotkey callback should be a function")

        _mockReloadCalls := 0
        _mockHotkeyCalls[2].callback.Call()
        if _mockReloadCalls != 1
            throw Error("Reload hotkey callback should call Reload()")

        ; Active bindings must be remembered for the next update
        if _activeHotkeys.main != "^!m" || _activeHotkeys.suspend != "CapsLock & x"
            throw Error("Active hotkey bindings not remembered")
    }

    Register_TurnsOffPreviousBindings() {
        global mainHotkey, reloadHotkey, closeWindowsHotkey, suspendHotkey
        global _activeHotkeys, _mockHotkeyCalls
        mainHotkey := "^!m"
        reloadHotkey := "^!r"
        closeWindowsHotkey := "^!w"
        suspendHotkey := "CapsLock & x"
        _activeHotkeys := { main: "old1", reload: "old2", closeWindows: "old3", suspend: "old4" }
        _mockHotkeyCalls := []

        _registerAllHotkeys()

        if _mockHotkeyCalls.Length != 8
            throw Error("Expected 4 Off + 4 On calls, got " _mockHotkeyCalls.Length)
        if _mockHotkeyCalls[1].key != "old1" || _mockHotkeyCalls[1].options != "Off"
            throw Error("Old main hotkey should be turned Off")
        if _mockHotkeyCalls[4].key != "old4" || _mockHotkeyCalls[4].options != "Off"
            throw Error("Old suspend hotkey should be turned Off")
        if _mockHotkeyCalls[5].options != "On"
            throw Error("New bindings should follow the Off calls")
    }

    Register_PartialPreviousBindings() {
        global mainHotkey, reloadHotkey, closeWindowsHotkey, suspendHotkey
        global _activeHotkeys, _mockHotkeyCalls
        mainHotkey := "^!m"
        reloadHotkey := "^!r"
        closeWindowsHotkey := "^!w"
        suspendHotkey := "CapsLock & x"
        _activeHotkeys := { main: "old1", reload: "", closeWindows: "", suspend: "" }
        _mockHotkeyCalls := []

        _registerAllHotkeys()

        if _mockHotkeyCalls.Length != 5
            throw Error("Expected 1 Off + 4 On calls, got " _mockHotkeyCalls.Length)
    }

    Handle_Suspend() {
        global _mockKeyWaitCalls, _mockCapsLockCalls, _mockToggleSuspendCalls
        _mockKeyWaitCalls := []
        _mockCapsLockCalls := []
        _mockToggleSuspendCalls := []

        handleHotkey("suspendHotkey")

        if _mockKeyWaitCalls.Length != 1 || _mockKeyWaitCalls[1] != "CapsLock"
            throw Error("Suspend should KeyWait CapsLock")
        if _mockCapsLockCalls.Length != 1 || _mockCapsLockCalls[1] != "Off"
            throw Error("Suspend should SetCapsLockState Off")
        if _mockToggleSuspendCalls.Length != 1
            throw Error("Suspend should call toggleSuspend")
    }

    Handle_ReloadScript() {
        global _mockReloadCalls
        _mockReloadCalls := 0
        handleHotkey("reloadScript")
        if _mockReloadCalls != 1
            throw Error("reloadScript should call Reload()")
    }

    Handle_CloseWindows_Match() {
        global _mockWinActiveResult, _mockCloseWindowCalls
        _mockWinActiveResult := 424242
        _mockCloseWindowCalls := 0
        handleHotkey("closeWindows")
        if _mockCloseWindowCalls != 1
            throw Error("closeWindows should trigger closeButtonAction on the input window")
        _mockWinActiveResult := ""
    }

    Handle_CloseWindows_NoMatch() {
        global _mockWinActiveResult, _mockCloseWindowCalls
        _mockWinActiveResult := 999999
        _mockCloseWindowCalls := 0
        handleHotkey("closeWindows")
        if _mockCloseWindowCalls != 0
            throw Error("closeWindows must not fire for an unrelated window")
        _mockWinActiveResult := ""
    }

    ; The real buildCommandMenu() ends with Menu.Show(), which blocks, so the
    ; showCommandMenu case is exercised through its failure path: an
    ; unenumerable `commands` global makes buildCommandMenu throw before
    ; Show(), which must be caught and surfaced by handleHotkey.
    Handle_ShowCommandMenu_ErrorsAreSurfaced() {
        global commands, _mockToolTipCalls, _mockSetTimerCalls
        oldCommands := commands
        commands := 5
        _mockToolTipCalls := []
        _mockSetTimerCalls := []
        try {
            handleHotkey("showCommandMenu")
        } catch Error as e {
            commands := oldCommands
            throw Error("handleHotkey should swallow handler errors: " e.Message)
        }
        commands := oldCommands
        if _mockToolTipCalls.Length != 1
            throw Error("Expected an error ToolTip")
        if _mockSetTimerCalls.Length != 1 || _mockSetTimerCalls[1].period != -5000
            throw Error("Expected ToolTip cleanup timer")
    }

}
