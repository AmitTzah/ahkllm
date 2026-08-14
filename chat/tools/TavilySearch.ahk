; ======================================================
; TavilySearch.ahk — Tavily web search backend (fallback for non-DeepSeek
; providers)
;
; Plain REST call to api.tavily.com/search (or the configured
; tavilyEndpoint, which is also the headless-test seam). The response is
; formatted into a compact text block that becomes the tool result the
; model sees. The request file (which embeds the API key) and the output
; files are deleted immediately after the call.
; ======================================================

#Include ..\..\api\SearchTools.ahk
#Include ..\..\shared\DebugLog.ahk

class TavilySearch {

    ; Returns formatted search results (or a failure message the model can
    ; understand — never throws).
    static Run(query, maxResults := 5) {
        key := SearchTools.TavilyKey()
        if !key {
            debugLog("[SEARCH] Tavily API key missing — set TAVILY_API_KEY or Settings -> General -> Tavily API Key")
            return "Web search failed: no Tavily API key configured."
        }

        payload := jsongo.Stringify({
            api_key: key,
            query: query,
            max_results: maxResults,
            search_depth: "basic",
            include_answer: true
        })

        uniqueID := A_TickCount "_" Random(1000, 999999)
        requestFile := A_Temp "\Tavily_Req_" uniqueID ".json"
        outputFile := A_Temp "\Tavily_Out_" uniqueID ".json"
        errorFile := A_Temp "\Tavily_Err_" uniqueID ".txt"
        FileOpen(requestFile, "w", "UTF-8-RAW").Write(payload)

        ; The 2> redirection routes cURL through cmd (same trick the streaming
        ; request path uses), which is required for the local mock servers in
        ; the headless suite to return responses.
        cURLCommand := 'cURL.exe -s --max-time 30 --connect-timeout 15 -X POST '
            . SearchTools.TavilyEndpoint() ' '
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

        TavilySearch._Cleanup(requestFile, outputFile, errorFile)

        if !raw {
            debugLog("[SEARCH] Tavily returned no response for query '" query "'")
            return "Web search failed: no response from the Tavily API."
        }

        try {
            parsed := jsongo.Parse(raw)
        } catch {
            debugLog("[SEARCH] Tavily returned unparseable JSON for query '" query "'")
            return "Web search failed: unparseable Tavily response."
        }
        if parsed.Has("error") {
            debugLog("[SEARCH] Tavily error for query '" query "': " (IsObject(parsed["error"]) ? jsongo.Stringify(parsed["error"]) : parsed["error"]))
            return "Web search failed: Tavily API error."
        }

        return TavilySearch._Format(parsed)
    }

    static _Format(parsed) {
        out := ""
        if parsed.Has("answer") && parsed["answer"] != ""
            out .= "Answer: " parsed["answer"] "`n`n"
        if parsed.Has("results") {
            count := 0
            for r in parsed["results"] {
                if count >= 5
                    break
                if !IsObject(r)
                    continue
                count++
                title := r.Has("title") ? r["title"] : ""
                url := r.Has("url") ? r["url"] : ""
                content := r.Has("content") ? r["content"] : ""
                if StrLen(content) > 600
                    content := SubStr(content, 1, 600) "…"
                out .= count ". " title "`n" url "`n" content "`n`n"
            }
        }
        if out = ""
            return "No results found for the query."
        return RTrim(out, "`n")
    }

    static _Cleanup(requestFile, outputFile, errorFile) {
        try FileDelete(requestFile)
        try FileDelete(outputFile)
        try FileDelete(errorFile)
    }
}
