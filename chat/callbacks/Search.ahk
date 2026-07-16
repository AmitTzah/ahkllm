; ======================================================
; Search.ahk — Message search callback
;
; Handles searchMessages action from WebView.
; Queries ChatDB.SearchMessages and posts results back.
; ======================================================

handleSearch(params, *) {
    query := params.Has("query") ? params["query"] : ""
    threadId := params.Has("threadId") ? params["threadId"] : ""
    queryId := params.Has("queryId") ? params["queryId"] : 0

    ; Minimum 2 characters required
    if StrLen(query) < 2 {
        postWebMessage("searchResults", { results: [], query: query, threadId: threadId, queryId: queryId })
        return
    }

    try {
        results := ChatDB.SearchMessages(query, threadId)
        postWebMessage("searchResults", { results: results, query: query, threadId: threadId, queryId: queryId })
    } catch Error as e {
        debugLog("[SEARCH] Error: " e.Message, "SearchHandler")
        ; Return empty results on error so UI doesn't hang in "Searching..." state
        postWebMessage("searchResults", { results: [], query: query, threadId: threadId, queryId: queryId })
    }
}
