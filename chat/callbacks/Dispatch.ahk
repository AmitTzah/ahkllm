; ======================================================
; ChatDispatch.ahk — WebMessage dispatch + callback includes
;
; Handles OnWebMessageReceived and includes all callback modules.
; Extracted from ChatWindow.ahk for cleaner separation.
; ======================================================

; Surface an error to both the debug log AND the chat UI.
; Callable from any callback — re-enables buttons and shows red banner.
_SurfaceError(context, err) {
    errorMsg := "[" context "] " err.Message
    debugLog("ERROR: " errorMsg "`nStack: " (err.HasProp("Stack") ? err.Stack : "none"), "ErrorHandler")
    postWebMessage("showError", { message: errorMsg })
    postWebMessage("setChatButtonsEnabled", true)
    startLoadingCursor(false)
}

OnWebMessageReceived(sender, args) {
    try {
        msg := args.TryGetWebMessageAsString()
        if !msg
            return
        parsed := jsongo.Parse(msg)
        action := parsed.Get("action", "")
        switch action {
            case "chatSend":
                handleChatSend(parsed)
            case "searchMessages":
                handleSearch(parsed)
            case "deleteAttachment":
                handleDeleteAttachment(parsed)
            case "retry":
                handleRetry(parsed)
            case "editMessage":
                handleEdit(parsed)
            case "deleteMessage":
                handleDelete(parsed.Get("id", ""))
            case "switchBranch":
                handleBranchSwitch(parsed)
            case "forkChat":
                handleFork(parsed.Get("id", ""))
            case "sidebarAction":
                handleSidebarAction(parsed)
            case "requestAssistantList":
                postAssistantsToWebView()
            case "updateModelSettings":
                handleModelSettingsUpdate(parsed)
            case "switchAssistant":
                handleSwitchAssistant(parsed)
            case "cancelStream":
                handleCancelStream()
            case "hideWindow":
                global chatWindow
                chatWindow.Hide()
            case "requestCurrentSettings":
                postCurrentSettingsToWebView()
            case "showApiLogs":
                debugLog("[DISPATCH] showApiLogs received, sending IPC to Main")
                CustomMessages.notifyShowApiLogs(requestParams["mainScriptHiddenhWnd"])
            case "webViewReady":
                _OnWebViewReady()
            case "requestAllSettings":
                _HandleRequestAllSettings()
            case "requestDefaultSettings":
                _HandleRequestDefaultSettings()
            case "saveSettings":
                _HandleSaveSettings(parsed)
            case "refreshModelPricing":
                _HandleRefreshModelPricing()
            case "reloadScript":
                CustomMessages.notifyReloadMain(requestParams["mainScriptHiddenhWnd"])
            case "browseIcon":
                _HandleBrowseIcon(parsed)
            case "debugLog":
                debugLog(parsed.Get("message", ""), "WebUI")
            case "updateFontSize":
                handleUpdateFontSize(parsed)
        }
    } catch Error as e {
        _SurfaceError("Dispatch." (IsSet(action) ? action : "unknown"), e)
    }
}

; WebView just loaded/reloaded — send current thread data if one exists.
; Replaces sessionStorage-based recovery with DB as single source of truth.
_OnWebViewReady() {
    global activeThreadId
    if activeThreadId
        _LoadThreadAndRefreshUI(activeThreadId)
}

; Send full settings (merged with defaults) to WebView
_HandleRequestAllSettings() {
    defaults := SettingsHandler.GetDefaults()
    loaded := SettingsHandler.Load()
    merged := SettingsHandler.Merge(loaded, defaults)
    postWebMessage("currentSettings", merged)
}

; Send raw defaults (not merged with loaded) to WebView for Reset button.
; Also saves the defaults immediately so the chat process reloads fresh model data.
_HandleRequestDefaultSettings() {
    defaults := SettingsHandler.GetDefaults()
    ; Save and apply defaults immediately — bypass merge with stale loaded data
    if SettingsHandler.Save(defaults) {
        SettingsHandler.ApplyToGlobals(defaults)
        postAssistantsToWebView()
        postCurrentSettingsToWebView()  ; refresh thinking levels for current model
        try {
            CustomMessages.notifySettingsUpdated(requestParams["mainScriptHiddenhWnd"])
        } catch Error as e2 {
            debugLog("[SETTINGS] Failed to notify Main process: " e2.Message)
        }
    }
    postWebMessage("defaultSettings", defaults)
}

