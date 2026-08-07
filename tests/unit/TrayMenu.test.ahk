; ======================================================
; TrayMenu.test.ahk - Regression tests for app/TrayMenu.ahk
;
; Bug: the tray menu was populated once at Main startup from trayMenuItems,
; so Menu Items edits (add/remove/rename) required a restart.
; _rebuildTrayMenu() now rebuilds A_TrayMenu from the current trayMenuItems
; global; Main calls it at startup and registers it as a SettingsService
; hook so settings updates rebuild the menu live (headless scenario 37
; asserts that wiring).
; ======================================================

class TrayMenuTest {

    static __New() {
        RegisterTestClass("TrayMenuTest")
    }

    _setItems() {
        global trayMenuItems
        trayMenuItems := [
            { menuText: "Reload App", action: "reload" },
            { menuText: "Exit App", action: "exit" }
        ]
    }

    ; The rebuild must read the current trayMenuItems global (not a startup
    ; snapshot) and rebuild A_TrayMenu from it.
    Rebuild_IteratesCurrentTrayMenuItems() {
        srcPath := A_ScriptDir "\..\app\TrayMenu.ahk"
        src := FileRead(srcPath)
        if !InStr(src, "_rebuildTrayMenu()")
            throw Error("_rebuildTrayMenu not defined in app/TrayMenu.ahk")
        if !InStr(src, "A_TrayMenu.Delete()")
            throw Error("rebuild must clear A_TrayMenu before re-adding items")
        if !InStr(src, "A_TrayMenu.Add")
            throw Error("rebuild must add items to A_TrayMenu")
        if !InStr(src, "for _, item in trayMenuItems")
            throw Error("rebuild must iterate the current trayMenuItems global")
    }

    ; Running the rebuild twice must not error - settings updates call it on
    ; every save, replacing (not duplicating) the menu items.
    Rebuild_RunsCleanlyTwice() {
        this._setItems()
        _rebuildTrayMenu()
        _rebuildTrayMenu()
    }
}
