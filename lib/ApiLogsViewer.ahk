; ----------------------------------------------------
; API Logs Viewer — persistent WebView2 window
;
; Created once at startup (hidden), shown/hidden on demand.
; Included from Main.ahk, not run standalone.
; ----------------------------------------------------

global apiLogsViewer := unset

InitApiLogsViewer() {
    global apiLogsViewer
    apiLogsViewer := WebViewToo(, , ,)
    apiLogsViewer.OnEvent("Close", (*) => apiLogsViewer.Hide())
    if (IsSet(darkMode) && darkMode)
        DllCall("Dwmapi\DwmSetWindowAttribute", "ptr", apiLogsViewer.hWnd, "int", 20, "int*", true, "int", 4)
    apiLogsViewer.AddHostObjectToScript("Logs", {
        GetLogs: (*) => jsongo.Stringify(ApiLogger.ReadLogs()),
        ClearLogs: (*) => (ApiLogger.ClearLogs(), "ok"),
        IsDarkMode: (*) => (IsSet(darkMode) && darkMode) ? "true" : "false",
        GetLogCount: (*) => ApiLogger.ReadLogs().Length
    })
    apiLogsViewer.Load("webui\api-logs.html")
}

ShowApiLogs() {
    global apiLogsViewer
    if !IsSet(apiLogsViewer) {
        InitApiLogsViewer()
        Sleep 500  ; let WebView2 finish initial render
    } else {
        ; ExecuteScriptAsync (fire-and-forget) — NOT ExecuteScript (blocking).
        ; Blocking would deadlock: OnDashboardWebMessage holds the main thread,
        ; and apiLogsViewer's WebView2 needs the main thread to deliver the
        ; ExecuteScript completion callback.
        apiLogsViewer.ExecuteScriptAsync("reloadLogs()")
    }
    apiLogsViewer.Show("x" (A_ScreenWidth - 900) // 2 " y" (A_ScreenHeight - 600) // 2 " w900 h600", "API Logs Viewer")
}

; Clean up on main script exit (called from Main.ahk)
CloseApiLogsViewer(*) {
    global apiLogsViewer
    if IsSet(apiLogsViewer) {
        try apiLogsViewer.Destroy()
        apiLogsViewer := unset
    }
}
