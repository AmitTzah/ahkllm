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
#NoTrayIcon

; ----------------------------------------------------
; Hotkeys
; ----------------------------------------------------

~Esc:: ChatHotkeys("Esc")
~^w:: ChatHotkeys("closeWindows")

ChatHotkeys(action) {
    switch action {
        case "Esc":
            curlPID := manageState("cURL", "get")
            hadCurl := ProcessExist(curlPID)
            if hadCurl {
                manageState("cURL", "close")
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
; ----------------------------------------------------

ChatDB.Open()
requestParams := Map()
requestParams["pasteMode"] := "chat"
requestParams["uniqueID"] := A_TickCount A_NowUTC
requestParams["mainScriptHiddenhWnd"] := A_Args.Length > 0 ? Integer(A_Args[1]) : 0
requestParams["providerName"] := "deepseek"
requestParams["singleAPIModelName"] := chatDefaultModel
requestParams["responseWindowTitle"] := "Chat"
requestParams["stream"] := true
requestParams["isFIM"] := false
requestParams["numberOfAPIModels"] := 1
requestParams["APIModelsIndex"] := 1
activeThreadId := ""

; Register IPC handlers for main-script commands
OnMessage(CustomMessages.WM_LOAD_THREAD, OnLoadThread)
OnMessage(CustomMessages.WM_NEW_CHAT, OnNewChat)

OnLoadThread(wParam, lParam, msg, hWnd) {
    global activeThreadId
    threadId := StrGet(wParam)
    if threadId {
        activeThreadId := threadId
        path := ChatDB.Msg_GetActivePath(activeThreadId)
        postWebMessage("initChatMode", buildStructuredMessagesFromPath(path))
        postWebMessage("renderChatTree", ChatDB.Msg_GetTree(activeThreadId))
        postThreadStats(activeThreadId)
    }
}

OnNewChat(wParam, lParam, msg, hWnd) {
    global activeThreadId
    activeThreadId := ChatDB.Thread_Create()
    postWebMessage("initChatMode", [])
}

; ----------------------------------------------------
; Create WebView and router
; ----------------------------------------------------

responseWindow := WebViewToo(, , ,)
responseWindow.OnEvent("Close", (*) => responseWindow.Hide())
global chatWindow := responseWindow

; Set up WebMessageReceived handler for JS→AHK communication via postMessage
responseWindow.WebMessageReceived(OnWebMessageReceived)
OnWebMessageReceived(sender, args) {
    try {
        msg := args.TryGetWebMessageAsString()
        if !msg
            return
        parsed := jsongo.Parse(msg)
        action := parsed.Get("action", "")
        switch action {
            case "chatSend":
                chatSendFromWebView(parsed.Get("message", ""))
            case "retry":
                retryFromWebView()
            case "editMessage":
                editMessageFromWebView(parsed)
            case "deleteMessage":
                deleteMessageFromWebView(parsed.Get("id", ""))
            case "undeleteMessage":
                undeleteMessageFromWebView(parsed.Get("id", ""))
            case "switchBranch":
                switchBranchFromWebView(parsed)
            case "forkChat":
                forkChatFromWebView(parsed.Get("id", ""))
            case "setFeedback":
                setFeedbackFromWebView(parsed)
            case "sidebarAction":
                sidebarActionFromWebView(parsed)
            case "buttonClick":
                buttonClickAction(parsed.Get("btnAction", ""))
        }
    }
}

if (darkMode)
    DllCall("Dwmapi\DwmSetWindowAttribute", "ptr", responseWindow.hWnd, "int", 20, "int*", true, "int", 4)

router := LLMClient(APIKey)

; ----------------------------------------------------
; Core functions (used by included modules below)
; ----------------------------------------------------

BuildAndWriteRequestFiles() {
    if !activeThreadId
        return ""
    path := ChatDB.Msg_GetActivePath(activeThreadId)
    if !path.Length
        return ""

    ; Build messages array as AHK objects for safe JSON serialization
    apiMessages := []
    for msg in path {
        apiMessages.Push({ role: msg.role, content: msg.content })
    }

    requestObj := { model: requestParams["singleAPIModelName"], messages: apiMessages }
    if requestParams["stream"]
        requestObj.stream := true

    payload := jsongo.Stringify(requestObj)
    ; jsongo serializes AHK v2 true/false as integers 1/0 — fix for DeepSeek API
    payload := StrReplace(payload, '"stream":1', '"stream":true')

    uniqueID := A_TickCount
    requestFile := A_Temp "\ChatWindow_Req_" uniqueID ".json"
    cURLFile := A_Temp "\ChatWindow_cURL_" uniqueID ".txt"
    outputFile := A_Temp "\ChatWindow_Out_" uniqueID ".json"
    errorFile := A_Temp "\ChatWindow_Err_" uniqueID ".txt"

    FileOpen(requestFile, "w", "UTF-8-RAW").Write(payload)
    cURLCommand := router.buildStreamcURLCommand(requestFile, outputFile, errorFile)
    FileOpen(cURLFile, "w", "UTF-8-RAW").Write(cURLCommand)

    requestParams["chatHistoryJSONRequestFile"] := requestFile
    requestParams["cURLCommandFile"] := cURLFile
    requestParams["cURLOutputFile"] := outputFile
    requestParams["cURLErrorFile"] := errorFile

    return payload
}

sendRequestToLLM(&chatHistoryJSONRequest, initialRequest := false) {
    sendStreamingRequest(&chatHistoryJSONRequest, initialRequest)
}

; ----------------------------------------------------
; Include modules
; ----------------------------------------------------

#Include ChatUtils.ahk
#Include StreamHandler.ahk
#Include ChatCallbacks_Message.ahk
#Include ChatCallbacks_Edit.ahk
#Include ChatCallbacks_Branch.ahk
#Include ChatCallbacks_Sidebar.ahk

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
    if WinGetMinMax(chatWindow.hWnd) = -1
        chatWindow.Flash()
    Sleep 500
    postWebMessage("setTheme", [darkMode])
    postWebMessage("setFontFace", [responseWindowFontFace])
    if initialRequest && requestParams["mainScriptHiddenhWnd"] {
        CustomMessages.notifyResponseWindowState(CustomMessages.WM_CHAT_WINDOW_OPENED,
            requestParams["uniqueID"], chatWindow.hWnd, requestParams["mainScriptHiddenhWnd"])
    }
}

showChatWindow(true)
postWebMessage("setChatButtonsEnabled", true)

; ----------------------------------------------------
; Load initial thread if passed via command-line arg
; ----------------------------------------------------

if (A_Args.Length >= 2 && A_Args[2] != "") {
    activeThreadId := A_Args[2]
    path := ChatDB.Msg_GetActivePath(activeThreadId)
    postWebMessage("initChatMode", buildStructuredMessagesFromPath(path))
    postThreadStats(activeThreadId)
    ; Clear loading state and check if we need to auto-fire LLM
    Sleep 500
    postWebMessage("setChatButtonsEnabled", true)
    
    ; Auto-trigger LLM if the last message is from the user (pending response)
    if path.Length > 0 && path[path.Length].role = "user" {
        chatHistoryJSONRequest := BuildAndWriteRequestFiles()
        if chatHistoryJSONRequest {
            postWebMessage("setChatButtonsEnabled", false)
            sendRequestToLLM(&chatHistoryJSONRequest)
        }
    }
}