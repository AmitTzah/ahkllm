; ======================================================
; ChatWindow.ahk — Single persistent chat window
;
; Runs as a sub-process spawned by Main.ahk. No tray icon.
; Close = hide. Re-opened via tray menu or command-line arg.
;
; Usage: AutoHotkey64.exe ChatWindow.ahk <mainScriptHwnd> [threadId]
; ======================================================

#Include ..\lib\Config.ahk
#SingleInstance Off
#NoTrayIcon

; ----------------------------------------------------
; Hotkeys
; ----------------------------------------------------

~Esc:: ChatHotkeys("Esc")
~^w:: ChatHotkeys("closeWindows")

ChatHotkeys(action) {
    switch action {
        case "Esc":
            curlPID := manageState("cURL", "get")
            hadCurl := ProcessExist(curlPID)
            if hadCurl {
                manageState("cURL", "close")
                postWebMessage("setChatButtonsEnabled", true)
            }
            ; Only hide window if no cURL was running (don't hide after cancelling a request)
            if WinActive("ahk_id " chatWindow.hWnd) && !hadCurl {
                chatWindow.Hide()
            }
        case "closeWindows":
            switch WinActive("A") {
                case chatWindow.hWnd: chatWindow.Hide()
            }
    }
}

; ----------------------------------------------------
; Initialize DB and request params
; ----------------------------------------------------

ChatDB.Open()
requestParams := Map()
requestParams["pasteMode"] := "chat"
requestParams["uniqueID"] := A_TickCount A_NowUTC
requestParams["mainScriptHiddenhWnd"] := A_Args.Length > 0 ? Integer(A_Args[1]) : 0
requestParams["providerName"] := "deepseek"
requestParams["singleAPIModelName"] := chatDefaultModel
requestParams["responseWindowTitle"] := "Chat"
requestParams["stream"] := true
requestParams["isFIM"] := false
requestParams["numberOfAPIModels"] := 1
requestParams["APIModelsIndex"] := 1
activeThreadId := ""

; Register IPC handlers for main-script commands
OnMessage(CustomMessages.WM_LOAD_THREAD, OnLoadThread)
OnMessage(CustomMessages.WM_NEW_CHAT, OnNewChat)

OnLoadThread(wParam, lParam, msg, hWnd) {
    global activeThreadId
    threadId := StrGet(wParam)
    if threadId {
        activeThreadId := threadId
        _restoreThreadSettings(activeThreadId)
        path := ChatDB.Msg_GetActivePath(activeThreadId)
        postWebMessage("initChatMode", buildStructuredMessagesFromPath(path))
        postWebMessage("renderChatTree", ChatDB.Msg_GetTree(activeThreadId))
        postThreadStats(activeThreadId)
        _sendDropdownLabel()
    }
}

OnNewChat(wParam, lParam, msg, hWnd) {
    global activeThreadId
    activeThreadId := ChatDB.Thread_Create()
    _resetToDefaultSettings()
    postWebMessage("initChatMode", [])
    _sendDropdownLabel()
}

; Apply saved per-thread settings from DB to requestParams.
_restoreThreadSettings(threadId) {
    settings := ChatDB.Thread_GetSettings(threadId)
    if !settings
        return
    if settings.modelOverride
        requestParams["singleAPIModelName"] := settings.modelOverride
    if settings.systemOverride
        requestParams["systemOverride"] := settings.systemOverride
    if settings.reasoningOverride
        requestParams["reasoningOverride"] := settings.reasoningOverride
    if settings.temperatureOverride
        requestParams["temperatureOverride"] := settings.temperatureOverride
    if settings.assistantId {
        requestParams["activeAssistantId"] := settings.assistantId
        asst := ChatDB.Assistant_Get(settings.assistantId)
        if asst {
            requestParams["singleAPIModelName"] := asst.baseModel
            requestParams["systemOverride"] := asst.systemPrompt
            requestParams["reasoningOverride"] := asst.reasoning
            requestParams["temperatureOverride"] := asst.temperature
        }
    }
}

; Persist current requestParams settings to a thread (called on thread creation).
_saveCurrentSettingsToThread(threadId) {
    ChatDB.Thread_UpdateSettings(threadId, {
        assistantId: requestParams.Has("activeAssistantId") ? requestParams["activeAssistantId"] : "",
        modelOverride: requestParams["singleAPIModelName"] != chatDefaultModel ? requestParams["singleAPIModelName"] : "",
        systemOverride: requestParams.Has("systemOverride") ? requestParams["systemOverride"] : "",
        reasoningOverride: requestParams.Has("reasoningOverride") ? requestParams["reasoningOverride"] : "",
        temperatureOverride: requestParams.Has("temperatureOverride") ? requestParams["temperatureOverride"] : ""
    })
}

; Reset settings to defaults (no assistant, default model, no overrides).
_resetToDefaultSettings() {
    requestParams["singleAPIModelName"] := chatDefaultModel
    if requestParams.Has("systemOverride")
        requestParams.Delete("systemOverride")
    if requestParams.Has("reasoningOverride")
        requestParams.Delete("reasoningOverride")
    if requestParams.Has("temperatureOverride")
        requestParams.Delete("temperatureOverride")
    if requestParams.Has("activeAssistantId")
        requestParams.Delete("activeAssistantId")
}

; Send current dropdown label to WebView (assistant name / model name / "Default Model").
_sendDropdownLabel() {
    if requestParams.Has("activeAssistantId") && requestParams["activeAssistantId"] {
        asst := ChatDB.Assistant_Get(requestParams["activeAssistantId"])
        if asst {
            postWebMessage("dropdownLabel", { text: asst.name, isAssistant: true })
            return
        }
    }
    model := requestParams["singleAPIModelName"]
    if model && model != chatDefaultModel {
        ; Show model name without provider prefix
        slashPos := InStr(model, "/")
        displayModel := slashPos > 0 ? SubStr(model, slashPos + 1) : model
        postWebMessage("dropdownLabel", { text: displayModel, isAssistant: false })
        return
    }
    postWebMessage("dropdownLabel", { text: "Default Model", isAssistant: false })
}

; ----------------------------------------------------
; Create WebView and router
; ----------------------------------------------------

responseWindow := WebViewToo(, , ,)
responseWindow.OnEvent("Close", (*) => responseWindow.Hide())
global chatWindow := responseWindow

; Set window icon (title bar / taskbar) to match the main script's tray icon
hIcon := LoadPicture(A_ScriptDir "\..\" iconOn, "Icon1 w32 h32", &imgType)
if hIcon {
    SendMessage(0x80, 0, hIcon, , "ahk_id " chatWindow.hWnd)  ; WM_SETICON, ICON_BIG (Alt+Tab)
    SendMessage(0x80, 1, hIcon, , "ahk_id " chatWindow.hWnd)  ; WM_SETICON, ICON_SMALL (title bar / taskbar)
}

; Set up WebMessageReceived handler for JS→AHK communication via postMessage
responseWindow.WebMessageReceived(OnWebMessageReceived)
OnWebMessageReceived(sender, args) {
    try {
        msg := args.TryGetWebMessageAsString()
        if !msg
            return
        parsed := jsongo.Parse(msg)
        action := parsed.Get("action", "")
        switch action {
            case "chatSend":
                chatSendFromWebView(parsed.Get("message", ""))
            case "retry":
                retryFromWebView(parsed)
            case "editMessage":
                editMessageFromWebView(parsed)
            case "deleteMessage":
                deleteMessageFromWebView(parsed.Get("id", ""))
            case "switchBranch":
                switchBranchFromWebView(parsed)
            case "forkChat":
                forkChatFromWebView(parsed.Get("id", ""))
            case "setFeedback":
                setFeedbackFromWebView(parsed)
            case "sidebarAction":
                sidebarActionFromWebView(parsed)
            case "buttonClick":
                buttonClickAction(parsed.Get("btnAction", ""))
            case "requestAssistantList":
                postAssistantsToWebView()
            case "updateModelSettings":
                updateModelSettingsFromWebView(parsed)
            case "switchAssistant":
                switchAssistantFromWebView(parsed)
            case "cancelStream":
                cancelStreamFromWebView()
            case "requestCurrentSettings":
                postCurrentSettingsToWebView()
        }
    }
}

if (darkMode)
    DllCall("Dwmapi\DwmSetWindowAttribute", "ptr", responseWindow.hWnd, "int", 20, "int*", true, "int", 4)

router := LLMClient(APIKey)

; ----------------------------------------------------
; Core functions (used by included modules below)
; ----------------------------------------------------

BuildAndWriteRequestFiles() {
    if !activeThreadId
        return ""
    path := ChatDB.Msg_GetActivePath(activeThreadId)
    if !path.Length
        return ""

    ; Resolve provider once — used for validation, cURL building, and provider-specific request fields
    providerInfo := LLMClient.ResolveProvider(requestParams["singleAPIModelName"])

    ; Validate: check API key is available for the selected provider
    if !providerInfo.apiKey {
        pInfo := providers[providerInfo.providerKey]
        envVar := pInfo ? pInfo.authEnvVar : providerInfo.providerKey
        errorMsg := "No API key configured for " providerInfo.providerKey ". Set " envVar " environment variable."
        postWebMessage("showError", { message: errorMsg })
        postWebMessage("setChatButtonsEnabled", true)
        startLoadingCursor(false)
        debugLog("ERROR: " errorMsg)
        return ""
    }

    ; Build messages array as AHK objects for safe JSON serialization
    apiMessages := []
    for msg in path {
        apiMessages.Push({ role: msg.role, content: msg.content })
    }

    ; Apply system prompt override if set via Settings modal
    if requestParams.Has("systemOverride") && requestParams["systemOverride"] {
        found := false
        for i, m in apiMessages {
            if m.role = "system" {
                apiMessages[i].content := requestParams["systemOverride"]
                found := true
                break
            }
        }
        ; If no system message exists (e.g. thread started with empty system prompt),
        ; prepend one so the override takes effect.
        if !found {
            apiMessages.InsertAt(1, { role: "system", content: requestParams["systemOverride"] })
        }
    }

    ; Strip provider prefix from model name for API call (e.g. "deepseek/deepseek-v4-flash" → "deepseek-v4-flash")
    apiModelName := requestParams["singleAPIModelName"]
    slashPos := InStr(apiModelName, "/")
    if slashPos > 0 {
        apiModelName := SubStr(apiModelName, slashPos + 1)
    }
    requestObj := { model: apiModelName, messages: apiMessages }

    ; Apply reasoning override with per-provider thinking control.
    ; Each provider has different mechanisms for enabling/disabling thinking.
    if requestParams.Has("reasoningOverride") && requestParams["reasoningOverride"] != "" {
        reasoningVal := requestParams["reasoningOverride"]

        if reasoningVal = "none" {
            ; User wants thinking disabled — use provider-specific mechanism
            if providerInfo.providerKey = "deepseek" {
                ; DeepSeek V4: thinking:disabled is the only way to disable.
                ; Do NOT send reasoning_effort at all — DeepSeek rejects "none".
                requestObj.thinking := { type: "disabled" }
            } else {
                ; OpenAI GPT-5.1+ / Gemini Flash: reasoning_effort: "none" works
                ; For models that can't disable (GPT-5, Gemini Pro), this is silently ignored
                requestObj.reasoning_effort := "none"
            }
        } else {
            ; Specific reasoning level (low/medium/high/xhigh)
            requestObj.reasoning_effort := reasoningVal
        }
    }

    ; Apply temperature override if set (use != "" not truthiness — "0" is falsy in AHK)
    if requestParams.Has("temperatureOverride") && requestParams["temperatureOverride"] != "" {
        try {
            requestObj.temperature := Float(requestParams["temperatureOverride"])
        } catch {
            debugLog("WARNING: invalid temperature value: " requestParams["temperatureOverride"])
        }
    }

    if requestParams["stream"] {
        requestObj.stream := true
        ; stream_options tells OpenAI-compatible APIs to include usage in the final SSE chunk
        requestObj.stream_options := { include_usage: true }
    }

    ; Gemini-specific: request thinking (thought summaries) via extra_body
    if providerInfo.providerKey = "google" {
        requestObj.extra_body := {
            google: {
                thinking_config: {
                    include_thoughts: true
                }
            }
        }
    }

    payload := LLMClient._FixStreamBoolean(jsongo.Stringify(requestObj))

    uniqueID := A_TickCount
    requestFile := A_Temp "\ChatWindow_Req_" uniqueID ".json"
    cURLFile := A_Temp "\ChatWindow_cURL_" uniqueID ".txt"
    outputFile := A_Temp "\ChatWindow_Out_" uniqueID ".json"
    errorFile := A_Temp "\ChatWindow_Err_" uniqueID ".txt"

    FileOpen(requestFile, "w", "UTF-8-RAW").Write(payload)
    if requestParams["stream"] {
        cURLCommand := LLMClient.BuildStreamcURLCommand(providerInfo, requestFile, outputFile, errorFile)
    } else {
        cURLCommand := LLMClient.BuildcURLCommand(providerInfo, requestFile, outputFile)
    }
    FileOpen(cURLFile, "w", "UTF-8-RAW").Write(cURLCommand)

    requestParams["chatHistoryJSONRequestFile"] := requestFile
    requestParams["cURLCommandFile"] := cURLFile
    requestParams["cURLOutputFile"] := outputFile
    requestParams["cURLErrorFile"] := errorFile

    return payload
}

sendRequestToLLM(&chatHistoryJSONRequest, initialRequest := false) {
    sendStreamingRequest(&chatHistoryJSONRequest, initialRequest)
}

; ----------------------------------------------------
switchAssistantFromWebView(parsed) {
    global activeThreadId
    assistantId := parsed.Get("assistantId", "")
    if !assistantId {
        ; User selected "Default Model" — clear assistant
        _resetToDefaultSettings()
        if activeThreadId {
            ChatDB.Thread_UpdateSettings(activeThreadId, {
                assistantId: "",
                modelOverride: "",
                systemOverride: "",
                reasoningOverride: "",
                temperatureOverride: ""
            })
        }
        _sendDropdownLabel()
        return
    }

    asst := ChatDB.Assistant_Get(assistantId)
    if !asst
        return

    requestParams["singleAPIModelName"] := asst.baseModel
    requestParams["systemOverride"] := asst.systemPrompt
    requestParams["reasoningOverride"] := asst.reasoning
    requestParams["temperatureOverride"] := asst.temperature
    requestParams["activeAssistantId"] := assistantId

    ; Update provider tracking for API logs
    slashPos := InStr(asst.baseModel, "/")
    if slashPos > 0 {
        requestParams["providerName"] := SubStr(asst.baseModel, 1, slashPos - 1)
    }

    ; Persist to DB
    if activeThreadId {
        ChatDB.Thread_UpdateSettings(activeThreadId, {
            assistantId: assistantId,
            modelOverride: "",
            systemOverride: "",
            reasoningOverride: "",
            temperatureOverride: ""
        })
    }

    _sendDropdownLabel()
    debugLog("Switched to assistant: " asst.name " (" asst.baseModel ")")
}

updateModelSettingsFromWebView(parsed) {
    model := parsed.Get("model", "")
    systemPrompt := parsed.Get("systemPrompt", "")
    reasoning := parsed.Get("reasoning", "")
    temperature := parsed.Get("temperature", "")

    ; Clear assistant when user manually changes settings via gear
    if requestParams.Has("activeAssistantId")
        requestParams.Delete("activeAssistantId")

    if model {
        requestParams["singleAPIModelName"] := model
        slashPos := InStr(model, "/")
        if slashPos > 0 {
            requestParams["providerName"] := SubStr(model, 1, slashPos - 1)
        }
    } else {
        requestParams["singleAPIModelName"] := chatDefaultModel
    }
    requestParams["systemOverride"] := systemPrompt
    requestParams["reasoningOverride"] := reasoning
    requestParams["temperatureOverride"] := temperature

    ; Persist to DB
    if activeThreadId {
        ChatDB.Thread_UpdateSettings(activeThreadId, {
            assistantId: "",
            modelOverride: requestParams["singleAPIModelName"] != chatDefaultModel ? requestParams["singleAPIModelName"] : "",
            systemOverride: systemPrompt,
            reasoningOverride: reasoning,
            temperatureOverride: temperature
        })
    }

    _sendDropdownLabel()
    debugLog("Model settings updated: model=" (model ? model : chatDefaultModel "(default)"))
}

postCurrentSettingsToWebView() {
    model := requestParams["singleAPIModelName"]
    systemPrompt := requestParams.Has("systemOverride") ? requestParams["systemOverride"] : ""
    reasoning := requestParams.Has("reasoningOverride") ? requestParams["reasoningOverride"] : ""
    temperature := requestParams.Has("temperatureOverride") ? requestParams["temperatureOverride"] : ""
    isReadOnly := requestParams.Has("activeAssistantId") && requestParams["activeAssistantId"] != ""
    postWebMessage("currentSettings", {
        model: model,
        systemPrompt: systemPrompt,
        reasoning: reasoning,
        temperature: temperature,
        readOnly: isReadOnly
    })
}

cancelStreamFromWebView() {
    ; Directly kill the cURL process without going through ChatHotkeys("Esc").
    ; ChatHotkeys("Esc") has window-hiding logic (hides window when no cURL is running),
    ; which is wrong for the Stop button — the Stop button should only cancel streaming,
    ; never hide the window.
    curlPID := manageState("cURL", "get")
    if curlPID && ProcessExist(curlPID) {
        manageState("cURL", "close")
        requestParams["_streamCancelled"] := true
        postWebMessage("setChatButtonsEnabled", true)
    }
}

; ----------------------------------------------------
postAssistantsToWebView() {
    assistants := ChatDB.Assistant_List()
    postWebMessage("assistantList", assistants)

    ; Also send model list grouped by provider for the two-dropdown selector
    modelByProvider := Map()
    for modelId, modelData in models {
        slashPos := InStr(modelId, "/")
        if slashPos > 0 {
            providerKey := SubStr(modelId, 1, slashPos - 1)
            shortName := SubStr(modelId, slashPos + 1)
            if !modelByProvider.Has(providerKey)
                modelByProvider[providerKey] := []
            modelByProvider[providerKey].Push({
                id: shortName,
                fullId: modelId,
                name: modelData.HasOwnProp("displayName") ? modelData.displayName : shortName,
                reasoning: modelData.HasOwnProp("reasoning") ? modelData.reasoning : false,
                vision: modelData.HasOwnProp("vision") ? modelData.vision : false
            })
        }
    }
    postWebMessage("modelList", modelByProvider)
}

; Delayed push: send assistant list after WebView page loads
; Called from the main init flow with a timer to avoid race conditions
SetTimer SendAssistantsDelayed, -500
SendAssistantsDelayed() {
    postAssistantsToWebView()
}

; Include modules
; ----------------------------------------------------

#Include ChatUtils.ahk
#Include StreamHandler.ahk
#Include ChatCallbacks_Message.ahk
#Include ChatCallbacks_Edit.ahk
#Include ChatCallbacks_Branch.ahk
#Include ChatCallbacks_Sidebar.ahk

; ----------------------------------------------------
; Load WebView
; ----------------------------------------------------

responseWindow.Load("..\webui\index.html")

; ----------------------------------------------------
; Show window
; ----------------------------------------------------

showChatWindow(initialRequest := true) {
    if initialRequest {
        desiredW := 900
        desiredH := 680
        X := (A_ScreenWidth - desiredW) // 2
        Y := (A_ScreenHeight - desiredH) // 4
        chatWindow.Show(Format("x{} y{} w{} h{}", X, Y, desiredW, desiredH), "Chat")
    } else {
        chatWindow.Show()
    }
    if !WinActive("ahk_id " chatWindow.hWnd)
        chatWindow.Flash()
    Sleep 500
    postWebMessage("setTheme", [darkMode])
    postWebMessage("setFontFace", [responseWindowFontFace])
    if initialRequest && requestParams["mainScriptHiddenhWnd"] {
        CustomMessages.notifyResponseWindowState(CustomMessages.WM_CHAT_WINDOW_OPENED,
            requestParams["uniqueID"], chatWindow.hWnd, requestParams["mainScriptHiddenhWnd"])
    }
}

; Check if pre-warming (spawned hidden at Main.ahk startup)
prewarming := (A_Args.Length >= 2 && A_Args[2] = "prewarm")

if prewarming {
    ; Pre-warm mode: initialize WebView2 in background, stay hidden.
    ; Set window size/position now so it appears centered when shown.
    desiredW := 900
    desiredH := 680
    X := (A_ScreenWidth - desiredW) // 2
    Y := (A_ScreenHeight - desiredH) // 4
    WinMove(X, Y, desiredW, desiredH, "ahk_id " chatWindow.hWnd)
    ; Post config messages so they're ready when user opens.
    postWebMessage("setTheme", [darkMode])
    postWebMessage("setFontFace", [responseWindowFontFace])
    postWebMessage("setChatButtonsEnabled", true)
    ; Notify main script so it knows we exist (for WinShow later).
    CustomMessages.notifyResponseWindowState(CustomMessages.WM_CHAT_WINDOW_OPENED,
        requestParams["uniqueID"], chatWindow.hWnd, requestParams["mainScriptHiddenhWnd"])
} else {
    showChatWindow(true)
    postWebMessage("setChatButtonsEnabled", true)
}

; ----------------------------------------------------
; Load initial thread if passed via command-line arg
; (skip in prewarm mode — "prewarm" is not a thread ID)
; ----------------------------------------------------

if (A_Args.Length >= 2 && A_Args[2] != "" && A_Args[2] != "prewarm") {
    activeThreadId := A_Args[2]
    path := ChatDB.Msg_GetActivePath(activeThreadId)
    postWebMessage("initChatMode", buildStructuredMessagesFromPath(path))
    postThreadStats(activeThreadId)
    ; Clear loading state and check if we need to auto-fire LLM
    Sleep 500
    postWebMessage("setChatButtonsEnabled", true)
    
    ; Auto-trigger LLM if the last message is from the user (pending response)
    if path.Length > 0 && path[path.Length].role = "user" {
        chatHistoryJSONRequest := BuildAndWriteRequestFiles()
        if chatHistoryJSONRequest {
            postWebMessage("setChatButtonsEnabled", false)
            sendRequestToLLM(&chatHistoryJSONRequest)
        }
    }
}