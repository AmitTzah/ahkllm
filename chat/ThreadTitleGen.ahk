; ----------------------------------------------------
; ThreadTitleGen — Fire-and-forget title generation
;
; Generates a short thread title from the first
; user+assistant exchange using a cheap LLM call.
; Extracted from ChatUtils.ahk.
; ----------------------------------------------------

generateThreadTitle(threadId) {
    if !IsSet(titleGenModel) || !titleGenModel
        return
    path := ChatDB.Msg_GetActivePath(threadId)
    if path.Length < 2
        return

    firstUser := "", firstAsst := ""
    for msg in path {
        if msg.role = "user" && !firstUser
            firstUser := msg.content
        if msg.role = "assistant" && firstUser && !firstAsst
            firstAsst := msg.content
    }
    if !firstUser || !firstAsst
        return

    genPrompt := "User: " SubStr(firstUser, 1, 200) "`nAssistant: " SubStr(firstAsst, 1, 200)
    titleGenStart := A_TickCount
    titleModel := ModelParser.StripProvider(titleGenModel)

    requestObj := { model: titleModel, messages: [
        { role: "system", content: titleGenSystemPrompt },
        { role: "user", content: genPrompt }
    ], max_tokens: titleGenMaxTokens, thinking: { type: "disabled" } }

    payload := jsongo.Stringify(requestObj)
    payload := StrReplace(payload, '"stream":1', '"stream":true')

    tmpFile := A_Temp "\ChatWindow_TitleGen_" A_TickCount ".json"
    outFile := A_Temp "\ChatWindow_TitleGen_Out_" A_TickCount ".json"
    FileOpen(tmpFile, "w", "UTF-8-RAW").Write(payload)

    cURLCommand := Format('cURL.exe -s --max-time 15 --connect-timeout 10 -X POST ' APIEndpoint ' -H "Authorization: Bearer ' llmClient.APIKey '" -H "Content-Type: application/json" -d @"' tmpFile '" -o "' outFile '"')
    Run(cURLCommand, , "Hide", &cURLPID)
    while ProcessExist(cURLPID)
        Sleep 200

    title := ""
    if FileExist(outFile) {
        raw := FileOpen(outFile, "r", "UTF-8-RAW").Read()
        try {
            parsed := jsongo.Parse(raw)
            if parsed.Has("choices") && parsed["choices"].Length > 0 {
                title := Trim(parsed["choices"][1]["message"]["content"])
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

    if title {
        ChatDB.Thread_Update(threadId, title)
        postWebMessage("threadList", ChatDB.Thread_List())
    }

    ApiLogger.LogRequest({
        timestamp: FormatTime(, "yyyy-MM-dd HH:mm:ss"),
        commandName: "Thread Title Generation",
        provider: "deepseek", model: titleGenModel, isFIM: false,
        endpoint: APIEndpoint, pasteMode: "none",
        request: payload, response: raw,
        status: title ? "success" : "failed",
        latencyMs: A_TickCount - titleGenStart
    })

    FileDelete(tmpFile)
    safeDelete(outFile)
}
