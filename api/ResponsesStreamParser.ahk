; ======================================================
; ResponsesStreamParser.ahk - DeepSeek /responses SSE stream parser
;
; DeepSeek's /responses web_search tool can stream its progress as
; Server-Sent Events. The app renders that progress live in the search card:
;   response.reasoning_text.delta  - the model's internal reasoning
;   response.output_text.delta     - the text it is composing (commentary +
;                                    final answer)
;   response.web_search_call.*     - search rounds in progress
; The message phase ("commentary" vs "final_answer") is only available on the
; response.output_item.added event, so item ids are tracked per stream.
; ======================================================

class ResponsesStreamParser {

    ; item_id -> "commentary" | "final_answer" | "" (per stream).
    static _phases := Map()

    static Reset() {
        this._phases := Map()
    }

    ; Parse a single SSE line. Returns:
    ;   {type:"reasoning", content} | {type:"answer", content, phase} |
    ;   {type:"search"} | {type:"done"} | {type:"failed", message} |
    ;   {type:"ignore"}
    static ParseLine(line) {
        if !InStr(line, "data: ")
            return { type: "ignore" }
        data := SubStr(line, InStr(line, "data: ") + 6)
        if data = "[DONE]"
            return { type: "done" }
        try {
            parsed := jsongo.Parse(data)
        } catch {
            return { type: "ignore" }
        }
        if Type(parsed) != "Map" || !parsed.Has("type")
            return { type: "ignore" }

        t := parsed["type"]
        ; Track message phases so output_text deltas can be attributed to the
        ; final answer vs the model's interim commentary.
        if t = "response.output_item.added" && parsed.Has("item") && IsObject(parsed["item"]) {
            item := parsed["item"]
            if item.Has("type") && item["type"] = "message" && item.Has("id")
                this._phases[item["id"]] := item.Has("phase") ? item["phase"] : ""
        }
        if t = "response.reasoning_text.delta" && parsed.Has("delta")
            return { type: "reasoning", content: parsed["delta"] }
        if t = "response.output_text.delta" && parsed.Has("delta") {
            phase := ""
            if parsed.Has("item_id") && this._phases.Has(parsed["item_id"])
                phase := this._phases[parsed["item_id"]]
            return { type: "answer", content: parsed["delta"], phase: phase }
        }
        if t = "response.web_search_call.searching" || t = "response.web_search_call.in_progress"
            return { type: "search" }
        if t = "response.web_search_call.completed"
            return { type: "search_done" }
        if t = "response.completed"
            return { type: "done" }
        if t = "response.failed" || t = "response.error" {
            message := "the DeepSeek search stream failed"
            if parsed.Has("response") && IsObject(parsed["response"]) && parsed["response"].Has("error") && IsObject(parsed["response"]["error"]) && parsed["response"]["error"].Has("message")
                message := parsed["response"]["error"]["message"]
            return { type: "failed", message: message }
        }
        return { type: "ignore" }
    }
}
