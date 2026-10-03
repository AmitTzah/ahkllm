#Include ExternalApplications.ahk
#Include ApplicationWire.ahk

; Inference ownership and wire history are kept separate from the application's opaque state.
class ApplicationChat {
    static active := Map()

    static Prepare(threadId, path, providerInfo, requestObj, preparedInput := "") {
        if !ApplicationRepo.Session(threadId)
            return
        if providerInfo.transport != "chatgpt-responses" && providerInfo.transport != "http"
            throw Error("This provider does not support application function tools. Select a Responses or OpenAI-compatible HTTP model.")
        if this.active.Has(threadId)
            throw Error("This application's previous turn is still running.")
        state := ApplicationRepo.State(threadId, path)
        description := ExternalApplications.Call(threadId, "session.describe", state)
        if description.Get("complete", false)
            throw Error("This application task is complete. Fork an earlier message to continue.")
        started := ExternalApplications.Call(threadId, "turn.begin", state)
        state := started.Get("state", state)
        externalTools := started.Get("tools", description["tools"])
        preamble := started.Get("message", "")
        output := []
        this.active[threadId] := Map("state", state, "turn", started["turn"], "parent", path[path.Length].id, "output", output, "rounds", 0, "label", description.Get("label", "Application"), "phase", started.Get("phase", description.Get("phase", "")))
        requestObj.external_tools := externalTools
        requestObj.external_input := IsObject(preparedInput) ? preparedInput : ApplicationRepo.Replay(path)
        if preamble != "" {
            input := Map("role", "user", "content", ApplicationWire.InputParts(preamble))
            requestObj.external_input.Push(input)
            output.Push(input)
        }
        if providerInfo.transport = "http" {
            requestObj.messages := ApplicationWire.ChatMessages(requestObj.external_input, requestObj.messages)
            tools := requestObj.HasOwnProp("tools") ? requestObj.tools : []
            for definition in externalTools {
                fn := definition.Clone()
                fn.Delete("type")
                tools.Push(Map("type", "function", "function", fn))
            }
            if tools.Length
                requestObj.tools := tools
            requestObj.DeleteProp("external_input")
            requestObj.DeleteProp("external_tools")
        }
    }

    static Tool(threadId, call) {
        if !this.active.Has(threadId)
            throw Error("No active external application turn owns this tool call.")
        context := this.active[threadId]
        args := jsongo.Parse(call.Get("arguments", "{}"))
        result := ExternalApplications.Call(threadId, "tools.call", context["state"], Map("turn", context["turn"], "name", call["name"], "arguments", args))
        return Map("type", "function_call_output", "call_id", call["call_id"], "output", jsongo.Stringify(result["result"]))
    }

    static RecordOutput(threadId, output, results := "") {
        if !this.active.Has(threadId)
            return
        context := this.active[threadId]
        for item in output
            context["output"].Push(item)
        if IsObject(results)
            for item in results
                context["output"].Push(item)
        context["rounds"]++
        if context["rounds"] > 64
            throw Error("External application exceeded the tool-round limit.")
    }

    static StageCompletion(threadId, parentId, responseOutput) {
        if !this.active.Has(threadId)
            return ""
        context := this.active[threadId]
        if context["parent"] != parentId
            throw Error("External application completion belongs to a different branch.")
        this.RecordOutput(threadId, responseOutput)
        committed := ExternalApplications.Call(threadId, "turn.commit", context["state"], Map("turn", context["turn"]))
        context["committed_state"] := committed["state"]
        return Map("state", committed["state"], "replay", context["output"])
    }

    static Accepted(threadId) {
        if !this.active.Has(threadId)
            return
        context := this.active[threadId]
        this.active.Delete(threadId)
        ; A lost acceptance acknowledgement is reconciled by session.describe using the durable checkpoint.
        try ExternalApplications.Call(threadId, "turn.accept", context["committed_state"], Map("turn", context["turn"]))
    }

    static Abort(threadId) {
        if !this.active.Has(threadId)
            return
        context := this.active[threadId]
        this.active.Delete(threadId)
        ExternalApplications.Call(threadId, "turn.abort", context["state"], Map("turn", context["turn"]))
    }
}