; Save settings from WebView, write to JSON, notify Main process
_HandleSaveSettings(parsed) {
    settingsData := parsed.Get("data", "")
    if !settingsData {
        postWebMessage("settingsSaved", { success: false, error: "No data received" })
        return
    }
    try {
        ; Convert jsongo object to AHK Map
        settingsMap := SettingsHandler._ToMap(settingsData)
        ; Merge into (saved file + defaults) so keys the UI didn't send keep saved values
        base := SettingsHandler.Merge(SettingsHandler.Load(), SettingsHandler.GetDefaults())
        merged := SettingsHandler.Merge(settingsMap, base)
        if SettingsHandler.Save(merged) {
            ; Apply to this process's globals
            SettingsHandler.ApplyToGlobals(merged)
            ; Push updated assistant list (and model list) to the chat sidebar
            postAssistantsToWebView()
            ; Refresh thinking levels for current model
            postCurrentSettingsToWebView()
            ; Notify Main process to reload
            try {
                CustomMessages.notifySettingsUpdated(requestParams["mainScriptHiddenhWnd"])
            } catch Error as e2 {
                debugLog("[SETTINGS] Failed to notify Main process: " e2.Message)
            }
            postWebMessage("settingsSaved", { success: true })
        } else {
            postWebMessage("settingsSaved", { success: false, error: "Failed to write settings.json" })
        }
    } catch Error as e {
        debugLog("[SETTINGS] Save error: " e.Message " at line " e.Line)
        postWebMessage("settingsSaved", { success: false, error: e.Message })
    }
}

; Run PowerShell pricing refresh and return results
_HandleRefreshModelPricing() {
    scriptPath := A_ScriptDir "\..\scripts\Refresh-Models.ps1"
    if !FileExist(scriptPath) {
        postWebMessage("modelPricingRefresh", { success: false, error: "scripts\Refresh-Models.ps1 not found" })
        return
    }
    try {
        cmd := "powershell -ExecutionPolicy Bypass -File `"" scriptPath "`""
        RunWait(cmd, A_ScriptDir, "Hide")
        ; Read the output file
        pricingFile := A_ScriptDir "\..\models_pricing.txt"
        if !FileExist(pricingFile) {
            postWebMessage("modelPricingRefresh", { success: false, error: "models_pricing.txt not generated" })
            return
        }
        content := FileRead(pricingFile, "UTF-8")
        ; Parse models from the file — extract the models := Map(...) block
        models := _ParsePricingFile(content)
        postWebMessage("modelPricingRefresh", { success: true, models: models })
    } catch Error as e {
        postWebMessage("modelPricingRefresh", { success: false, error: e.Message })
    }
}

; Parse models_pricing.txt to extract model entries for the refresh popup
_ParsePricingFile(content) {
    ; Find the models := Map( ... ) block
    result := []
    ; Simple line-by-line parser for "provider/model", { ... } entries
    inBlock := false
    currentModel := ""
    for line in StrSplit(content, "`n", "`r") {
        line := Trim(line)
        if line = "" || InStr(line, ";") = 1
            continue
        if InStr(line, "models := Map(")
            inBlock := true
        else if inBlock && line = ")"
            break
        else if inBlock {
            ; Look for "provider/model", { ... } pattern
            if InStr(line, ", {") || InStr(line, "`, {") {
                ; Model name is before the comma
                modelPart := StrSplit(line, [",", "`,"])
                modelName := Trim(Trim(modelPart[1]), "`" ")
                if modelName != "" {
                    result.Push({ id: modelName, raw: line })
                }
            }
        }
    }
    return result
}

_HandleBrowseIcon(parsed) {
    field := parsed.Get("field", "")
    if field != "iconOn" && field != "iconOff"
        return
    selected := FileSelect(3, A_ScriptDir "\..\icons", "Select icon file", "Icon Files (*.ico)")
    if !selected
        return
    ; Store path relative to repo root when possible (settings.json uses e.g. "icons\IconOn.ico")
    repoRoot := A_ScriptDir "\.."
    if InStr(selected, repoRoot) = 1
        selected := SubStr(selected, StrLen(repoRoot) + 2)
    postWebMessage("iconFileSelected", { field: field, path: selected })
}

#Include Message.ahk
#Include Edit.ahk
#Include Branch.ahk
#Include Sidebar.ahk
#Include Search.ahk
