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
    return 0
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
; Post token usage and cost stats for the current thread
; Computes estimates from DB, sends to WebView
; ----------------------------------------------------

postThreadStats(threadId := "") {
    if !threadId
        return
    stats := ChatDB.Msg_GetThreadStats(threadId)
    postWebMessage("updateTokenUsage", stats)
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

; ----------------------------------------------------
; Generate a thread title from the first user+assistant exchange
; Fire-and-forget: runs asynchronously via SetTimer, never blocks
; ----------------------------------------------------

generateThreadTitle(threadId) {
    if !IsSet(titleGenModel) || !titleGenModel
        return   ; title generation disabled in config
    path := ChatDB.Msg_GetActivePath(threadId)
    if path.Length < 2
        return

    ; Find first user message and first assistant response
    firstUser := ""
    firstAsst := ""
    for msg in path {
        if msg.role = "user" && !firstUser
            firstUser := msg.content
        if msg.role = "assistant" && firstUser && !firstAsst
            firstAsst := msg.content
    }
    if !firstUser || !firstAsst
        return

    ; Build minimal prompt for title generation
    genPrompt := "User: " SubStr(firstUser, 1, 200) "`nAssistant: " SubStr(firstAsst, 1, 200)

    ; Track timing
    titleGenStart := A_TickCount

    ; Build API request
    ; Disable thinking for title generation — we want clean output, not reasoning
    requestObj := { model: titleGenModel, messages: [
        { role: "system", content: titleGenSystemPrompt },
        { role: "user", content: genPrompt }
    ], max_tokens: titleGenMaxTokens, thinking: { type: "disabled" } }

    payload := jsongo.Stringify(requestObj)
    ; Fix jsongo boolean serialization
    payload := StrReplace(payload, '"stream":1', '"stream":true')

    ; Write temp request file
    tmpFile := A_Temp "\ChatWindow_TitleGen_" A_TickCount ".json"
    outFile := A_Temp "\ChatWindow_TitleGen_Out_" A_TickCount ".json"
    FileOpen(tmpFile, "w", "UTF-8-RAW").Write(payload)

    ; Build and run cURL command
    cURLCommand := Format('cURL.exe -s --max-time 15 --connect-timeout 10 -X POST ' APIEndpoint ' -H "Authorization: Bearer ' router.APIKey '" -H "Content-Type: application/json" -d @"' tmpFile '" -o "' outFile '"')
    FileAppend("[DEBUG-TITLE] Running title gen cURL...`n", A_Temp "\LLM_Debug_Log.txt")
    Run(cURLCommand, , "Hide", &cURLPID)
    while ProcessExist(cURLPID)
        Sleep 200
    FileAppend("[DEBUG-TITLE] cURL completed, checking output...`n", A_Temp "\LLM_Debug_Log.txt")

    ; Parse response
    title := ""
    if FileExist(outFile) {
        FileAppend("[DEBUG-TITLE] Output file exists`n", A_Temp "\LLM_Debug_Log.txt")
        raw := FileOpen(outFile, "r", "UTF-8-RAW").Read()
        FileAppend("[DEBUG-TITLE] Raw response (" StrLen(raw) " bytes): " SubStr(raw, 1, 200) "`n", A_Temp "\LLM_Debug_Log.txt")
        try {
            parsed := jsongo.Parse(raw)
            if parsed.Has("choices") && parsed["choices"].Length > 0 {
                title := Trim(parsed["choices"][1]["message"]["content"])
                ; Strip leading/trailing quotes and periods, truncate long titles
                if SubStr(title, 1, 1) = '"' || SubStr(title, 1, 1) = "'"
                    title := SubStr(title, 2)
                lastChar := SubStr(title, StrLen(title))
                if lastChar = '"' || lastChar = "'"
                    title := SubStr(title, 1, StrLen(title) - 1)
                if SubStr(title, -1) = "."
                    title := SubStr(title, 1, StrLen(title) - 1)
                if StrLen(title) > 60
                    title := SubStr(title, 1, 60)
            }
        }
    }

    ; Update DB and refresh sidebar if title was generated
    if title {
        FileAppend("[DEBUG-TITLE] Generated title: '" title "'`n", A_Temp "\LLM_Debug_Log.txt")
        ChatDB.Thread_Update(threadId, title)
        postWebMessage("threadList", ChatDB.Thread_List())
    } else {
        FileAppend("[DEBUG-TITLE] No title generated (empty response or parse failed)`n", A_Temp "\LLM_Debug_Log.txt")
    }

    ; Log the title generation to API logs (transparency)
    ApiLogger.LogRequest({
        timestamp: FormatTime(, "yyyy-MM-dd HH:mm:ss"),
        promptName: "Thread Title Generation",
        provider: "deepseek",
        model: titleGenModel,
        isFIM: false,
        endpoint: APIEndpoint,
        pasteMode: "none",
        request: payload,
        response: raw,
        status: title ? "success" : "failed",
        latencyMs: A_TickCount - titleGenStart
    })

    ; Cleanup temp files
    FileDelete(tmpFile)
    FileExist(outFile) ? FileDelete(outFile) : ""
}
