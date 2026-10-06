; Validate a complete native batch before any application operation can run.
class ApplicationNativeTools {
    static MAX_INVALID_ROUNDS := 3

    static Arguments(call, definition, omitNulls := false) {
        text := call.Get("arguments", "{}")
        if Type(text) != "String"
            throw Error("arguments must be JSON text encoding one object.")
        args := ApplicationArgumentJson.Parse(text)
        if !(args is Map)
            throw Error("arguments must be a JSON object, not a string, array, null, or scalar.")
        if omitNulls
            ApplicationNullableArguments.Restore(args, definition["parameters"])
        ApplicationToolArguments.Validate(args, definition["parameters"])
        return args
    }

    static Feedback(call, message) {
        feedback := Map("ok", ApplicationJsonLiteral("false"), "error", "invalid_tool_arguments", "message", message,
            "instructions", "No application tools in this batch were executed. Correct the arguments to match the advertised schemas and retry the required calls.")
        return Map("type", "function_call_output", "call_id", call["call_id"], "output", ApplicationArgumentJson.Serialize(feedback))
    }

    static RunRound(threadId, calls, progress) {
        context := ApplicationChat.active[threadId]
        prepared := Map(), invalid := Map(), outputs := [], firstInvalid := ""
        for call in calls {
            definition := ApplicationTextProtocol.FindTool(context["tools"], call["name"])
            if call.Get("call_id", "") = "" || prepared.Has(call["call_id"]) || invalid.Has(call["call_id"])
                throw Error("Application tool calls require distinct nonempty call IDs.")
            try prepared[call["call_id"]] := this.Arguments(call, definition, context.Get("omitNullableArguments", false))
            catch Error as e {
                invalid[call["call_id"]] := "Invalid arguments for " call["name"] ": " e.Message
                if firstInvalid = ""
                    firstInvalid := invalid[call["call_id"]]
            }
        }
        if invalid.Count {
            count := context.Get("invalidArgumentRounds", 0) + 1
            context["invalidArgumentRounds"] := count
            if count >= this.MAX_INVALID_ROUNDS
                throw Error("Application tools stopped after " count " invalid argument rounds. " firstInvalid)
            for call in calls {
                message := invalid.Get(call["call_id"], "This batch was not executed because another call had invalid arguments.")
                progress.Call("Rejected " call["name"] "; asking the model to correct its arguments.")
                outputs.Push(this.Feedback(call, message))
            }
            outputs.rejected := true
            return outputs
        }
        context["invalidArgumentRounds"] := 0
        for call in calls {
            progress.Call("Using " call["name"] "…")
            try outputs.Push(ApplicationChat.Tool(threadId, call, prepared[call["call_id"]]))
            catch Error as e
                throw Error("Tool '" call["name"] "' failed: " e.Message)
            progress.Call("Finished " call["name"] ".")
        }
        return outputs
    }
}
