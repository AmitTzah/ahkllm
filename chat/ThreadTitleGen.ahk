; ----------------------------------------------------
; ThreadTitleGen — Fire-and-forget title generation
;
; Generates a short thread title from the first
; user+assistant exchange using a cheap LLM call.
; Delegates request building to LLMRequestBuilder
; and cURL execution to CurlBuilder.
; ----------------------------------------------------

generateThreadTitle(threadId) {
    if !autoTitleGenerationEnabled || !IsSet(titleGenModel) || !titleGenModel
        return

    prompt := _TitleGen_BuildPrompt(threadId)
    if !prompt
        return

    titleGenStart := A_TickCount
    providerInfo := ProviderResolver.Resolve(titleGenModel)

    payload := LLMRequestBuilder.createJSONRequest(
        titleGenModel,
        titleGenSystemPrompt,
        prompt,
        "",                    ; temperature
        titleGenMaxTokens,     ; maxTokens
        "",                    ; stop
        false,                 ; stream
        "disabled"             ; reasoningEffort — explicitly disable thinking
    )

    raw := _TitleGen_ExecuteRequest(payload, providerInfo)
    result := _TitleGen_ParseResponse(raw)
    title := result.title
    promptTokens := result.promptTokens
    completionTokens := result.completionTokens
    thinkingTokens := result.thinkingTokens

    debugLog("[API] Title gen — prompt=" promptTokens " completion=" completionTokens " model=" titleGenModel)

    _TitleGen_TrackUsage(titleGenModel, providerInfo.providerKey, promptTokens, completionTokens, thinkingTokens, titleGenStart)

    if title {
        ChatDB.Thread_Update(threadId, title)
        postWebMessage("threadList", ChatDB.Thread_List())
        postWebMessage("updateTopbarTitle", { text: title, folder: "Unfiled" })
    }

    _TitleGen_LogRequest(titleGenModel, providerInfo.providerKey, providerInfo.endpoint, payload, raw, title, titleGenStart)
}

; Build the prompt from the first user+assistant exchange.
_TitleGen_BuildPrompt(threadId) {
    path := ChatDB.Msg_GetActivePath(threadId)
    if path.Length < 2
        return ""
    firstUser := "", firstAsst := ""
    for msg in path {
        if msg.role = "user" && !firstUser
            firstUser := msg.content
        if msg.role = "assistant" && firstUser && !firstAsst
            firstAsst := msg.content
    }
    if !firstUser || !firstAsst
        return ""
    return "User: " SubStr(firstUser, 1, 200) "`nAssistant: " SubStr(firstAsst, 1, 200)
}

; Execute the title generation cURL request using CurlBuilder.
_TitleGen_ExecuteRequest(payload, providerInfo) {
    tmpFile := A_Temp "\ChatWindow_TitleGen_" A_TickCount ".json"
    outFile := A_Temp "\ChatWindow_TitleGen_Out_" A_TickCount ".json"
    FileOpen(tmpFile, "w", "UTF-8-RAW").Write(payload)

    cURLCommand := CurlBuilder.Build(providerInfo, tmpFile, outFile)
    Run(cURLCommand, , "Hide", &cURLPID)
    while ProcessExist(cURLPID)
        Sleep 200

    raw := ""
    if FileExist(outFile)
        raw := FileOpen(outFile, "r", "UTF-8-RAW").Read()

    safeDelete(tmpFile)
    safeDelete(outFile)
    return raw
}

; Parse the title and token usage from the raw JSON response.
_TitleGen_ParseResponse(raw) {
    title := "", promptTokens := 0, completionTokens := 0, thinkingTokens := 0
    if !raw
        return { title: title, promptTokens: promptTokens, completionTokens: completionTokens, thinkingTokens: thinkingTokens }

    try {
        parsed := jsongo.Parse(raw)
        if parsed.Has("usage") {
            u := parsed["usage"]
            promptTokens := u.Has("prompt_tokens") ? u["prompt_tokens"] : 0
            completionTokens := u.Has("completion_tokens") ? u["completion_tokens"] : 0
            if u.Has("completion_tokens_details") {
                d := u["completion_tokens_details"]
                if d.Has("reasoning_tokens")
                    thinkingTokens := d["reasoning_tokens"]
            }
        }
        if parsed.Has("choices") && parsed["choices"].Length > 0 {
            title := _TitleGen_CleanTitle(Trim(parsed["choices"][1]["message"]["content"]))
        }
    }
    return { title: title, promptTokens: promptTokens, completionTokens: completionTokens, thinkingTokens: thinkingTokens }
}

; Clean up the raw title: strip quotes, trailing period, truncate to 60 chars.
_TitleGen_CleanTitle(rawTitle) {
    if SubStr(rawTitle, 1, 1) = '"' || SubStr(rawTitle, 1, 1) = "'"
        rawTitle := SubStr(rawTitle, 2)
    lastChar := SubStr(rawTitle, StrLen(rawTitle))
    if lastChar = '"' || lastChar = "'"
        rawTitle := SubStr(rawTitle, 1, StrLen(rawTitle) - 1)
    if SubStr(rawTitle, -1) = "."
        rawTitle := SubStr(rawTitle, 1, StrLen(rawTitle) - 1)
    if StrLen(rawTitle) > 60
        rawTitle := SubStr(rawTitle, 1, 60)
    return rawTitle
}

; Track title generation usage in the dashboard.
_TitleGen_TrackUsage(titleModel, providerKey, promptTokens, completionTokens, thinkingTokens, titleGenStart) {
    if promptTokens <= 0
        return
    usage := { promptTokens: promptTokens, completionTokens: completionTokens, cachedTokens: 0 }
    costs := CostCalculator.ComputeTokenCosts(titleModel, usage)
    ChatDB.CommandUsage_Upsert({
        date: FormatTime(, "yyyy-MM-dd"),
        model: titleModel,
        provider: providerKey,
        command_name: "Title Generation",
        prompt_tokens: promptTokens,
        completion_tokens: completionTokens,
        thinking_tokens: thinkingTokens,
        cached_tokens: 0,
        input_cost: costs.inputCost != "" ? costs.inputCost : 0,
        cached_input_cost: costs.cachedInputCost != "" ? costs.cachedInputCost : 0,
        output_cost: costs.outputCost != "" ? costs.outputCost : 0,
        total_cost: costs.totalCost != "" ? costs.totalCost : 0,
        response_time_ms: A_TickCount - titleGenStart
    })
}

; Log the title generation API request.
_TitleGen_LogRequest(titleModel, providerKey, endpoint, payload, raw, title, titleGenStart) {
    ApiLogger.LogRequest({
        timestamp: FormatTime(, "yyyy-MM-dd HH:mm:ss"),
        commandName: "Thread Title Generation",
        provider: providerKey, model: titleModel, isFIM: false,
        endpoint: endpoint, pasteMode: "none",
        request: payload, response: raw,
        status: title ? "success" : "failed",
        responseTimeMs: A_TickCount - titleGenStart
    })
}
