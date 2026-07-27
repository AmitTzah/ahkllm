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
; Load settings from settings.json (fall back to UserConfig.ahk defaults)
; ----------------------------------------------------
settings := SettingsHandler.Load()
defaults := SettingsHandler.GetDefaults()
merged := SettingsHandler.Merge(settings, defaults)
SettingsHandler.ApplyToGlobals(merged)
RuntimeResolver_CheckApiKeys()
RuntimeResolver_ResolvePrimaryProvider()
RuntimeResolver_ResolveDefaultAssistant()
debugLog("[APP] Settings loaded" (settings.Count ? " from settings.json" : " from UserConfig defaults"))
; Global error handler for main script — surfaces to tooltip + debug log
OnError((err, mode) => (
    debugLog("RUNTIME ERROR (main): " err.Message "`nStack: " (err.HasProp("Stack") ? err.Stack : "none"), "ErrorHandler"),
    ToolTip("Error: " err.Message, , , 19),
    SetTimer(() => ToolTip(, , , 19), -5000)
), -1)

; ----------------------------------------------------
; Hotkeys (registered dynamically from UserConfig.ahk)
; ----------------------------------------------------

Hotkey(mainHotkey, (*) => handleHotkey("showCommandMenu"))
Hotkey(saveReloadHotkey, (*) => handleHotkey("saveAndReloadScript"))
Hotkey(closeWindowsHotkey, (*) => handleHotkey("closeWindows"))
Hotkey(suspendHotkey, (*) => handleHotkey("suspendHotkey"), "S")

handleHotkey(action) {
    try {
    switch action {
        case "showCommandMenu":
            buildCommandMenu()

        case "suspendHotkey":
            KeyWait "CapsLock", "L"
            SetCapsLockState "Off"
            toggleSuspend(A_IsSuspended)

        case "saveAndReloadScript":
            if !WinActive("UserConfig.ahk") {
                return
            }

            ; Small delay to ensure file operations are complete
            Sleep 100

            if (getActiveModels().Count > 0) {
                MsgBox("Script will automatically reload once the chat window is closed.",
                    "LLM AutoHotkey Assistant", 64)
                handleLoadingState(0, 0, "reloadScript", 0)
            } else {
                Reload()
            }

        case "closeWindows":
            switch WinActive("A") {
                case commandInputWindow.guiObj.hWnd: commandInputWindow.closeButtonAction()
            }
    }
    } catch Error as e {
        debugLog("ERROR in handleHotkey(" action "): " e.Message "`n" e.Stack, "ErrorHandler")
        ToolTip("Error: " e.Message, , , 19)
        SetTimer(() => ToolTip(, , , 19), -5000)
    }
}

; ----------------------------------------------------
; Initialize Chat DB (persistent chat history)
;
; ChatDB is also opened by ChatWindow.ahk (separate process).
; Both processes need direct DB access: Main creates threads/messages
; for new commands; ChatWindow loads threads and saves responses.
; SQLite WAL mode allows safe concurrent access between processes.
; ----------------------------------------------------

ChatDB.Open()
ChatDB.Assistant_Seed()

; ----------------------------------------------------
; Pre-warm ChatWindow: spawn hidden at startup so WebView2
; is initialized before user first opens it (avoids black flash)
; ----------------------------------------------------
global chatWindowPID := 0
global chatWindowhWnd := 0

; Spawn ChatWindow hidden on startup — it initializes WebView2 and then hides itself
; The "prewarm" arg tells ChatWindow to stay hidden after init
mainScriptHiddenhWnd := WinExist("ahk_class AutoHotkey")
Run(Format('"{}" "{}" {} "prewarm"', A_AhkPath, A_ScriptDir "\chat\ChatWindow.ahk", mainScriptHiddenhWnd), , "Hide", &chatWindowPID)

; ----------------------------------------------------
; Chat window state (single persistent window)
; ----------------------------------------------------

_spawnChatWindow(threadId := "") {
    global chatWindowPID
    mainScriptHiddenhWnd := WinExist("ahk_class AutoHotkey")
    if threadId
        Run(Format('"{}" "{}" {} "{}"', A_AhkPath, A_ScriptDir "\chat\ChatWindow.ahk", mainScriptHiddenhWnd, threadId), , , &chatWindowPID)
    else
        Run(Format('"{}" "{}" {}', A_AhkPath, A_ScriptDir "\chat\ChatWindow.ahk", mainScriptHiddenhWnd), , , &chatWindowPID)
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
; Generate tray menu dynamically from UserConfig.ahk
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

commandInputWindow := InputWindow("Custom command")

; ----------------------------------------------------
; Register sendButtonActions
; ----------------------------------------------------

commandInputWindow.sendButtonAction(onCommandInputSend)

; ----------------------------------------------------
; Initialize Suspend GUI
; ----------------------------------------------------

suspendBanner := Gui()
suspendBanner.SetFont(suspendBannerFontSize, suspendBannerFontFace)
suspendBanner.Add("Text", suspendBannerTextColor " Center", suspendBannerText)
suspendBanner.BackColor := suspendBannerBackground
suspendBanner.Opt("-Caption +Owner -SysMenu +AlwaysOnTop")
suspendBannerWidth := ""
suspendBanner.GetPos(, , &suspendBannerWidth)

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
    debugLog("[SETTINGS] Reloaded settings globals")
))

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
