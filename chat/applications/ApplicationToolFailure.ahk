; Retain diagnostics before abort/cleanup removes the provider's output file.
_FailApplicationToolRound(stream, detail) {
    _LoadStreamIntoParams(stream)
    _RestoreFailedRetryLeaf()
    message := "Application tool failed: " detail
    response := Map("error", Map("message", message), "application_output", stream.responseOutput)
    if stream.transport = "http" {
        calls := []
        for index, call in stream.toolCalls
            calls.Push(Map("name", call.name, "call_id", call.id, "arguments", call.arguments))
        response["application_tool_calls"] := calls
    }
    entry := {
        timestamp: FormatTime(, "yyyy-MM-dd HH:mm:ss"), commandName: stream.logWindowTitle,
        provider: stream.logProviderName, model: stream.logModel, isFIM: false,
        endpoint: stream.logEndpoint, pasteMode: stream.logPasteMode,
        request: stream.wireRequestJSON, response: jsongo.Stringify(response),
        status: "error", requestKind: "application tool failure",
        responseTimeMs: A_TickCount - stream.requestStartTime
    }
    ApplicationStreamDiagnostics.Attach(entry, stream)
    try ApiLogger.LogRequest(entry)
    try ApplicationChat.Abort(stream.threadId)
    ; Adapter IPC may dispatch another chat's send while we wait for abort.
    _LoadStreamIntoParams(stream)
    _failToolLoop(message, "", "", stream, "APPLICATION")
}
