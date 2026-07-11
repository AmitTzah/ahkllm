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

~Esc:: ChatHotkeys("Esc")
~^w:: ChatHotkeys("closeWindows")

ChatHotkeys(action) {
    switch action {
        case "Esc":
            curlPID := cURLState("get")
            hadCurl := ProcessExist(curlPID)
            if hadCurl {
                ; Mark as cancelled so _finalizeStreaming logs properly
                requestParams["_streamCancelled"] := true
                cURLState("close")
                postWebMessage("setChatButtonsEnabled", true)
            }
            ; Only hide window if no cURL was running (don't hide after cancelling a request)
            if WinActive("ahk_id " chatWindow.hWnd) && !hadCurl {
                chatWindow.Hide()
            }
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
global chatWindow := responseWindow

; Set window icon (title bar / taskbar) to match the main script's tray icon
hIcon := LoadPicture(A_ScriptDir "\..\" iconOn, "Icon1 w32 h32", &imgType)
if hIcon {
    SendMessage(0x80, 0, hIcon, , "ahk_id " chatWindow.hWnd)  ; WM_SETICON, ICON_BIG (Alt+Tab)
    SendMessage(0x80, 1, hIcon, , "ahk_id " chatWindow.hWnd)  ; WM_SETICON, ICON_SMALL (title bar / taskbar)
}

; Set up WebMessageReceived handler for JS→AHK communication via postMessage
responseWindow.WebMessageReceived(OnWebMessageReceived)

if (darkMode)
    DllCall("Dwmapi\DwmSetWindowAttribute", "ptr", responseWindow.hWnd, "int", 20, "int*", true, "int", 4)

llmClient := LLMRequestBuilder(APIKey)

; ----------------------------------------------------
; Utility modules, dispatch, and callbacks
; ----------------------------------------------------

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
        desiredW := 900
        desiredH := 680
        X := (A_ScreenWidth - desiredW) // 2
        Y := (A_ScreenHeight - desiredH) // 4
        chatWindow.Show(Format("x{} y{} w{} h{}", X, Y, desiredW, desiredH), "Chat")
    } else {
        chatWindow.Show()
    }
    if !WinActive("ahk_id " chatWindow.hWnd)
        chatWindow.Flash()
    Sleep 500
    postWebMessage("setTheme", [darkMode])
    postWebMessage("setFontFace", [responseWindowFontFace])
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
    desiredW := 900
    desiredH := 680
    X := (A_ScreenWidth - desiredW) // 2
    Y := (A_ScreenHeight - desiredH) // 4
    WinMove(X, Y, desiredW, desiredH, "ahk_id " chatWindow.hWnd)
    ; Post config messages so they're ready when user opens.
    postWebMessage("setTheme", [darkMode])
    postWebMessage("setFontFace", [responseWindowFontFace])
    postWebMessage("setChatButtonsEnabled", true)
    ; Notify main script so it knows we exist (for WinShow later).
    CustomMessages.notifyLoadingState(CustomMessages.WM_CHAT_WINDOW_OPENED,
        requestParams["uniqueID"], chatWindow.hWnd, requestParams["mainScriptHiddenhWnd"])
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
