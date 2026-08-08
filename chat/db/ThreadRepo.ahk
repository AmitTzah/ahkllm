; ======================================================
; ThreadRepo.ahk — Thread CRUD operations
;
; Part of ChatDB split. All thread-related database
; operations extracted from ChatDB.ahk.
; ======================================================

class ThreadRepo {

    ; Normalize a JSON boolean / 1 / 0 / "true" / "false" value to a real boolean.
    static _ToBool(value) {
        if value = 1 || value = "1" || value = "true" || value = "on" || value = "yes"
            return true
        return false
    }

    ; Create a new thread. Returns thread id string.
    static Create(title := "New Chat") {
        id := ChatDB._UUID()
        safeTitle := SQLite.Escape(title)
        ChatDB.db.Exec("INSERT INTO chat_threads (id, title) VALUES('" id "', '" safeTitle "');")
        return id
    }

    ; Save per-thread settings (model, assistant, system, reasoning, temperature,
    ; fontSize, and the right-rail Advanced toggles).
    static UpdateSettings(threadId, settings) {
        safeId := SQLite.Escape(threadId)
        parts := []
        if settings.HasOwnProp("assistantId")
            parts.Push("assistant_id = " (settings.assistantId ? "'" SQLite.Escape(settings.assistantId) "'" : "NULL"))
        if settings.HasOwnProp("modelOverride")
            parts.Push("model_override = " (settings.modelOverride ? "'" SQLite.Escape(settings.modelOverride) "'" : "NULL"))
        if settings.HasOwnProp("systemOverride")
            parts.Push("system_override = " (settings.systemOverride ? "'" SQLite.Escape(settings.systemOverride) "'" : "NULL"))
        if settings.HasOwnProp("reasoningOverride")
            parts.Push("reasoning_override = " (settings.reasoningOverride ? "'" SQLite.Escape(settings.reasoningOverride) "'" : "NULL"))
        if settings.HasOwnProp("temperatureOverride")
            parts.Push("temperature_override = " (settings.temperatureOverride != "" ? settings.temperatureOverride : "NULL"))
        if settings.HasOwnProp("fontSize")
            parts.Push("font_size = " (settings.fontSize ? settings.fontSize : "17"))
        if settings.HasOwnProp("codeExecution") || settings.HasOwnProp("webSearch") {
            togglesJson := jsongo.Stringify({
                codeExecution: settings.HasOwnProp("codeExecution") ? ThreadRepo._ToBool(settings.codeExecution) : false,
                webSearch: settings.HasOwnProp("webSearch") ? ThreadRepo._ToBool(settings.webSearch) : false
            })
            parts.Push("advanced_toggles = '" SQLite.Escape(togglesJson) "'")
        }
        if parts.Length {
            setClause := ""
            for i, p in parts
                setClause .= (i > 1 ? ", " : "") p
            ChatDB.db.Exec("UPDATE chat_threads SET " setClause " WHERE id='" safeId "';")
        }
    }

    ; Get per-thread settings.
    static GetSettings(threadId) {
        safeId := SQLite.Escape(threadId)
        table := ChatDB.db.Exec("SELECT assistant_id, model_override, system_override, reasoning_override, temperature_override, font_size, advanced_toggles FROM chat_threads WHERE id='" safeId "';")
        if table.count {
            row := table[1]
            codeExecution := false, webSearch := false
            if row.advanced_toggles {
                try {
                    toggles := jsongo.Parse(row.advanced_toggles)
                    codeExecution := toggles.Has("codeExecution") ? ThreadRepo._ToBool(toggles["codeExecution"]) : false
                    webSearch := toggles.Has("webSearch") ? ThreadRepo._ToBool(toggles["webSearch"]) : false
                } catch {
                    debugLog("[THREAD] Failed to parse advanced_toggles for " threadId)
                }
            }
            return {
                assistantId: row.assistant_id,
                modelOverride: row.model_override,
                systemOverride: row.system_override,
                reasoningOverride: row.reasoning_override,
                temperatureOverride: row.temperature_override,
                codeExecution: codeExecution,
                webSearch: webSearch,
                fontSize: row.font_size ? row.font_size : 17
            }
        }
        return ""
    }

