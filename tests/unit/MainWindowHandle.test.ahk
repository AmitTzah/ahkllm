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
}
