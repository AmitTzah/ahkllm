; Keep failure details before the exec JSONL capture is cleaned up.
class CodexCliErrors {
    static FromEvents(eventsText) {
        message := "", terminalMessage := ""
        for line in StrSplit(eventsText, "`n", "`r") {
            try event := jsongo.Parse(line)
            catch
                continue
            if !(event is Map)
                continue
            kind := event.Get("type", "")
            if kind != "error" && kind != "turn.failed"
                continue
            detail := event.Get("error", event)
            candidate := detail is Map ? detail.Get("message", "") : detail
            if Type(candidate) != "String" || Trim(candidate) = ""
                continue
            message := Trim(candidate)
            if kind = "turn.failed"
                terminalMessage := message
        }
        return terminalMessage != "" ? terminalMessage : message
    }

    static Normalize(errorFile, exitCode, eventsFile := "") {
        stderr := FileExist(errorFile) ? Trim(FileRead(errorFile, "UTF-8")) : ""
        events := eventsFile != "" && FileExist(eventsFile) ? FileRead(eventsFile, "UTF-8") : ""
        detail := this.FromEvents(events)
        if detail = "" {
            for line in StrSplit(stderr, "`n", "`r") {
                if Trim(line) = "Reading prompt from stdin..."
                    continue
                detail .= (detail = "" ? "" : "`n") line
            }
            detail := Trim(detail)
        }
        guidance := ""
        if RegExMatch(detail, "i)(auth|login|logged in|unauthori[sz]ed|credential|401)")
            guidance := "Run 'codex login' and choose ChatGPT authentication."
        else if RegExMatch(detail, "i)(quota|rate limit|too many requests|429|usage limit|subscription limit)")
            guidance := "Try again after your Codex allowance resets or choose another backend."
        else if RegExMatch(detail, "i)(unknown option|unrecognized option|unknown config|strict.?config|invalid .*config)")
            guidance := "Update AhkLLM/Codex to a version compatible with the safe LLM-only profile."
        message := "Codex CLI exited with code " exitCode "."
        message .= detail != "" ? "`n" SubStr(detail, 1, 2400) : " No failure detail was returned by the CLI."
        if guidance != ""
            message .= "`n" guidance
        FileOpen(errorFile, "w", "UTF-8-RAW").Write(message)
        return message
    }
}
