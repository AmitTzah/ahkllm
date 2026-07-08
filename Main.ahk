#Include <Config>
#SingleInstance

; ----------------------------------------------------
; Clear diagnostic debug log from previous session
; ----------------------------------------------------

debugLogFile := A_Temp "\LLM_Debug_Log.txt"
if FileExist(debugLogFile) {
    FileDelete(debugLogFile)
}

; ----------------------------------------------------
; Hotkeys (registered dynamically from UserConfig.ahk)
; ----------------------------------------------------

Hotkey(mainHotkey, (*) => handleHotkey("showCommandMenu"))
Hotkey(saveReloadHotkey, (*) => handleHotkey("saveAndReloadScript"))
Hotkey(closeWindowsHotkey, (*) => handleHotkey("closeWindows"))
Hotkey(suspendHotkey, (*) => handleHotkey("suspendHotkey"), "S")

handleHotkey(action) {
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
                MsgBox("Script will automatically reload once all Response Windows are closed.",
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

    if chatWindowhWnd && WinExist("ahk_id " chatWindowhWnd) {
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
    global chatWindowPID
    if chatWindowPID
        ProcessClose(chatWindowPID)
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

; ----------------------------------------------------
; Include application modules
; ----------------------------------------------------

#Include app\ClipboardCapture.ahk
#Include app\InlineRequestRunner.ahk
#Include app\menu\CommandMenu.ahk
#Include app\menu\CommandState.ahk
#Include app\RequestProcessor.ahk
#Include app\LoadingTracker.ahk
#Include app\LoadingUI.ahk
