;--------------------------------------------------
; cURL process management
;--------------------------------------------------

manageState(component, action, data := 0) {
    static cURLPID := 0

    if component = "cURL" {
        switch action {
            case "get": return cURLPID
            case "set": cURLPID := data
            case "close": ProcessClose(cURLPID), cURLPID := 0
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
