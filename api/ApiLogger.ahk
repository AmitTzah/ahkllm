; ----------------------------------------------------
; ApiLogger — API request/response logging
;
; Logs API interactions to %TEMP%\LLM_API_Log.json.
; Capped at apiLogMaxEntries entries (newest first).
; Set apiLogMaxEntries to 0 to disable logging entirely.
; ----------------------------------------------------

class ApiLogger {
    static logFilePath := A_Temp "\LLM_API_Log.json"

    ; Logs a single API interaction entry
    static _readLogFile() {
        if FileExist(this.logFilePath) {
            try {
                return jsongo.Parse(FileOpen(this.logFilePath, "r", "UTF-8-RAW").Read())
            }
        }
        return []
    }

    static LogRequest(entry) {
        if (apiLogMaxEntries <= 0)
            return

        logs := this._readLogFile()

        ; Add timestamp if not already present
        if !entry.HasProp("timestamp") || entry.timestamp = "" {
            entry.timestamp := FormatTime(, "yyyy-MM-dd HH:mm:ss")
        }

        logs.InsertAt(1, entry)

        ; Trim oldest entries to stay within the configured limit
        while logs.Length > apiLogMaxEntries {
            logs.RemoveAt(logs.Length)
        }

        this._WriteLogs(logs)
    }

    ; Reads the log file and returns the entries array (newest first)
    static ReadLogs() {
        return this._readLogFile()
    }

    ; Clears the log file entirely
    ; Trim existing log entries to the current max limit (called when settings change)
    static TrimToLimit() {
        if (apiLogMaxEntries <= 0)
            return
        logs := this._readLogFile()
        if logs.Length <= apiLogMaxEntries
            return
        while logs.Length > apiLogMaxEntries
            logs.RemoveAt(logs.Length)
        this._WriteLogs(logs)
    }

    ; Write the log array atomically (bug #111): write a temp file in the same
    ; directory, then rename it over the target, so a crash mid-write never
    ; leaves truncated JSON that ReadLogs fails to parse (same class as #97).
    static _WriteLogs(logs) {
        tmpPath := this.logFilePath ".tmp"
        try {
            f := FileOpen(tmpPath, "w", "UTF-8-RAW")
            f.Write(jsongo.Stringify(logs))
            f.Close()
            ; FileMove's return value is unreliable in this AHK build (it can
            ; be empty even on success), so verify success by file state.
            FileMove(tmpPath, this.logFilePath, 1)
            if FileExist(tmpPath) || !FileExist(this.logFilePath)
                throw Error("FileMove failed: " tmpPath " -> " this.logFilePath)
        } finally {
            try FileDelete(tmpPath)
        }
    }

    static ClearLogs() {
        if FileExist(this.logFilePath) {
            FileDelete(this.logFilePath)
        }
    }

    ; Returns the path to the log file (for reference/display)
    static GetLogFilePath() {
        return this.logFilePath
    }
}
