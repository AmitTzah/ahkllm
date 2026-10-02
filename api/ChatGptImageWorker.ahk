; ======================================================
; ChatGptImageWorker.ahk — isolated Codex CLI image-generation worker
;
; This is deliberately not a chat transport. It receives one explicit
; generate_image tool prompt from the ChatGPT Responses loop, exposes only
; Codex image generation (all other local/agent surfaces remain disabled by
; CodexCliRuntime), and returns generated attachments to AhkLLM.
; ======================================================

class ChatGptImageWorker {
    static MAX_TOOL_ROUNDS := 4

    static Execute(modelName, prompt, requestPath := "", cancelState := "") {
        prompt := Trim(String(prompt))
        if prompt = ""
            throw Error("Image generation tool call did not include a prompt.")

        unique := ChatDB._UUID()
        requestFile := A_Temp "\AhkLLM_ImageWorker_Req_" unique ".json"
        outputFile := A_Temp "\AhkLLM_ImageWorker_Out_" unique ".json"
        errorFile := A_Temp "\AhkLLM_ImageWorker_Err_" unique ".txt"
        ; Share the caller's cancellation object so a Stop action received
        ; while Codex is running is observed by CodexCliTransport's COM-pumped
        ; wait loop. The image worker adds only the narrowly scoped params it
        ; needs; AhkLLM chat history remains outside Codex.
        scope := IsObject(cancelState) ? cancelState : { cancelRequested: false, cancelled: false }
        scope.params := Map(
            "singleAPIModelName", "codex/" modelName,
            "imageGeneration", true,
            "_codexInputImages", ChatGptImageWorker.CollectInputImages(requestPath)
        )

        requestObj := Map(
            "model", modelName,
            "messages", [
                Map(
                    "role", "system",
                    "content", "You are AhkLLM's isolated image-generation worker. Use the available image-generation capability to create or edit the requested image. Do not browse the web, inspect local files, run shell commands, or perform unrelated work. A text-only answer is not sufficient when image generation succeeds."
                ),
                Map("role", "user", "content", prompt)
            ]
        )
        FileOpen(requestFile, "w", "UTF-8-RAW").Write(LLMRequestBuilder._FixStreamBoolean(jsongo.Stringify(requestObj)))

        providerInfo := {
            providerKey: "codex",
            modelName: modelName,
            endpoint: "",
            fimEndpoint: "",
            transport: "codex-cli",
            authMode: "chatgpt",
            billingMode: "chatgpt-subscription",
            apiKey: ""
        }

        try {
            result := CodexCliTransport.ExecuteRequest(
                providerInfo,
                requestFile,
                outputFile,
                errorFile,
                scope,
                false,
                "",
                "",
                true
            )
            if result.cancelled
                return { success: false, cancelled: true, error: "Image generation was cancelled.", attachments: [] }
            if !result.success {
                message := result.HasOwnProp("error") && result.error != "" ? result.error : ""
                if message = "" && FileExist(errorFile)
                    message := Trim(FileRead(errorFile, "UTF-8"))
                if message = ""
                    message := "Codex image generation failed."
                return { success: false, cancelled: false, error: message, attachments: [] }
            }
            attachments := result.HasOwnProp("generatedAttachments") && IsObject(result.generatedAttachments)
                ? result.generatedAttachments : []
            if !attachments.Length
                return { success: false, cancelled: false, error: "Codex completed without producing an image.", attachments: [] }
            return {
                success: true,
                cancelled: false,
                error: "",
                attachments: attachments,
                response: result.HasOwnProp("response") ? result.response : ""
            }
        } finally {
            for path in [requestFile, outputFile, errorFile] {
                if path && FileExist(path)
                    try FileDelete(path)
            }
        }
    }

    static CollectInputImages(requestPath) {
        images := []
        seen := Map()
        if !IsObject(requestPath)
            return images
        for msg in requestPath {
            if !IsObject(msg) || !msg.HasOwnProp("id") || !msg.id
                continue
            attachments := ChatDB.Attachment_GetByMessage(msg.id)
            for att in attachments {
                if !IsObject(att) || att.attachment_type != "image" || !att.file_path
                    continue
                fullPath := ChatGptImageWorker._ResolveAttachmentPath(att.file_path)
                if fullPath = ""
                    continue
                key := StrLower(fullPath)
                if seen.Has(key)
                    continue
                seen[key] := true
                images.Push(fullPath)
            }
        }
        return images
    }

    static _ResolveAttachmentPath(relativePath) {
        relativePath := StrReplace(String(relativePath), "/", "\")
        prefix := "attachments\"
        if StrLower(SubStr(relativePath, 1, StrLen(prefix))) != prefix
            return ""
        if InStr(relativePath, "..") || InStr(relativePath, ":")
            return ""
        tail := SubStr(relativePath, StrLen(prefix) + 1)
        if tail = "" || SubStr(tail, 1, 1) = "\"
            return ""
        fullPath := AppInfo.DataDir "\" relativePath
        return FileExist(fullPath) ? fullPath : ""
    }
}