    ; Get threads sorted by most recent first.
    static List(showTrash := false) {
        query := "SELECT t.id, t.title, t.created_at, t.updated_at, t.folder_id, COALESCE(f.name, '') AS folder_name FROM chat_threads t LEFT JOIN chat_folders f ON t.folder_id = f.id WHERE t.is_deleted=" (showTrash ? 1 : 0)
        query .= " ORDER BY t.updated_at DESC"
        table := ChatDB.db.Exec(query)
        threads := []
        for row in table.rows {
            model := ""
            modelTable := ChatDB.db.Exec("SELECT model FROM messages WHERE thread_id='" SQLite.Escape(row.id) "' AND role='assistant' AND model IS NOT NULL AND model != '' ORDER BY created_at DESC LIMIT 1;")
            if modelTable.count
                model := modelTable[1, "model"]
            threads.Push({
                id: row.id,
                title: row.title,
                created_at: row.created_at,
                updated_at: row.updated_at,
                model: model,
                folder_id: row.folder_id ? row.folder_id : "",
                folder_name: row.folder_name ? row.folder_name : ""
            })
        }
        return threads
    }

    ; Trash a thread (soft-delete).
    static SoftDelete(threadId) {
        ; Bug #80 (security): escape the id - a crafted id with ' could inject SQL.
        safeId := SQLite.Escape(threadId)
        debugLog("[THREAD] Deleted — id=" threadId)
        ChatDB.db.Exec("UPDATE chat_threads SET is_deleted=1, deleted_at=datetime('now'), updated_at=datetime('now') WHERE id='" safeId "';")
    }

    ; Restore a trashed thread.
    static Restore(threadId) {
        ; Bug #80 (security): escape the id.
        safeId := SQLite.Escape(threadId)
        ChatDB.db.Exec("UPDATE chat_threads SET is_deleted=0, deleted_at=NULL, updated_at=datetime('now') WHERE id='" safeId "';")
    }

    ; Permanently delete expired trashed threads.
    static PurgeExpired() {
        if (IsSet(trashRetentionDays) && trashRetentionDays <= 0) || (!IsSet(trashRetentionDays))
            return
        ; Coerce to a number so a crafted setting value cannot break the SQL.
        retention := Integer(trashRetentionDays)
        ; Clean up attachment files on disk BEFORE the raw SQL DELETEs.
        ; The CASCADE FK would auto-delete message_attachments rows but leave orphan files.
        expiredTable := ChatDB.db.Exec("SELECT id FROM chat_threads WHERE is_deleted=1 AND deleted_at < datetime('now', '-" retention " days');")
        for row in expiredTable.rows
            AttachmentRepo.DeleteByThread(row.id)
        ChatDB.db.Exec("DELETE FROM messages WHERE thread_id IN (SELECT id FROM chat_threads WHERE is_deleted=1 AND deleted_at < datetime('now', '-" retention " days'));")
        ChatDB.db.Exec("DELETE FROM chat_threads WHERE is_deleted=1 AND deleted_at < datetime('now', '-" retention " days');")
    }

    ; Permanently delete a thread and all its messages.
    static Delete(threadId) {
        ; Bug #80 (security): escape the id everywhere it is interpolated.
        safeId := SQLite.Escape(threadId)
        debugLog("[THREAD] Deleted — id=" threadId)
        ; Bug #116: pass the RAW id - DeleteByThread escapes it internally.
        ; Passing safeId (already escaped) double-escaped it, so crafted-id
        ; threads deleted their messages but orphaned their attachment rows.
        AttachmentRepo.DeleteByThread(threadId)
        ChatDB.db.Exec("DELETE FROM messages WHERE thread_id='" safeId "';")
        ChatDB.db.Exec("DELETE FROM chat_threads WHERE id='" safeId "';")
    }

    ; Update thread title and timestamp.
    static Update(threadId, title, updateTimestamp := true) {
        if !threadId
            return
        ; Bug #80 (security): escape the id.
        safeId := SQLite.Escape(threadId)
        safeTitle := SQLite.Escape(title)
        if updateTimestamp
            ChatDB.db.Exec("UPDATE chat_threads SET title='" safeTitle "', updated_at=datetime('now') WHERE id='" safeId "';")
        else
            ChatDB.db.Exec("UPDATE chat_threads SET title='" safeTitle "' WHERE id='" safeId "';")
    }
}
