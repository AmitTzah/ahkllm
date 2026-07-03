#Include <Config>
#SingleInstance

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
; Generate tray menu dynamically from UserConfig.ahk
; ----------------------------------------------------

TraySetIcon(iconOn)
A_TrayMenu.Delete()
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
