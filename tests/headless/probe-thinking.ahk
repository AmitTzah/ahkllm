; probe-thinking.ahk — Bug #22 regression check: command `thinking` metadata must
; survive a settings.json round-trip (cmd.thinking is an AHK Map; the helper reads
; Map entries with Has()/[] instead of HasOwnProp).
; Lightweight: includes ONLY CommandMenu.ahk (no Config/test harness).
; Usage: AutoHotkey64.exe probe-thinking.ahk <outFile>
#Requires AutoHotkey v2.0.18+
#ErrorStdOut
#SingleInstance Off
#NoTrayIcon
global outFile := A_Args.Length >= 1 ? A_Args[1] : A_Temp "\bughunt_thinking_result.txt"
global logLines := []
Log(m) {
    global logLines
    logLines.Push(m)
}
SetTimer(ExitProbe, -15000)
ExitProbe(*) {
    Log("WATCHDOG fired")
    Finish()
    ExitApp(1)
}
OnError((e, m) => (Log("ERROR: " e.Message), Finish(), ExitApp(1)), -1)

; CommandMenu.ahk's function bodies reference app-level identifiers that a
; standalone probe does not define. In this environment, unresolved identifier
; references in function bodies hang the script at load, so define stubs first.
global commands := [], chatShortcut := "", quickAccessMenuItems := [], submenuOrder := [], selectedCommand := {}
global commandInputWindow := {
    guiObj: { hWnd: 0 },
    EditControl: { Value: "" },
    showInputWindow: (*) => "",
    closeButtonAction: (*) => "",
    validateInputAndHide: (*) => true
}
setSelectedCommand(*) => ""
processInitialRequest(*) => ""
openChatWindow(*) => ""
runOptionsMenuAction(*) => ""

#Include ..\..\shared\SystemMessageResolver.ahk
#Include ..\..\app\menu\CommandMenu.ahk

Finish() {
    global outFile, logLines
    try FileAppend(Join("`n", logLines), outFile, "UTF-8")
}
Join(sep, arr) {
    out := ""
    for i, v in arr
        out .= (i > 1 ? sep : "") v
    return out
}

; Post-round-trip shape: command built by _ApplyCommands from a settings Map.
settingsCmd := {}
settingsCmd.thinking := Map("type", "enabled", "level", "none")
settingsCmd.pasteMode := "replace"
settingsCmd.isFIM := false
settingsCmd.userMessage := "{{selection}}"

params := _extractCommandParams(settingsCmd, "")
mapType := params[8]
mapLevel := params[9]
Log("Map-form thinking  -> type='" mapType "' level='" mapLevel "'")

; Control: object literal (fresh defaults, no settings.json yet).
objCmd := { thinking: { type: "enabled", level: "none" }, pasteMode: "replace", isFIM: false, userMessage: "{{selection}}" }
params2 := _extractCommandParams(objCmd, "")
objType := params2[8]
objLevel := params2[9]
Log("Object-form thinking -> type='" objType "' level='" objLevel "'")

if (mapType = "enabled" && mapLevel = "none" && objType = "enabled" && objLevel = "none")
    Log("RESULT: BUG22 FIXED (Map-form and object-form thinking both survive)")
else
    Log("RESULT: unexpected (" mapType "/" mapLevel " vs " objType "/" objLevel ")")

Finish()
ExitApp(0)
