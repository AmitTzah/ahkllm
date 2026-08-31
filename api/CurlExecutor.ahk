; ======================================================
; CurlExecutor.ahk — run a cURL command synchronously
;
; Runs the command hidden, waits for the process to exit,
; and returns the contents of the output file ("" if absent).
; Shared by InlineRequestRunner and ThreadTitleGen.
; ======================================================

class CurlExecutor {
    static Run(cURLCommand, outputFile, pollIntervalMs := 250, cancelState := "") {
        Run(cURLCommand, , "Hide", &cURLPID)
        if IsObject(cancelState) {
            cancelState.pid := cURLPID
            if !cancelState.HasOwnProp("cancelled")
                cancelState.cancelled := false
        }

        try {
            while ProcessExist(cURLPID) {
                shouldCancel := false
                if IsObject(cancelState) {
                    if cancelState.HasOwnProp("cancelRequested") && cancelState.cancelRequested
                        shouldCancel := true
                    else if cancelState.HasOwnProp("cancelOnEscape") && cancelState.cancelOnEscape && GetKeyState("Esc", "P")
                        shouldCancel := true
                }

                if shouldCancel {
                    cancelState.cancelled := true
                    ; cURL is launched through cmd because the generated command
                    ; redirects stderr. Kill the whole tree so the child cURL
                    ; cannot keep running/writing after the command is cancelled.
                    try RunWait('taskkill /PID ' cURLPID ' /T /F', , "Hide")
                    catch Error as e {
                        if ProcessExist(cURLPID)
                            try ProcessClose(cURLPID)
                    }
                    break
                }
                Sleep pollIntervalMs
            }
        } finally {
            if IsObject(cancelState)
                cancelState.pid := 0
        }

        raw := ""
        if FileExist(outputFile)
            raw := FileOpen(outputFile, "r", "UTF-8-RAW").Read()
        return raw
    }
}
