; ======================================================
; ChatDB.ahk - Chat persistence facade
;
; Thin facade over ThreadRepo, MessageRepo, and AssistantRepo.
; All callers use ChatDB.XXX() - internal delegation to repos
; is transparent.
; ======================================================

; Include repo implementations (must be at top level)
#Include ThreadRepo.ahk
#Include MessageRepo.ahk
#Include TreeRepo.ahk
#Include AssistantRepo.ahk
#Include SearchRepo.ahk
#Include AttachmentRepo.ahk
#Include UsageRepo.ahk
#Include ..\..\shared\AppInfo.ahk

class ChatDB {
    static db := unset
    static dbPath := ""
    static isOpen := false

    ; Open (or create) the database.
    static Open(dbPath := "") {
        if ChatDB.isOpen
            return
        if !dbPath || InStr(dbPath, AppInfo.Name) {
            if IsSet(testMode) && testMode {
                FileAppend("[CRITICAL] ChatDB.Open() attempted production DB path in test mode! Path: '" dbPath "'`n", "*")
                ExitApp(99)
            }
        }
        ChatDB.dbPath := dbPath ? dbPath : AppInfo.DataDir "\chat_history.db"
        dirPath := SubStr(ChatDB.dbPath, 1, InStr(ChatDB.dbPath, "\", , -1))
        if !DirExist(dirPath)
            DirCreate(dirPath)
        ChatDB.db := SQLite(ChatDB.dbPath)
        ChatDB.db.Exec("PRAGMA journal_mode=WAL;")
        ChatDB.db.Exec("PRAGMA busy_timeout=5000;")
        ; Hardening item 2: enforce referential integrity (ON DELETE CASCADE /
        ; SET NULL) instead of relying on app-side deletion order.
        ChatDB.db.Exec("PRAGMA foreign_keys=ON;")
        ChatDB._CreateSchema()
        ChatDB.isOpen := true
        debugLog("[DB] Opened - path=" ChatDB.dbPath)
    }

    static Close() {
        if ChatDB.isOpen {
            ChatDB.db.Close()
            ChatDB.db := unset
            ChatDB.isOpen := false
        }
    }

    static _CreateSchema() {
        ChatDB.db.Exec("CREATE TABLE IF NOT EXISTS chat_threads (id TEXT PRIMARY KEY, title TEXT DEFAULT 'New Chat', is_deleted INTEGER DEFAULT 0, deleted_at TEXT, created_at TEXT DEFAULT (datetime('now')), updated_at TEXT DEFAULT (datetime('now')), active_leaf_id TEXT, cumulative_input_tokens INTEGER DEFAULT 0, cumulative_output_tokens INTEGER DEFAULT 0, cumulative_cached_tokens INTEGER DEFAULT 0, cumulative_cost REAL DEFAULT 0, cumulative_input_cost REAL DEFAULT 0, cumulative_cached_input_cost REAL DEFAULT 0, cumulative_output_cost REAL DEFAULT 0, assistant_id TEXT, model_override TEXT, system_override TEXT, reasoning_override TEXT, temperature_override REAL);")
        ChatDB.db.Exec("CREATE TABLE IF NOT EXISTS messages (id TEXT PRIMARY KEY, thread_id TEXT NOT NULL, role TEXT NOT NULL, content TEXT NOT NULL, model TEXT, parent_id TEXT, sibling_group TEXT, sibling_index INTEGER DEFAULT 0, reasoning TEXT DEFAULT '', token_count INTEGER DEFAULT 0, prompt_tokens INTEGER DEFAULT 0, thinking_tokens INTEGER DEFAULT 0, cached_tokens INTEGER DEFAULT 0, response_time_ms INTEGER DEFAULT 0, ttft_ms INTEGER DEFAULT 0, active_path_tokens INTEGER DEFAULT 0, is_local_copy INTEGER DEFAULT 0, input_cost REAL DEFAULT 0, cached_input_cost REAL DEFAULT 0, output_cost REAL DEFAULT 0, total_cost REAL DEFAULT 0, created_at TEXT DEFAULT (datetime('now')));")
        ChatDB.db.Exec("CREATE TABLE IF NOT EXISTS assistants (id TEXT PRIMARY KEY, name TEXT NOT NULL, base_model TEXT NOT NULL, system_prompt TEXT DEFAULT '', description TEXT DEFAULT '', reasoning TEXT DEFAULT '', temperature REAL DEFAULT NULL, is_default INTEGER DEFAULT 0, created_at TEXT DEFAULT (datetime('now')));")
        ChatDB.db.Exec("CREATE TABLE IF NOT EXISTS chat_folders (id TEXT PRIMARY KEY, name TEXT NOT NULL, created_at TEXT DEFAULT (datetime('now')));")
        ChatDB.db.Exec("CREATE TABLE IF NOT EXISTS message_attachments (id TEXT PRIMARY KEY, message_id TEXT NOT NULL, attachment_type TEXT NOT NULL, file_path TEXT NOT NULL, mime_type TEXT, original_filename TEXT, file_size INTEGER DEFAULT 0, extracted_text TEXT DEFAULT '', created_at TEXT DEFAULT (datetime('now')), FOREIGN KEY (message_id) REFERENCES messages(id) ON DELETE CASCADE);")
        ChatDB.db.Exec("CREATE TABLE IF NOT EXISTS command_usage (date TEXT NOT NULL, model TEXT NOT NULL, provider TEXT NOT NULL, command_name TEXT NOT NULL, call_count INTEGER DEFAULT 1, prompt_tokens INTEGER DEFAULT 0, completion_tokens INTEGER DEFAULT 0, thinking_tokens INTEGER DEFAULT 0, cached_tokens INTEGER DEFAULT 0, input_cost REAL DEFAULT 0, cached_input_cost REAL DEFAULT 0, output_cost REAL DEFAULT 0, total_cost REAL DEFAULT 0, total_response_time_ms INTEGER DEFAULT 0, total_ttft_ms INTEGER DEFAULT 0, PRIMARY KEY (date, model, provider, command_name));")
        ChatDB.db.Exec("CREATE TABLE IF NOT EXISTS chat_usage (date TEXT NOT NULL, model TEXT NOT NULL, provider TEXT NOT NULL, call_count INTEGER DEFAULT 1, prompt_tokens INTEGER DEFAULT 0, completion_tokens INTEGER DEFAULT 0, thinking_tokens INTEGER DEFAULT 0, cached_tokens INTEGER DEFAULT 0, input_cost REAL DEFAULT 0, cached_input_cost REAL DEFAULT 0, output_cost REAL DEFAULT 0, total_cost REAL DEFAULT 0, total_response_time_ms INTEGER DEFAULT 0, total_ttft_ms INTEGER DEFAULT 0, PRIMARY KEY (date, model, provider));")
        ChatDB.db.Exec("CREATE INDEX IF NOT EXISTS idx_attachments_message ON message_attachments(message_id);")
        ChatDB.db.Exec("CREATE INDEX IF NOT EXISTS idx_messages_thread ON messages(thread_id);")
        ChatDB.db.Exec("CREATE INDEX IF NOT EXISTS idx_messages_parent ON messages(parent_id);")
        ChatDB.db.Exec("CREATE INDEX IF NOT EXISTS idx_messages_sibling ON messages(sibling_group, sibling_index);")

        ; Hardening item 2: schema evolution is versioned (PRAGMA user_version)
        ; instead of unconditional try/catch ALTER TABLEs.
        ChatDB._Migrate()

        ; FTS5 full-text search - maintained incrementally by MessageRepo (FTS_Sync).
        ; Repair on startup only if counts mismatch (first run or corruption).
        ChatDB.db.Exec("CREATE VIRTUAL TABLE IF NOT EXISTS messages_fts USING fts5(msg_id, content);")
        ftsCount := ChatDB.db.Exec("SELECT COUNT(*) AS cnt FROM messages_fts;")
        msgCount := ChatDB.db.Exec("SELECT COUNT(*) AS cnt FROM messages;")
        if Integer(ftsCount[1, "cnt"]) != Integer(msgCount[1, "cnt"]) {
            ChatDB.db.Exec("DELETE FROM messages_fts;")
            ChatDB.db.Exec("INSERT INTO messages_fts(msg_id, content) SELECT id, content FROM messages;")
            ; Bug #165: the rebuild must also index attachment extracted_text
            ; (the bulk SQL above cannot decode the base64-stored text).
            attMsgs := ChatDB.db.Query("SELECT DISTINCT message_id FROM message_attachments WHERE extracted_text != '';")
            for am in attMsgs.rows
                ChatDB.FTS_ResyncForAttachments(am.message_id)
            debugLog("[DB] FTS5 rebuilt - " Integer(msgCount[1, "cnt"]) " messages indexed")
        }

    }

    ; Versioned migrations. Each step runs only when user_version is behind,
    ; and _AddColumnIfMissing skips columns that already exist, so old
    ; databases are brought forward exactly once and fresh databases no-op.
    static _Migrate() {
        versionRow := ChatDB.db.Exec("PRAGMA user_version;")
        version := versionRow.count ? Integer(versionRow[1, "user_version"]) : 0

        ; v1: per-thread font size + right-rail Advanced toggles.
        if version < 1 {
            ChatDB._AddColumnIfMissing("chat_threads", "font_size", "INTEGER DEFAULT 17")
            ChatDB._AddColumnIfMissing("chat_threads", "advanced_toggles", "TEXT DEFAULT ''")
            ChatDB.db.Exec("PRAGMA user_version = 1;")
        }
        ; v2: folder membership.
        if version < 2 {
            ChatDB._AddColumnIfMissing("chat_threads", "folder_id", "TEXT REFERENCES chat_folders(id) ON DELETE SET NULL")
            ChatDB.db.Exec("PRAGMA user_version = 2;")
        }
        ; v3: assistant API prompt_tokens ground truth (bug #107).
        if version < 3 {
            ChatDB._AddColumnIfMissing("messages", "prompt_tokens", "INTEGER DEFAULT 0")
            ChatDB.db.Exec("PRAGMA user_version = 3;")
        }
        ; v4: assistant description.
        if version < 4 {
            ChatDB._AddColumnIfMissing("assistants", "description", "TEXT DEFAULT ''")
            ChatDB.db.Exec("PRAGMA user_version = 4;")
        }
        ; v5: persisted local-copy flag (bug #144) so cumulative counters and
        ; token backfills can distinguish a local branch-edit copy from a real
        ; API call.
        if version < 5 {
            ChatDB._AddColumnIfMissing("messages", "is_local_copy", "INTEGER DEFAULT 0")
            ChatDB.db.Exec("PRAGMA user_version = 5;")
        }
        ; v6: per-message COST snapshots (bug #153) - a later price change in
        ; Settings must never re-price a thread's HISTORICAL calls. New inserts
        ; snapshot their costs at the price in effect when the call was made;
        ; legacy rows are backfilled once from the current model prices (best
        ; effort - a fresh open without pricing data simply leaves them 0, and
        ; _RecomputeCumulativeCounters falls back to current prices for those).
        if version < 6 {
            ChatDB._AddColumnIfMissing("messages", "input_cost", "REAL DEFAULT 0")
            ChatDB._AddColumnIfMissing("messages", "cached_input_cost", "REAL DEFAULT 0")
            ChatDB._AddColumnIfMissing("messages", "output_cost", "REAL DEFAULT 0")
            ChatDB._AddColumnIfMissing("messages", "total_cost", "REAL DEFAULT 0")
            try {
                legacyRows := ChatDB.db.Query("SELECT id, model, token_count, prompt_tokens, thinking_tokens, cached_tokens FROM messages WHERE role='assistant' AND model IS NOT NULL AND model != '';")
                for legacyRow in legacyRows.rows {
                    pt := Integer(legacyRow.prompt_tokens ? legacyRow.prompt_tokens : 0)
                    ct := Integer(legacyRow.token_count ? legacyRow.token_count : 0)
                    tht := Integer(legacyRow.thinking_tokens ? legacyRow.thinking_tokens : 0)
                    ckt := Integer(legacyRow.cached_tokens ? legacyRow.cached_tokens : 0)
                    if pt = 0 && ct = 0 && tht = 0 && ckt = 0
                        continue
                    usage := { promptTokens: pt, completionTokens: ct + tht, totalTokens: pt + ct + tht, cachedTokens: ckt }
                    costs := CostCalculator.ComputeTokenCosts(legacyRow.model, usage)
                    if costs.totalCost != "" {
                        ChatDB.db.Query("UPDATE messages SET input_cost=?, cached_input_cost=?, output_cost=?, total_cost=? WHERE id=?;", costs.inputCost != "" ? costs.inputCost : 0, costs.cachedInputCost != "" ? costs.cachedInputCost : 0, costs.outputCost != "" ? costs.outputCost : 0, costs.totalCost, legacyRow.id)
                    }
                }
            }
            ChatDB.db.Exec("PRAGMA user_version = 6;")
        }
    }

    ; Add a column only when it is missing (table/column names are trusted
    ; constants, never user input).
    static _AddColumnIfMissing(tableName, columnName, definition) {
        cols := ChatDB.db.Exec("PRAGMA table_info(" tableName ");")
        for row in cols.rows {
            if row.name = columnName
                return
        }
        ChatDB.db.Exec("ALTER TABLE " tableName " ADD COLUMN " columnName " " definition ";")
    }

    ; FTS5 sync - called from MessageRepo on Insert/Edit.
    ; Values are bound parameters - msg_id/content can never alter the SQL.
    static FTS_Sync(msgId, content) {
        ; Bug #165: index attachment extracted_text too, so a term inside an
        ; attached PDF/office file is searchable (it is part of the context
        ; the API sees). The column stores base64 - decode it for the index.
        attachedText := ""
        attRows := ChatDB.db.Query("SELECT extracted_text FROM message_attachments WHERE message_id=?;", msgId)
        for attRow in attRows.rows {
            if attRow.extracted_text
                attachedText .= " " AttachmentRepo._Base64ToStr(attRow.extracted_text)
        }
        if attachedText
            content := content " " attachedText
        try {
            ChatDB.db.Query("DELETE FROM messages_fts WHERE msg_id=?;", msgId)
            ChatDB.db.Query("INSERT INTO messages_fts(msg_id, content) VALUES(?, ?);", msgId, content)
        } catch Error as e {
            debugLog("[FTS] Sync ERROR: " e.Message, "FTS")
        }
    }

    ; Re-index a message's FTS entry after its attachments change (bug #165).
    static FTS_ResyncForAttachments(msgId) {
        row := ChatDB.db.Query("SELECT content FROM messages WHERE id=?;", msgId)
        if row.count
            ChatDB.FTS_Sync(msgId, row[1, "content"])
    }

    static FTS_Remove(msgId) {
        ChatDB.db.Query("DELETE FROM messages_fts WHERE msg_id=?;", msgId)
    }

    static _UUID() {
        return Format("{1:08x}-{2:04x}-{3:04x}-{4:04x}-{5:012x}",
            A_TickCount, Random(0, 0xFFFF), Random(0, 0xFFFF),
            Random(0, 0xFFFF), Random(0, 0xFFFFFFFF))
    }

    ; Thread operations - delegate to ThreadRepo
    static Thread_Create(title := "New Chat") => ThreadRepo.Create(title)
    static Thread_UpdateSettings(threadId, settings) => ThreadRepo.UpdateSettings(threadId, settings)
    static Thread_GetSettings(threadId) => ThreadRepo.GetSettings(threadId)
    static Thread_List(showTrash := false) => ThreadRepo.List(showTrash)
    static Thread_SoftDelete(threadId) => ThreadRepo.SoftDelete(threadId)
    static Thread_Restore(threadId) => ThreadRepo.Restore(threadId)
    static Thread_PurgeExpired() => ThreadRepo.PurgeExpired()
    static Thread_Delete(threadId) => ThreadRepo.Delete(threadId)
    static Thread_Update(threadId, title, updateTimestamp := true) => ThreadRepo.Update(threadId, title, updateTimestamp)

    ; Message operations - delegate to MessageRepo
    static Msg_Insert(msgObj) => MessageRepo.Insert(msgObj)
    static Msg_HardDelete(msgId) => MessageRepo.HardDelete(msgId)
    static Msg_Edit(msgId, newContent) => MessageRepo.Edit(msgId, newContent)
    static Msg_GetActivePath(threadId) => TreeRepo.GetActivePath(threadId)
    static Msg_GetSiblings(msgId) => TreeRepo.GetSiblings(msgId)
    static Msg_GetTree(threadId) => TreeRepo.GetTree(threadId)
    static Msg_ForkThread(threadId, upToMsgId) => TreeRepo.ForkThread(threadId, upToMsgId)
    static Msg_SetActiveLeaf(threadId, msgId) => TreeRepo.SetActiveLeaf(threadId, msgId)
    static Msg_SwitchBranch(threadId, msgId, direction := 1) => TreeRepo.SwitchBranch(threadId, msgId, direction)
    static Msg_GetThreadStats(threadId) => TreeRepo.GetThreadStats(threadId)

    ; Attachment operations - delegate to AttachmentRepo
    static Attachment_Insert(msgId, attObj) => AttachmentRepo.Insert(msgId, attObj)
    static Attachment_Save(msgId, att) => AttachmentRepo.SaveAttachment(msgId, att)
    static Attachment_GetByMessage(msgId) => AttachmentRepo.GetByMessage(msgId)
    static Attachment_GetByThread(threadId) => AttachmentRepo.GetByThread(threadId)
    static Attachment_DeleteByMessage(msgId) => AttachmentRepo.DeleteByMessage(msgId)
    static Attachment_DeleteByThread(threadId) => AttachmentRepo.DeleteByThread(threadId)
    static Attachment_DeleteOne(attachmentId) => AttachmentRepo.DeleteOne(attachmentId)
    static Attachment_CopyForMessage(srcMsgId, dstMsgId, excludeAttachmentIds := "") => AttachmentRepo.CopyForMessage(srcMsgId, dstMsgId, excludeAttachmentIds)

    ; Usage operations - delegate to UsageRepo
    static Usage_Query(filters) => UsageRepo.Query(filters)
    static CommandUsage_Upsert(data) => UsageRepo.CommandUpsert(data)
    static ChatUsage_Upsert(data) => UsageRepo.ChatUpsert(data)

    ; Search operations - delegate to SearchRepo
    static SearchMessages(query, threadId := "") => SearchRepo.Search(query, threadId)
}
