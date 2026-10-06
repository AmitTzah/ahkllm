#Include ..\applications\ApplicationStreamDiagnostics.ahk

; A successful tool-call response is its own provider request, before continuation.
_LogCompletedProviderToolRound(stream, applicationCalls := "") {
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
    else if IsObject(applicationCalls) {
        messages := ApplicationWire.ChatMessages(applicationCalls)
        entry.response := jsongo.Stringify(Map("model", stream.logModel, "choices", [Map("message", messages[1], "finish_reason", "tool_calls")]))
        parsed := jsongo.Parse(stream.rawLastResponse)
        if parsed is Map && parsed.Has("usage") {
            response := jsongo.Parse(entry.response)
            response["usage"] := parsed["usage"]
            entry.response := jsongo.Stringify(response)
        }
        entry.requestKind := "application tool-call round"
    }
    if IsObject(applicationCalls) || (stream.transport = "chatgpt-responses" && ApplicationChat.active.Has(stream.threadId))
        ApplicationStreamDiagnostics.Attach(entry, stream)
    else if ThreadLockService.ShouldRedactContent(stream.threadId) {
        entry.request := "<hidden: locked chat>"
        entry.response := "<hidden: locked chat>"
    }
    ApiLogger.LogRequest(entry)
}
