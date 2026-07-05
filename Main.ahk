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

Hotkey(mainHotkey, (*) => mainScriptHotkeyActions("showPromptMenu"))
Hotkey(saveReloadHotkey, (*) => mainScriptHotkeyActions("saveAndReloadScript"))
Hotkey(closeWindowsHotkey, (*) => mainScriptHotkeyActions("closeWindows"))
Hotkey(suspendHotkey, (*) => mainScriptHotkeyActions("suspendHotkey"), "S")

mainScriptHotkeyActions(action) {
    switch action {
        case "showPromptMenu":
            buildPromptMenu()

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
                responseWindowState(0, 0, "reloadScript", 0)
            } else {
                Reload()
            }

        case "closeWindows":
            switch WinActive("A") {
                case customPromptInputWindow.guiObj.hWnd: customPromptInputWindow.closeButtonAction()
                case sendToPromptNameInputWindow.guiObj.hWnd: sendToPromptNameInputWindow.closeButtonAction()
                case sendToAllModelsInputWindow.guiObj.hWnd: sendToAllModelsInputWindow.closeButtonAction()
            }
    }
}

; ----------------------------------------------------
; Initialize Chat DB (persistent chat history)
; ----------------------------------------------------

ChatDB.Open()

; ----------------------------------------------------
; Chat window state (single persistent window)
; ----------------------------------------------------

global chatWindowPID := 0
global chatWindowhWnd := 0

OpenOrSpawnChatWindow(threadId := "") {
    global chatWindowPID, chatWindowhWnd

    if chatWindowhWnd && WinExist("ahk_id " chatWindowhWnd) {
        WinShow("ahk_id " chatWindowhWnd)
        WinActivate("ahk_id " chatWindowhWnd)
    } else {
        ; Get main script's hidden hWnd for IPC
        mainScriptHiddenhWnd := WinExist("ahk_class AutoHotkey")
        ; Pass threadId as third argument (A_Args[2] in ChatWindow.ahk)
        if threadId
            Run(Format('"{}" "{}" {} "{}"', A_AhkPath, A_ScriptDir "\chat\ChatWindow.ahk", mainScriptHiddenhWnd, threadId), , , &chatWindowPID)
        else
            Run(Format('"{}" "{}" {}', A_AhkPath, A_ScriptDir "\chat\ChatWindow.ahk", mainScriptHiddenhWnd), , , &chatWindowPID)
    }
}

; Handler for chat window opened notification
OnChatWindowOpened(uniqueID, lParam, msg, hWnd) {
    global chatWindowhWnd
    chatWindowhWnd := lParam
}

OnChatWindowClosed(uniqueID, lParam, msg, hWnd) {
    global chatWindowhWnd
    ; Window is hidden, don't clear hWnd — it still exists
}

; Clean up ChatWindow sub-process when Main.ahk exits
OnExit(KillChatWindow)
KillChatWindow(ExitReason, ExitCode) {
    global chatWindowPID
    if chatWindowPID
        ProcessClose(chatWindowPID)
}

; ----------------------------------------------------
; Generate tray menu dynamically from UserConfig.ahk
; ----------------------------------------------------

TraySetIcon(iconOn)
A_TrayMenu.Delete()
A_TrayMenu.Add("📋 Open Chat Window", (*) => OpenOrSpawnChatWindow())
A_TrayMenu.Add("📝 New Chat", (*) => OpenOrSpawnChatWindow(ChatDB.Thread_Create()))
A_TrayMenu.Add()
for _, item in trayMenuItems {
    switch item.action {
        case "reload": A_TrayMenu.Add(item.menuText, (*) => Reload())
        case "exit":   A_TrayMenu.Add(item.menuText, (*) => ExitApp())
    }
}
A_IconTip := "LLM AutoHotkey Assistant"

; ----------------------------------------------------
; Create new instance of LLMClient class
; ----------------------------------------------------

router := LLMClient(APIKey)

; ----------------------------------------------------
; Create Input Windows
; ----------------------------------------------------

customPromptInputWindow := InputWindow("Custom prompt")
sendToAllModelsInputWindow := InputWindow("Send message to all")
sendToPromptNameInputWindow := InputWindow("Send message to prompt")

; ----------------------------------------------------
; Register sendButtonActions
; ----------------------------------------------------

customPromptInputWindow.sendButtonAction(customPromptSendButtonAction)
sendToAllModelsInputWindow.sendButtonAction(sendToAllModelsSendButtonAction)
sendToPromptNameInputWindow.sendButtonAction(sendToGroupSendButtonAction)

; ----------------------------------------------------
; Initialize Suspend GUI
; ----------------------------------------------------

scriptSuspendStatus := Gui()
scriptSuspendStatus.SetFont(suspendBannerFontSize, suspendBannerFontFace)
scriptSuspendStatus.Add("Text", suspendBannerTextColor " Center", suspendBannerText)
scriptSuspendStatus.BackColor := suspendBannerBackground
scriptSuspendStatus.Opt("-Caption +Owner -SysMenu +AlwaysOnTop")
scriptSuspendStatusWidth := ""
scriptSuspendStatus.GetPos(, , &scriptSuspendStatusWidth)

; ----------------------------------------------------
; Register inter-process communication handlers
; ----------------------------------------------------

CustomMessages.registerHandlers("mainScript", responseWindowState)

; ----------------------------------------------------
; Include application modules
; ----------------------------------------------------

#Include app\PromptMenu.ahk
#Include app\PromptManager.ahk
#Include app\RequestProcessor.ahk
#Include app\ModelTracker.ahk
#Include app\UiHelpers.ahk
