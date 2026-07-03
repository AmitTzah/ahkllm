#Requires AutoHotkey v2.0.18+
#Include ..\UserConfig.ahk        ; All user-facing configuration
#Include Dark_MsgBox.ahk                  ; Dark mode MsgBox and InputBox
#Include Dark_Menu.ahk                    ; Dark mode menus
#Include SystemThemeAwareToolTip.ahk       ; Dark mode tooltips
#Include WebViewToo.ahk             ; WebView2 Framework for Web-based GUIs
#Include jsongo.v2.ahk              ; JSON parsing
#Include AutoXYWH.ahk               ; Auto-resizing of GUI controls
#Include ToolTipEx.ahk              ; Tooltip tracking and dragging
DetectHiddenWindows true            ; Enables detection of hidden windows for inter-process communication

; ----------------------------------------------------
; LLM Client (OpenAI-compatible API)
; ----------------------------------------------------

class LLMClient {
    ; Chat completions cURL template
    static cURLCommand :=
        'cURL.exe -s -X POST ' APIEndpoint ' '
        . '-H "Authorization: Bearer {1}" '
        . '-H "Content-Type: application/json" '
        . '-d @"{2}" '
        . '-o "{3}"'

    ; FIM (Fill In the Middle) cURL template — uses the DeepSeek beta endpoint
    static FIMcURLCommand :=
        'cURL.exe -s -X POST ' FIMEndpoint ' '
        . '-H "Authorization: Bearer {1}" '
        . '-H "Content-Type: application/json" '
        . '-d @"{2}" '
        . '-o "{3}"'

    __New(APIKey) {
        this.APIKey := APIKey
    }

    createJSONRequest(APIModel, systemPrompt, userPrompt, temperature := "", maxTokens := "", stop := "") {
        requestObj := {}
        requestObj.model := APIModel
        requestObj.messages := [{ role: "user", content: userPrompt }]
        if systemPrompt != "" {
            requestObj.messages.InsertAt(1, { role: "system", content: systemPrompt })
        }
        if temperature != ""
            requestObj.temperature := temperature
        if maxTokens != ""
            requestObj.max_tokens := maxTokens
        if stop != "" && stop.Length > 0
            requestObj.stop := stop
        return jsongo.Stringify(requestObj)
    }

    extractJSONResponse(var) {
        response := var.Get("choices")[1].Get("message").Get("content")
        model := var.Get("model")
        return {
            response: response,
            model: model
        }
    }

    extractErrorResponse(var) {
        error := var.Get("error").Get("message")
        code := var.Get("error").Get("code")
        return {
            error: error,
            code: code,
        }
    }

    appendToChatHistory(role, message, &chatHistoryJSONRequest, chatHistoryJSONRequestFile) {
        obj := jsongo.Parse(chatHistoryJSONRequest)
        obj["messages"].Push({
            role: role,
            content: message
        })
        chatHistoryJSONRequest := jsongo.Stringify(obj)
        FileOpen(chatHistoryJSONRequestFile, "w", "UTF-8-RAW").Write(chatHistoryJSONRequest)
    }

    getMessages(obj) {
        messages := []
        for i in obj["messages"] {
            messages.Push({
                role: i["role"],
                content: i["content"]
            })
        }
        return messages
    }

    removeLastAssistantMessage(&chatHistoryJSONRequest) {
        obj := jsongo.Parse(chatHistoryJSONRequest)
        messagesArray := obj["messages"]
        lastIndex := messagesArray.Length
        if (messagesArray[lastIndex]["role"] = "assistant") {
            messagesArray.RemoveAt(lastIndex)
        }
        chatHistoryJSONRequest := jsongo.Stringify(obj)
    }

    buildcURLCommand(chatHistoryJSONRequestFile, cURLOutputFile) {
        return Format(LLMClient.cURLCommand, this.APIKey, chatHistoryJSONRequestFile, cURLOutputFile)
    }

    ; ----------------------------------------------------
    ; FIM-specific methods (Fill In the Middle)
    ; ----------------------------------------------------

