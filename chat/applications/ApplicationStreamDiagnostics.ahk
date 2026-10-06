; Retain the unparsed current-round provider response before cleanup.
class ApplicationStreamDiagnostics {
    static Attach(entry, stream) {
        if ThreadLockService.ShouldRedactContent(stream.threadId) {
            entry.request := "<hidden: locked chat>"
            entry.response := "<hidden: locked chat>"
            return
        }
        capture := Map("transport", stream.transport, "source", "provider stdout before SSE parsing", "raw_response", "")
        try capture["raw_response"] := FileRead(stream.outputFile, "UTF-8-RAW")
        catch Error as e
            capture["capture_error"] := "Provider response capture unavailable: " e.Message
        response := jsongo.Parse(entry.response)
        if !(response is Map)
            response := Map("assembled_response", entry.response)
        response["_ahkllm_stream_diagnostics"] := capture
        entry.response := jsongo.Stringify(response)
    }
}
