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
defaults := SettingsHandler.GetDefaults()
merged := SettingsHandler.Merge(settings, defaults)
SettingsHandler.ApplyToGlobals(merged)
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

; Spawn ChatWindow hidden on startup — it initializes WebView2 and then hides itself
; The "prewarm" arg tells ChatWindow to stay hidden after init
mainScriptHiddenHwnd := WinExist("ahk_class AutoHotkey")
Run(Format('"{}" "{}" {} "prewarm"', A_AhkPath, A_ScriptDir "\chat\ChatWindow.ahk", mainScriptHiddenHwnd), , "Hide", &chatWindowPID)

; ----------------------------------------------------
; Chat window state (single persistent window)
; ----------------------------------------------------

_spawnChatWindow(threadId := "") {
    global chatWindowPID
    mainScriptHiddenHwnd := WinExist("ahk_class AutoHotkey")
    if threadId
        Run(Format('"{}" "{}" {} "{}"', A_AhkPath, A_ScriptDir "\chat\ChatWindow.ahk", mainScriptHiddenHwnd, threadId), , , &chatWindowPID)
    else
        Run(Format('"{}" "{}" {}', A_AhkPath, A_ScriptDir "\chat\ChatWindow.ahk", mainScriptHiddenHwnd), , , &chatWindowPID)
}

openChatWindow(threadId := "") {
    global chatWindowPID, chatWindowhWnd

    if IsSet(chatWindowhWnd) && chatWindowhWnd && WinExist("ahk_id " chatWindowhWnd) {
        WinShow("ahk_id " chatWindowhWnd)
        WinActivate("ahk_id " chatWindowhWnd)
        if threadId {
            CustomMessages.notifyLoadThread(threadId, chatWindowhWnd)
        }
    } else {
        _spawnChatWindow(threadId)
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
    global chatWindowPID

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
    if WinExist("ChatWindow.ahk ahk_class AutoHotkey") {
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
; Generate tray menu dynamically from DefaultSettings.ahk
; ----------------------------------------------------

TraySetIcon(iconOn)
A_TrayMenu.Delete()
A_TrayMenu.Add("📋 Open Chat Window", (*) => openChatWindow())
A_TrayMenu.Add("📝 New Chat", (*) => openChatWindow(ChatDB.Thread_Create()))
A_TrayMenu.Add()
for _, item in trayMenuItems {
    switch item.action {
        case "reload": A_TrayMenu.Add(item.menuText, (*) => Reload())
        case "exit":   A_TrayMenu.Add(item.menuText, (*) => ExitApp())
    }
}
A_IconTip := "LLM AutoHotkey Assistant"

; ----------------------------------------------------
; Create new instance of LLMRequestBuilder class
; ----------------------------------------------------

llmClient := LLMRequestBuilder(APIKey)

; ----------------------------------------------------
; Create Input Windows
; ----------------------------------------------------

; Create the command input window (rebuildable on settings updates so
; background/font/size edits apply live).
_rebuildInputWindow(onCommandInputSend)

; ----------------------------------------------------
; Initialize Suspend GUI
; ----------------------------------------------------

#Include app\SuspendBanner.ahk
_rebuildSuspendBanner()

; ----------------------------------------------------
; Register inter-process communication handlers
; ----------------------------------------------------

CustomMessages.registerHandlers("mainScript", handleLoadingState)

; Handle settings updated notification from ChatWindow
OnMessage(CustomMessages.WM_SETTINGS_UPDATED, (*) => (
    debugLog("[SETTINGS] Received settingsUpdated from ChatWindow, reloading..."),
    settings := SettingsHandler.Load(),
    defaults := SettingsHandler.GetDefaults(),
    merged := SettingsHandler.Merge(settings, defaults),
    SettingsHandler.ApplyToGlobals(merged),
    _rebuildSuspendBanner(),
    _rebuildInputWindow(onCommandInputSend),
    _registerAllHotkeys(),
    RuntimeResolver_ResolvePrimaryProvider(),
    ChatDB.Thread_PurgeExpired(),
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
SetTimer(InitApiLogsViewer, -2000)

; ----------------------------------------------------
; Usage Dashboard — inline in ChatWindow via IPC
; ----------------------------------------------------
#Include app\viewers\UsageDashboard.ahk

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
