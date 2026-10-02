; ======================================================
; ChatGptResponsesTransport.ahk — direct ChatGPT-plan Responses transport
;
; AhkLLM owns conversation state. Each request sends the selected history as
; Responses input with store=false and stream=true. OAuth bearer credentials
; are supplied to curl through an inherited stdin config, never argv or disk.
; ======================================================

#Include ImagePayloadSerializer.ahk

class ChatGptResponsesTransport {
    static DEFAULT_RESPONSES_ENDPOINT := "https://api.openai.com/v1/responses"

    static ResolveEndpoint() {
        if EnvGet("AHKLLM_E2E_WORKER") != "" && EnvGet("AHKLLM_E2E_DATA_DIR") != "" {
            value := EnvGet("AHKLLM_E2E_CHATGPT_RESPONSES_ENDPOINT")
            if RegExMatch(value, "i)^http://127\.0\.0\.1:\d+/v1/responses$")
                return value
        }
        return ChatGptResponsesTransport.DEFAULT_RESPONSES_ENDPOINT
    }

    static PrepareRequestFile(requestFile, webSearch := false, imageGeneration := false) {
        requestObj := jsongo.Parse(FileRead(requestFile, "UTF-8"))
        payload := ChatGptResponsesTransport.BuildPayload(requestObj, webSearch, imageGeneration)
        json := ChatGptResponsesTransport.Serialize(payload)
        FileOpen(requestFile, "w", "UTF-8-RAW").Write(json)
        return { payload: payload, json: json }
    }

    static BuildPayload(requestObj, webSearch := false, imageGeneration := false) {
        if !IsObject(requestObj) || !requestObj.Has("messages") || !(requestObj["messages"] is Array)
            throw Error("ChatGPT-plan Responses requires a messages array.")

        instructions := []
        input := []
        for msg in requestObj["messages"] {
            if !IsObject(msg) || !msg.Has("role")
                continue
            role := String(msg["role"])
            if role = "system" || role = "developer" {
                text := ChatGptResponsesTransport._ContentText(msg.Has("content") ? msg["content"] : "")
                if text != ""
                    instructions.Push(text)
                continue
            }
            if role != "user" && role != "assistant"
                throw Error("ChatGPT-plan Responses cannot replay role '" role "' in normal chat history.")
            input.Push(ChatGptResponsesTransport._MessageInput(role, msg.Has("content") ? msg["content"] : ""))
        }

        if !input.Length
            throw Error("ChatGPT-plan Responses request has no user/assistant input.")

        payload := Map(
            "model", requestObj.Has("model") ? requestObj["model"] : "",
            "input", input,
            "store", false,
            "stream", true,
            "parallel_tool_calls", false
        )
        if payload["model"] = ""
            throw Error("ChatGPT-plan Responses request has no model.")

        instructionText := CodexCliRuntime.Join(instructions, Chr(10) Chr(10))
        if imageGeneration {
            imageInstruction := "AhkLLM Image Generation is enabled. When the user asks to create, generate, render, redraw, or edit an image, call the ahkllm.generate_image function with a self-contained image prompt that resolves relevant conversation context. Do not claim the image-generation capability is unavailable."
            instructionText .= (instructionText = "" ? "" : Chr(10) Chr(10)) imageInstruction
        }
        if instructionText != ""
            payload["instructions"] := instructionText

        if requestObj.Has("reasoning_effort") && requestObj["reasoning_effort"] != ""
            payload["reasoning"] := Map("effort", requestObj["reasoning_effort"], "summary", "auto")

        tools := []
        if webSearch
            tools.Push(Map("type", "web_search"))
        if imageGeneration
            tools.Push(ChatGptResponsesTransport.ImageNamespaceTool())
        if tools.Length
            payload["tools"] := tools

        return payload
    }

