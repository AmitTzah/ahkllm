; ======================================================
; ThreadRepo.ahk — Thread CRUD operations
;
; Part of ChatDB split. All thread-related database
; operations extracted from ChatDB.ahk.
; ======================================================

class ThreadRepo {

    ; Create a new thread. Returns thread id string.
    static Create(title := "New Chat") {
        id := ChatDB._UUID()
        safeTitle := SQLite.Escape(title)
        ChatDB.db.Exec("INSERT INTO chat_threads (id, title) VALUES('" id "', '" safeTitle "');")
        return id
    }

    ; Save per-thread settings (model, assistant, system, reasoning, temperature).
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
        table := ChatDB.db.Exec("SELECT assistant_id, model_override, system_override, reasoning_override, temperature_override FROM chat_threads WHERE id='" safeId "';")
        if table.count {
            row := table[1]
            return {
                assistantId: row.assistant_id,
                modelOverride: row.model_override,
                systemOverride: row.system_override,
                reasoningOverride: row.reasoning_override,
                temperatureOverride: row.temperature_override
            }
        }
        return ""
    }

    ; Get threads sorted by most recent first.
    static List(showTrash := false) {
        query := "SELECT id, title, created_at, updated_at FROM chat_threads WHERE is_deleted=" (showTrash ? 1 : 0)
        query .= " ORDER BY updated_at DESC"
        table := ChatDB.db.Exec(query)
        threads := []
        for row in table.rows {
            model := ""
            modelTable := ChatDB.db.Exec("SELECT model FROM messages WHERE thread_id='" row.id "' AND role='assistant' AND model IS NOT NULL AND model != '' ORDER BY created_at DESC LIMIT 1;")
            if modelTable.count
                model := modelTable[1, "model"]
            threads.Push({
                id: row.id,
                title: row.title,
                created_at: row.created_at,
                updated_at: row.updated_at,
                model: model
            })
        }
        return threads
    }

    ; Trash a thread (soft-delete).
    static SoftDelete(threadId) {
        ChatDB.db.Exec("UPDATE chat_threads SET is_deleted=1, deleted_at=datetime('now'), updated_at=datetime('now') WHERE id='" threadId "';")
    }

    ; Restore a trashed thread.
    static Restore(threadId) {
        ChatDB.db.Exec("UPDATE chat_threads SET is_deleted=0, deleted_at=NULL, updated_at=datetime('now') WHERE id='" threadId "';")
    }

    ; Permanently delete expired trashed threads.
    static PurgeExpired() {
        if (IsSet(trashRetentionDays) && trashRetentionDays <= 0) || (!IsSet(trashRetentionDays))
            return
        ChatDB.db.Exec("DELETE FROM messages WHERE thread_id IN (SELECT id FROM chat_threads WHERE is_deleted=1 AND deleted_at < datetime('now', '-" trashRetentionDays " days'));")
        ChatDB.db.Exec("DELETE FROM chat_threads WHERE is_deleted=1 AND deleted_at < datetime('now', '-" trashRetentionDays " days');")
    }

    ; Permanently delete a thread and all its messages.
    static Delete(threadId) {
        ChatDB.db.Exec("DELETE FROM messages WHERE thread_id='" threadId "';")
        ChatDB.db.Exec("DELETE FROM chat_threads WHERE id='" threadId "';")
    }

    ; Update thread title and timestamp.
    static Update(threadId, title, updateTimestamp := true) {
        if !threadId
            return
        safeTitle := SQLite.Escape(title)
        if updateTimestamp
            ChatDB.db.Exec("UPDATE chat_threads SET title='" safeTitle "', updated_at=datetime('now') WHERE id='" threadId "';")
        else
            ChatDB.db.Exec("UPDATE chat_threads SET title='" safeTitle "' WHERE id='" threadId "';")
    }
}
