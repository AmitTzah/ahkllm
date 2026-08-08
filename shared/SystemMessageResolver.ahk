; ======================================================
; SystemMessageResolver.ahk - single resolver for object
; system messages (assistants and commands).
;
; Step 5 of the architecture refactor: AssistantRepo and
; CommandMenu used to carry identical-but-separate copies
; of this search logic (bug #50: the command copy did not
; search default-settings/system-messages/). Resolve() is
; now the one implementation; callers keep their own
; error reporting.
;
; Named SystemMessageResolver (not SystemMessage) for the
; same AHK case-insensitivity reason as ModelResolver -
; "systemMessage" is used as a local variable all over the
; codebase, which would shadow a class named SystemMessage
; inside functions.
; ======================================================

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
            ; Bug #72: UNC paths (\\server\share) and rooted paths (\foo) are
            ; absolute even though they have no drive-letter colon - use them
            ; as-is instead of searching the relative candidates.
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
