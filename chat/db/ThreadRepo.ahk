; ======================================================
; ThreadRepo.ahk - Thread CRUD operations
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
        ChatDB.db.Query("INSERT INTO chat_threads (id, title) VALUES(?, ?);", id, title)
        ChatDB._MarkPersistentDataChanged()
        return id
    }

    ; Save per-thread settings (model, assistant, system, reasoning, temperature,
    ; fontSize, and the right-rail Advanced toggles).
    static UpdateSettings(threadId, settings) {
        parts := []
        params := []
        if settings.HasOwnProp("assistantId")
            parts.Push("assistant_id = ?") params.Push(settings.assistantId ? settings.assistantId : SQLite.Null)
        if settings.HasOwnProp("modelOverride")
            parts.Push("model_override = ?") params.Push(settings.modelOverride ? settings.modelOverride : SQLite.Null)
        if settings.HasOwnProp("systemOverride")
            parts.Push("system_override = ?") params.Push(settings.systemOverride ? settings.systemOverride : SQLite.Null)
        if settings.HasOwnProp("reasoningOverride")
            parts.Push("reasoning_override = ?") params.Push(settings.reasoningOverride ? settings.reasoningOverride : SQLite.Null)
        if settings.HasOwnProp("temperatureOverride")
            parts.Push("temperature_override = ?") params.Push(settings.temperatureOverride != "" ? settings.temperatureOverride : SQLite.Null)
        if settings.HasOwnProp("fontSize")
            parts.Push("font_size = ?") params.Push(settings.fontSize ? settings.fontSize : 17)
        if settings.HasOwnProp("webSearch") {
            togglesJson := jsongo.Stringify({
                webSearch: ThreadRepo._ToBool(settings.webSearch)
            })
            parts.Push("advanced_toggles = ?") params.Push(togglesJson)
        }
        if parts.Length {
            setClause := ""
            for i, p in parts
                setClause .= (i > 1 ? ", " : "") p
            params.Push(threadId)
            ChatDB.db.Query("UPDATE chat_threads SET " setClause " WHERE id=?;", params*)
            ChatDB._MarkPersistentDataChanged()
        }
    }

    ; Get per-thread settings.
    static GetSettings(threadId) {
        table := ChatDB.db.Query("SELECT assistant_id, model_override, system_override, reasoning_override, temperature_override, font_size, advanced_toggles FROM chat_threads WHERE id=?;", threadId)
        if table.count {
            row := table[1]
            webSearch := false
            if row.advanced_toggles {
                try {
                    toggles := jsongo.Parse(row.advanced_toggles)
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
                webSearch: webSearch,
                fontSize: row.font_size ? row.font_size : 17
            }
        }
        return ""
    }

    ; Get threads sorted by most recent first.
    static List(showTrash := false) {
        query := "SELECT t.id, t.title, t.created_at, t.updated_at, t.active_leaf_id, t.folder_id, t.is_locked, COALESCE(f.name, '') AS folder_name FROM chat_threads t LEFT JOIN chat_folders f ON t.folder_id = f.id WHERE t.is_deleted=" (showTrash ? 1 : 0)
        query .= " ORDER BY t.updated_at DESC"
        table := ChatDB.db.Exec(query)
        threads := []
        ; Bug #180: the badge walk used to issue one active_leaf lookup plus
        ; one SELECT per ancestor for EVERY listed thread (N+1 queries per
        ; sidebar refresh). Load the message rows for all listed threads in a
        ; single query and walk the ancestor chains in memory instead.
        msgMap := Map()
        if table.count {
            msgTable := ChatDB.db.Query("SELECT id, parent_id, role, model FROM messages WHERE thread_id IN (SELECT id FROM chat_threads WHERE is_deleted=" (showTrash ? 1 : 0) ");")
            for msgRow in msgTable.rows {
                msgMap[msgRow.id] := {
                    parent_id: msgRow.parent_id ? msgRow.parent_id : "",
                    role: msgRow.role,
                    model: msgRow.model ? msgRow.model : ""
                }
            }
        }
        for row in table.rows {
            ; Bug #155: the sidebar badge must reflect the ACTIVE path's model
            ; (the last assistant on the path currently open), not the
            ; LAST-INSERTED assistant row in the thread (which can live on an
            ; off-path branch after a retry/branch switch). Walk from the active
            ; leaf up to the nearest assistant.
            model := ""
            currentId := row.active_leaf_id ? row.active_leaf_id : ""
            while currentId && msgMap.Has(currentId) {
                msg := msgMap[currentId]
                if msg.role = "assistant" && msg.model {
                    model := msg.model
                    break
                }
                currentId := msg.parent_id
            }
            ; Bug (locked chats): a locked thread's real title can leak intent
            ; (e.g. "Salary negotiation", "therapy notes"), so it is redacted
            ; everywhere the list renders - sidebar AND trash - UNLESS the user
            ; already unlocked it in this ChatWindow session (then the real
            ; title is shown and renaming works normally). ThreadLockService
            ; only exists in the ChatWindow process; other processes (Main)
            ; simply keep the redacted title.
            isLocked := Integer(row.is_locked ? row.is_locked : 0)
            title := row.title
            if isLocked && IsSet(ThreadLockService) && !ThreadLockService.IsUnlockedInSession(row.id)
                title := "Locked chat"
            threads.Push({
                id: row.id,
                title: title,
                is_locked: isLocked,
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
        debugLog("[THREAD] Deleted - id=" threadId)
        ChatDB.db.Query("UPDATE chat_threads SET is_deleted=1, deleted_at=datetime('now'), updated_at=datetime('now') WHERE id=?;", threadId)
        ChatDB._MarkPersistentDataChanged()
    }

    ; Restore a trashed thread.
    static Restore(threadId) {
        ChatDB.db.Query("UPDATE chat_threads SET is_deleted=0, deleted_at=NULL, updated_at=datetime('now') WHERE id=?;", threadId)
        ChatDB._MarkPersistentDataChanged()
    }

    ; Permanently delete expired trashed threads.
    static PurgeExpired() {
        if (IsSet(trashRetentionDays) && trashRetentionDays <= 0) || (!IsSet(trashRetentionDays))
            return
        ; Coerce to a number and bind it as the datetime modifier - a crafted
        ; setting value can never alter the SQL text.
        retention := Integer(trashRetentionDays)
        retentionModifier := "-" retention " days"
        ; Clean up attachment files on disk BEFORE the raw SQL DELETEs.
        ; The CASCADE FK would auto-delete message_attachments rows but leave orphan files.
        expiredTable := ChatDB.db.Query("SELECT id FROM chat_threads WHERE is_deleted=1 AND deleted_at < datetime('now', ?);", retentionModifier)
        if !expiredTable.count
            return
        ; Bug #129: keep messages_fts in sync with messages - remove the FTS
        ; rows for every purged message (same guarantee as MessageRepo.HardDelete
        ; -> FTS_Remove). The raw DELETEs below never touch the FTS index.
        changed := false
        for row in expiredTable.rows {
            msgIds := ChatDB.db.Query("SELECT id FROM messages WHERE thread_id=?;", row.id)
            for m in msgIds.rows
                ChatDB.FTS_Remove(m.id)
            if AttachmentRepo.DeleteByThread(row.id, false) > 0
                changed := true
        }
        ChatDB.db.Query("DELETE FROM messages WHERE thread_id IN (SELECT id FROM chat_threads WHERE is_deleted=1 AND deleted_at < datetime('now', ?));", retentionModifier)
        if ThreadRepo._Changes() > 0
            changed := true
        ChatDB.db.Query("DELETE FROM chat_threads WHERE is_deleted=1 AND deleted_at < datetime('now', ?);", retentionModifier)
        if ThreadRepo._Changes() > 0
            changed := true
        if changed
            ChatDB._MarkPersistentDataChanged()
    }

    static _Changes() {
        result := ChatDB.db.Exec("SELECT changes() AS count;")
        return result.count ? Integer(result[1, "count"]) : 0
    }

    ; Permanently delete a thread and all its messages.
    static Delete(threadId) {
        debugLog("[THREAD] Deleted - id=" threadId)
        ; Bug #116: pass the RAW id - DeleteByThread escapes it internally.
        ; Passing safeId (already escaped) double-escaped it, so crafted-id
        ; threads deleted their messages but orphaned their attachment rows.
        AttachmentRepo.DeleteByThread(threadId)
        ; Bug #129: remove the FTS index rows before the raw DELETE - thread-
        ; level delete previously skipped FTS cleanup (unlike HardDelete),
        ; leaving stale index rows until the next startup rebuild.
        msgIds := ChatDB.db.Query("SELECT id FROM messages WHERE thread_id=?;", threadId)
        for m in msgIds.rows
            ChatDB.FTS_Remove(m.id)
        ChatDB.db.Query("DELETE FROM messages WHERE thread_id=?;", threadId)
        ChatDB.db.Query("DELETE FROM chat_threads WHERE id=?;", threadId)
        ChatDB._MarkPersistentDataChanged()
    }

    ; Update thread title and timestamp.
    static Update(threadId, title, updateTimestamp := true) {
        if !threadId
            return
        if updateTimestamp
            ChatDB.db.Query("UPDATE chat_threads SET title=?, updated_at=datetime('now') WHERE id=?;", title, threadId)
        else
            ChatDB.db.Query("UPDATE chat_threads SET title=? WHERE id=?;", title, threadId)
        ChatDB._MarkPersistentDataChanged()
    }
}
