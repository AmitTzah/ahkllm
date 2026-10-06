#Requires AutoHotkey v2.0.18+
#SingleInstance Off
#NoTrayIcon
#ErrorStdOut
#Include ..\..\lib\jsongo.v2.ahk

requestText := FileOpen("*", "r", "UTF-8").Read()
request := jsongo.Parse(requestText)
if EnvGet("AHKLLM_E2E_NULLABLE_TOOLS") = "1"
    FileAppend(requestText, A_Temp "\example-native-raw-rpc.jsonl", "UTF-8-RAW")
FileAppend(jsongo.Stringify(request) "`n", A_Temp "\example-protocol-log.jsonl", "UTF-8-RAW")
params := request.Get("params", Map())
state := params.Get("state", Map("checkpoint", 0))
switch request["method"] {
    case "session.describe":
        blocked := state.Get("checkpoint", 0) = 0 && FileExist(A_Temp "\example-context-changed.flag")
        result := Map("state", state, "label", "Example application", "phase", "discussion", "complete", state.Get("complete", false),
            "tools", [Map("type", "function", "name", "echo_text", "description", "Echo supplied text.", "strict", true,
                "parameters", Map("type", "object", "properties", Map("text", Map("type", "string")), "required", ["text"], "additionalProperties", false))],
            "actions", [Map("id", "complete", "label", "Complete example", "confirm", true, "description", "Ends this example. Its saved chat remains readable.", "confirmation_message", "End this example and keep its saved chat readable?")])
        result["can_run"] := true
        if EnvGet("AHKLLM_E2E_NULLABLE_TOOLS") = "1" {
            result["tools"] := [Map("type", "function", "name", "inspect_optional", "strict", true,
                "parameters", Map("type", "object", "properties", Map("path", Map("type", ["string", "null"]), "depth", Map("type", "integer")), "required", ["path", "depth"], "additionalProperties", false)),
                Map("type", "function", "name", "inspect_text", "strict", true,
                "parameters", Map("type", "object", "properties", Map("text", Map("type", "string")), "required", ["text"], "additionalProperties", false))]
        }
        if blocked {
            result["notice"] := "Current context will be reconciled automatically. Existing edits will stay in place."
        }
    case "turn.begin":
        result := Map("turn", "example-turn")
        if state.Get("checkpoint", 0) = 0 && FileExist(A_Temp "\example-context-changed.flag") {
            result["state"] := Map("checkpoint", 10)
            result["message"] := "AUTOMATIC CURRENT CONTEXT: existing edits are preserved."
            result["tools"] := []
            result["phase"] := "reconciled"
        }
    case "tools.call":
        if params.Get("arguments", Map()).Get("text", "") = "NATIVE ADAPTER FAIL" {
            FileAppend(jsongo.Stringify(Map("jsonrpc", "2.0", "id", request["id"], "error", Map("code", -32000, "message", "'str' object has no attribute 'get'"))) "`n", "*", "UTF-8-RAW")
            ExitApp()
        }
        result := Map("result", params.Get("arguments", Map()))
    case "action.perform":
        result := Map("state", Map("checkpoint", state.Get("checkpoint", 0) + 1, "complete", true), "message", "The author selected an example action.")
    case "turn.commit", "session.fork":
        result := Map("state", Map("checkpoint", state.Get("checkpoint", 0) + 1))
    case "turn.accept", "turn.abort", "session.release":
        result := Map("state", state, "released", true)
    default:
        result := params
}
FileAppend(jsongo.Stringify(Map("jsonrpc", "2.0", "id", request["id"], "result", result)) "`n", "*", "UTF-8-RAW")
