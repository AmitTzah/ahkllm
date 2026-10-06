; Project durable Responses/tool items into OpenAI-compatible chat messages.
class ApplicationWire {
    static ResponsesInput(items) {
        result := []
        for item in items {
            copy := item.Clone()
            ; Chat Completions reasoning is not a valid Responses message field.
            if copy.Has("reasoning_content")
                copy.Delete("reasoning_content")
            result.Push(copy)
        }
        return result
    }
    static InputParts(text, maximumBytes := 750000) {
        if maximumBytes < 4
            throw Error("Input text segment size must allow a complete Unicode character.")
        parts := []
        while text != "" {
            low := 1, high := StrLen(text), chosen := 1
            while low <= high {
                middle := (low + high) // 2
                if StrPut(SubStr(text, 1, middle), "UTF-8") - 1 <= maximumBytes {
                    chosen := middle
                    low := middle + 1
                } else
                    high := middle - 1
            }
            last := Ord(SubStr(text, chosen, 1))
            if last >= 0xD800 && last <= 0xDBFF
                chosen--
            parts.Push(Map("type", "input_text", "text", SubStr(text, 1, chosen)))
            text := SubStr(text, chosen + 1)
        }
        return parts.Length ? parts : [Map("type", "input_text", "text", "")]
    }

    static Text(content) {
        if !IsObject(content)
            return String(content)
        text := ""
        for part in content
            if part.Has("text") && (part.Get("type", "") = "text" || part.Get("type", "") = "input_text" || part.Get("type", "") = "output_text")
                text .= part["text"]
        return text
    }

    static ChatMessages(items, originalMessages := "") {
        messages := []
        if IsObject(originalMessages)
            for message in originalMessages
                if message.role = "system" || message.role = "developer"
                    messages.Push(message)
        for item in items {
            kind := item.Get("type", "")
            if kind = "function_call" {
                last := messages.Length ? messages[messages.Length] : ""
                if !last || last.role != "assistant" {
                    last := {role: "assistant", content: ""}
                    messages.Push(last)
                }
                if !last.HasOwnProp("tool_calls")
                    last.tool_calls := []
                last.tool_calls.Push({id: item["call_id"], type: "function", function: {name: item["name"], arguments: item["arguments"]}})
            } else if kind = "function_call_output" {
                messages.Push({role: "tool", tool_call_id: item["call_id"], content: item["output"]})
            } else if item.Has("role") {
                content := item.Get("content", "")
                parts := [], hasImage := false
                if IsObject(content)
                    for part in content {
                        if part.Get("type", "") = "input_image" {
                            hasImage := true
                            parts.Push(Map("type", "image_url", "image_url", Map("url", part["image_url"])))
                        } else if part.Has("text")
                            parts.Push(Map("type", "text", "text", part["text"]))
                    }
                message := {role: item["role"], content: hasImage ? parts : this.Text(content)}
                if item.Has("reasoning_content")
                    message.reasoning_content := item["reasoning_content"]
                messages.Push(message)
            }
        }
        return messages
    }
}
