; Only provider-supplied summaries and observable tool activity enter chat history.
_AppendPublicStreamActivity(state, text, doPost := false) {
    if text = ""
        return
    addition := (state.reasoning != "" ? "`n" : "") text "`n"
    state.reasoning .= addition
    if doPost
        postWebMessage("streamReasoning", {content:addition,collapsed:true,kind:"activity",persistent:true,summary:"Thinking and tools"})
}

_RecordApplicationToolActivity(stream, text) {
    global _currentStreamKey
    _AppendPublicStreamActivity(stream, text, _shouldPostStreamToUI())
    if _currentStreamKey = stream.key
        requestParams["_streamReasoning"] := stream.reasoning
}
