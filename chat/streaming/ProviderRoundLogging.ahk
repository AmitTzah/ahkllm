; A successful tool-call response is its own provider request, before continuation.
_LogCompletedProviderToolRound(stream) {
    entry := {
        timestamp: FormatTime(, "yyyy-MM-dd HH:mm:ss"),
        commandName: stream.logWindowTitle, provider: stream.logProviderName,
        model: stream.logModel, isFIM: false, endpoint: stream.logEndpoint,
        pasteMode: stream.logPasteMode, request: stream.wireRequestJSON,
        response: stream.rawLastResponse, status: "success",
        responseTimeMs: A_TickCount - stream.requestStartTime, requestKind: "tool-call round"
    }
    if stream.transport = "chatgpt-responses"
        entry.response := ChatGptResponseLog.Normalize(stream.rawLastResponse, "success", "", stream.responseOutput)
    if ThreadLockService.ShouldRedactContent(stream.threadId) {
        entry.request := "<hidden: locked chat>"
        entry.response := "<hidden: locked chat>"
    }
    ApiLogger.LogRequest(entry)
}
