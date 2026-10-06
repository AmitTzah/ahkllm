; Response logs show completed Responses objects, never a transcript of token deltas.
class ChatGptResponseLog {
    static Normalize(raw, status := "success", fallbackText := "", fallbackOutput := "") {
        if Type(raw) != "String" || !InStr(raw, '"response.')
            return raw
        ; Embedded SSE diagnostic text inside a JSON string is not an SSE log.
        if !RegExMatch(raw, "m)^\s*data: ") {
            try parsed := jsongo.Parse(raw)
            catch
                return raw
            if !(parsed is Map) || !InStr(parsed.Get("type", ""), "response.")
                return raw
            raw := "data: " raw
        }
        output := [], content := "", reasoning := "", final := "", recognized := false, errorMessage := ""
        for line in StrSplit(raw, Chr(10), Chr(13)) {
            if Trim(line) = ""
                continue
            chunk := ChatGptResponsesStreamParser.ParseLine(line)
            if InStr("|content|reasoning|responses_output_item|finish|error|", "|" chunk.type "|")
                recognized := true
            switch chunk.type {
                case "content": content .= chunk.content
                case "reasoning": reasoning .= chunk.content
                case "responses_output_item":
                    output := ChatGptResponsesStreamParser.MergeOutput(output, [chunk.item])
                case "finish":
                    ChatGptResponsesStreamParser.CompleteOutput(chunk, output)
                    output := chunk.responseOutput
                    final := chunk.rawResponse.Clone()
                case "error":
                    errorMessage := chunk.HasOwnProp("message") ? chunk.message : "Response interrupted."
            }
        }
        if !recognized
            return raw
        if IsObject(fallbackOutput) && fallbackOutput is Array
            output := ChatGptResponsesStreamParser.MergeOutput(output, fallbackOutput)
        if !IsObject(final)
            final := Map("status", status = "success" ? "incomplete" : status, "partial", true)
        if errorMessage != ""
            final["error"] := Map("message", errorMessage)
        final["output"] := output
        text := ChatGptResponsesStreamParser.FinalTextWithCitations(output)
        final["output_text"] := text != "" ? text : content != "" ? content : fallbackText
        if reasoning != "" && !output.Length
            final["reasoning_summary"] := reasoning
        return ChatGptResponsesTransport.Serialize(final)
    }
}
