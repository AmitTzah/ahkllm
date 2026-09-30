#Requires AutoHotkey v2.0.18+
#Warn All, StdOut
#Include ..\..\shared\DebugLog.ahk
#Include ..\..\api\CurlExecutor.ahk

if A_Args.Length < 1
    ExitApp 2

resultFile := A_Args[1]
unique := A_TickCount "_" Random(1000, 999999)
childScript := A_Temp "\ahkllm-inline-cancel-child-" unique ".ahk"
outputFile := A_Temp "\ahkllm-inline-cancel-output-" unique ".txt"

try {
    childText := "#Requires AutoHotkey v2.0.18+`nSleep 750`n"
    FileOpen(childScript, "w", "UTF-8-RAW").Write(childText)

    physicalObserved := CurlExecutor._EscapePhysicalDown() ? 1 : 0
    asyncRaw := DllCall("User32\GetAsyncKeyState", "Int", 0x1B, "Short")
    windowsDown := (asyncRaw & 0x8000) != 0 ? 1 : 0

    cancelState := {
        cancelOnEscape: true,
        cancelRequested: false,
        cancelled: false,
        pid: 0,
        diagnosticId: "e2e-stale-esc",
        commandName: "E2E stale Escape"
    }
    command := '"' A_AhkPath '" /ErrorStdOut "' childScript '"'
    started := A_TickCount
    CurlExecutor.Run(command, outputFile, 25, cancelState)
    elapsed := A_TickCount - started

    FileOpen(resultFile, "w", "UTF-8-RAW").Write(
        "physicalObserved|" physicalObserved "`n"
        . "windowsDown|" windowsDown "`n"
        . "cancelled|" (cancelState.cancelled ? 1 : 0) "`n"
        . "elapsed|" elapsed "`n"
    )
} finally {
    if FileExist(childScript)
        FileDelete(childScript)
    if FileExist(outputFile)
        FileDelete(outputFile)
}
