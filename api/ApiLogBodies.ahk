; Large exact payloads live beside the bounded log index; previews never replace them.
class ApiLogBodies {
    static directory(logPath) => logPath ".bodies"

    static Archive(entry, logPath, byteLimit) {
        entry.log_id := DllCall("GetCurrentProcessId") "-" A_TickCount "-" Random(1, 2147483647)
        for field in ["request", "response"] {
            if !entry.HasOwnProp(field) || Type(entry.%field%) != "String"
                continue
            text := entry.%field%
            if StrLen(text) <= 65536 && StrPut(text, "UTF-8") - 1 <= byteLimit
                continue
            DirCreate(this.directory(logPath))
            name := "body-" entry.log_id "-" field ".txt"
            FileOpen(this.directory(logPath) "\" name, "w", "UTF-8-RAW").Write(text)
            archiveField := field "_archive", sizeField := field "_chars"
            entry.%archiveField% := name
            entry.%sizeField% := StrLen(text)
        }
    }

    static PreviewArchived(entry) {
        for field in ["request", "response"] {
            if !entry.HasOwnProp(field "_archive") || StrLen(entry.%field%) <= 6000
                continue
            text := entry.%field%
            entry.%field% := SubStr(text, 1, 3000) "`n[" (StrLen(text) - 6000) " characters omitted from preview; full payload retained]`n" SubStr(text, -3000)
        }
    }

    static Read(logPath, name) {
        if !RegExMatch(name, "^body-\d+-\d+-\d+-(request|response)\.txt$")
            throw Error("Invalid retained API payload identifier.")
        path := this.directory(logPath) "\" name
        if !FileExist(path)
            throw Error("The full payload is no longer retained. Refresh the log viewer.")
        return FileRead(path, "UTF-8-RAW")
    }

    static Delete(entry, logPath) {
        for field in ["request_archive", "response_archive"] {
            name := entry is Map ? entry.Get(field, "") : entry.HasOwnProp(field) ? entry.%field% : ""
            if RegExMatch(name, "^body-\d+-\d+-\d+-(request|response)\.txt$")
                try FileDelete(this.directory(logPath) "\" name)
        }
        try DirDelete(this.directory(logPath))
    }
}