    static ImageNamespaceTool() {
        return Map(
            "type", "namespace",
            "name", "ahkllm",
            "description", "AhkLLM client-side capabilities explicitly enabled by the user.",
            "tools", [
                Map(
                    "type", "function",
                    "name", "generate_image",
                    "description", "Generate or edit an image requested by the user. Supply a self-contained visual prompt that incorporates any relevant conversation and image context.",
                    "parameters", Map(
                        "type", "object",
                        "properties", Map(
                            "prompt", Map(
                                "type", "string",
                                "description", "Complete image-generation prompt describing the desired result."
                            )
                        ),
                        "required", ["prompt"],
                        "additionalProperties", false
                    ),
                    "strict", true
                )
            ]
        )
    }

    static BuildToolContinuation(previousPayload, responseOutput, functionCallOutputs) {
        if !IsObject(previousPayload) || !previousPayload.Has("input") || !(previousPayload["input"] is Array)
            throw Error("ChatGPT tool continuation is missing the original Responses input.")

        nextInput := []
        for item in previousPayload["input"]
            nextInput.Push(item)

        if IsObject(responseOutput) && responseOutput is Array {
            for item in responseOutput
                nextInput.Push(item)
        }

        if !IsObject(functionCallOutputs) || !(functionCallOutputs is Array) || !functionCallOutputs.Length
            throw Error("ChatGPT tool continuation has no function outputs.")
        for item in functionCallOutputs
            nextInput.Push(item)

        next := Map()
        for key, value in previousPayload {
            if key = "input"
                continue
            next[key] := value
        }
        next["input"] := nextInput
        next["store"] := false
        next["stream"] := true
        return next
    }

    static Serialize(payload) {
        return LLMRequestBuilder._FixStreamBoolean(ImagePayloadSerializer.Stringify(payload))
    }

    static WritePayload(requestFile, payload) {
        json := ChatGptResponsesTransport.Serialize(payload)
        FileOpen(requestFile, "w", "UTF-8-RAW").Write(json)
        return json
    }

    static StartStreaming(requestFile, outputFile, errorFile, cancelState := "") {
        accessToken := ChatGptPlanAuth.EnsureAccessToken()
        return ChatGptResponsesTransport._StartSecureCurl(
            ChatGptResponsesTransport.ResolveEndpoint(),
            requestFile,
            outputFile,
            errorFile,
            accessToken,
            cancelState
        )
    }

    ; Inline commands still receive the required wire stream, but AhkLLM
    ; buffers it and only returns success after response.completed.
    static ExecuteBuffered(requestFile, outputFile, errorFile, cancelState := "", webSearch := false, imageGeneration := false) {
        prepared := ChatGptResponsesTransport.PrepareRequestFile(requestFile, webSearch, imageGeneration)
        process := ChatGptResponsesTransport.StartStreaming(requestFile, outputFile, errorFile, cancelState)
        cancelled := false
        try {
            loop {
                wait := DllCall("WaitForSingleObject", "Ptr", process.processHandle, "UInt", 25, "UInt")
                if wait = 0
                    break
                if wait != 0x102
                    throw OSError(A_LastError, "WaitForSingleObject failed for ChatGPT Responses")
                if ChatGptResponsesTransport._CancellationRequested(cancelState) {
                    cancelled := true
                    if IsObject(cancelState)
                        cancelState.cancelled := true
                    try RunWait('taskkill /PID ' process.pid ' /T /F', , "Hide")
                    catch
                        DllCall("TerminateProcess", "Ptr", process.processHandle, "UInt", 1)
                    DllCall("WaitForSingleObject", "Ptr", process.processHandle, "UInt", 2000, "UInt")
                    break
                }
            }
        } finally {
            if process.processHandle
                DllCall("CloseHandle", "Ptr", process.processHandle)
            if IsObject(cancelState)
                cancelState.pid := 0
        }

        raw := FileExist(outputFile) ? FileRead(outputFile, "UTF-8") : ""
        if cancelled
            return { success: false, cancelled: true, raw: raw, prepared: prepared }

        parsed := ChatGptResponsesTransport.ParseBuffered(raw)
        parsed.raw := raw
        parsed.prepared := prepared
        if !parsed.success && FileExist(errorFile) {
            stderrText := Trim(FileRead(errorFile, "UTF-8"))
            if parsed.error = "" && stderrText != ""
                parsed.error := stderrText
        }
        return parsed
    }

