; ----------------------------------------------------
; Usage Dashboard — persistent WebView2 window
;
; Created on first use, hidden on close (persistent).
; Included from Main.ahk, not run standalone.
; ----------------------------------------------------

global usageDashboard := unset

InitUsageDashboard() {
    global usageDashboard
    ; Guard: if already initialized and window is alive, skip
    if IsSet(usageDashboard) {
        try if WinExist("ahk_id" usageDashboard.hWnd)
            return
        ; Window was destroyed externally — clean up and re-create
        usageDashboard := unset
    }
    usageDashboard := WebViewToo(, , ,)
    usageDashboard.OnEvent("Close", (*) => usageDashboard.Hide())
    if (IsSet(darkMode) && darkMode)
        DllCall("Dwmapi\DwmSetWindowAttribute", "ptr", usageDashboard.hWnd, "int", 20, "int*", true, "int", 4)
    usageDashboard.AddHostObjectToScript("Dashboard", {
        QueryUsage: (filtersJson) => jsongo.Stringify(ChatDB.Usage_Query(jsongo.Parse(filtersJson)))
    })
    usageDashboard.WebMessageReceived(OnDashboardWebMessage)
    usageDashboard.Load("webui\usage-dashboard.html")
}

OnDashboardWebMessage(sender, args) {
    try {
        msg := args.TryGetWebMessageAsString()
        if !msg
            return
        parsed := jsongo.Parse(msg)
        action := parsed.Get("action", "")
        if action = "showApiLogs"
            ShowApiLogs()
    } catch Error as e {
        debugLog("Dashboard WebMessage error: " e.Message, "UsageDashboard")
    }
}

ShowUsageDashboard() {
    debugLog("[DASHBOARD] Opened")
    global usageDashboard
    if !IsSet(usageDashboard) {
        InitUsageDashboard()
        Sleep 500
    } else {
        try usageDashboard.ExecuteScript("if(typeof loadData==='function')loadData()")
    }
    w := Min(1400, Round(A_ScreenWidth * 0.75))
    h := Round(A_ScreenHeight * 0.85)
    usageDashboard.Show("x" (A_ScreenWidth - w) // 2 " y" (A_ScreenHeight - h) // 2 " w" w " h" h, "Usage Dashboard")
}

CloseUsageDashboard(*) {
    global usageDashboard
    if IsSet(usageDashboard) {
        try usageDashboard.Destroy()
        usageDashboard := unset
    }
}
