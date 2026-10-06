; Text-protocol orchestration shared by local and HTTP application transports.
class ApplicationTextTools {
    static MAX_TOOL_ROUNDS := 32

    static Enabled(threadId) {
        return ApplicationChat.UsesTextProtocol(threadId)
    }

    static Advance(threadId, text, usage, progress, cancelled) {
        context := ApplicationChat.active[threadId]
        reply := ApplicationTextProtocol.Parse(text, context["tools"])
        context["usage"] := _AccumulateResponsesUsage(context["usage"], usage)
        if reply.kind = "final"
            return {kind: "final", content: reply.content, usage: context["usage"], items: []}
        if context["rounds"] >= this.MAX_TOOL_ROUNDS
            throw Error("Application text protocol exceeded its tool-round limit.")
        results := []
        for call in reply.calls {
            if cancelled.Call()
                throw Error("Application tool request was cancelled.")
            progress.Call("Using " call["name"] "…")
            results.Push(ApplicationChat.Tool(threadId, call))
            progress.Call("Finished " call["name"] ".")
        }
        if cancelled.Call()
            throw Error("Application tool request was cancelled.")
        ApplicationChat.RecordOutput(threadId, reply.calls, results)
        appended := reply.calls.Clone()
        for result in results
            appended.Push(result)
        return {kind: "tool_calls", content: "", usage: context["usage"], items: appended}
    }

    static AppendRequest(request, items) {
        projected := ApplicationTextProtocol.Messages(items)
        if request.Has("messages") {
            for message in projected
                request["messages"].Push(message)
        } else if request.Has("input") {
            for message in projected
                request["input"].Push(ChatGptResponsesTransport._MessageInput(message.role, message.content))
        } else
            throw Error("Application text continuation lost its original request.")
        return LLMRequestBuilder._FixStreamBoolean(ImagePayloadSerializer.Stringify(request))
    }

    static ContinueNonStream(scope, providerInfo, requestStartTime, continuation) {
        if !this.Enabled(scope.threadId)
            return false
        raw := FileRead(scope.params["cURLOutputFile"], "UTF-8")
        response := ResponseParser.ParseChatResponse(jsongo.Parse(raw))
        if response.toolCalls.Length
            throw Error("Text-protocol application models must use the text envelope for functions.")
        context := ApplicationChat.active[scope.threadId]
        if scope.params.Has("_codexReasoningSummary") && scope.params["_codexReasoningSummary"] != ""
            context["activity"] .= scope.params["_codexReasoningSummary"] "`n"
        progress := (text) => this.NonStreamActivity(scope, providerInfo, text)
        reply := this.Advance(scope.threadId, response.response, response.usage, progress, () => scope.cancelled)
        scope.params["_codexReasoningSummary"] := context["activity"]
        if reply.kind = "final" {
            scope.params["_applicationTextFinal"] := reply
            return false
        }
        this.LogNonStreamRound(scope, providerInfo, raw, requestStartTime)
        request := jsongo.Parse(FileRead(scope.params["chatHistoryJSONRequestFile"], "UTF-8"))
        json := this.AppendRequest(request, reply.items)
        FileOpen(scope.params["chatHistoryJSONRequestFile"], "w", "UTF-8-RAW").Write(json)
        for key in ["cURLOutputFile", "cURLErrorFile"]
            if FileExist(scope.params[key])
                FileDelete(scope.params[key])
        SetTimer(continuation, -1)
        return true
    }

    static NonStreamActivity(scope, providerInfo, text) {
        context := ApplicationChat.active[scope.threadId]
        context["activity"] .= text "`n"
        _PostCodexActivity(scope, providerInfo, {content: context["activity"], replace: true, kind: "activity", summary: "Thinking and tools"})
    }

    static LogNonStreamRound(scope, providerInfo, raw, requestStartTime) {
        params := scope.params
        record := {
            threadId: scope.threadId, transport: providerInfo.transport,
            logWindowTitle: params["windowTitle"], logProviderName: params["providerName"],
            logModel: params["singleAPIModelName"], logPasteMode: params["pasteMode"],
            logEndpoint: providerInfo.endpoint != "" ? providerInfo.endpoint : "local:" providerInfo.transport,
            requestStartTime: requestStartTime,
            wireRequestJSON: FileRead(params["chatHistoryJSONRequestFile"], "UTF-8"), rawLastResponse: raw
        }
        _LogCompletedProviderToolRound(record)
    }

    static ContinueStream() {
        stream := _FindStreamByKey(_currentStreamKey)
        if !IsObject(stream)
            throw Error("Application text continuation lost its originating stream.")
        _SaveStreamFromParams(stream)
        if stream.toolCalls.Count || stream.responsesToolCalls.Length
            throw Error("Text-protocol application models must request functions through the text envelope.")
        progress := (text) => _RecordApplicationToolActivity(stream, text)
        reply := this.Advance(stream.threadId, stream.content, stream.usage, progress, () => stream.cancelled)
        if reply.kind = "final" {
            requestParams["_streamContent"] := reply.content
            requestParams["_streamUsage"] := reply.usage
            requestParams["_streamResponseOutput"] := [Map("type", "message", "role", "assistant", "content", [Map("type", "output_text", "text", reply.content)])]
            if _shouldPostStreamToUI()
                postWebMessage("streamContent", reply.content)
            return false
        }
        _LogCompletedProviderToolRound(stream)
        request := jsongo.Parse(FileRead(stream.requestFile, "UTF-8"))
        stream.wireRequestJSON := this.AppendRequest(request, reply.items)
        FileOpen(stream.requestFile, "w", "UTF-8-RAW").Write(stream.wireRequestJSON)
        this.RestartStream(stream, request)
        return true
    }

    static RestartStream(stream, request) {
        for file in [stream.outputFile, stream.errorFile]
            if FileExist(file)
                FileDelete(file)
        stream.lastPos := 0
        stream.pendingLine := ""
        stream.rawLastResponse := ""
        stream.rawSseChunks := ""
        stream.content := ""
        stream.usage := {}
        stream.toolCalls := Map()
        stream.httpCompleted := false
        stream.responseOutput := []
        stream.responsesToolCalls := []
        stream.responsesCompleted := false
        if stream.transport = "chatgpt-responses" {
            stream.responsesPayload := request
            process := ChatGptResponsesTransport.StartStreaming(stream.requestFile, stream.outputFile, stream.errorFile)
            stream.pid := process.pid
            if process.processHandle
                DllCall("CloseHandle", "Ptr", process.processHandle)
        } else {
            command := FileRead(stream.cURLCommandFile, "UTF-8")
            Run(command, , "Hide", &pid)
            stream.pid := pid
        }
        cURLState("set", stream.pid)
        _LoadStreamIntoParams(stream)
    }
}
