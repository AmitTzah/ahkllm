; UTF-8 JSON-lines subprocess transport. No shell, persistent daemon, or credentials.
class ApplicationProcess {
    static Quote(value) {
        ; Windows CommandLineToArgvW quoting, including trailing backslashes.
        result := '"', slashes := 0
        loop parse String(value) {
            if A_LoopField = "\" {
                slashes++
                continue
            }
            if A_LoopField = '"'
                result .= this.Repeat("\", slashes * 2 + 1) '"'
            else
                result .= this.Repeat("\", slashes) A_LoopField
            slashes := 0
        }
        return result this.Repeat("\", slashes * 2) '"'
    }

    static Repeat(value, count) {
        result := ""
        loop count
            result .= value
        return result
    }

    static Call(profile, method, params) {
        directory := A_Temp "\AhkLLM_Application_" ChatDB._UUID()
        DirCreate(directory)
        inputPath := directory "\input.jsonl", outputPath := directory "\output.jsonl", errorPath := directory "\error.txt"
        requestId := ChatDB._UUID()
        FileOpen(inputPath, "w", "UTF-8-RAW").Write(jsongo.Stringify(Map("jsonrpc", "2.0", "id", requestId, "method", method, "params", params)) "`n")
        command := ""
        for arg in profile["command"]
            command .= (command = "" ? "" : " ") this.Quote(arg)
        try {
            this.Run(command, profile.Get("working_directory", ""), inputPath, outputPath, errorPath, profile.Get("timeout_seconds", 60))
            response := jsongo.Parse(FileRead(outputPath, "UTF-8"))
            if response.Get("id", "") != requestId || response.Get("jsonrpc", "") != "2.0"
                throw Error("External application returned a mismatched response.")
            if response.Has("error")
                throw Error(response["error"].Get("message", "External application operation failed."))
            return response["result"]
        } finally {
            ; This exact directory was created above; never clean an application-supplied path.
            try DirDelete(directory, true)
        }
    }

    static Run(command, cwd, inputPath, outputPath, errorPath, timeoutSeconds) {
        security := Buffer(A_PtrSize = 8 ? 24 : 12, 0)
        NumPut("UInt", security.Size, security, 0)
        NumPut("Int", 1, security, A_PtrSize = 8 ? 16 : 8)
        handles := [], process := Buffer(A_PtrSize = 8 ? 24 : 16, 0)
        try {
            for pair in [[inputPath, 0x80000000, 3], [outputPath, 0x40000000, 2], [errorPath, 0x40000000, 2]] {
                handle := DllCall("CreateFileW", "Str", pair[1], "UInt", pair[2], "UInt", 3, "Ptr", security, "UInt", pair[3], "UInt", 0x80, "Ptr", 0, "Ptr")
                if handle = -1
                    throw OSError(A_LastError, "Cannot open external application transport file")
                handles.Push(handle)
            }
            startup := Buffer(A_PtrSize = 8 ? 104 : 68, 0)
            NumPut("UInt", startup.Size, startup, 0)
            NumPut("UInt", 0x100, startup, A_PtrSize = 8 ? 60 : 44)
            NumPut("Ptr", handles[1], startup, A_PtrSize = 8 ? 80 : 56)
            NumPut("Ptr", handles[2], startup, A_PtrSize = 8 ? 88 : 60)
            NumPut("Ptr", handles[3], startup, A_PtrSize = 8 ? 96 : 64)
            if !DllCall("CreateProcessW", "Ptr", 0, "Str", command, "Ptr", 0, "Ptr", 0, "Int", true, "UInt", 0x08000000, "Ptr", 0, "Ptr", cwd = "" ? 0 : StrPtr(cwd), "Ptr", startup, "Ptr", process)
                throw OSError(A_LastError, "Cannot start external application")
            processHandle := NumGet(process, 0, "Ptr")
            threadHandle := NumGet(process, A_PtrSize, "Ptr")
            started := A_TickCount
            while DllCall("WaitForSingleObject", "Ptr", processHandle, "UInt", 0) = 0x102 {
                if A_TickCount - started > Max(1, Min(timeoutSeconds, 300)) * 1000 {
                    DllCall("TerminateProcess", "Ptr", processHandle, "UInt", 1)
                    throw Error("External application timed out. Reopen its chat to recover interrupted work.")
                }
                Sleep(10)
            }
            exitCode := 0
            DllCall("GetExitCodeProcess", "Ptr", processHandle, "UInt*", &exitCode)
            if exitCode
                throw Error("External application exited with code " exitCode ".")
        } finally {
            for handle in handles
                DllCall("CloseHandle", "Ptr", handle)
            if IsSet(processHandle)
                DllCall("CloseHandle", "Ptr", processHandle)
            if IsSet(threadHandle)
                DllCall("CloseHandle", "Ptr", threadHandle)
        }
    }
}
