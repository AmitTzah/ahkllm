; ----------------------------------------------------
; DebugLog — Shared diagnostic logging
;
; Appends timestamped lines to %TEMP%\LLM_Debug_Log.txt.
; Rolling log: keeps last ~500KB when file exceeds 1MB.
; Replaces 2 duplicate debugLog() implementations.
; ----------------------------------------------------

debugLog(message, prefix := "") {
    static logPath := A_Temp "\LLM_Debug_Log.txt"
    static callCount := 0

    timestamp := FormatTime(, "HH:mm:ss")
    prefixStr := prefix ? " [" prefix "] " : " "
    try FileAppend(timestamp prefixStr message "`n", logPath)

    ; Rolling log: truncate every 100 writes when file exceeds 1MB
    callCount++
    if Mod(callCount, 100) = 0 {
        try {
            fileSize := FileGetSize(logPath)
            if fileSize > 1048576 {  ; 1MB
                ; Read last ~500KB and rewrite
                keepSize := 524288  ; 512KB
                f := FileOpen(logPath, "r", "UTF-8-RAW")
                if f.Length > keepSize {
                    f.Pos := f.Length - keepSize
                    ; Skip to next newline for clean truncation
                    partialLine := f.ReadLine()
                    remaining := f.Read()
                    f.Close()
                    fw := FileOpen(logPath, "w", "UTF-8-RAW")
                    fw.Write("[log truncated at " timestamp " — kept last ~512KB]`n")
                    fw.Write(remaining)
                    fw.Close()
                } else {
                    f.Close()
                }
            }
        }
    }
}

safeDelete(path) {
    if FileExist(path)
        FileDelete(path)
}
