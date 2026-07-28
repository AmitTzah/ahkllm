; ======================================================
; ChatWindow.ahk — Single persistent chat window
;
; Runs as a sub-process spawned by Main.ahk. No tray icon.
; Close = hide. Re-opened via tray menu or command-line arg.
;
; Usage: AutoHotkey64.exe ChatWindow.ahk <mainScriptHwnd> [threadId]
; ======================================================

#Include ..\lib\Config.ahk
#SingleInstance Off

; Global error handler — surfaces errors to chat UI and debug log
OnError((err, mode) => (
    debugLog("RUNTIME ERROR: " err.Message "`nStack: " (err.HasProp("Stack") ? err.Stack : "none"), "ErrorHandler"),
    (IsSet(postWebMessage) ? postWebMessage("showError", { message: "Runtime Error: " err.Message }) : ""),
    (IsSet(startLoadingCursor) ? startLoadingCursor(false) : ""),
    (IsSet(postWebMessage) ? postWebMessage("setChatButtonsEnabled", true) : "")
), -1)
#NoTrayIcon

; ----------------------------------------------------
; Hotkeys
; ----------------------------------------------------

~^w:: ChatHotkeys("closeWindows")

ChatHotkeys(action) {
    switch action {
        case "closeWindows":
            switch WinActive("A") {
                case chatWindow.hWnd: chatWindow.Hide()
            }
    }
}

; ----------------------------------------------------
; Initialize DB and request params
;
; ChatDB is opened here AND in Main.ahk — both processes need
; direct DB access. Main.ahk creates threads/messages; this process
; loads threads, saves responses, manages settings. SQLite WAL mode
; allows safe concurrent access. Each process is single-threaded (AHK).
;
; requestParams is a shared Map used across ALL included modules:
; ChatIPC, ChatSettings, ChatRequestBuilder, ChatUtils, StreamHandler,
; and all ChatCallbacks_*.ahk files. It holds the current thread's
; model, provider, overrides, stream state, and temp file paths.
; ----------------------------------------------------

ChatDB.Open()

; ----------------------------------------------------
; Load settings from settings.json (fall back to UserConfig.ahk defaults)
; ----------------------------------------------------
settings := SettingsHandler.Load()
merged := SettingsHandler.Merge(settings, SettingsHandler.GetDefaults())
SettingsHandler.ApplyToGlobals(merged)
RuntimeResolver_CheckApiKeys()
RuntimeResolver_ResolvePrimaryProvider()
RuntimeResolver_ResolveDefaultAssistant()
debugLog("[CHAT] Settings loaded" (settings.Count ? " from settings.json" : " from UserConfig defaults"))

; Clean up DB and cURL on exit (ProcessClose from Main.ahk is force-kill;
; this runs when ChatWindow exits gracefully via WinClose or user action)
_ChatWindowOnExit(*) {
    try ChatDB.Close()
    try {
        if IsSet(cURLState) {
            pid := cURLState("get")
            if pid && ProcessExist(pid)
                cURLState("close")
        }
    }
}
OnExit(_ChatWindowOnExit)

requestParams := Map()
requestParams["pasteMode"] := "chat"
requestParams["uniqueID"] := A_TickCount A_NowUTC
requestParams["mainScriptHiddenhWnd"] := A_Args.Length > 0 ? Integer(A_Args[1]) : 0
requestParams["providerName"] := "deepseek"
requestParams["singleAPIModelName"] := chatDefaultModel
requestParams["windowTitle"] := "Chat"
requestParams["stream"] := true
requestParams["isFIM"] := false
requestParams["numberOfAPIModels"] := 1
requestParams["APIModelsIndex"] := 1
activeThreadId := ""

; ----------------------------------------------------
; IPC handlers (ChatIPC), settings (ChatSettings),
; and request builder (ChatRequestBuilder)
; ----------------------------------------------------

#Include ChatSettings.ahk
#Include ChatRequestBuilder.ahk
#Include ChatIPC.ahk

; ----------------------------------------------------
; Create WebView and LLM client
; ----------------------------------------------------

global responseWindow := WebViewToo(, , ,)
responseWindow.OnEvent("Close", (*) => responseWindow.Hide())
responseWindow.Title := "LLM AutoHotkey Assistant"
global chatWindow := responseWindow

