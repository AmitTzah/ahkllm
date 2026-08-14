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
    ; ephemeral tool exchange for the next request. Returns the new context
    ; message id ("" when there is no parent thread to attach to).
    static QueueFollowUp(execResult, threadId, parentId, loopCount) {
        global requestParams
        ctxId := ""
        if threadId && parentId && execResult.contextText != "" {
            ctxId := ChatDB.Msg_Insert({
                thread_id: threadId,
                role: "user",
                content: execResult.contextText,
                parent_id: parentId,
                sibling_group: "",
                sibling_index: 0
            })
        }
        requestParams["_pendingToolMessages"] := execResult.toolMessages
        requestParams["_toolLoopCount"] := loopCount
        return ctxId
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
