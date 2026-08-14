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
        if parsed.Has("error") {
            errText := IsObject(parsed["error"]) ? jsongo.Stringify(parsed["error"]) : parsed["error"]
            debugLog("[SEARCH] DeepSeek Responses error for query '" query "': " errText)
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
