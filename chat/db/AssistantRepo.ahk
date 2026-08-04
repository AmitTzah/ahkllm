; ======================================================
; AssistantRepo.ahk — Assistant CRUD operations
;
; Part of ChatDB split. Extracted from ChatDB.ahk.
; ======================================================

class AssistantRepo {

    ; Get an assistant by ID from the global assistants array (populated by SettingsHandler)
    static GetFromSettings(assistantId) {
        global assistants
        if !IsSet(assistants)
            return ""
        for a in assistants {
            if a.HasOwnProp("id") && a.id = assistantId
                return a
        }
        return ""
    }

    static _resolveSystemMessage(a) {
        if a.HasProp("systemMessageFile") && a.systemMessageFile {
            filePath := a.systemMessageFile
            if !InStr(filePath, ":") {
                ; Relative path — search script dir, repo root, system-messages/ dirs, then user AppData folder.
; Also try bare filenames (e.g. "violet.txt") under default-settings/system-messages/.
                SplitPath(filePath, &name)
                candidates := [A_ScriptDir "\" filePath
                             , A_ScriptDir "\..\" filePath
                             , A_ScriptDir "\default-settings\system-messages\" filePath
                             , A_ScriptDir "\..\default-settings\system-messages\" filePath]
                candidates.Push(A_AppData "\LLM-AutoHotkey-Assistant\system-messages\" name)
                for _, cand in candidates {
                    if FileExist(cand) {
                        filePath := cand
                        break
                    }
                }
            }
            try {
                content := FileRead(filePath, "UTF-8")
                ; Normalize line endings to LF
                content := StrReplace(content, "`r`n", "`n")
                return StrReplace(content, "`r", "`n")
            } catch Error as e {
                debugLog("[SETTINGS] Failed to read assistant system message: " filePath " — " e.Message)
                return a.HasProp("systemMessage") ? a.systemMessage : ""
            }
        }
        return a.HasProp("systemMessage") ? a.systemMessage : ""
    }
}
