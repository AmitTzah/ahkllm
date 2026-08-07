; ======================================================
; TrayIcon.test.ahk - Regression tests for app/TrayIcon.ahk
;
; Bug: the tray icon was applied once at Main startup (and only re-applied
; when suspend was toggled), so tray-icon edits required a restart.
; _rebuildTrayIcon() now re-applies the icon from the current globals and
; honors the suspend state; Main calls it at startup and registers it as a
; SettingsService hook so settings updates re-apply it too (headless
; scenario 34 asserts that wiring).
; ======================================================

class TrayIconTest {

    static __New() {
        RegisterTestClass("TrayIconTest")
    }

    _setIcons() {
        global iconOn, iconOff
        iconOn := "icons\IconOn.ico"
        iconOff := "icons\IconOff.ico"
    }

    ; Active (not suspended): the rebuild must pick iconOn from the globals.
    ActiveState_PicksIconOn() {
        global iconOn
        this._setIcons()
        oldSuspended := A_IsSuspended
        try {
            if oldSuspended
                Suspend -1
            picked := _trayIconForCurrentState()
            if picked != iconOn
                throw Error("active state picked '" picked "' expected '" iconOn "'")
        } finally {
            if oldSuspended
                Suspend -1
        }
    }

    ; Suspended: the rebuild must pick iconOff.
    SuspendedState_PicksIconOff() {
        global iconOff
        this._setIcons()
        oldSuspended := A_IsSuspended
        try {
            if !oldSuspended
                Suspend -1
            picked := _trayIconForCurrentState()
            if picked != iconOff
                throw Error("suspended state picked '" picked "' expected '" iconOff "'")
        } finally {
            if !oldSuspended
                Suspend -1
        }
    }

    ; Rebuild must run cleanly in both states against real icon files (the
    ; startup + settings-update wiring is asserted by headless scenario 34).
    Rebuild_RunsCleanlyInBothStates() {
        global iconOn, iconOff
        iconOn := A_ScriptDir "\..\icons\IconOn.ico"
        iconOff := A_ScriptDir "\..\icons\IconOff.ico"
        oldSuspended := A_IsSuspended
        try {
            if A_IsSuspended
                Suspend -1
            _rebuildTrayIcon()
            Suspend -1
            _rebuildTrayIcon()
        } finally {
            if !oldSuspended
                Suspend -1
        }
    }
}
