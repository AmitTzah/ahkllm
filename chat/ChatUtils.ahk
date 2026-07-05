; ----------------------------------------------------
; Manage Chat History JSON
; ----------------------------------------------------

manageChatHistoryJSON(action, data := unset) {
    static JSONRequest := ""

    switch action {
        case "get":
            if JSONRequest = "" && requestParams.Has("chatHistoryJSONRequestFile") && FileExist(requestParams["chatHistoryJSONRequestFile"])
                JSONRequest := FileOpen(requestParams["chatHistoryJSONRequestFile"], "r", "UTF-8-RAW").Read()
            return JSONRequest
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
        cURLPID: 0
    }

    switch component {
        case "model":
            switch action {
                case "get": return state.modelHistory
                case "add": state.modelHistory.Push(data)
                case "remove": (state.modelHistory.Length) ? state.modelHistory.Pop() : ""
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
; Post a message to the WebView
; ----------------------------------------------------

postWebMessage(target, data := unset) {
    msgObj := { target: target }

    ; If data is provided, add it to the message object
    msgObj.data := IsSet(data) ? data : unset

    jsonStr := jsongo.Stringify(msgObj)
    responseWindow.PostWebMessageAsJSON(jsonStr)
}

; ----------------------------------------------------
; Delete temp files
; ----------------------------------------------------

deleteTempFiles() {
    FileDelete(requestParams["chatHistoryJSONRequestFile"])
    FileDelete(requestParams["cURLCommandFile"])
    FileExist(requestParams["cURLOutputFile"]) ? FileDelete(requestParams["cURLOutputFile"]) : ""
    FileExist(requestParams["cURLErrorFile"]) ? FileDelete(requestParams["cURLErrorFile"]) : ""
}

; ----------------------------------------------------
; Build structured message array from chat history JSON
; Used to populate the chat UI (initChatMode / appendChatMessage)
; ----------------------------------------------------

buildStructuredMessages(chatHistoryJSONRequest) {
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

    return structuredMessages
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

; ----------------------------------------------------
; Diagnostic logging helper
; Append a timestamped line to %TEMP%\LLM_Debug_Log.txt
; ----------------------------------------------------

debugLog(message) {
    timestamp := FormatTime(, "HH:mm:ss")
    logLine := timestamp " [" requestParams["singleAPIModelName"] "] " message "`n"
    FileAppend(logLine, A_Temp "\LLM_Debug_Log.txt")
}