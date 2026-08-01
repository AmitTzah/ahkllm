; ======================================================
; CurlExecutor.ahk — run a cURL command synchronously
;
; Runs the command hidden, waits for the process to exit,
; and returns the contents of the output file ("" if absent).
; Shared by InlineRequestRunner and ThreadTitleGen.
; ======================================================

class CurlExecutor {
    static Run(cURLCommand, outputFile, pollIntervalMs := 250) {
        Run(cURLCommand, , "Hide", &cURLPID)
        while ProcessExist(cURLPID)
            Sleep pollIntervalMs
        raw := ""
        if FileExist(outputFile)
            raw := FileOpen(outputFile, "r", "UTF-8-RAW").Read()
        return raw
    }
}