    ; Builds the FIM JSON request: {model, prompt, suffix?, max_tokens}
    createFIMRequest(APIModel, prefix, suffix, temperature := "", maxTokens := "", stop := "") {
        maxTokens := (maxTokens != "") ? maxTokens : FIMMaxTokens
        requestObj := { model: APIModel, prompt: prefix, max_tokens: maxTokens }
        if (suffix != "") {
            requestObj.suffix := suffix
        }
        if temperature != ""
            requestObj.temperature := temperature
        if stop != "" && stop.Length > 0
            requestObj.stop := stop
        return jsongo.Stringify(requestObj)
    }

    ; Extracts FIM response: choices[0].text
    extractFIMResponse(var) {
        response := var.Get("choices")[1].Get("text")
        model := var.Get("model")
        return {
            response: response,
            model: model
        }
    }

    ; Builds the cURL command for the FIM endpoint
    buildFIMcURLCommand(chatHistoryJSONRequestFile, cURLOutputFile) {
        return Format(LLMClient.FIMcURLCommand, this.APIKey, chatHistoryJSONRequestFile, cURLOutputFile)
    }

    ; ----------------------------------------------------
    ; API request/response logging
    ; ----------------------------------------------------
    ;
    ; Logs a single API interaction to %TEMP%\LLM_API_Log.json.
    ; The log is capped at apiLogMaxEntries entries (newest first).
    ; Set apiLogMaxEntries to 0 to disable logging entirely.
    ;
    static logFilePath := A_Temp "\LLM_API_Log.json"

    static LogRequest(entry) {
        if (apiLogMaxEntries <= 0) {
            return
        }

        logs := []
        if FileExist(this.logFilePath) {
            try {
                logs := jsongo.Parse(FileOpen(this.logFilePath, "r", "UTF-8-RAW").Read())
            }
        }

        ; Add timestamp if not already present
        if !entry.HasProp("timestamp") || entry.timestamp = "" {
            entry.timestamp := FormatTime(, "yyyy-MM-dd HH:mm:ss")
        }

        logs.InsertAt(1, entry)

        ; Trim oldest entries to stay within the configured limit
        while logs.Length > apiLogMaxEntries {
            logs.RemoveAt(logs.Length)
        }

        FileOpen(this.logFilePath, "w", "UTF-8-RAW").Write(jsongo.Stringify(logs))
    }

    ; Reads the log file and returns the entries array (newest first).
    static ReadLogs() {
        logs := []
        if FileExist(this.logFilePath) {
            try {
                logs := jsongo.Parse(FileOpen(this.logFilePath, "r", "UTF-8-RAW").Read())
            }
        }
        return logs
    }

    ; Clears the log file entirely.
    static ClearLogs() {
        if FileExist(this.logFilePath) {
            FileDelete(this.logFilePath)
        }
    }

    ; Returns the path to the log file (for reference/display).
    static GetLogFilePath() {
        return this.logFilePath
    }
}

; ----------------------------------------------------
; Input Window
; ----------------------------------------------------

class InputWindow {
    __New(windowTitle, skipConfirmation := false) {
        this.inputWindowSkipConfirmation := skipConfirmation

        ; Create Input Window — uses settings from UserConfig.ahk
        this.guiObj := Gui("Resize", windowTitle)
        this.guiObj.OnEvent("Close", this.closeButtonAction.Bind(this))
        this.guiObj.OnEvent("Escape", this.closeButtonAction.Bind(this))
        this.guiObj.OnEvent("Size", this.resizeAction.Bind(this))
        if (darkMode) {
            this.guiObj.BackColor := inputWindowBackground
            this.guiObj.SetFont(inputWindowFontSize " " inputWindowFontColor, inputWindowFontFace)
            this.EditControl := this.guiObj.Add("Edit", "x20 y+5 w" inputWindowWidth " h" inputWindowHeight " Background" inputWindowBackground)
        } else {
            this.guiObj.SetFont(inputWindowFontSize " cDefault", inputWindowFontFace)
            this.EditControl := this.guiObj.Add("Edit", "x20 y+5 w" inputWindowWidth " h" inputWindowHeight)
        }
        this.SendButton := this.guiObj.Add("Button", "x240 y+10 w80", "Send")

        ; Apply dark mode to title bar
        ; Reference: https://www.autohotkey.com/boards/viewtopic.php?p=422034#p422034
        if (darkMode) {
            DllCall("Dwmapi\DwmSetWindowAttribute", "ptr", this.guiObj.hWnd, "int", 20, "int*", true, "int", 4)
        }

        ; Apply dark mode to Send button and Edit control
        if (darkMode) {
            for ctrl in [this.SendButton, this.EditControl] {
                DllCall("uxtheme\SetWindowTheme", "ptr", ctrl.hWnd, "str", "DarkMode_Explorer", "ptr", 0)
            }
        }
    }

