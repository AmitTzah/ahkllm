; ======================================================
; SearchToolExecutor.ahk — runs the model's web_search tool calls
;
; The tool loop (streaming or single-shot) hands this module the accumulated
; tool_calls from the model. It:
;   1. picks the backend (DeepSeek native /responses for the deepseek
;      provider, Tavily otherwise),
;   2. builds the assistant tool_calls message + role:"tool" results the next
;      API request must contain,
;   3. produces the human-readable search context text persisted as a plain
;      user-role message so follow-up turns keep the results in history.
; ======================================================

#Include TavilySearch.ahk
#Include DeepSeekSearch.ahk

class SearchToolExecutor {

    ; toolCalls: array of {id, name, arguments} from the stream/response.
    ; providerInfo: ProviderResolver.Resolve(...) output.
    ; testRunner: optional function-object seam for unit tests (returns the
    ; search answer for a query instead of hitting a real backend).
    ; Returns { toolMessages, contextText }.
    static Execute(toolCalls, providerInfo, testRunner := "") {
        native := SearchTools.IsNativeDeepSeek(providerInfo.providerKey)
        toolMessages := []
        assistantMsg := { role: "assistant", content: "", tool_calls: [] }
        contextParts := []

        ; toolCalls is a Map keyed by call index — AHK v2 `for x in Map`
        ; iterates KEYS, so use the two-variable form to get the values.
        for idx, tc in toolCalls {
            id := tc.HasOwnProp("id") ? tc.id : ""
            name := tc.HasOwnProp("name") ? tc.name : ""
            argsText := tc.HasOwnProp("arguments") ? tc.arguments : ""
            assistantMsg.tool_calls.Push({
                id: id,
                type: "function",
                function: { name: name, arguments: argsText }
            })

            resultText := ""
            if name = "web_search" {
                query := ""
                try {
                    args := jsongo.Parse(argsText)
                    if IsObject(args) && args.Has("query")
                        query := args["query"]
                } catch {
                    query := ""
                }
                if query = "" {
                    resultText := "Web search failed: missing query argument."
                } else if testRunner != "" {
                    resultText := testRunner(query)
                } else if native {
                    resultText := DeepSeekSearch.Run(query, providerInfo)
                } else {
                    resultText := TavilySearch.Run(query)
                }
                contextParts.Push(SearchTools.BuildContextText(query, resultText))
            } else {
                resultText := "Tool '" name "' is not available. Only web_search is supported."
            }
            toolMessages.Push({ role: "tool", tool_call_id: id, content: resultText })
        }

        toolMessages.InsertAt(1, assistantMsg)
        return {
            toolMessages: toolMessages,
            contextText: contextParts.Length ? RTrim(SearchToolExecutor._Join(contextParts, "`n`n"), "`n") : ""
        }
    }

    ; Persist the search context as a user-role message and stage the
    ; ephemeral tool exchange for the next request. When a "Searching…"
    ; placeholder was staged via PrepareFollowUp, the placeholder row is
    ; EDITED to the real result instead of inserting a second message, so
    ; each round produces exactly one card that updates in place. Returns the
    ; context message id ("" when there is no parent thread to attach to).
    static QueueFollowUp(execResult, threadId, parentId, loopCount) {
        global requestParams
        ctxId := ""
        if requestParams.Has("_pendingSearchPlaceholderId") && requestParams["_pendingSearchPlaceholderId"] != "" {
            ctxId := requestParams["_pendingSearchPlaceholderId"]
            try ChatDB.Msg_Edit(ctxId, execResult.contextText)
            requestParams.Delete("_pendingSearchPlaceholderId")
            requestParams.Delete("_pendingSearchPlaceholderQuery")
        } else if threadId && parentId && execResult.contextText != "" {
            ctxId := ChatDB.Msg_Insert({
                thread_id: threadId,
                role: "user",
                content: execResult.contextText,
                parent_id: parentId,
                sibling_group: "",
                sibling_index: 0
            })
            ; Track the inserted context message so THIS round's follow-up
            ; request can exclude it from the history (canonical
            ; function-calling order: assistant tool_calls -> role:"tool"
            ; carry the results; the context re-enters history for later
            ; requests once the tool loop clears the staged state).
            if ctxId != "" {
                if !requestParams.Has("_pendingSearchContextIds")
                    requestParams["_pendingSearchContextIds"] := []
                requestParams["_pendingSearchContextIds"].Push(ctxId)
            }
        }
        requestParams["_pendingToolMessages"] := execResult.toolMessages
        requestParams["_toolLoopCount"] := loopCount
        return ctxId
    }

    ; Create the durable search-context message as an IMMEDIATE "Searching…"
    ; placeholder (persisted + posted to the UI) so the user sees what the AI
    ; is searching for while the backend runs. QueueFollowUp edits this row to
    ; the real result afterwards. Returns the placeholder message id.
    static PrepareFollowUp(toolCalls, threadId, parentId) {
        global requestParams
        ctxId := ""
        query := SearchToolExecutor.FirstQuery(toolCalls)
        if threadId && parentId && query != "" {
            ctxId := ChatDB.Msg_Insert({
                thread_id: threadId,
                role: "user",
                content: SearchTools.BuildContextText(query, "Searching…"),
                parent_id: parentId,
                sibling_group: "",
                sibling_index: 0
            })
            if ctxId != "" {
                if !requestParams.Has("_pendingSearchContextIds")
                    requestParams["_pendingSearchContextIds"] := []
                requestParams["_pendingSearchContextIds"].Push(ctxId)
                requestParams["_pendingSearchPlaceholderId"] := ctxId
                requestParams["_pendingSearchPlaceholderQuery"] := query
            }
        }
        return ctxId
    }

    ; The placeholder text the UI shows while the backend runs.
    static PlaceholderContent(toolCalls) {
        return SearchTools.BuildContextText(SearchToolExecutor.FirstQuery(toolCalls), "Searching…")
    }

    ; The query of the first web_search tool call (used for the placeholder).
    static FirstQuery(toolCalls) {
        for idx, tc in toolCalls {
            if tc.HasOwnProp("name") && tc.name = "web_search" {
                try {
                    args := jsongo.Parse(tc.HasOwnProp("arguments") ? tc.arguments : "")
                    if IsObject(args) && args.Has("query")
                        return args["query"]
                }
            }
        }
        return ""
    }

    static MaxIterationsReached(loopCount) {
        return loopCount > SearchTools.MAX_TOOL_ITERATIONS
    }

    ; AHK v2 has no native array join.
    static _Join(arr, sep) {
        out := ""
        for item in arr
            out .= (out = "" ? "" : sep) item
        return out
    }
}
