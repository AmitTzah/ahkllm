#Include <Config>
#SingleInstance

; ----------------------------------------------------
; Clear diagnostic debug log from previous session
; ----------------------------------------------------

debugLogFile := A_Temp "\LLM_Debug_Log.txt"
if FileExist(debugLogFile) {
    FileDelete(debugLogFile)
}

debugLog("[APP] Started")

; ----------------------------------------------------
; Load settings from settings.json (fall back to DefaultSettings.ahk)
; ----------------------------------------------------
settings := SettingsHandler.Load()
SettingsHandler.CacheInitialDefaults()
SettingsService.Apply(SettingsHandler.Merge(settings, SettingsHandler.GetDefaults()))
RuntimeResolver_CheckApiKeys()
RuntimeResolver_ResolvePrimaryProvider()
debugLog("[APP] Settings loaded" (settings.Count ? " from settings.json" : " from DefaultSettings"))
; Global error handler for main script — surfaces to tooltip + debug log.
; Returns true so AHK does not ALSO show a modal error dialog: a modal dialog
; blocks the app (and the headless harness) on background/async errors like
; WebView2 teardown races, and the log + tooltip already carry the details.
; The lambda body is a comma expression (AHK v2 fat arrows cannot take a block);
; the trailing `true` is the return value, which tells AHK not to ALSO show a
; modal error dialog (the log + tooltip already carry the details).
OnError((err, mode) => (
    debugLog("RUNTIME ERROR (main): " err.Message "`nStack: " (err.HasProp("Stack") ? err.Stack : "none"), "ErrorHandler"),
    ToolTip("Error: " err.Message, , , 19),
    SetTimer(() => ToolTip(, , , 19), -5000),
    true
), -1)

; ----------------------------------------------------
; Hotkeys (registered dynamically via HotkeyRegistrar)
; ----------------------------------------------------

#Include app\HotkeyRegistrar.ahk

; Register initial hotkeys after globals are populated
_registerAllHotkeys()

; ----------------------------------------------------
; Initialize Chat DB (persistent chat history)
;
; ChatDB is also opened by ChatWindow.ahk (separate process).
; Both processes need direct DB access: Main creates threads/messages
; for new commands; ChatWindow loads threads and saves responses.
; SQLite WAL mode allows safe concurrent access between processes.
; ----------------------------------------------------

ChatDB.Open()

; Main owns the only backup lifecycle. ChatWindow forwards durable-change
; notifications here because it has its own SQLite connection.
global gBackupManager := BackupManager()
gBackupManager.Init(SettingsHandler.Merge(settings, SettingsHandler.GetDefaults()))
SettingsService.RegisterHook("backup", gBackupManager.ApplySettings.Bind(gBackupManager))
OnMessage(CustomMessages.WM_BACKUP_DIRTY, (*) => gBackupManager.MarkDirty())
_handleBackupNow(*) {
    global gBackupManager
    config := CustomMessages.consumeBackupNowConfig()
    ; ChatWindow persists the displayed backup config before posting this
    ; message. The request-file handoff is the fast path; if it is missing or
    ; unreadable, recover the same committed config from settings.json in every
    ; environment rather than falling back only in the E2E harness.
    if !IsObject(config) {
        fallbackSettings := SettingsService.LoadMerged()
        if fallbackSettings.Has("backup")
            config := fallbackSettings["backup"]
    }
    gBackupManager.BackupNow(false, config)
}
OnMessage(CustomMessages.WM_BACKUP_NOW, _handleBackupNow)
OnMessage(CustomMessages.WM_BACKUP_STATUS_REQUEST, (*) => gBackupManager.PublishStatus())

; ----------------------------------------------------
; Trash retention — auto-purge expired trashed threads
; ----------------------------------------------------

; Purge once at startup so threads past their retention period don't survive
; a restart, then keep checking on a timer (settings changes below re-purge
; immediately so lowering retention takes effect without waiting for the tick).
TrashRetentionPurge() {
    ChatDB.Thread_PurgeExpired()
}
ChatDB.Thread_PurgeExpired()
SetTimer(TrashRetentionPurge, 3600000)

; ----------------------------------------------------
; Pre-warm ChatWindow: spawn hidden at startup so WebView2
; is initialized before user first opens it (avoids black flash)
; ----------------------------------------------------
global chatWindowPID := 0
global chatWindowhWnd := 0
global chatOpeningCount := 0

; E2E workers run several Main copies in parallel. The worker token is passed
; through to ChatWindow's command line so headless probes and cleanup can target
; the right process without touching another worker or the user's own app.
_e2eWorkerArg() {
    worker := EnvGet("AHKLLM_E2E_WORKER")
    return worker != "" ? ' "--e2e-worker=' worker '"' : ""
}