; Set window icon (title bar / taskbar) to match the main script's tray icon
hIcon := LoadPicture(A_ScriptDir "\..\" iconOn, "Icon1 w32 h32", &imgType)
if hIcon {
    SendMessage(0x80, 0, hIcon, , "ahk_id " chatWindow.hWnd)  ; WM_SETICON, ICON_BIG (Alt+Tab)
    SendMessage(0x80, 1, hIcon, , "ahk_id " chatWindow.hWnd)  ; WM_SETICON, ICON_SMALL (title bar / taskbar)
}

; Set up WebMessageReceived handler for JS→AHK communication via postMessage
responseWindow.WebMessageReceived(OnWebMessageReceived)

; Register Dashboard host object for inline usage dashboard
responseWindow.AddHostObjectToScript("Dashboard", {
    QueryUsage: (filtersJson) => jsongo.Stringify(ChatDB.Usage_Query(jsongo.Parse(filtersJson)))
})

llmClient := LLMRequestBuilder(APIKey)

; ----------------------------------------------------
; Utility modules, dispatch, and callbacks
; ----------------------------------------------------

; Handle inline dashboard IPC from Main.ahk
OnMessage(CustomMessages.WM_SHOW_DASHBOARD, (*) => (
    postWebMessage("showDashboard"),
    chatWindow.Show(),
    WinActivate("ahk_id " chatWindow.hWnd)
))

#Include ChatUtils.ahk
#Include ThreadTitleGen.ahk
#Include streaming\StreamHandler.ahk
#Include callbacks\Dispatch.ahk

; ----------------------------------------------------
; Load WebView
; ----------------------------------------------------

responseWindow.Load("..\webui\index.html")

; ----------------------------------------------------
; Show window
; ----------------------------------------------------

showChatWindow(initialRequest := true) {
    if initialRequest {
        _SetChatWindowSize()
        chatWindow.Show(_WindowPosStr(), "Chat")
    } else {
        chatWindow.Show()
    }
    if !WinActive("ahk_id " chatWindow.hWnd)
        chatWindow.Flash()
    Sleep 500
    if initialRequest && requestParams["mainScriptHiddenhWnd"] {
        CustomMessages.notifyLoadingState(CustomMessages.WM_CHAT_WINDOW_OPENED,
            requestParams["uniqueID"], chatWindow.hWnd, requestParams["mainScriptHiddenhWnd"])
    }
}

; Check if pre-warming (spawned hidden at Main.ahk startup)
prewarming := (A_Args.Length >= 2 && A_Args[2] = "prewarm")

if prewarming {
    ; Pre-warm mode: initialize WebView2 in background, stay hidden.
    ; Set window size/position now so it appears centered when shown.
    _SetChatWindowSize()
    ; Post config messages so they're ready when user opens.
    postWebMessage("setChatButtonsEnabled", true)
    ; Notify main script so it knows we exist (for WinShow later).
    CustomMessages.notifyLoadingState(CustomMessages.WM_CHAT_WINDOW_OPENED,
        requestParams["uniqueID"], chatWindow.hWnd, requestParams["mainScriptHiddenhWnd"])
    debugLog("[APP] ChatWindow prewarmed — hWnd=" chatWindow.hWnd)
} else {
    showChatWindow(true)
    postWebMessage("setChatButtonsEnabled", true)
}

; ----------------------------------------------------
; Load initial thread if passed via command-line arg
; (skip in prewarm mode — "prewarm" is not a thread ID)
; ----------------------------------------------------

if (A_Args.Length >= 2 && A_Args[2] != "" && A_Args[2] != "prewarm") {
    LoadThreadIntoUI(A_Args[2], true)  ; autoFire=true for command-line-arg path
    Sleep 500
    postWebMessage("setChatButtonsEnabled", true)
}

; Default chat window dimensions used by showChatWindow and prewarm.
_ChatWindowDims() {
    return { w: 900, h: 680,
             x: (A_ScreenWidth - 900) // 2,
             y: (A_ScreenHeight - 680) // 4 }
}

; Compute default chat window size and position, then move the window.
_SetChatWindowSize() {
    d := _ChatWindowDims()
    WinMove(d.x, d.y, d.w, d.h, "ahk_id " chatWindow.hWnd)
}

; Return a position string "xX yY wW hH" for the default chat window layout.
_WindowPosStr() {
    d := _ChatWindowDims()
    return Format("x{} y{} w{} h{}", d.x, d.y, d.w, d.h)
}
