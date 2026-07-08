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

        FileOpen(this.logFilePath, "w", "UTF-8-RAW").Write(jsongo.Stringify(logs))
    }

    ; Reads the log file and returns the entries array (newest first)
    static ReadLogs() {
        return this._readLogFile()
    }

    ; Clears the log file entirely
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
