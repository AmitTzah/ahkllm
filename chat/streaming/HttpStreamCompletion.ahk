; A process exiting is not evidence that an SSE response completed normally.
class HttpStreamCompletion {
    static Observe(state, chunk) {
        if !state.HasOwnProp("transport") || state.transport != "http"
            return
        reason := chunk.HasOwnProp("reason") ? chunk.reason : ""
        if chunk.type = "done" || (reason != "" && reason != "null")
            state.httpCompleted := true
    }
    static ErrorFromParams(params) {
        if params.Get("_streamTransport", "http") != "http" || params.Get("_streamHttpCompleted", false) || params.Get("_streamOutputAlreadyParsed", false)
            return ""
        errorFile := params.Get("cURLErrorFile", "")
        detail := ""
        providerError := _extractErrorMsg(params.Get("_streamRawLastResponse", ""))
        outputFile := params.Get("_streamOutputFile", "")
        if providerError = "" && outputFile != "" && FileExist(outputFile)
            providerError := _extractErrorMsg(FileRead(outputFile, "UTF-8"))
        if providerError != ""
            return providerError
        if errorFile != "" && FileExist(errorFile)
            detail := Trim(FileRead(errorFile, "UTF-8"))
        return detail != "" ? "The response stream failed before completion: " SubStr(detail, 1, 1200)
            : "The response stream ended before completion. The partial output is not a completed answer."
    }
}
