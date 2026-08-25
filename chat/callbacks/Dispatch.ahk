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
    global activeThreadId
    reqId := ""
    try {
        msg := args.TryGetWebMessageAsString()
        if !msg
            return
        parsed := jsongo.Parse(msg)
        action := parsed.Get("action", "")
        ; Correlation id (step 2 of the IPC refactor): every WebView request
        ; carries a reqId; the dispatch answers with an ack carrying the same
        ; id so the WebView can resolve promises and surface failures.
        reqId := parsed.Get("reqId", "")
        ; Locked-chat gate: actions that read or mutate the ACTIVE thread are
        ; rejected while it is locked (and not unlocked in this session).
        ; Content can never be reached through a side channel like the tree
        ; modal or the right-rail settings, and global search is filtered at
        ; the SQL level instead.
        ; ChatDB.isOpen guards the test harness (stale activeThreadId with a
        ; closed DB); production always has the DB open, so behavior is unchanged.
        if _IsLockedThreadContentAction(action, parsed) && IsSet(activeThreadId) && ChatDB.isOpen
            ThreadLockService.RequireUnlocked(activeThreadId)
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
                CustomMessages.notifyShowApiLogs(requestParams["mainScriptHiddenHwnd"])
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
                CustomMessages.notifyReloadMain(requestParams["mainScriptHiddenHwnd"])
            case "browseIcon":
                _HandleBrowseIcon(parsed)
            case "browseBackupFolder":
                _HandleBrowseBackupFolder(parsed)
            case "backupNow":
                _HandleBackupNow(parsed)
            case "debugLog":
                debugLog(parsed.Get("message", ""), "WebUI")
            case "updateFontSize":
                handleUpdateFontSize(parsed)
            case "unlockThread":
                handleUnlockThread(parsed)
            case "setThreadLock":
                handleSetThreadLock(parsed)
            case "lockChatNow":
                handleLockChatNow(parsed)
            case "dismissLockedThread":
                handleDismissLockedThread(parsed)
            case "getThreadLockInfo":
                handleGetThreadLockInfo(parsed)
        }
        _AckWebMessage(reqId, action, true, "")
    } catch Error as e {
        _SurfaceError("Dispatch." (IsSet(action) ? action : "unknown"), e)
        _AckWebMessage(reqId, IsSet(action) ? action : "unknown", false, e.Message)
    }
}

; True for actions whose handler reads or mutates the active thread's
; content/settings and must therefore be blocked while it is locked.
_IsLockedThreadContentAction(action, parsed) {
    switch action {
        case "chatSend", "retry", "editMessage", "deleteMessage", "deleteAttachment",
             "forkChat", "switchBranch", "updateModelSettings", "switchAssistant",
             "updateFontSize", "requestCurrentSettings":
            return true
        case "searchMessages":
            ; Global search is filtered at the SQL level (locked chats never
            ; match); scoped search of a locked thread is blocked.
            return parsed.Has("threadId")
        case "sidebarAction":
            sub := parsed.Has("subAction") ? parsed["subAction"] : ""
            ; loadTree renders the ACTIVE thread's tree; navigateToMessage and
            ; loadThread are already gated by _LoadThreadAndRefreshUI.
            return sub = "loadTree"
    }
    return false
}

; Acknowledge a WebView request. Only sent when the request carried a reqId
; (older ad-hoc posts are not acknowledged, keeping the contract opt-in).
_AckWebMessage(reqId, action, ok, errorMsg) {
    if reqId = ""
        return
    ack := { reqId: reqId, action: action, ok: ok }
    if errorMsg != ""
        ack.error := errorMsg
    postWebMessage("ack", ack)
}

; WebView just loaded/reloaded — send current thread data if one exists.
; Replaces sessionStorage-based recovery with DB as single source of truth.
_OnWebViewReady() {
    global activeThreadId
    ; Always re-enable the chat buttons on the ready handshake. The startup
    ; setChatButtonsEnabled posts in ChatWindow.ahk race the page load:
    ; WebView2 drops messages posted before the page installed its 'message'
    ; listener, which left the Send button unwired on those launches. The page
    ; posts webViewReady AFTER installing the listener, so this is the only
    ; reliable point to wire the UI.
    postWebMessage("setChatButtonsEnabled", true)
    ; The assistant/model list has the same race: ChatSettings.ahk pushes it
    ; on a one-shot 500ms timer at startup, and a slow page load drops that
    ; post, leaving the assistant picker (and _assistantList) empty until the
    ; user opens Settings. Re-push on the ready handshake — the one point we
    ; know the page is listening.
    postAssistantsToWebView()
    ; Bug #45: re-push the full merged settings so the page applies UI CSS
    ; vars (ui-theme.js sets --chat-font-family from ui.responseFont) at
    ; startup, without the user opening Settings.
    _HandleRequestAllSettings()
    if activeThreadId
        _LoadThreadAndRefreshUI(activeThreadId)
}