; Spawn ChatWindow hidden on startup — it initializes WebView2 and then hides itself
; The "prewarm" arg tells ChatWindow to stay hidden after init
; Resolve Main's own script window, not an arbitrary AutoHotkey v2
; script window" - the user may run other AHK scripts, and WinExist on the
; class alone can return one of THEIR windows, so ChatWindow's settings-
; updated/loading/reload IPC would be posted to the wrong process and
; silently dropped.
mainScriptHiddenHwnd := A_ScriptHwnd
Run(Format('"{}" "{}" {} "prewarm"{}', A_AhkPath, A_ScriptDir "\chat\ChatWindow.ahk", mainScriptHiddenHwnd, _e2eWorkerArg()), , "Hide", &chatWindowPID)

; ----------------------------------------------------
; Chat window state (single persistent window)
; ----------------------------------------------------

_spawnChatWindow(threadId := "", activate := true) {
    global chatWindowPID
    ; A_ScriptHwnd is Main's own hidden window.
    mainScriptHiddenHwnd := A_ScriptHwnd
    if threadId {
        noActivateArg := activate ? "" : ' "noactivate"'
        Run(Format('"{}" "{}" {} "{}"{}{}', A_AhkPath, A_ScriptDir "\chat\ChatWindow.ahk", mainScriptHiddenHwnd, threadId, noActivateArg, _e2eWorkerArg()), , , &chatWindowPID)
    }
    else {
        workerArg := _e2eWorkerArg()
        if workerArg
            Run(Format('"{}" "{}" {} ""{}', A_AhkPath, A_ScriptDir "\chat\ChatWindow.ahk", mainScriptHiddenHwnd, workerArg), , , &chatWindowPID)
        else
            Run(Format('"{}" "{}" {}', A_AhkPath, A_ScriptDir "\chat\ChatWindow.ahk", mainScriptHiddenHwnd), , , &chatWindowPID)
    }
}

prepareChatWindow() {
    global chatWindowhWnd
    if IsSet(chatWindowhWnd) && chatWindowhWnd && WinExist("ahk_id " chatWindowhWnd)
        WinHide("ahk_id " chatWindowhWnd)
}

beginChatOpeningIndicator() {
    global chatOpeningCount
    chatOpeningCount++
    updateLoadingUI("Loading")
    CoordMode("ToolTip", "Screen")
    _followChatOpeningTooltip()
    SetTimer(_followChatOpeningTooltip, 30)
}

endChatOpeningIndicator() {
    global chatOpeningCount
    if chatOpeningCount > 0
        chatOpeningCount--
    if chatOpeningCount = 0 {
        SetTimer(_followChatOpeningTooltip, 0)
        ToolTip(,,, 20)
        updateLoadingUI("Reset")
    }
}

; Keep the command-progress tooltip anchored to the cursor. ToolTipEX's
; generic follow mode can lag or jump when the pointer moves quickly, while a
; short screen-coordinate update keeps this transient indicator smooth.
_followChatOpeningTooltip(*) {
    global chatOpeningCount
    if !chatOpeningCount {
        SetTimer(_followChatOpeningTooltip, 0)
        ToolTip(,,, 20)
        return
    }
    MouseGetPos(&x, &y)
    ToolTip("Opening chat...", x + 16, y + 16, 20)
}

openChatWindow(threadId := "", activate := true) {
    global chatWindowPID, chatWindowhWnd

    if IsSet(chatWindowhWnd) && chatWindowhWnd && WinExist("ahk_id " chatWindowhWnd) {
        if threadId {
            ; Load the requested thread while the window is hidden. The
            ; ChatWindow process reveals it after the WebView has received the
            ; new thread state, so the previous chat cannot flash first.
            WinHide("ahk_id " chatWindowhWnd)
            CustomMessages.notifyLoadThread(threadId, chatWindowhWnd, activate)
        } else {
            WinShow("ahk_id " chatWindowhWnd)
            WinActivate("ahk_id " chatWindowhWnd)
        }
    } else {
        _spawnChatWindow(threadId, activate)
    }
}

; Handler for chat window opened notification
onChatWindowOpened(uniqueID, lParam, msg, hWnd) {
    global chatWindowhWnd
    chatWindowhWnd := lParam
}

; Clean up ChatWindow sub-process when Main.ahk exits
OnExit(closeChatWindow)
closeChatWindow(ExitReason, ExitCode) {
    debugLog("[APP] Exiting — reason=" ExitReason)
    global chatWindowPID, gBackupManager
    try gBackupManager.Shutdown()

    ; Close child ChatWindow process. Try graceful close first,
    ; then force kill. PID may be 0 if spawn failed.
    if (chatWindowPID && ProcessExist(chatWindowPID)) {
        try {
            if WinExist("ahk_pid " chatWindowPID)
                WinClose("ahk_pid " chatWindowPID)
            Sleep 300
        }
    }
    if (chatWindowPID && ProcessExist(chatWindowPID))
        ProcessClose(chatWindowPID)

    ; Fallback: kill by window title if PID tracking failed
    if EnvGet("AHKLLM_E2E_WORKER") = "" && WinExist("ChatWindow.ahk ahk_class AutoHotkey") {
        try {
            fallbackPID := WinGetPID("ChatWindow.ahk ahk_class AutoHotkey")
            WinClose("ChatWindow.ahk ahk_class AutoHotkey")
            Sleep 300
            if ProcessExist(fallbackPID)
                ProcessClose(fallbackPID)
        }
    }

    ; Close Main's own DB connection AFTER child process cleanup
    try ChatDB.Close()
}