    showInputWindow(message := "", title := unset, windowID := unset) {
        this.EditControl.Value := message
        if IsSet(title) {
            this.guiObj.Title := title
        }

        this.EditControl.Focus()
        this.guiObj.Show("AutoSize")
        if IsSet(windowID) {
            ControlSend("^{End}", "Edit1", windowID)
        }
    }

    validateInputAndHide(*) {
        if !this.EditControl.Value {
            MsgBox "Please enter a message or close the window.", "No text entered", "IconX"
            return false
        }
        this.guiObj.Hide
        return true
    }

    sendButtonAction(functionToCall) {
        this.SendButton.OnEvent("Click", functionToCall.Bind(this))
    }

    closeButtonAction(*) {
        if this.inputWindowSkipConfirmation || (MsgBox("Close " this.guiObj.Title " window?", this.guiObj.Title, 308) = "Yes") {
            this.EditControl.Value := ""
            this.guiObj.Hide
            return
        }

        return true
    }

    resizeAction(*) {
        AutoXYWH("wh", this.EditControl)
        AutoXYWH("x0.5 y", this.SendButton)
    }

    setSkipConfirmation(value) {
        this.inputWindowSkipConfirmation := value
    }
}

; ----------------------------------------------------
; Custom messages
; ----------------------------------------------------

class CustomMessages {
    static WM_RESPONSE_WINDOW_OPENED := 0x400 + 125
    static WM_RESPONSE_WINDOW_CLOSED := 0x400 + 126
    static WM_SEND_TO_ALL_MODELS := 0x400 + 127
    static WM_RESPONSE_WINDOW_LOADING_START := 0x400 + 123
    static WM_RESPONSE_WINDOW_LOADING_FINISH := 0x400 + 124

    static registerHandlers(origin, handle) {
        switch origin {
            case "mainScript":
                for msg in [this.WM_RESPONSE_WINDOW_OPENED, this.WM_RESPONSE_WINDOW_CLOSED, this.WM_RESPONSE_WINDOW_LOADING_START,
                    this.WM_RESPONSE_WINDOW_LOADING_FINISH]
                    OnMessage(msg, handle)

            case "subScript": OnMessage(this.WM_SEND_TO_ALL_MODELS, handle)
        }
    }

    static notifyResponseWindowState(state, uniqueID, responseWindowhWnd := unset, mainScriptHiddenhWnd := unset) {
        switch state {
            case this.WM_RESPONSE_WINDOW_OPENED, this.WM_RESPONSE_WINDOW_CLOSED:
                PostMessage(state, uniqueID, responseWindowhWnd, , "ahk_id " mainScriptHiddenhWnd)
            case this.WM_SEND_TO_ALL_MODELS:
                PostMessage(state, uniqueID, 0, , "ahk_id " responseWindowhWnd)
            case this.WM_RESPONSE_WINDOW_LOADING_START, this.WM_RESPONSE_WINDOW_LOADING_FINISH:
                PostMessage(state, uniqueID, 0, , "ahk_id " mainScriptHiddenhWnd)
        }
    }
}
