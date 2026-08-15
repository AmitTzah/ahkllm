; ======================================================
; DeepSeekSearch.ahk — DeepSeek native web search backend
;
; DeepSeek's server-side web_search tool is only available on the Responses
; API (POST /responses); /chat/completions rejects the non-function tool
; with a 400. This executor sends a single non-streaming /responses call
; with the query, lets DeepSeek's servers run the search, and returns the
; answer text as the tool result. No Tavily key is needed for DeepSeek.
; ======================================================

#Include ..\..\api\SearchTools.ahk
#Include ..\..\api\ResponsesParser.ahk
#Include ..\..\api\CurlBuilder.ahk
#Include ..\..\shared\DebugLog.ahk

class DeepSeekSearch {

    ; Returns the answer text (or a failure message — never throws).
    static Run(query, providerInfo) {
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
        cURLCommand := 'cURL.exe -s --max-time 60 --connect-timeout 15 -X POST '
            . endpoint ' '
            . '-H "Authorization: Bearer ' CurlBuilder._SafeApiKey(providerInfo.apiKey) '" '
            . '-H "Content-Type: application/json" '
            . '-d @"' requestFile '" '
            . '-o "' outputFile '" '
            . '2>"' errorFile '"'
        startTime := A_TickCount
        Run(cURLCommand, , "Hide", &cURLPID)
        while ProcessExist(cURLPID)
            Sleep 100
        responseTimeMs := A_TickCount - startTime

        raw := ""
        if FileExist(outputFile)
            raw := FileOpen(outputFile, "r", "UTF-8-RAW").Read()

        DeepSeekSearch._Cleanup(requestFile, outputFile, errorFile)

        result := ""
        status := "success"
        if !raw {
            debugLog("[SEARCH] DeepSeek Responses returned no response for query '" query "'")
            result := "Web search failed: no response from the DeepSeek search API."
            status := "error"
        } else {
            try {
                parsed := jsongo.Parse(raw)
                result := DeepSeekSearch.ExtractResult(parsed, query)
            } catch {
                debugLog("[SEARCH] DeepSeek Responses returned unparseable JSON for query '" query "'")
                result := "Web search failed: unparseable DeepSeek search response."
                status := "error"
            }
        }
        if InStr(result, "Web search failed")
            status := "error"

        DeepSeekSearch._LogRequest(query, providerInfo, payload, raw, result, status, responseTimeMs)
        return result
    }

    ; Record the /responses call in the API log so searches are visible in
    ; the API Logs viewer like chat/title requests (logging is best-effort).
    static _LogRequest(query, providerInfo, payload, raw, result, status, responseTimeMs) {
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
                response: raw,
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
