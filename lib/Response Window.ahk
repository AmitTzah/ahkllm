#Include Config.ahk
#SingleInstance Off
#NoTrayIcon

; ----------------------------------------------------
; Hotkeys
; ----------------------------------------------------

~Esc:: subScriptHotkeyActions("Esc")
~^w:: subScriptHotkeyActions("closeWindows")

subScriptHotkeyActions(action) {
    switch action {

        ; Handles request cancellation based on Response Window state:
        ;
        ; Background window: Stop request, keep window open
        ; Active window: Stop request, keep window open
        ; Hidden window: Stop request only
        case "Esc":
            switch {
                case WinExist(responseWindow.hWnd) && !(WinActive(responseWindow.hWnd))
                && ProcessExist(manageState("cURL", "get")):
                    manageState("cURL", "close")
                    postWebMessage("setChatButtonsEnabled", true)

                case WinActive(responseWindow.hWnd):
                    switch {
                        case ProcessExist(manageState("cURL", "get")):
                            manageState("cURL", "close")
                            postWebMessage("setChatButtonsEnabled", true)

                        Default:
                            buttonClickAction("Close")
                    }

                case ProcessExist(manageState("cURL", "get")):
                    manageState("cURL", "close")
            }

        case "closeWindows":
            switch WinActive("A") {
                case responseWindow.hWnd: buttonClickAction("Close")
            }
    }
}

; ----------------------------------------------------
; Read data from main script and start loading cursor
; ----------------------------------------------------

requestParams := jsongo.Parse(FileOpen(A_Args[1], "r", "UTF-8").Read())
startLoadingCursor(true)

; ----------------------------------------------------
; Change icon based on providerName
; ----------------------------------------------------

