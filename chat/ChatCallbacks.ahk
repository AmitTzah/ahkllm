; ----------------------------------------------------
; Chat mode: Handle messages sent from the inline chat input
; ----------------------------------------------------

chatSendFromWebView(message, *) {
    ; The message is passed directly as a string from the WebView HostObject call
    if !message {
        return
    }

    debugLog("chatSendFromWebView: message length=" StrLen(message))
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

retryFromWebView(*) {
    ; Delegate to buttonClickAction which has the same logic
    buttonClickAction("Retry")
}

; ----------------------------------------------------
; Button click actions dispatched from the WebView
; ----------------------------------------------------

buttonClickAction(action) {
    debugLog("buttonClickAction: " action)
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