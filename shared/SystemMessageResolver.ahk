; SystemMessageResolver.ahk — resolves assistant and command system messages.
; The class name avoids AHK v2's case-insensitive collision with systemMessage locals.

#Include AppInfo.ahk

class SystemMessageResolver {

    ; Resolve an object's system message:
    ;   - systemMessageFile: absolute path used as-is; relative paths are
    ;     searched against the script dir, repo root, default-settings/
    ;     system-messages/, and the user AppData system-messages folder.
    ;   - fallback: inline systemMessage.
    ; Returns { text, error } where error is non-empty when a file was
    ; configured but could not be read.
    static Resolve(obj) {
        if obj.HasProp("systemMessageFile") && obj.systemMessageFile {
            filePath := obj.systemMessageFile
            ; UNC and rooted paths are absolute even without a drive-letter colon.
            if !InStr(filePath, ":") && !(SubStr(filePath, 1, 1) = "\") && !(SubStr(filePath, 1, 1) = "/") {
                SplitPath(filePath, &name)
                candidates := [A_ScriptDir "\" filePath
                             , A_ScriptDir "\..\" filePath
                             , A_ScriptDir "\default-settings\system-messages\" filePath
                             , A_ScriptDir "\..\default-settings\system-messages\" filePath]
                candidates.Push(AppInfo.DataDir "\system-messages\" name)
                for _, cand in candidates {
                    if FileExist(cand) {
                        filePath := cand
                        break
                    }
                }
            }
            try {
                content := FileRead(filePath, "UTF-8")
                ; Normalize line endings to LF: CRLF pairs first, then stray CR.
                content := StrReplace(content, "`r`n", "`n")
                return { text: StrReplace(content, "`r", "`n"), error: "" }
            } catch Error as e {
                return { text: obj.HasProp("systemMessage") ? obj.systemMessage : "", error: e.Message }
            }
        }
        return { text: obj.HasProp("systemMessage") ? obj.systemMessage : "", error: "" }
    }
}
