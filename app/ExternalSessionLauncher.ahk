#Requires AutoHotkey v2.0.18+
#SingleInstance Off
#NoTrayIcon
#ErrorStdOut
#Include ..\lib\Config.ahk

; Generic public entry point: --register connection.json --open session.json
try {
    packagePath := ""
    targetWindow := 0
    index := 1
    while index <= A_Args.Length {
        option := A_Args[index]
        index++
        if index > A_Args.Length
            throw Error("Missing application launcher argument.")
        value := A_Args[index]
        index++
        if option = "--register"
            ExternalApplications.Register(jsongo.Parse(FileRead(value, "UTF-8")))
        else if option = "--open"
            packagePath := value
        else if option = "--target-window"
            targetWindow := Integer(value)
        else
            throw Error("Unknown application launcher option.")
    }
    if packagePath = ""
        ExitApp(0)
    loop files A_ScriptDir "\..\Main.ahk"
        mainPath := A_LoopFileFullPath
    if !IsSet(mainPath)
        throw Error("Cannot locate AhkLLM Main.ahk.")
    DetectHiddenWindows(true)
    SetTitleMatchMode(2)
    handle := targetWindow ? targetWindow : WinExist(mainPath " ahk_class AutoHotkey")
    if !handle && !targetWindow
        Run(ApplicationProcess.Quote(A_AhkPath) " " ApplicationProcess.Quote(mainPath), , "Hide")
    payload := Buffer((StrLen(packagePath) + 1) * 2, 0)
    StrPut(packagePath, payload, "UTF-16")
    copyData := Buffer(A_PtrSize * 3, 0)
    NumPut("UPtr", 0x41484B41, copyData, 0)
    NumPut("UInt", payload.Size, copyData, A_PtrSize)
    NumPut("Ptr", payload.Ptr, copyData, A_PtrSize * 2)
    accepted := false
    started := A_TickCount
    while A_TickCount - started < 30000 {
        handle := targetWindow ? targetWindow : WinExist(mainPath " ahk_class AutoHotkey")
        if handle {
            try accepted := SendMessage(0x4A, 0, copyData.Ptr, , "ahk_id " handle, , , , 5000) = 1
            if accepted
                break
        }
        Sleep(100)
    }
    if !accepted
        throw Error("AhkLLM did not accept the session. Restart an older running version after updating it.")
    ExitApp(0)
} catch Error as e {
    FileAppend(e.Message "`n", "**", "UTF-8")
    ExitApp(1)
}
