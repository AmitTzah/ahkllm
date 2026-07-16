; ----------------------------------------------------
; API Logs Viewer — persistent WebView2 window
;
; Created once at startup (hidden), shown/hidden on demand.
; Included from Main.ahk, not run standalone.
; ----------------------------------------------------

global apiLogsViewer := unset

InitApiLogsViewer() {
    global apiLogsViewer
    debugLog("[APILOGS] InitApiLogsViewer: creating WebViewToo")
    try {
        apiLogsViewer := WebViewToo(, , ,)
        debugLog("[APILOGS] WebViewToo created, hWnd=" apiLogsViewer.hWnd)
    } catch Error as e {
        debugLog("[APILOGS] WebViewToo FAILED: " e.Message)
        return
    }
    apiLogsViewer.OnEvent("Close", (*) => apiLogsViewer.Hide())
    apiLogsViewer.AddHostObjectToScript("Logs", {
        GetLogs: (*) => jsongo.Stringify(ApiLogger.ReadLogs()),
        ClearLogs: (*) => (ApiLogger.ClearLogs(), "ok"),
        GetLogCount: (*) => ApiLogger.ReadLogs().Length
    })
    apiLogsViewer.Load("webui\api-logs.html")
}

ShowApiLogs() {
    debugLog("[APILOGS] ShowApiLogs called, IsSet(apiLogsViewer)=" IsSet(apiLogsViewer))
    global apiLogsViewer
    if !IsSet(apiLogsViewer) {
        debugLog("[APILOGS] Initializing new viewer window")
        InitApiLogsViewer()
        Sleep 500  ; let WebView2 finish initial render
    } else {
        ; ExecuteScriptAsync (fire-and-forget) — NOT ExecuteScript (blocking).
        ; Blocking would deadlock: OnDashboardWebMessage holds the main thread,
        ; and apiLogsViewer's WebView2 needs the main thread to deliver the
        ; ExecuteScript completion callback.
        apiLogsViewer.ExecuteScriptAsync("reloadLogs()")
    }
    debugLog("[APILOGS] About to show viewer at x" (A_ScreenWidth - 900) // 2 " y" (A_ScreenHeight - 600) // 2)
    try {
        apiLogsViewer.Show("x" (A_ScreenWidth - 900) // 2 " y" (A_ScreenHeight - 600) // 2 " w900 h600", "API Logs Viewer")
        debugLog("[APILOGS] Show() succeeded, hWnd=" apiLogsViewer.hWnd)
    } catch Error as e {
        debugLog("[APILOGS] Show() FAILED: " e.Message)
    }
}

; Clean up on main script exit (called from Main.ahk)
CloseApiLogsViewer(*) {
    global apiLogsViewer
    if IsSet(apiLogsViewer) {
        try apiLogsViewer.Destroy()
        apiLogsViewer := unset
    }
}
