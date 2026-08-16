; ======================================================
; DeepSeekSearch.ahk - DeepSeek native web search backend
;
; DeepSeek's server-side web_search tool is only available on the Responses
; API (POST /responses); /chat/completions rejects the non-function tool
; with a 400. This executor sends a STREAMING /responses call so the search
; card can show live progress (search rounds + reasoning + the answer being
; composed), lets DeepSeek's servers run the search, and returns the final
; answer text as the tool result. No Tavily key is needed for DeepSeek.
; ======================================================

#Include ..\..\api\SearchTools.ahk
#Include ..\..\api\ResponsesParser.ahk
#Include ..\..\api\ResponsesStreamParser.ahk
#Include ..\..\api\CurlBuilder.ahk
#Include ..\..\shared\DebugLog.ahk

class DeepSeekSearch {

    ; Returns the answer text (or a failure message - never throws).
    ; onProgress: optional function receiving the live card content
    ; ("[Web search: <query>]\n\n<progress>") as the search streams.
    static Run(query, providerInfo, onProgress := "") {
        global requestParams
        if !providerInfo.apiKey {
            debugLog("[SEARCH] DeepSeek API key missing for native web search")
            return "Web search failed: no DeepSeek API key configured."
        }

        payload := jsongo.Stringify({
            model: providerInfo.modelName,
            input: [{ role: "user", content: [{ type: "input_text", text: query }] }],
            ; Search-heavy models burn output tokens on their internal
            ; search/open_page rounds before writing the answer - 600 left
            ; deepseek-v4-flash truncated ("incomplete: max_output_tokens")
            ; and the final answer never appeared. 4096 lets the search and
            ; the answer both complete.
            max_output_tokens: 4096,
            ; Reasoning is disabled for the SEARCH call: with it enabled,
            ; the model can burn the whole output budget on its internal
            ; search/reason loop and end the response with NO answer message
            ; at all (real-API report 2026-08-16: "Iran war news today"
            ; streamed for 71s, status completed, zero message items).
            ; With effort "none" the same query answers in ~25s while still
            ; performing the web searches. The chat request keeps the user's
            ; thinking setting; only the search backend runs reasoning-free.
            reasoning: { effort: "none" },
            stream: true,
            tools: [{ type: "web_search" }]
        })

        uniqueID := A_TickCount "_" Random(1000, 999999)
        requestFile := A_Temp "\DSearch_Req_" uniqueID ".json"
        outputFile := A_Temp "\DSearch_Out_" uniqueID ".json"
        errorFile := A_Temp "\DSearch_Err_" uniqueID ".txt"
        FileOpen(requestFile, "w", "UTF-8-RAW").Write(payload)

        endpoint := SearchTools.ResponsesEndpoint(providerInfo.endpoint)
        ; 2> redirection routes cURL through cmd so local mock servers in the
        ; headless suite can answer (same pattern as the chat stream path).
        ; -N disables output buffering so the output file grows as events
        ; arrive. Real search-heavy calls routinely take 30-60s, so the
        ; max-time is 120 (the old 60s killed legitimate calls mid-search).
        cURLCommand := 'cURL.exe -sN --max-time 120 --connect-timeout 15 -X POST '
            . endpoint ' '
            . '-H "Authorization: Bearer ' CurlBuilder._SafeApiKey(providerInfo.apiKey) '" '
            . '-H "Content-Type: application/json" '
            . '-d @"' requestFile '" '
            . '-o "' outputFile '" '
            . '2>"' errorFile '"'
        startTime := A_TickCount
        Run(cURLCommand, , "Hide", &cURLPID)
        ; Exposed so handleCancelStream can kill the search cURL when the
        ; user presses Stop mid-search.
        requestParams["_pendingSearchPid"] := cURLPID

        ResponsesStreamParser.Reset()
        state := { reasoning: "", answer: "", finalAnswer: "", searchRounds: 0, failedMsg: "", lastProgressTick: 0 }
        buffer := ""
        lastPos := 0
        f := ""
        while ProcessExist(cURLPID) {
            Sleep 100
            DeepSeekSearch._ReadMore(outputFile, &f, &lastPos, &buffer, state, query, onProgress)
        }
        ; Final drain: cURL can exit right after writing the last bytes.
        DeepSeekSearch._ReadMore(outputFile, &f, &lastPos, &buffer, state, query, onProgress)
        if f
            try f.Close()

        DeepSeekSearch._Cleanup(requestFile, outputFile, errorFile)
        responseTimeMs := A_TickCount - startTime
        if requestParams.Has("_pendingSearchPid")
            requestParams.Delete("_pendingSearchPid")

        if requestParams.Has("_toolLoopCancelled") && requestParams["_toolLoopCancelled"] {
            DeepSeekSearch._LogRequest(query, providerInfo, payload, "Web search cancelled.", "Web search cancelled.", "cancelled", responseTimeMs)
            return "Web search cancelled."
        }
        result := ""
        status := "success"
        if state.failedMsg != "" {
            debugLog("[SEARCH] DeepSeek Responses failed for query '" query "': " state.failedMsg)
            result := "Web search failed: " state.failedMsg
            status := "error"
        } else if state.finalAnswer = "" {
            debugLog("[SEARCH] DeepSeek search returned an empty answer for query '" query "'")
            result := "Web search failed: DeepSeek returned no answer."
            status := "error"
        } else {
            result := state.finalAnswer
        }

        DeepSeekSearch._LogRequest(query, providerInfo, payload, result, result, status, responseTimeMs)
        return result
    }

