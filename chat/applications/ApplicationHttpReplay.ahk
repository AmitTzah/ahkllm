; Preserve provider-returned assistant data, separate from UI reasoning/activity.
class ApplicationHttpReplay {
    static Accumulate(state, chunk) {
        if !state.HasOwnProp("transport") || state.transport != "http" || !ApplicationChat.active.Has(requestParams.Get("_streamThreadId", ""))
            || ApplicationChat.UsesTextProtocol(requestParams.Get("_streamThreadId", ""))
            return
        text := chunk.HasOwnProp("messageContent") ? chunk.messageContent : ""
        reasoning := chunk.HasOwnProp("reasoningContent") ? chunk.reasoningContent : ""
        if text = "" && reasoning = ""
            return
        if !state.responseOutput.Length
            state.responseOutput.Push(Map("type", "message", "role", "assistant", "content", [Map("type", "output_text", "text", "")]))
        message := state.responseOutput[state.responseOutput.Length]
        message["content"][1]["text"] .= text
        if reasoning != ""
            message["reasoning_content"] := message.Get("reasoning_content", "") reasoning
    }
}