    static ParseBuffered(raw) {
        content := ""
        reasoning := ""
        usage := { promptTokens: 0, completionTokens: 0, thinkingTokens: 0, cachedTokens: 0, totalTokens: 0 }
        completed := false
        model := ""
        errorMessage := ""
        errorCode := ""
        responseOutput := []

        for line in StrSplit(String(raw), Chr(10), Chr(13)) {
            if Trim(line) = ""
                continue
            chunk := ChatGptResponsesStreamParser.ParseLine(line)
            switch chunk.type {
                case "content":
                    content .= chunk.content
                case "reasoning":
                    reasoning .= chunk.content
                case "responses_output_item":
                    responseOutput := ChatGptResponsesStreamParser.MergeOutput(responseOutput, [chunk.item])
                case "finish":
                    ChatGptResponsesStreamParser.CompleteOutput(chunk, responseOutput)
                    responseOutput := chunk.responseOutput
                    if chunk.finalText != ""
                        content := chunk.finalText
                    completed := chunk.HasOwnProp("completed") && chunk.completed
                    if chunk.HasOwnProp("usage")
                        usage := chunk.usage
                    if chunk.HasOwnProp("model")
                        model := chunk.model
                case "error":
                    errorMessage := chunk.HasOwnProp("message") ? chunk.message : "The ChatGPT Responses request failed."
                    if chunk.HasOwnProp("code") && chunk.code != ""
                        errorCode := chunk.code
            }
        }

        if errorMessage = "" && !InStr(String(raw), "data: ") {
            errorMessage := ChatGptResponsesTransport.ExtractAdmissionError(raw)
            errorCode := ChatGptResponsesTransport.ExtractAdmissionCode(raw)
        }

        if errorMessage != ""
            return { success: false, cancelled: false, error: errorMessage, errorCode: errorCode, content: content, reasoning: reasoning, usage: usage, model: model, completed: false }
        if !completed
            return { success: false, cancelled: false, error: "The ChatGPT Responses stream ended without response.completed.", errorCode: errorCode, content: content, reasoning: reasoning, usage: usage, model: model, completed: false }

        return {
            success: true,
            cancelled: false,
            error: "",
            content: content,
            reasoning: reasoning,
            usage: usage,
            model: model,
            completed: true,
            responseOutput: responseOutput,
            functionCalls: ChatGptResponsesStreamParser.ExtractFunctionCalls(responseOutput),
            response: { response: content, reasoning: reasoning, usage: usage }
        }
    }

    static ExtractAdmissionError(raw) {
        raw := Trim(String(raw))
        if raw = ""
            return ""
        try parsed := jsongo.Parse(raw)
        catch
            return ""
        if !IsObject(parsed)
            return ""
        if Type(parsed) = "Array" && parsed.Length
            parsed := parsed[1]
        if !IsObject(parsed)
            return ""

        if parsed.Has("detail") && parsed["detail"] != "" {
            detail := parsed["detail"]
            if !IsObject(detail)
                return String(detail)
            if detail.Has("message") && detail["message"] != ""
                return String(detail["message"])
        }
        if parsed.Has("message") && parsed["message"] != ""
            return String(parsed["message"])
        if parsed.Has("error") {
            err := parsed["error"]
            if IsObject(err) {
                if err.Has("message") && err["message"] != ""
                    return String(err["message"])
                if err.Has("detail") && err["detail"] != ""
                    return String(err["detail"])
                if err.Has("code") && err["code"] != ""
                    return String(err["code"])
            } else if err != ""
                return String(err)
        }
        return ""
    }

    static ExtractAdmissionCode(raw) {
        raw := Trim(String(raw))
        if raw = ""
            return ""
        try parsed := jsongo.Parse(raw)
        catch
            return ""
        if !IsObject(parsed)
            return ""
        if Type(parsed) = "Array" && parsed.Length
            parsed := parsed[1]
        if !IsObject(parsed)
            return ""

        if parsed.Has("error") && IsObject(parsed["error"]) {
            err := parsed["error"]
            if err.Has("code") && err["code"] != ""
                return String(err["code"])
        }
        if parsed.Has("detail") && IsObject(parsed["detail"]) {
            detail := parsed["detail"]
            if detail.Has("code") && detail["code"] != ""
                return String(detail["code"])
        }
        if parsed.Has("code") && parsed["code"] != ""
            return String(parsed["code"])
        return ""
    }

