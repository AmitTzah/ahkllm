#Requires AutoHotkey v2.0.18+
#Include ..\UserConfig.ahk        ; All user-facing configuration
#Include Dark_MsgBox.ahk                  ; Dark mode MsgBox and InputBox
#Include Dark_Menu.ahk                    ; Dark mode menus
#Include SystemThemeAwareToolTip.ahk       ; Dark mode tooltips
#Include WebViewToo.ahk             ; WebView2 Framework for Web-based GUIs
#Include jsongo.v2.ahk              ; JSON parsing
#Include AutoXYWH.ahk               ; Auto-resizing of GUI controls
#Include ToolTipEx.ahk              ; Tooltip tracking and dragging
#Include SQLite\SQLite.ahk          ; SQLite database wrapper
DetectHiddenWindows true            ; Enables detection of hidden windows for inter-process communication

; Shared utilities
#Include ..\lib\shared\ModelParser.ahk
#Include ..\lib\shared\TokenEstimation.ahk
#Include ..\lib\shared\DebugLog.ahk

; Application classes
#Include ..\api\CurlBuilder.ahk
#Include ..\api\ProviderResolver.ahk
#Include ..\api\ResponseParser.ahk
#Include ..\api\LLMRequestBuilder.ahk
#Include ..\api\SSEParser.ahk
#Include ..\api\ApiLogger.ahk
#Include ..\api\CostCalculator.ahk
#Include ..\ui\InputWindow.ahk
#Include ..\ipc\CustomMessages.ahk
#Include ..\chat\db\ChatDB.ahk       ; Chat persistence (SQLite-backed)