; Send full settings (merged with defaults) to WebView
_HandleRequestAllSettings() {
    defaults := SettingsHandler.GetDefaults()
    loaded := SettingsHandler.Load()
    merged := SettingsHandler.Merge(loaded, defaults)
    ; Step 3 of the IPC refactor: the full settings payload is a distinct
    ; message (appSettings) so it can never be mistaken for the right-rail
    ; per-thread payload (threadSettings).
    postWebMessage("appSettings", merged)
    if requestParams.Has("mainScriptHiddenHwnd")
        CustomMessages.notifyBackupStatusRequest(requestParams["mainScriptHiddenHwnd"])
}

; Send raw defaults (not merged with loaded) to WebView for Reset button.
; Also saves the defaults immediately so the chat process reloads fresh model data.
_HandleRequestDefaultSettings() {
    defaults := SettingsHandler.GetDefaults()
    ; Save and apply defaults immediately — bypass merge with stale loaded data
    if SettingsHandler.Save(defaults) {
        ; Apply + run registered update hooks (chat hotkeys re-register here).
        SettingsService.Apply(defaults)
        postAssistantsToWebView()
        postCurrentSettingsToWebView()  ; refresh thinking levels for current model
        try {
            CustomMessages.notifySettingsUpdated(requestParams["mainScriptHiddenHwnd"])
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
        ; Single apply path: merge (each section payload authoritative for its
        ; own top-level key), persist, apply globals, run update hooks.
        merged := SettingsService.SaveFromWebView(settingsData)
        if merged {
            ; Push updated assistant list (and model list) to the chat sidebar
            postAssistantsToWebView()
            ; Bug #45: re-push merged settings so UI CSS vars (e.g. the
            ; response font) apply immediately after a save, without reopening
            ; Settings.
            _HandleRequestAllSettings()
            ; Refresh thinking levels for current model
            postCurrentSettingsToWebView()
            ; Notify Main process to reload
            try {
                CustomMessages.notifySettingsUpdated(requestParams["mainScriptHiddenHwnd"])
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
        ; -NoPause: without it the script blocks on "Press any key" and hangs the hidden window
        cmd := "powershell -NoProfile -ExecutionPolicy Bypass -File `"" scriptPath "`" -NoPause"
        exitCode := RunWait(cmd, A_ScriptDir, "Hide")
        if exitCode != 0 {
            postWebMessage("modelPricingRefresh", { success: false, error: "Refresh-Models.ps1 exited with code " exitCode })
            return
        }
        ; Read the generated model metadata file the pipeline writes
        pricingFile := A_ScriptDir "\..\default-settings\DefaultModels.ahk"
        if !FileExist(pricingFile) {
            postWebMessage("modelPricingRefresh", { success: false, error: "DefaultModels.ahk not generated" })
            return
        }
        content := FileRead(pricingFile, "UTF-8")
        ; Parse models from the file — extract the models := Map(...) block
        models := ModelPricingParser.Parse(content)
        if models.Length = 0 {
            postWebMessage("modelPricingRefresh", { success: false, error: "No models parsed from DefaultModels.ahk" })
            return
        }
        postWebMessage("modelPricingRefresh", { success: true, models: models })
    } catch Error as e {
        postWebMessage("modelPricingRefresh", { success: false, error: e.Message })
    }
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

_HandleBrowseBackupFolder(parsed) {
    current := parsed.Get("folder", "")
    ; AutoHotkey's numeric mode 2 is a save-file dialog. Use the explicit
    ; directory mode so Browse cannot select a backup file; also discard a
    ; stale/typed file path as the dialog's starting directory.
    currentDir := DirExist(current) ? current : ""
    selected := FileSelect("D", currentDir, "Select AHKLLM backup folder")
    if selected
        postWebMessage("backupFolderSelected", { folder: selected })
}

_HandleBackupNow(parsed) {
    config := parsed.Get("backup", "")
    if !IsObject(config)
        throw Error("backupNow requires the currently displayed backup configuration")
    merged := SettingsService.SaveFromWebView({ backup: config })
    if !merged
        throw Error("could not persist the backup configuration")
    ; The config is persisted/applied in this process and is also sent
    ; explicitly to Main. Do not send a second settings-updated notification:
    ; that notification can race after the manual backup and leave the just-
    ; completed backup falsely pending for the settings change itself.
    if !CustomMessages.notifyBackupNow(requestParams["mainScriptHiddenHwnd"], config)
        throw Error("could not send the manual backup request to Main")
}

#Include Message.ahk
#Include Edit.ahk
#Include Branch.ahk
#Include Sidebar.ahk
#Include Search.ahk
#Include Lock.ahk
