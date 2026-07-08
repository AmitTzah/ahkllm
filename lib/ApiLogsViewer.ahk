#Requires AutoHotkey v2.0.18+
#SingleInstance Off
#NoTrayIcon
#Include ..\lib\Config.ahk

; ----------------------------------------------------
; API Logs Viewer
; ----------------------------------------------------
; Standalone script launched from Options > API Logs.
; Reads the LLM_API_Log.json file and displays it in a
; WebViewToo window with expandable request/response details.

; If already open, bring to front and exit
if WinExist("API Logs Viewer") {
    WinActivate("API Logs Viewer")
    ExitApp()
}

; Create the Webview Window
viewerWindow := WebViewToo(, , ,)
viewerWindow.OnEvent("Close", (*) => ExitApp())
viewerWindow.Load("..\webui\api-logs.html")

; Apply dark mode to title bar
DllCall("Dwmapi\DwmSetWindowAttribute", "ptr", viewerWindow.hWnd, "int", 20, "int*", true, "int", 4)

; Expose log read/clear and dark mode to JavaScript
viewerWindow.AddHostObjectToScript("Logs", {
    GetLogs: GetLogs,
    ClearLogs: ClearLogs,
    IsDarkMode: IsDarkMode,
    GetLogCount: GetLogCount
})

; Show the window centered
viewerWindow.Show("x" (A_ScreenWidth - 900) // 2 " y" (A_ScreenHeight - 600) // 2 " w900 h600", "API Logs Viewer")

; ----------------------------------------------------
; Functions exposed to JavaScript via host object
; ----------------------------------------------------
; These must return values so the JS Promise resolves.

GetLogs(*) {
    logs := ApiLogger.ReadLogs()
    return jsongo.Stringify(logs)
}

ClearLogs(*) {
    ApiLogger.ClearLogs()
    return "ok"
}

IsDarkMode(*) {
    return (IsSet(darkMode) && darkMode) ? "true" : "false"
}

GetLogCount(*) {
    logs := ApiLogger.ReadLogs()
    return logs.Length
}