    ; Read newly-appended bytes from the stream output file and feed complete
    ; SSE lines to the progress builder.
    static _ReadMore(outputFile, &f, &lastPos, &buffer, state, query, onProgress) {
        if !f && FileExist(outputFile)
            f := FileOpen(outputFile, "r", "UTF-8-RAW")
        if !f
            return
        size := f.Length
        if size <= lastPos
            return
        f.Seek(lastPos)
        buffer .= f.Read()
        lastPos := f.Pos
        loop {
            nl := InStr(buffer, "`n")
            if !nl
                break
            line := RTrim(SubStr(buffer, 1, nl - 1), "`r")
            buffer := SubStr(buffer, nl + 1)
            DeepSeekSearch._FeedProgress(line, state, query, onProgress)
        }
    }

    ; Feed one SSE line into the live progress state and (throttled) push the
    ; card content to the UI.
    static _FeedProgress(line, state, query, onProgress) {
        result := ResponsesStreamParser.ParseLine(line)
        if result.type = "reasoning"
            state.reasoning .= result.content
        else if result.type = "answer" {
            state.answer .= result.content
            if result.phase = "final_answer"
                state.finalAnswer .= result.content
        } else if result.type = "search"
            state.searchRounds++
        else if result.type = "failed" && state.failedMsg = ""
            state.failedMsg := result.message

        if onProgress != "" && (result.type = "reasoning" || result.type = "answer" || result.type = "search") {
            body := DeepSeekSearch._ProgressBody(state)
            if body != "" && (state.lastProgressTick = 0 || A_TickCount - state.lastProgressTick >= 250) {
                state.lastProgressTick := A_TickCount
                onProgress(SearchTools.BuildContextText(query, body))
            }
        }
    }

    ; The live card body: search rounds, reasoning, and the answer being
    ; composed - each section appears as it becomes available.
    static _ProgressBody(state) {
        if state.searchRounds = 0 && state.reasoning = "" && state.answer = ""
            return ""
        body := "**Searching...**`n`n"
        if state.searchRounds > 0
            body .= "Searching for related terms (round " state.searchRounds ")...`n`n"
        if state.reasoning != ""
            body .= "**Reasoning...**`n`n" state.reasoning "`n`n"
        if state.answer != ""
            body .= "**Answer...**`n`n" state.answer
        return body
    }

    ; Record the /responses call in the API log so searches are visible in
    ; the API Logs viewer like chat/title requests (logging is best-effort).
    static _LogRequest(query, providerInfo, payload, response, result, status, responseTimeMs) {
        if apiLogMaxEntries <= 0
            return
        try {
            ApiLogger.LogRequest({
                timestamp: FormatTime(, "yyyy-MM-dd HH:mm:ss"),
                commandName: "Web Search (DeepSeek)",
                provider: providerInfo.providerKey,
                model: providerInfo.modelName,
                isFIM: false,
                endpoint: SearchTools.ResponsesEndpoint(providerInfo.endpoint),
                pasteMode: "chat",
                request: payload,
                response: response,
                status: status,
                responseTimeMs: responseTimeMs,
                searchQuery: query,
                searchResult: result
            })
        } catch Error as e {
            debugLog("[SEARCH] API log write failed: " e.Message)
        }
    }

    ; Translate a parsed /responses body into the tool result. Split out of
    ; Run() so unit tests exercise response handling without cURL.
    ;
    ; DeepSeek's /responses envelope ALWAYS carries an "error" key - JSON
    ; null on success (OpenAI Responses API shape). jsongo parses JSON null
    ; as "" (empty string), so a present-but-empty error key means SUCCESS;
    ; only a non-empty error is a real failure. Treating the null key as an
    ; error made every successful search report "Web search failed: " with
    ; no reason (real-API report 2026-08-15).
    static ExtractResult(parsed, query := "") {
        if parsed.Has("error") && parsed["error"] != "" {
            err := parsed["error"]
            ; Prefer the error object's human-readable message (real DeepSeek
            ; failures carry {"message": ...}); fall back to the raw value.
            if IsObject(err) && err.Has("message") && err["message"] != ""
                errText := err["message"]
            else if IsObject(err)
                errText := jsongo.Stringify(err)
            else
                errText := err
            debugLog("[SEARCH] DeepSeek Responses error for query '" query "': " (IsObject(err) ? jsongo.Stringify(err) : err))
            return "Web search failed: " SubStr(errText, 1, 300)
        }

        result := ResponsesParser.Parse(parsed)
        if result.response = "" {
            debugLog("[SEARCH] DeepSeek search returned an empty answer for query '" query "'")
            return "Web search failed: DeepSeek returned no answer."
        }
        return result.response
    }

    static _Cleanup(requestFile, outputFile, errorFile) {
        try FileDelete(requestFile)
        try FileDelete(outputFile)
        try FileDelete(errorFile)
    }
}
