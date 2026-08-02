; ======================================================
; SuspendBanner.test.ahk — Regression tests for app/SuspendBanner.ahk
;
; Bug: the suspend banner GUI was built once at startup from the then-current
; ui.suspendBanner settings; settings saves refreshed the globals but never the
; GUI, so banner edits required a restart. _rebuildSuspendBanner() now rebuilds
; the GUI from the current globals (and re-shows it when already suspended).
; ======================================================

class SuspendBannerTest {

    static __New() {
        RegisterTestClass("SuspendBannerTest")
    }

    _setGlobals() {
        global suspendBannerText, suspendBannerFontSize, suspendBannerFontFace
        global suspendBannerTextColor, suspendBannerBackground
        suspendBannerText := "SUSPENDED TEST"
        suspendBannerFontSize := "s14"
        suspendBannerFontFace := "Consolas"
        suspendBannerTextColor := "cRed"
        suspendBannerBackground := "0x123456"
    }

    ; Rebuild must create a FRESH GUI from the current globals and destroy the
    ; previous one (the bug built it once at startup and reused it forever).
    Rebuild_CreatesFreshGui_FromCurrentSettings() {
        global suspendBanner, suspendBannerWidth
        this._setGlobals()
        suspendBanner := ""

        _rebuildSuspendBanner()

        if !IsObject(suspendBanner)
            throw Error("suspendBanner was not created")
        if suspendBannerWidth != "" && suspendBannerWidth < 0
            throw Error("suspendBannerWidth invalid: " suspendBannerWidth)
        firstHwnd := suspendBanner.hWnd

        _rebuildSuspendBanner()

        if suspendBanner.hWnd = firstHwnd
            throw Error("Rebuild reused the same GUI; expected a fresh one")
        if WinExist("ahk_id " firstHwnd)
            throw Error("Previous banner GUI still exists after rebuild")
        suspendBanner.Destroy()
    }

    ; Rebuild must re-show the banner when the script is already suspended.
    Rebuild_ShowsBannerWhenSuspended() {
        global suspendBanner
        this._setGlobals()
        suspendBanner := ""

        oldSuspended := A_IsSuspended
        Suspend -1
        try {
            _rebuildSuspendBanner()
            hwnd := suspendBanner.hWnd
            if !WinExist("ahk_id " hwnd)
                throw Error("Rebuilt banner should be visible while suspended")
            text := WinGetText("ahk_id " hwnd)
            if !InStr(text, "SUSPENDED TEST")
                throw Error("Banner text not applied from current globals: '" text "'")
        } finally {
            if !oldSuspended
                Suspend -1
            try suspendBanner.Destroy()
        }
    }
}