    static _MessageInput(role, content) {
        if !IsObject(content) {
            itemType := role = "assistant" ? "output_text" : "input_text"
            return Map(
                "type", "message",
                "role", role,
                "content", [Map("type", itemType, "text", String(content))]
            )
        }

        if !(content is Array)
            throw Error("Unsupported message content shape for ChatGPT-plan Responses.")

        parts := []
        for part in content {
            if !IsObject(part)
                continue
            partType := part.Has("type") ? String(part["type"]) : ""
            if partType = "text" {
                if part.Has("text")
                    parts.Push(Map("type", role = "assistant" ? "output_text" : "input_text", "text", String(part["text"])))
                continue
            }
            if (partType = "image_url" || partType = "input_image") && role = "user" {
                imageUrl := ""
                if part.Has("image_url") {
                    imageValue := part["image_url"]
                    if IsObject(imageValue) && imageValue.Has("url")
                        imageUrl := String(imageValue["url"])
                    else
                        imageUrl := String(imageValue)
                }
                if imageUrl != ""
                    parts.Push(Map("type", "input_image", "image_url", imageUrl))
                continue
            }
        }
        if !parts.Length
            parts.Push(Map("type", role = "assistant" ? "output_text" : "input_text", "text", ""))
        return Map("type", "message", "role", role, "content", parts)
    }

    static _ContentText(content) {
        if !IsObject(content)
            return String(content)
        if !(content is Array)
            return ""
        out := ""
        for part in content {
            if IsObject(part) && part.Has("type") && part["type"] = "text" && part.Has("text")
                out .= (out = "" ? "" : Chr(10) Chr(10)) String(part["text"])
        }
        return out
    }

    static _StartSecureCurl(url, requestFile, outputFile, errorFile, accessToken, cancelState) {
        saSize := A_PtrSize = 8 ? 24 : 12
        sa := Buffer(saSize, 0)
        NumPut("UInt", saSize, sa, 0)
        NumPut("Ptr", 0, sa, A_PtrSize = 8 ? 8 : 4)
        NumPut("Int", true, sa, A_PtrSize = 8 ? 16 : 8)

        stdinRead := 0
        stdinWrite := 0
        outputHandle := 0
        errorHandle := 0
        processHandle := 0
        try {
            if !DllCall("CreatePipe", "Ptr*", &stdinRead, "Ptr*", &stdinWrite, "Ptr", sa.Ptr, "UInt", 0, "Int")
                throw OSError(A_LastError, "CreatePipe failed for ChatGPT Responses curl")
            if !DllCall("SetHandleInformation", "Ptr", stdinWrite, "UInt", 1, "UInt", 0, "Int")
                throw OSError(A_LastError, "SetHandleInformation failed for ChatGPT Responses stdin")

            outputHandle := ChatGptResponsesTransport._OpenInheritedWriteFile(outputFile, sa)
            errorHandle := ChatGptResponsesTransport._OpenInheritedWriteFile(errorFile, sa)

            commandLine := 'curl.exe --no-buffer --silent --show-error --fail-with-body --config -'
            commandBuf := Buffer(StrPut(commandLine, "UTF-16") * 2, 0)
            StrPut(commandLine, commandBuf, "UTF-16")

            siSize := A_PtrSize = 8 ? 104 : 68
            piSize := A_PtrSize = 8 ? 24 : 16
            startupInfo := Buffer(siSize, 0)
            processInfo := Buffer(piSize, 0)
            NumPut("UInt", siSize, startupInfo, 0)
            NumPut("UInt", 0x100, startupInfo, A_PtrSize = 8 ? 60 : 44)
            NumPut("Ptr", stdinRead, startupInfo, A_PtrSize = 8 ? 80 : 56)
            NumPut("Ptr", outputHandle, startupInfo, A_PtrSize = 8 ? 88 : 60)
            NumPut("Ptr", errorHandle, startupInfo, A_PtrSize = 8 ? 96 : 64)

            created := DllCall(
                "CreateProcessW",
                "Ptr", 0,
                "Ptr", commandBuf.Ptr,
                "Ptr", 0,
                "Ptr", 0,
                "Int", true,
                "UInt", 0x08000000,
                "Ptr", 0,
                "Ptr", 0,
                "Ptr", startupInfo.Ptr,
                "Ptr", processInfo.Ptr,
                "Int"
            )
            if !created
                throw OSError(A_LastError, "Could not start curl.exe for ChatGPT Responses")

            processHandle := NumGet(processInfo, 0, "Ptr")
            threadHandle := NumGet(processInfo, A_PtrSize, "Ptr")
            pid := NumGet(processInfo, A_PtrSize * 2, "UInt")
            if threadHandle
                DllCall("CloseHandle", "Ptr", threadHandle)

            DllCall("CloseHandle", "Ptr", stdinRead)
            stdinRead := 0
            DllCall("CloseHandle", "Ptr", outputHandle)
            outputHandle := 0
            DllCall("CloseHandle", "Ptr", errorHandle)
            errorHandle := 0

            config := ChatGptResponsesTransport._CurlConfig(url, requestFile, accessToken)
            ChatGptResponsesTransport._WriteAll(stdinWrite, config)
            DllCall("CloseHandle", "Ptr", stdinWrite)
            stdinWrite := 0

            if IsObject(cancelState)
                cancelState.pid := pid

            return { pid: pid, processHandle: processHandle }
        } catch {
            for handle in [stdinRead, stdinWrite, outputHandle, errorHandle, processHandle] {
                if handle && handle != -1
                    try DllCall("CloseHandle", "Ptr", handle)
            }
            throw
        }
    }

