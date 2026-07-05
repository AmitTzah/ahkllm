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
            switch {
                case WinExist(chatWindow.hWnd) && !WinActive(chatWindow.hWnd) && ProcessExist(manageState("cURL", "get")):
                    manageState("cURL", "close")
                    postWebMessage("setChatButtonsEnabled", true)
                case WinActive(chatWindow.hWnd):
                    switch {
                        case ProcessExist(manageState("cURL", "get")):
                            manageState("cURL", "close")
                            postWebMessage("setChatButtonsEnabled", true)
                        Default:
                            chatWindow.Hide()
                    }
                case ProcessExist(manageState("cURL", "get")):
                    manageState("cURL", "close")
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

    msgs := "["
    for i, msg in path {
        if i > 1
            msgs .= ","
        escapedContent := StrReplace(StrReplace(StrReplace(msg.content, "\", "\\"), '"', '\"'), "`n", "\n")
        if msg.role = "system"
            msgs .= '{"role":"system","content":"' escapedContent '"}'
        else if msg.role = "user"
            msgs .= '{"role":"user","content":"' escapedContent '"}'
        else
            msgs .= '{"role":"assistant","content":"' escapedContent '"}'
    }
    msgs .= "]"

    payload := '{"model":"' requestParams["singleAPIModelName"] '","messages":' msgs
    if requestParams["stream"]
        payload .= ',"stream":true'
    payload .= "}"

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
    if requestParams["stream"] {
        sendStreamingRequest(&chatHistoryJSONRequest, initialRequest)
        return
    }
    cURLCommand := FileOpen(requestParams["cURLCommandFile"], "r", "UTF-8").Read()
    Run(cURLCommand, , "Hide", &cURLPID)
    manageState("cURL", "set", cURLPID)
    while ProcessExist(cURLPID)
        Sleep 250
    if !manageState("cURL", "get") {
        manageState("cURL", "close")
        startLoadingCursor(false)
        return
    }
    manageState("cURL", "set", 0)
    if !FileExist(requestParams["cURLOutputFile"]) {
        postWebMessage("setChatButtonsEnabled", true)
        startLoadingCursor(false)
        return
    }
    JSONResponseFromLLM := FileOpen(requestParams["cURLOutputFile"], "r", "UTF-8").Read()
    responseFromLLM := router.extractJSONResponse(jsongo.Parse(JSONResponseFromLLM))
    responseFromLLM.model := StrReplace(SubStr(responseFromLLM.model, InStr(responseFromLLM.model, "/") + 1), ":", "-")
    router.appendToChatHistory("assistant", responseFromLLM.response, &chatHistoryJSONRequest, requestParams["chatHistoryJSONRequestFile"])
    manageChatHistoryJSON("set", chatHistoryJSONRequest)
    structuredMessages := buildStructuredMessagesFromPath(ChatDB.Msg_GetActivePath(activeThreadId))
    if initialRequest
        postWebMessage("initChatMode", structuredMessages)
    else {
        lastMsg := structuredMessages[structuredMessages.Length]
        postWebMessage("appendChatMessage", lastMsg)
    }
    postWebMessage("setChatButtonsEnabled", true)
    startLoadingCursor(false)
}

; ----------------------------------------------------
; Include modules (must be before Load() for HostObjects to be registered on time)
; ----------------------------------------------------

#Include ChatIPC.ahk
#Include ChatUtils.ahk
#Include StreamHandler.ahk
#Include ChatCallbacks.ahk

; ----------------------------------------------------
; ----------------------------------------------------
; Register HostObjects BEFORE Load() — required by WebViewToo
; ----------------------------------------------------
; NOTE: HostObjects with { func: ... } pattern are NOT used for JS→AHK calls.
; Instead, we use window.chrome.webview.postMessage() with WebMessageReceived handler.
; These registrations are kept for backward compatibility but should not be relied upon.

; Set postWebMessageFn for ChatUtils (used by StreamHandler)
ChatIPCHandler.postWebMessageFn := (target, data) => postWebMessage(target, data)

; ----------------------------------------------------
; Load WebView — now that HostObjects are registered
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
    ; Clear loading state and check if we need to auto-fire LLM
    Sleep 500
    postWebMessage("setChatButtonsEnabled", true)
    
    ; Auto-trigger LLM if the last message is from the user (pending response)
    if path.Length > 0 && path[path.Length].role = "user" {
        chatHistoryJSONRequest := BuildAndWriteRequestFiles()
        if chatHistoryJSONRequest {
            manageChatHistoryJSON("set", chatHistoryJSONRequest)
            postWebMessage("setChatButtonsEnabled", false)
            sendRequestToLLM(&chatHistoryJSONRequest)
        }
    }
}