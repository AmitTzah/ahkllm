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
            max_output_tokens: 600,
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
        Run(cURLCommand, , "Hide", &cURLPID)
        while ProcessExist(cURLPID)
            Sleep 100

        raw := ""
        if FileExist(outputFile)
            raw := FileOpen(outputFile, "r", "UTF-8-RAW").Read()

        DeepSeekSearch._Cleanup(requestFile, outputFile, errorFile)

        if !raw {
            debugLog("[SEARCH] DeepSeek Responses returned no response for query '" query "'")
            return "Web search failed: no response from the DeepSeek search API."
        }

        try {
            parsed := jsongo.Parse(raw)
        } catch {
            debugLog("[SEARCH] DeepSeek Responses returned unparseable JSON for query '" query "'")
            return "Web search failed: unparseable DeepSeek search response."
        }
        return DeepSeekSearch.ExtractResult(parsed, query)
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