    static _OpenInheritedWriteFile(path, sa) {
        handle := DllCall(
            "CreateFileW",
            "Str", path,
            "UInt", 0x40000000,
            "UInt", 0x3,
            "Ptr", sa.Ptr,
            "UInt", 2,
            "UInt", 0x80,
            "Ptr", 0,
            "Ptr"
        )
        if handle = -1
            throw OSError(A_LastError, "Could not open ChatGPT Responses output file")
        return handle
    }

    static _CurlConfig(url, requestFile, accessToken) {
        q := Chr(34)
        path := StrReplace(String(requestFile), "\", "/")
        tokenHeader := "Authorization: Bearer " accessToken
        lines := [
            "url = " q ChatGptResponsesTransport._CurlEscape(url) q,
            "request = " q "POST" q,
            "header = " q ChatGptResponsesTransport._CurlEscape(tokenHeader) q,
            "header = " q "Content-Type: application/json" q,
            "header = " q "Accept: text/event-stream" q,
            "data-binary = " q "@" ChatGptResponsesTransport._CurlEscape(path) q,
            "connect-timeout = 30",
            "max-time = 600"
        ]
        return CodexCliRuntime.Join(lines, Chr(10)) Chr(10)
    }

    static _CurlEscape(value) {
        value := StrReplace(String(value), "\", "\\")
        return StrReplace(value, Chr(34), "\" Chr(34))
    }

    static _WriteAll(handle, text) {
        bytes := ChatGptPlanCrypto.Utf8Buffer(text)
        offset := 0
        while offset < bytes.Size {
            wrote := 0
            ok := DllCall("WriteFile", "Ptr", handle, "Ptr", bytes.Ptr + offset, "UInt", bytes.Size - offset, "UInt*", &wrote, "Ptr", 0, "Int")
            if !ok
                throw OSError(A_LastError, "Could not send secure curl configuration")
            if wrote <= 0
                throw Error("curl stdin accepted zero bytes.")
            offset += wrote
        }
    }

    static _CancellationRequested(cancelState) {
        if !IsObject(cancelState)
            return false
        if cancelState.HasOwnProp("cancelled") && cancelState.cancelled
            return true
        if cancelState.HasOwnProp("cancelRequested") && cancelState.cancelRequested
            return true
        return cancelState.HasOwnProp("cancelOnEscape") && cancelState.cancelOnEscape
            && (DllCall("User32\GetAsyncKeyState", "Int", 0x1B, "Short") & 0x8000) != 0
    }
}
