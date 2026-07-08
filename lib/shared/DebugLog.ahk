; ----------------------------------------------------
; DebugLog — Shared diagnostic logging
;
; Appends timestamped lines to %TEMP%\LLM_Debug_Log.txt.
; Replaces 2 duplicate debugLog() implementations.
; ----------------------------------------------------

debugLog(message, prefix := "") {
    timestamp := FormatTime(, "HH:mm:ss")
    prefixStr := prefix ? " [" prefix "] " : " "
    FileAppend(timestamp prefixStr message "`n", A_Temp "\LLM_Debug_Log.txt")
}

safeDelete(path) {
    if FileExist(path)
        FileDelete(path)
}
