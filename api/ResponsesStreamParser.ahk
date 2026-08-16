; ======================================================
; ResponsesStreamParser.ahk - DeepSeek /responses SSE stream parser
;
; DeepSeek's /responses web_search tool can stream its progress as
; Server-Sent Events. The app renders that progress live in the search card:
;   response.reasoning_text.delta  - the model's internal reasoning
;   response.output_text.delta     - the text it is composing (commentary +
;                                    final answer)
;   response.web_search_call.*     - search rounds in progress
; The message phase ("commentary" vs "final_answer") is tagged on
; response.output_item.added, but DeepSeek's backend tags EVERY message item
; "final_answer" at add time and only sets the true phase on
; response.output_item.done (real capture 2026-08-16: interim "Let me search
; ..." texts are corrected to "commentary" at done time, the final answer
; stays "final_answer"). The parser tracks item ids per stream and the DONE
; event's phase WINS, so consumers can attribute output_text deltas
; correctly after the stream finishes.
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
        ; The done event carries the AUTHORITATIVE phase: DeepSeek tags every
        ; message "final_answer" on added and only marks interim commentary
        ; texts correctly on done. Overwrite the add-time guess so the final
        ; result never includes the model's interim narration.
        if t = "response.output_item.done" && parsed.Has("item") && IsObject(parsed["item"]) {
            item := parsed["item"]
            if item.Has("type") && item["type"] = "message" && item.Has("id") && item.Has("phase")
                this._phases[item["id"]] := item["phase"]
        }
        if t = "response.reasoning_text.delta" && parsed.Has("delta")
            return { type: "reasoning", content: parsed["delta"] }
        if t = "response.output_text.delta" && parsed.Has("delta") {
            phase := ""
            itemId := parsed.Has("item_id") ? parsed["item_id"] : ""
            if itemId != "" && this._phases.Has(itemId)
                phase := this._phases[itemId]
            return { type: "answer", content: parsed["delta"], phase: phase, itemId: itemId }
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

    ; The phase recorded for a message item AFTER the stream's done events
    ; have been processed ("" when unknown).
    static PhaseOf(itemId) {
        return this._phases.Has(itemId) ? this._phases[itemId] : ""
    }
}
