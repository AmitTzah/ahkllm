; ======================================================
; SuspendBanner.ahk — suspend indicator GUI lifecycle
;
; The banner is rebuilt from the current ui.suspendBanner settings whenever
; they change, so text/font/color edits apply live instead of requiring a
; restart. Called at startup and again from Main's settings-updated handler.
; ======================================================

global suspendBanner := ""
global suspendBannerWidth := ""

_rebuildSuspendBanner() {
    global suspendBanner, suspendBannerWidth

    if suspendBanner
        suspendBanner.Destroy()

    suspendBanner := Gui()
    suspendBanner.SetFont(suspendBannerFontSize, suspendBannerFontFace)
    suspendBanner.Add("Text", suspendBannerTextColor " Center", suspendBannerText)
    suspendBanner.BackColor := suspendBannerBackground
    suspendBanner.Opt("-Caption +Owner -SysMenu +AlwaysOnTop")
    suspendBannerWidth := ""
    suspendBanner.GetPos(, , &suspendBannerWidth)

    ; If the script is already suspended, re-show the rebuilt banner so the
    ; new styling is visible immediately rather than on the next toggle.
    if A_IsSuspended
        suspendBanner.Show("AutoSize x" (A_ScreenWidth - suspendBannerWidth) / 2 " y" (A_ScreenHeight - 80) " NA")
}
