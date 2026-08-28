; ======================================================
; MainWindowHandle.test.ahk - Regression tests for bug #227
;
; Bug: Main.ahk resolved its own hidden script window with
; WinExist("ahk_class AutoHotkey"), which matches ANY AutoHotkey v2 script
; window. With the user's other AHK scripts running, the lookup could return
; one of THEIR windows, so ChatWindow's settings-updated/loading/reload IPC
; was posted to the wrong process and silently dropped (e.g. the trash-
; retention purge hook never ran after a Settings save). The fix resolves the
; handle with A_ScriptHwnd (Main's own window) in both the prewarm spawn and
; _spawnChatWindow.
; ======================================================

class MainWindowHandleTest {

    static __New() {
        RegisterTestClass("MainWindowHandleTest")
    }

    _readMainAhk() {
        ; A_ScriptDir is the RUNNER's dir (tests/) - Main.ahk is one level up.
        path := A_ScriptDir "\..\Main.ahk"
        if !FileExist(path)
            throw Error("Main.ahk not found at " path)
        return FileRead(path, "UTF-8")
    }

    ; Both places that hand the main-script handle to ChatWindow must use
    ; Main's OWN window (A_ScriptHwnd) - the prewarm spawn and _spawnChatWindow.
    MainScriptHandle_ResolvedWithOwnHwnd() {
        src := this._readMainAhk()
        own := 0
        pos := 1
        loop {
            start := InStr(src, "mainScriptHiddenHwnd := A_ScriptHwnd", , pos)
            if !start
                break
            own++
            pos := start + 1
        }
        if own != 2
            throw Error("Expected mainScriptHiddenHwnd := A_ScriptHwnd in BOTH the prewarm spawn and _spawnChatWindow; found " own)
    }

    ; The ambiguous class lookup (matches any AHK v2 script window) must never
    ; be used for mainScriptHiddenHwnd.
    MainScriptHandle_NoAmbiguousClassLookup() {
        src := this._readMainAhk()
        if InStr(src, 'mainScriptHiddenHwnd := WinExist("ahk_class AutoHotkey")')
            throw Error('mainScriptHiddenHwnd still uses the ambiguous WinExist("ahk_class AutoHotkey") class lookup (bug #227 not fixed)')
    }

    ; Regression: switching the persistent chat window to a command-created
    ; thread must hide the old view before the asynchronous load and carry an
    ; explicit activation request for user-facing opens.
    CommandChatSwitch_HidesBeforeLoadAndRefreshesWithoutReopen() {
        src := this._readMainAhk()
        preparePos := InStr(src, "prepareChatWindow()")
        hidePos := InStr(src, 'WinHide("ahk_id " chatWindowhWnd)')
        notifyPos := InStr(src, "CustomMessages.notifyLoadThread(threadId, chatWindowhWnd, activate)")
        if !preparePos || !hidePos || !notifyPos
            throw Error("thread switch must hide before notifying the ChatWindow")
        if hidePos > notifyPos
            throw Error("WinHide must occur before notifyLoadThread")
        if !InStr(src, 'openChatWindow(threadId := "", activate := true)')
            throw Error("openChatWindow must expose an explicit activation option")
    }

    CommandChatOpeningIndicator_FollowsCursorWithDedicatedTimer() {
        src := this._readMainAhk()
        if !InStr(src, "SetTimer(_followChatOpeningTooltip, 30)")
            throw Error("chat opening indicator must use a dedicated follow timer")
        if !InStr(src, 'ToolTip("Opening chat...", x + 16, y + 16, 20)')
            throw Error("chat opening indicator must update in screen coordinates near the cursor")
    }
}
