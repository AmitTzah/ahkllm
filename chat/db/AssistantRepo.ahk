; ======================================================
; AssistantRepo.ahk — Assistant CRUD operations
;
; Part of ChatDB split. Extracted from ChatDB.ahk.
; ======================================================

class AssistantRepo {

    ; Seed assistants from UserConfig on startup.
    ; REMOVED: assistants are now read from the global 'assistants' array populated by SettingsHandler.
    ; Kept as no-op for backward compatibility.
    static Seed() {
        ; No-op — assistants come from settings.json now
    }

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

    ; List all assistant profiles.
    static List() {
        table := ChatDB.db.Exec("SELECT id, name, base_model, system_prompt, description, reasoning, temperature, is_default FROM assistants ORDER BY is_default DESC, name ASC;")
        result := []
        for row in table.rows {
            result.Push({
                id: row.id,
                name: row.name,
                baseModel: row.base_model,
                systemMessage: row.system_prompt,
                description: row.description ? row.description : "",
                reasoning: row.reasoning,
                temperature: row.temperature,
                isDefault: row.is_default = 1
            })
        }
        return result
    }

    ; Get a single assistant by ID.
    static Get(assistantId) {
        safeId := SQLite.Escape(assistantId)
        table := ChatDB.db.Exec("SELECT id, name, base_model, system_prompt, description, reasoning, temperature, is_default FROM assistants WHERE id='" safeId "';")
        if table.count {
            row := table[1]
            return {
                id: row.id,
                name: row.name,
                baseModel: row.base_model,
                systemMessage: row.system_prompt,
                description: row.description ? row.description : "",
                reasoning: row.reasoning,
                temperature: row.temperature,
                isDefault: row.is_default = 1
            }
        }
        return ""
    }

    static _resolveSystemMessage(a) {
        if a.HasProp("systemMessageFile") && a.systemMessageFile {
            filePath := a.systemMessageFile
            if !InStr(filePath, ":") && !InStr(filePath, "\\")
                filePath := A_ScriptDir "\\" filePath
            try {
                content := FileRead(filePath, "UTF-8")
                ; Normalize all line endings to LF: `r`n pairs first, then any stray `r
                content := StrReplace(content, "`r`n", "`n")
                return StrReplace(content, "`r", "`n")
            } catch Error as e {
                MsgBox("Failed to read assistant system message:`n" filePath "`n`n" e.Message,
                    "System Message Error", "IconX")
                return a.HasProp("systemMessage") ? a.systemMessage : ""
            }
        }
        return a.HasProp("systemMessage") ? a.systemMessage : ""
    }
}
