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
#Include ..\..\api\LLMRequestBuilder.ahk
#Include ..\..\shared\DebugLog.ahk

class DeepSeekSearch {

    ; Returns the answer text (or a failure message - never throws).
    ; onProgress: optional function receiving the live card content
    ; ("[Web search: <query>]\n\n<progress>") as the search streams.
    static Run(query, providerInfo, onProgress := "", loopState := "") {
        if !providerInfo.apiKey {
            debugLog("[SEARCH] DeepSeek API key missing for native web search")
            return "Web search failed: no DeepSeek API key configured."
        }

        payload := DeepSeekSearch._BuildPayload(query, providerInfo)

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
        SearchTools.RegisterProcess(loopState, cURLPID)

        ResponsesStreamParser.Reset()
        ; items/itemOrder keep per-message text so the final result can be
        ; rebuilt from the AUTHORITATIVE phases (output_item.done): DeepSeek
        ; tags every message "final_answer" at add time and corrects interim
        ; commentary to "commentary" at done time (real capture 2026-08-16).
        state := { reasoning: "", answer: "", items: Map(), itemOrder: [], searchRounds: 0, failedMsg: "", lastProgressTick: 0 }
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
        ; A non-SSE body (e.g. a 400 validation error) never produces stream
        ; events - capture it before the temp files are deleted so the real
        ; API error can surface instead of a misleading "no answer".
        apiError := DeepSeekSearch._ReadApiError(outputFile)

        DeepSeekSearch._Cleanup(requestFile, outputFile, errorFile)
        responseTimeMs := A_TickCount - startTime
        wasCancelled := SearchTools.IsCancelled(loopState)
        SearchTools.ClearProcess(loopState, cURLPID)
        if wasCancelled {
            DeepSeekSearch._LogRequest(query, providerInfo, payload, "Web search cancelled.", "Web search cancelled.", "cancelled", responseTimeMs, loopState)
            return "Web search cancelled."
        }
        result := ""
        status := "success"
        if state.failedMsg != "" {
            debugLog("[SEARCH] DeepSeek Responses failed for query '" query "': " state.failedMsg)
            result := "Web search failed: " state.failedMsg
            status := "error"
        } else {
            state.finalAnswer := DeepSeekSearch._BuildFinalAnswer(state)
            if state.finalAnswer = "" {
                ; A non-SSE body (e.g. a 400 validation error) never produces
                ; stream events - surface the REAL API error instead of the
                ; misleading "no answer" message. This is how the stream:1
                ; rejection ("invalid type: integer `1`, expected a boolean")
                ; was hiding for days (real-API report 2026-08-16 18:48).
                if apiError != "" {
                    debugLog("[SEARCH] DeepSeek Responses API error for query '" query "': " apiError)
                    result := "Web search failed: " apiError
                    status := "error"
                } else {
                    debugLog("[SEARCH] DeepSeek search returned an empty answer for query '" query "'")
                    result := "Web search failed: DeepSeek returned no answer."
                    status := "error"
                }
            } else {
                result := state.finalAnswer
            }
        }

        DeepSeekSearch._LogRequest(query, providerInfo, payload, result, result, status, responseTimeMs, loopState)
        return result
    }

    ; Build the /responses wire payload. jsongo serializes AHK true as JSON 1,
    ; and DeepSeek's /responses API REJECTS "stream":1 with a 400
    ; ("invalid type: integer `1`, expected a boolean") - every search call
    ; failed instantly and was misreported as "no answer" until the payload
    ; carried a real boolean. Reuses the quote-aware chat-path fix.
    static _BuildPayload(query, providerInfo) {
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
        return LLMRequestBuilder._FixStreamBoolean(payload)
    }

    ; Read a plain (non-SSE) JSON error body from the cURL output file - the
    ; shape a 4xx validation failure returns before any SSE event. Returns
    ; the API's human-readable error message ("" when there is none).
    static _ReadApiError(outputFile) {
        if !FileExist(outputFile)
            return ""
        f := FileOpen(outputFile, "r", "UTF-8-RAW")
        if !f
            return ""
        raw := f.Read(8192)
        try f.Close()
        raw := Trim(raw)
        if SubStr(raw, 1, 1) != "{"
            return ""
        try {
            parsed := jsongo.Parse(raw)
        } catch {
            return ""
        }
        if !IsObject(parsed) || !parsed.Has("error") || parsed["error"] = ""
            return ""
        err := parsed["error"]
        if IsObject(err) && err.Has("message") && err["message"] != ""
            return err["message"]
        if IsObject(err)
            return jsongo.Stringify(err)
        return err
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
            ; The live card shows EVERYTHING the model streams (commentary +
            ; final answer) so the user sees exactly what the search is doing.
            state.answer .= result.content
            if result.HasOwnProp("itemId") && result.itemId != "" {
                if !state.items.Has(result.itemId) {
                    state.items[result.itemId] := ""
                    state.itemOrder.Push(result.itemId)
                }
                state.items[result.itemId] .= result.content
            }
        } else if result.type = "search"
            state.searchRounds++
        else if result.type = "failed" && state.failedMsg = ""
            state.failedMsg := result.message

        if onProgress != "" && (result.type = "reasoning" || result.type = "search") {
            body := DeepSeekSearch._ProgressBody(state)
            if body != "" && (state.lastProgressTick = 0 || A_TickCount - state.lastProgressTick >= 250) {
                state.lastProgressTick := A_TickCount
                onProgress(SearchTools.BuildContextText(query, body))
            }
        }
    }

    ; The live card body: search rounds + reasoning only. The final
    ; answer is not streamed into the card - it stays in the assistant
    ; bubble afterwards, so the card shows *what was searched* and *what
    ; was thought*, not a duplicate response (user report 2026-08-16).
    static _ProgressBody(state) {
        if state.searchRounds = 0 && state.reasoning = ""
            return ""
        body := "**Searching...**`n`n"
        if state.searchRounds > 0
            body .= "Searching for related terms (round " state.searchRounds ")...`n`n"
        if state.reasoning != ""
            body .= state.reasoning "`n`n"
        return RTrim(body, "`n")
    }

    ; Rebuild the final answer from the per-item text using the phases the
    ; stream settled on (output_item.done wins over output_item.added):
    ; concatenate every item whose final phase is "final_answer" in stream
    ; order, falling back to the LAST message when no phase markers exist.
    static _BuildFinalAnswer(state) {
        if !state.items.Count
            return ""
        finalText := ""
        lastItemId := ""
        for itemId in state.itemOrder {
            lastItemId := itemId
            if ResponsesStreamParser.PhaseOf(itemId) = "final_answer"
                finalText .= state.items[itemId]
        }
        if finalText = "" && lastItemId != ""
            finalText := state.items[lastItemId]
        return finalText
    }

    ; Record the /responses call in the API log so searches are visible in
    ; the API Logs viewer like chat/title requests (logging is best-effort).
    static _LogRequest(query, providerInfo, payload, response, result, status, responseTimeMs, loopState := "") {
        if apiLogMaxEntries <= 0
            return
        try {
            logEntry := {
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
            }
            threadId := IsObject(loopState) && loopState.HasOwnProp("threadId") ? loopState.threadId : ""
            if ThreadLockService.ShouldRedactContent(threadId) {
                logEntry.request := "<hidden: locked chat>"
                logEntry.response := "<hidden: locked chat>"
                logEntry.searchQuery := "<hidden: locked chat>"
                logEntry.searchResult := "<hidden: locked chat>"
            }
            ApiLogger.LogRequest(logEntry)
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