TraySetIcon(FileExist(icon := "..\icons\" requestParams["providerName"] ".ico") ? icon : "..\icons\IconOn.ico")

; ----------------------------------------------------
; Create new instance of LLMClient class
; ----------------------------------------------------

router := LLMClient(APIKey)

; ----------------------------------------------------
; Create Response Window
; ----------------------------------------------------

; Create the Webview Window
responseWindow := WebViewToo(, , ,)
responseWindow.OnEvent("Close", (*) => buttonClickAction("Close"))
responseWindow.Load("..\resources\index.html")

; Apply dark mode to title bar
; Reference: https://www.autohotkey.com/boards/viewtopic.php?p=422034#p422034
if (darkMode) {
    DllCall("Dwmapi\DwmSetWindowAttribute", "ptr", responseWindow.hWnd, "int", 20, "int*", true, "int", 4)
}

; Assign actions to click events
responseWindow.AddHostObjectToScript("ButtonClick", { func: buttonClickAction })
responseWindow.AddHostObjectToScript("ChatSend", { func: chatSendFromWebView })

buttonClickAction(action) {
    switch action {
        case "Retry":
            manageState("model", "remove")
            postWebMessage("setChatButtonsEnabled", false)
            startLoadingCursor(true)
            chatHistoryJSONRequest := manageChatHistoryJSON("get")
            router.removeLastAssistantMessage(&chatHistoryJSONRequest)
            FileOpen(requestParams["chatHistoryJSONRequestFile"], "w", "UTF-8-RAW").Write(chatHistoryJSONRequest)
            manageChatHistoryJSON("set", chatHistoryJSONRequest)
            sendRequestToLLM(&chatHistoryJSONRequest)

        case "Close":
            if (!requestParams["skipConfirmation"]) {
                if (MsgBox("End your chat session with " requestParams["responseWindowTitle"] "?",
                    "Close " requestParams["responseWindowTitle"],
                    "308 Owner" responseWindow.hWnd) != "Yes") {
                    return true
                }
            }

            ; Proceed with closing (either no warning needed or user clicked "Yes")
            if (ProcessExist(manageState("cURL", "get"))) {
                manageState("cURL", "close")

                ; Sometimes the cURLOutputFile is still being accessed
                ; Sleep here to make sure the file is not opened anymore
                Sleep 100
            }

            deleteTempFiles()
            startLoadingCursor(false)

            ; Sends a PostMessage to main script saying the
            ; Response Window has been closed, then terminates
            ; the Response Window script afterwards
            CustomMessages.notifyResponseWindowState(CustomMessages.WM_RESPONSE_WINDOW_CLOSED,
                requestParams["uniqueID"],
                responseWindow.hWnd,
                requestParams["mainScriptHiddenhWnd"])
            ExitApp
    }
}

; ----------------------------------------------------
; Chat mode: Handle messages sent from the inline chat input
; ----------------------------------------------------

chatSendFromWebView(message, *) {
    ; The message is passed directly as a string from the WebView HostObject call
    if !message {
        return
    }

    startLoadingCursor(true)
    postWebMessage("setChatButtonsEnabled", false)
    chatHistoryJSONRequest := manageChatHistoryJSON("get")
    router.appendToChatHistory("user", message, &
        chatHistoryJSONRequest, requestParams["chatHistoryJSONRequestFile"])
    manageChatHistoryJSON("set", chatHistoryJSONRequest)
    sendRequestToLLM(&chatHistoryJSONRequest)
}

; ----------------------------------------------------
; Chat mode: Handle retry request from WebView
; ----------------------------------------------------

responseWindow.AddHostObjectToScript("RetryAction", { func: retryFromWebView })
retryFromWebView(*) {
    manageState("model", "remove")
    startLoadingCursor(true)
    chatHistoryJSONRequest := manageChatHistoryJSON("get")
    router.removeLastAssistantMessage(&chatHistoryJSONRequest)
    FileOpen(requestParams["chatHistoryJSONRequestFile"], "w", "UTF-8-RAW").Write(chatHistoryJSONRequest)
    manageChatHistoryJSON("set", chatHistoryJSONRequest)
    sendRequestToLLM(&chatHistoryJSONRequest)
}

showResponseWindow(responseWindowTextContent, initialRequest, noActivate := false) {
    postWebMessage("setTheme", [darkMode])

    ; For chat mode, the structured message array is already sent by sendRequestToLLM.
    ; For non-chat mode (FIM fallback), render markdown in the content area.
    if requestParams["pasteMode"] != "chat" {
        postWebMessage("renderMarkdown", [responseWindowTextContent])
    }

    if initialRequest {

        ; Response Window's width and height
        desiredW := 600
        desiredH := 600

        ; Calculate screen center
        screenW := A_ScreenWidth
        screenH := A_ScreenHeight

        ; Define an X and Y coordinate variables
        X := (screenW - desiredW) // 2
        Y := (screenH - desiredH) // 4

        ; Compute the arrangement of Response Windows based on the number of models:
        ; If there is one Response Window, it will be in the center
        ; If there are two, they will be side by side in the center
        ; If there are three, they will be arranged in the center
        ; If there are more than three, it will be the same as three for the first three,
        ; then additional windows will be in the center as a stack and have a slight downward offset
        switch requestParams["numberOfAPIModels"] {
            case 1:
                pos := Format("x{} y{} w{} h{}", X - 100, Y, desiredW, desiredH)

            case 2:
                X := (requestParams["APIModelsIndex"] = 1) ? (screenW // 2) - (desiredW * 1.3) : (screenW // 2)
                pos := Format("x{} y{} w{} h{}", X, Y, desiredW, desiredH)

            case 3:
                switch requestParams["APIModelsIndex"] {
                    case 1:
                        ; Left
                        X := (screenW // 2) - (desiredW * 1.6)

                    case 2:
                        ; Center
                        X := (screenW - desiredW) // 2

                    default:
                        ; Right
                        X := (screenW // 2) + (desiredW * 0.4)
                }

                pos := Format("x{} y{} w{} h{}", X, Y, desiredW, desiredH)

            default:
                if (requestParams["APIModelsIndex"] < 4) {
                    switch requestParams["APIModelsIndex"] {
                        case 1: X := (screenW // 2) - (desiredW * 1.6)
                        case 2: X := (screenW - desiredW) // 2
                        case 3: X := (screenW // 2) + (desiredW * 0.4)
                    }
                } else {
                    X := (screenW - desiredW) // 2
                    Y := Y + (requestParams["APIModelsIndex"] - 3) * 30
                }

                pos := Format("x{} y{} w{} h{}", X, Y, desiredW, desiredH)
        }

        responseWindow.Show(pos, requestParams["responseWindowTitle"])
    }

    ; Flash the Response Window if it is minimized or not active
    (WinGetMinMax(responseWindow.hWnd) = -1) || noActivate ? responseWindow.Flash() : ""
}

; ----------------------------------------------------
; Custom messages for detecting Response Windows
; and their open/close state, as well as detecting
; the "Send message to all models" feature
; ----------------------------------------------------

CustomMessages.registerHandlers("subScript", responseWindowSendToAllModels)
CustomMessages.notifyResponseWindowState(CustomMessages.WM_RESPONSE_WINDOW_OPENED, requestParams["uniqueID"],
    responseWindow.hWnd, requestParams["mainScriptHiddenhWnd"])

responseWindowSendToAllModels(uniqueID, lParam, msg, responseWindowhWnd) {
    if (ProcessExist(manageState("cURL", "get"))) {
        manageState("cURL", "close")
    }

    ; Re-read the updated JSON file and call sendRequestToLLM() again
    chatHistoryJSONRequest := FileOpen(requestParams["chatHistoryJSONRequestFile"], "r", "UTF-8-RAW").Read()
    startLoadingCursor(true)
    manageChatHistoryJSON("set", chatHistoryJSONRequest)
    postWebMessage("setChatButtonsEnabled", false)
    sendRequestToLLM(&chatHistoryJSONRequest)
}

; ----------------------------------------------------
; Run cURL command and process response
; ----------------------------------------------------

chatHistoryJSONRequest := manageChatHistoryJSON("get")
sendRequestToLLM(&chatHistoryJSONRequest, true)

sendRequestToLLM(&chatHistoryJSONRequest, initialRequest := false) {

    ; Run the cURL command asynchronously and store the PID
    Run(FileOpen(requestParams["cURLCommandFile"], "r", "UTF-8").Read(), , "Hide", &cURLPID)
    manageState("cURL", "set", cURLPID)

    ; Waits for the process to complete or be aborted
    ; while allowing the script to process events
    while (ProcessExist(cURLPID)) {
        Sleep 250
    }

    ; If user cancels the process, exit
    if !manageState("cURL", "get") {
        manageState("cURL", "close")
        startLoadingCursor(false)
        if initialRequest {
            deleteTempFiles()

            ; Sends a message to main script saying the Response Window has been closed,
            ; then terminates the Response Window script
            CustomMessages.notifyResponseWindowState(CustomMessages.WM_RESPONSE_WINDOW_CLOSED,
                requestParams["uniqueID"], responseWindow.hWnd, requestParams["mainScriptHiddenhWnd"])
            ExitApp
        }
        Exit
    }

    ; Reset the PID as the process has completed
    cURLPID := 0
    manageState("cURL", "set", cURLPID)

    ; Read the output after the process has completed
    JSONResponseFromLLM := FileOpen(requestParams["cURLOutputFile"], "r", "UTF-8").Read()

    ; Process the JSON response from the LLM API
    try {
        JSONResponseVar := jsongo.Parse(JSONResponseFromLLM)

        ; Use FIM or chat extraction based on request params
        if requestParams["isFIM"] {
            responseFromLLM := router.extractFIMResponse(JSONResponseVar)
        } else {
            responseFromLLM := router.extractJSONResponse(JSONResponseVar)
        }

        ; Get text after forward slash as responseFromLLM.model and replace colon (:) with dash (-)
        responseFromLLM.model := StrReplace(SubStr(responseFromLLM.model, InStr(responseFromLLM.model, "/") + 1), ":",
        "-")

        manageState("model", "add", responseFromLLM.model)
        if !requestParams["isFIM"] {
            ; Only append to chat history for chat completions (FIM has no chat history)
            router.appendToChatHistory("assistant",
                responseFromLLM.response, &chatHistoryJSONRequest, requestParams["chatHistoryJSONRequestFile"])
        }

        ; Log the successful API interaction
        LLMClient.LogRequest({
            timestamp: FormatTime(, "yyyy-MM-dd HH:mm:ss"),
            promptName: requestParams["responseWindowTitle"],
            provider: requestParams["providerName"],
            model: requestParams["singleAPIModelName"],
            isFIM: requestParams["isFIM"],
            endpoint: requestParams["isFIM"] ? FIMEndpoint : APIEndpoint,
            pasteMode: requestParams["pasteMode"],
            request: chatHistoryJSONRequest,
            response: JSONResponseFromLLM,
            status: "success"
        })
    } catch as e {
        ; Log the failed API interaction
        LLMClient.LogRequest({
            timestamp: FormatTime(, "yyyy-MM-dd HH:mm:ss"),
            promptName: requestParams["responseWindowTitle"],
            provider: requestParams["providerName"],
            model: requestParams["singleAPIModelName"],
            isFIM: requestParams["isFIM"],
            endpoint: requestParams["isFIM"] ? FIMEndpoint : APIEndpoint,
            pasteMode: requestParams["pasteMode"],
            request: chatHistoryJSONRequest,
            response: JSONResponseFromLLM,
            status: "error"
        })
        JSONResponseFromLLM := router.extractErrorResponse(JSONResponseVar)
        responseFromLLM :=
            "**⛔ Error parsing response**`n`n" e.Message
            . "`n`n---`n`n**⚠️ Response from the API**`n`n"
            . JSONResponseFromLLM.error
            . "`n`n---`n`n"
        errorCodes := {
            400: "You may have specified an invalid API model. See [this guide](https://github.com/kdalanon/LLM-AutoHotkey-Assistant/blob/main/README.md#apimodels) on how to get the correct API models.",
            401: "Authentication failed. Your API key or session might be invalid or expired. Check your keys [here](https://openrouter.ai/settings/keys), re-add it to the app, and try again.",
            402: "Insufficient funds. Click [here](https://openrouter.ai/credits) to check your available credits.",
            403: "Content flagged as inappropriate. Your input triggered content moderation and was rejected. Please revise your request and try again with different content.",
            408: "Request timed out. The API request took too long to process. This might be due to network issues or server overload.",
            429: "You've hit the rate limit of **" requestParams["singleAPIModelName"] "**. Try again after some time.",
            502: "Service temporarily unavailable. The chosen model is either down or returned an invalid response. Please try again later or select a different model.",
            503: "No suitable model available. There are no providers currently meeting your request requirements. Please try again later or adjust your routing settings."
        }

        ; Only append an error code explanation for known numeric codes
        try {
            errorCodeValue := errorCodes.%JSONResponseFromLLM.code%
            if errorCodeValue != "" {
                responseFromLLM .= errorCodeValue
            }
        }

        if requestParams["pasteMode"] = "chat" {
            ; In chat mode, append the error as an assistant message
            postWebMessage("appendChatMessage", { role: "assistant", content: responseFromLLM, model: "Error" })
            showResponseWindow("", initialRequest)
        } else {
            showResponseWindow(responseFromLLM, initialRequest)
        }
        postWebMessage("setChatButtonsEnabled", true)
        startLoadingCursor(false)
        Exit
    }

    ; Save Chat History and Latest Response
    if !requestParams["isFIM"] {
        manageChatHistoryJSON("set", chatHistoryJSONRequest)

        if requestParams["pasteMode"] = "chat" {
            ; --- Chat mode: Send structured message arrays to the WebView ---

            ; Build the full structured messages array from the JSON
            obj := jsongo.Parse(chatHistoryJSONRequest)
            messages := router.getMessages(obj)
            structuredMessages := []
            modelIndex := 1
            modelNames := manageState("model", "get")

            for index, message in messages {
                msgObj := { role: message.role, content: message.content }

                ; Add model name for assistant messages
                if (message.role = "assistant") {
                    msgObj.model := modelIndex <= modelNames.Length ? modelNames[modelIndex] : requestParams["singleAPIModelName"]
                    modelIndex++
                }

                structuredMessages.Push(msgObj)
            }

            if initialRequest {
                ; On initial request, initialize the full chat
                postWebMessage("initChatMode", structuredMessages)
            } else {
                ; On subsequent requests, send just the new assistant message
                ; The last element is the new assistant response
                lastMsg := structuredMessages[structuredMessages.Length]
                postWebMessage("appendChatMessage", lastMsg)
            }

        } else {
            ; --- Non-chat mode: Build chat history string for the old format ---
            obj := jsongo.Parse(chatHistoryJSONRequest)
            messages := router.getMessages(obj)
            totalMessages := messages.Length

            ; Chat History - Iterate over each message in the 'messages' array
            chatHistory := ""
            modelIndex := 1
            for index, message in messages {
                role := message.role
                content := message.content

                switch role {
                    case "system": chatHistory .= "**🔧 System Prompt**`n`n" content
                    case "user": chatHistory .= "`n`n---`n`n**🔵 You**`n`n" content
                    case "assistant": chatHistory .= "`n`n---`n`n**🟡 " manageState("model", "get")[modelIndex++] "**`n`n" content
                }
            }

            ; Latest Response - iterate backwards to find last assistant message
            latestResponse := ""
            loop totalMessages {
                currentIndex := totalMessages - A_Index + 1
                msg := messages[currentIndex]
                if (msg.role = "assistant") {
                    latestResponse := msg.content
                    break
                }
            }

            manageState("chat", "add", { chatHistory: chatHistory, latestResponse: latestResponse })
        }
    }

    if requestParams["pasteMode"] = "replace" || requestParams["pasteMode"] = "append" {
        A_Clipboard := responseFromLLM.response
        if requestParams["pasteMode"] = "append" {
            Send("{Right}")       ; Move cursor past the selection before pasting
        }
        Send("^v")
        Sleep 50
        ; Move cursor slightly within pasted text to force scroll-to-cursor
        Send("{Left}{Right}")
        startLoadingCursor(false)
        CustomMessages.notifyResponseWindowState(CustomMessages.WM_RESPONSE_WINDOW_CLOSED, requestParams["uniqueID"],
            responseWindow.hWnd, requestParams["mainScriptHiddenhWnd"])
        deleteTempFiles()
        ExitApp
    } else {
        ; For chat mode or default display mode
        if requestParams["pasteMode"] != "chat" {
            ; Non-chat mode: show the response in the content area
            showResponseWindow(responseFromLLM.response, initialRequest, !initialRequest && !(WinActive(responseWindow.hWnd
            )))
        } else {
            ; Chat mode: ensure the window is shown/flashed
            if initialRequest {
                showResponseWindow("", initialRequest)
            } else {
                responseWindow.Flash()
            }
        }
        postWebMessage("setChatButtonsEnabled", true)
        startLoadingCursor(false)
    }
}

; ----------------------------------------------------
; Manage Chat History requests
; ----------------------------------------------------

manageChatHistoryJSON(action, data := unset) {
    static JSONRequest := FileOpen(requestParams["chatHistoryJSONRequestFile"], "r", "UTF-8-RAW").Read()

    switch action {
        case "get": return JSONRequest
        case "set": JSONRequest := data
    }
}

;--------------------------------------------------
; Combined state management for model history,
; chat history, and cURL process
;--------------------------------------------------

manageState(component, action, data := {}) {
    static state := {
        modelHistory: [],
        chatHistory: { chatHistory: "", latestResponse: "" },
        cURLPID: 0
    }

    switch component {
        case "model":
            switch action {
                case "get": return state.modelHistory
                case "add": state.modelHistory.Push(data)
                case "remove": (state.modelHistory.Length) ? state.modelHistory.Pop() : ""
            }

        case "chat":
            switch action {
                case "get": return state.chatHistory
                case "add":
                    state.chatHistory.chatHistory := data.chatHistory
                    state.chatHistory.latestResponse := data.latestResponse
            }

        case "cURL":
            switch action {
                case "get": return state.cURLPID
                case "set": state.cURLPID := data
                case "close": ProcessClose(state.cURLPID), state.cURLPID := 0
            }
    }
}

; ----------------------------------------------------
; Call main.js functions
; ----------------------------------------------------

postWebMessage(target, data := unset) {
    msgObj := { target: target }

    ; If data is provided, add it to the message object
    msgObj.data := IsSet(data) ? data : unset

    jsonStr := jsongo.Stringify(msgObj)
    responseWindow.PostWebMessageAsJSON(jsonStr)
}

; ----------------------------------------------------
; Deletes the files created by the main script
; ----------------------------------------------------

deleteTempFiles() {
    FileDelete(requestParams["chatHistoryJSONRequestFile"])
    FileDelete(requestParams["cURLCommandFile"])
    FileExist(requestParams["cURLOutputFile"]) ? FileDelete(requestParams["cURLOutputFile"]) : ""
    FileDelete(A_Args[1])
}

; ----------------------------------------------------
; Start or stop loading cursor
; ----------------------------------------------------

startLoadingCursor(status) {
    status ? CustomMessages.notifyResponseWindowState(CustomMessages.WM_RESPONSE_WINDOW_LOADING_START,
        requestParams["uniqueID"], , requestParams["mainScriptHiddenhWnd"])
            : CustomMessages.notifyResponseWindowState(CustomMessages.WM_RESPONSE_WINDOW_LOADING_FINISH,
                requestParams["uniqueID"], , requestParams["mainScriptHiddenhWnd"])
}