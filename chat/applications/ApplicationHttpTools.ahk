; Continue the same captured HTTP stream after generic client-side function calls.
_ContinueApplicationHttpTools(stream) {
    _SaveStreamFromParams(stream)
    calls := [], output := []
    for index, call in stream.toolCalls {
        normalized := Map("type", "function_call", "call_id", call.id, "name", call.name, "arguments", call.arguments)
        calls.Push(normalized)
        _RecordApplicationToolActivity(stream, "Using " call.name "…")
        output.Push(ApplicationChat.Tool(stream.threadId, normalized))
        _RecordApplicationToolActivity(stream, "Finished " call.name ".")
    }
    ApplicationChat.RecordOutput(stream.threadId, calls, output)
    _LogCompletedProviderToolRound(stream)
    ; Only append this round's exchange; older rounds are already in the current request.
    appended := []
    for call in calls
        appended.Push(call)
    for item in output
        appended.Push(item)
    original := jsongo.Parse(FileRead(stream.requestFile, "UTF-8"))
    for message in ApplicationWire.ChatMessages(appended)
        original["messages"].Push(message)
    stream.wireRequestJSON := LLMRequestBuilder._FixStreamBoolean(jsongo.Stringify(original))
    FileOpen(stream.requestFile, "w", "UTF-8-RAW").Write(stream.wireRequestJSON)
    for file in [stream.outputFile, stream.errorFile]
        if FileExist(file)
            FileDelete(file)
    stream.lastPos := 0
    stream.pendingLine := ""
    stream.rawLastResponse := ""
    stream.toolCalls := Map()
    command := FileRead(stream.cURLCommandFile, "UTF-8")
    Run(command, , "Hide", &pid)
    stream.pid := pid
    cURLState("set", pid)
    _LoadStreamIntoParams(stream)
}
