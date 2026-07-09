; ======================================================
; AssistantRepo.ahk — Assistant CRUD operations
;
; Part of ChatDB split. Extracted from ChatDB.ahk.
; ======================================================

class AssistantRepo {

    ; Seed assistants from UserConfig on startup.
    static Seed() {
        ChatDB.db.Exec("DELETE FROM assistants;")
        for a in assistants {
            id := ChatDB._UUID()
            safeName := SQLite.Escape(a.name)
            safeModel := SQLite.Escape(a.baseModel)
            prompt := AssistantRepo._resolveSystemMessage(a)
            safePrompt := SQLite.Escape(prompt)
            safeReasoning := SQLite.Escape(a.reasoning)
            temp := a.temperature = "" ? "NULL" : a.temperature
            isDef := a.isDefault ? 1 : 0
            ChatDB.db.Exec("INSERT INTO assistants (id, name, base_model, system_prompt, reasoning, temperature, is_default) VALUES('" id "', '" safeName "', '" safeModel "', '" safePrompt "', '" safeReasoning "', " temp ", " isDef ");")
        }
    }

    ; List all assistant profiles.
    static List() {
        table := ChatDB.db.Exec("SELECT id, name, base_model, system_prompt, reasoning, temperature, is_default FROM assistants ORDER BY is_default DESC, name ASC;")
        result := []
        for row in table.rows {
            result.Push({
                id: row.id,
                name: row.name,
                baseModel: row.base_model,
                systemMessage: row.system_prompt,
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
        table := ChatDB.db.Exec("SELECT id, name, base_model, system_prompt, reasoning, temperature, is_default FROM assistants WHERE id='" safeId "';")
        if table.count {
            row := table[1]
            return {
                id: row.id,
                name: row.name,
                baseModel: row.base_model,
                systemMessage: row.system_prompt,
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
                return FileRead(filePath, "UTF-8")
            } catch Error as e {
                MsgBox("Failed to read assistant system message:`n" filePath "`n`n" e.Message,
                    "System Message Error", "IconX")
                return a.HasProp("systemMessage") ? a.systemMessage : ""
            }
        }
        return a.HasProp("systemMessage") ? a.systemMessage : ""
    }
}