; ----------------------------------------------------
; Generate tray menu + icon dynamically from DefaultSettings.ahk
; ----------------------------------------------------

#Include app\TrayIcon.ahk
#Include app\TrayMenu.ahk
_rebuildTrayIcon()
_rebuildTrayMenu()
A_IconTip := AppInfo.Name

; ----------------------------------------------------
; Create new instance of LLMRequestBuilder class
; ----------------------------------------------------

llmClient := LLMRequestBuilder(APIKey)

; ----------------------------------------------------
; Create Input Windows
; ----------------------------------------------------

; Create the command input window (rebuildable on settings updates so
; background/font/size edits apply live).
_rebuildInputWindow(onCommandInputSend, onCommandInputCancel)

; ----------------------------------------------------
; Initialize Suspend GUI
; ----------------------------------------------------

#Include app\SuspendBanner.ahk
_rebuildSuspendBanner()

; ----------------------------------------------------
; Settings update hooks — single apply path (SettingsService)
; ----------------------------------------------------
; SettingsService.Apply runs these after every settings reload. New settings-
; driven rebuilds register a hook here instead of adding another call site.
SettingsService.RegisterHook("trayIcon", _rebuildTrayIcon)
SettingsService.RegisterHook("trayMenu", _rebuildTrayMenu)
SettingsService.RegisterHook("suspendBanner", _rebuildSuspendBanner)
SettingsService.RegisterHook("inputWindow", _rebuildInputWindow.Bind(onCommandInputSend, onCommandInputCancel))
SettingsService.RegisterHook("hotkeys", _registerAllHotkeys.Bind(true))
SettingsService.RegisterHook("runtimeResolver", RuntimeResolver_ResolvePrimaryProvider)
; Hooks are invoked via fn.Call(); wrap static methods where AHK would bind them incorrectly.
; (ChatDB.Thread_PurgeExpired) throws "Missing a required parameter" in AHK v2
; (probe-verified: even .Bind() throws). Register the plain zero-arg wrapper
; instead, so lowering Trash Retention purges expired trash immediately.
SettingsService.RegisterHook("purgeExpired", TrashRetentionPurge)

; ----------------------------------------------------
; Register inter-process communication handlers
; ----------------------------------------------------

CustomMessages.registerHandlers("mainScript", handleLoadingState)

; Handle settings updated notification from ChatWindow
OnMessage(CustomMessages.WM_SETTINGS_UPDATED, (*) => (
    debugLog("[SETTINGS] Received settingsUpdated from ChatWindow, reloading..."),
    SettingsService.ReloadFromDisk(),
    gBackupManager.MarkDirty(),
    debugLog("[SETTINGS] Reloaded settings globals and re-registered hotkeys")
))

; Reload request from ChatWindow (e.g. "Restart Now" after hotkey changes).
; Main's normal exit path force-kills the ChatWindow process.
OnMessage(CustomMessages.WM_RELOAD_MAIN, (*) => Reload())

; ----------------------------------------------------
; Include application modules
; ----------------------------------------------------

#Include app\TextCapture.ahk
#Include app\InlineRequestRunner.ahk
#Include app\menu\CommandMenu.ahk
#Include app\menu\CommandState.ahk
#Include app\RequestProcessor.ahk
#Include app\LoadingTracker.ahk
#Include app\LoadingUI.ahk

; ----------------------------------------------------
; API Logs Viewer — persistent, pre-created at startup
; ----------------------------------------------------
#Include app\viewers\ApiLogsViewer.ahk
if EnvGet("AHKLLM_E2E_WORKER") = ""
    SetTimer(InitApiLogsViewer, -2000)

; ----------------------------------------------------
; Usage Dashboard — inline in ChatWindow via IPC
; ----------------------------------------------------
#Include app\viewers\UsageDashboard.ahk

; Settings panel — inline in ChatWindow via IPC
; ----------------------------------------------------
#Include app\viewers\SettingsPanel.ahk

; ----------------------------------------------------
; UIA COM initialization sets SPI_SETSCREENREADER
; (a system-wide flag) during CoCreateInstance. This
; causes Word to switch to accessibility rendering
; (solid black selection highlight). We monitor and
; reset the flag immediately after UIA initializes.
; Once reset, the timer deactivates itself.
; ----------------------------------------------------
ResetScreenReaderOnInit() {
    DllCall("user32.dll\SystemParametersInfo", "uint", 0x0046, "uint", 0, "ptr*", &state:=0, "uint", 0)
    if state {
        DllCall("user32.dll\SystemParametersInfo", "uint", 0x0047, "uint", 0, "uint", 0, "int", 2)
        SetTimer(, 0)  ; deactivate this timer — job done
    }
}
SetTimer(ResetScreenReaderOnInit, 500)
OnExit(CloseApiLogsViewer)
