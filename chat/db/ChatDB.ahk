; ======================================================
; ChatDB.ahk — Chat persistence facade
;
; Thin facade over ThreadRepo, MessageRepo, and AssistantRepo.
; All callers use ChatDB.XXX() — internal delegation to repos
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
        ChatDB._CreateSchema()
        ChatDB.isOpen := true
        debugLog("[DB] Opened — path=" ChatDB.dbPath)
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
        try ChatDB.db.Exec("ALTER TABLE chat_threads ADD COLUMN font_size INTEGER DEFAULT 17;")
        ; Right-rail Advanced toggles (Code Execution / Web Search — persisted
        ; stubs), stored as a JSON object, e.g. {"codeExecution":true,...}
        try ChatDB.db.Exec("ALTER TABLE chat_threads ADD COLUMN advanced_toggles TEXT DEFAULT '';")
        ; messages.active_path_tokens: total context tokens from root to this message (inclusive).
        ; For assistants: API prompt_tokens + token_count (ground truth at insert time).
        ; For user/system: parent.active_path_tokens + token_count (prefix sum).
        ; After structural changes (delete/edit): recomputed as parent + token_count.
        ; Read by GetThreadStats() from the leaf message — O(1), no thread-level storage needed.
        ChatDB.db.Exec("CREATE TABLE IF NOT EXISTS messages (id TEXT PRIMARY KEY, thread_id TEXT NOT NULL, role TEXT NOT NULL, content TEXT NOT NULL, model TEXT, parent_id TEXT, sibling_group TEXT, sibling_index INTEGER DEFAULT 0, reasoning TEXT DEFAULT '', token_count INTEGER DEFAULT 0, thinking_tokens INTEGER DEFAULT 0, cached_tokens INTEGER DEFAULT 0, response_time_ms INTEGER DEFAULT 0, ttft_ms INTEGER DEFAULT 0, active_path_tokens INTEGER DEFAULT 0, created_at TEXT DEFAULT (datetime('now')));")
        ChatDB.db.Exec("CREATE TABLE IF NOT EXISTS assistants (id TEXT PRIMARY KEY, name TEXT NOT NULL, base_model TEXT NOT NULL, system_prompt TEXT DEFAULT '', description TEXT DEFAULT '', reasoning TEXT DEFAULT '', temperature REAL DEFAULT NULL, is_default INTEGER DEFAULT 0, created_at TEXT DEFAULT (datetime('now')));")
        try ChatDB.db.Exec("ALTER TABLE assistants ADD COLUMN description TEXT DEFAULT '';")
        ChatDB.db.Exec("CREATE TABLE IF NOT EXISTS chat_folders (id TEXT PRIMARY KEY, name TEXT NOT NULL, created_at TEXT DEFAULT (datetime('now')));")
        ; Add folder_id to chat_threads if it doesn't exist (idempotent)
        try ChatDB.db.Exec("ALTER TABLE chat_threads ADD COLUMN folder_id TEXT REFERENCES chat_folders(id) ON DELETE SET NULL;")
        ChatDB.db.Exec("CREATE TABLE IF NOT EXISTS message_attachments (id TEXT PRIMARY KEY, message_id TEXT NOT NULL, attachment_type TEXT NOT NULL, file_path TEXT NOT NULL, mime_type TEXT, original_filename TEXT, file_size INTEGER DEFAULT 0, extracted_text TEXT DEFAULT '', created_at TEXT DEFAULT (datetime('now')), FOREIGN KEY (message_id) REFERENCES messages(id) ON DELETE CASCADE);")
        ChatDB.db.Exec("CREATE TABLE IF NOT EXISTS command_usage (date TEXT NOT NULL, model TEXT NOT NULL, provider TEXT NOT NULL, command_name TEXT NOT NULL, call_count INTEGER DEFAULT 1, prompt_tokens INTEGER DEFAULT 0, completion_tokens INTEGER DEFAULT 0, thinking_tokens INTEGER DEFAULT 0, cached_tokens INTEGER DEFAULT 0, input_cost REAL DEFAULT 0, cached_input_cost REAL DEFAULT 0, output_cost REAL DEFAULT 0, total_cost REAL DEFAULT 0, total_response_time_ms INTEGER DEFAULT 0, total_ttft_ms INTEGER DEFAULT 0, PRIMARY KEY (date, model, provider, command_name));")
        ChatDB.db.Exec("CREATE TABLE IF NOT EXISTS chat_usage (date TEXT NOT NULL, model TEXT NOT NULL, provider TEXT NOT NULL, call_count INTEGER DEFAULT 1, prompt_tokens INTEGER DEFAULT 0, completion_tokens INTEGER DEFAULT 0, thinking_tokens INTEGER DEFAULT 0, cached_tokens INTEGER DEFAULT 0, input_cost REAL DEFAULT 0, cached_input_cost REAL DEFAULT 0, output_cost REAL DEFAULT 0, total_cost REAL DEFAULT 0, total_response_time_ms INTEGER DEFAULT 0, total_ttft_ms INTEGER DEFAULT 0, PRIMARY KEY (date, model, provider));")
        ChatDB.db.Exec("CREATE INDEX IF NOT EXISTS idx_attachments_message ON message_attachments(message_id);")
        ChatDB.db.Exec("CREATE INDEX IF NOT EXISTS idx_messages_thread ON messages(thread_id);")
        ChatDB.db.Exec("CREATE INDEX IF NOT EXISTS idx_messages_parent ON messages(parent_id);")
        ChatDB.db.Exec("CREATE INDEX IF NOT EXISTS idx_messages_sibling ON messages(sibling_group, sibling_index);")

        ; FTS5 full-text search — maintained incrementally by MessageRepo (FTS_Sync).
        ; Repair on startup only if counts mismatch (first run or corruption).
        ChatDB.db.Exec("CREATE VIRTUAL TABLE IF NOT EXISTS messages_fts USING fts5(msg_id, content);")
        ftsCount := ChatDB.db.Exec("SELECT COUNT(*) AS cnt FROM messages_fts;")
        msgCount := ChatDB.db.Exec("SELECT COUNT(*) AS cnt FROM messages;")
        if Integer(ftsCount[1, "cnt"]) != Integer(msgCount[1, "cnt"]) {
            ChatDB.db.Exec("DELETE FROM messages_fts;")
            ChatDB.db.Exec("INSERT INTO messages_fts(msg_id, content) SELECT id, content FROM messages;")
            debugLog("[DB] FTS5 rebuilt — " Integer(msgCount[1, "cnt"]) " messages indexed")
        }

    }

    ; FTS5 sync — called from MessageRepo on Insert/Edit.
    ; NOTE: SQLite.Escape only doubles internal single quotes (' → ''),
    ; it does NOT wrap in quotes. The caller must add wrapping quotes.
    ;   WRONG: VALUES(..., SQLite.Escape(val))     → VALUES(..., Hi)
    ;   RIGHT: VALUES(..., '" SQLite.Escape(val) "') → VALUES(..., 'Hi')
    static FTS_Sync(msgId, content) {
        ChatDB.db.Exec("DELETE FROM messages_fts WHERE msg_id='" msgId "';")
        safeContent := SQLite.Escape(content)
        try {
            ; Wrapping quotes around safeContent: '" safeContent "'
            ChatDB.db.Exec("INSERT INTO messages_fts(msg_id, content) VALUES('" msgId "', '" safeContent "');")
        } catch Error as e {
            debugLog("[FTS] Sync ERROR: " e.Message, "FTS")
        }
    }

    static FTS_Remove(msgId) {
        ChatDB.db.Exec("DELETE FROM messages_fts WHERE msg_id='" msgId "';")
    }

    static _UUID() {
        return Format("{1:08x}-{2:04x}-{3:04x}-{4:04x}-{5:012x}",
            A_TickCount, Random(0, 0xFFFF), Random(0, 0xFFFF),
            Random(0, 0xFFFF), Random(0, 0xFFFFFFFF))
    }

    ; Thread operations — delegate to ThreadRepo
    static Thread_Create(title := "New Chat") => ThreadRepo.Create(title)
    static Thread_UpdateSettings(threadId, settings) => ThreadRepo.UpdateSettings(threadId, settings)
    static Thread_GetSettings(threadId) => ThreadRepo.GetSettings(threadId)
    static Thread_List(showTrash := false) => ThreadRepo.List(showTrash)
    static Thread_SoftDelete(threadId) => ThreadRepo.SoftDelete(threadId)
    static Thread_Restore(threadId) => ThreadRepo.Restore(threadId)
    static Thread_PurgeExpired() => ThreadRepo.PurgeExpired()
    static Thread_Delete(threadId) => ThreadRepo.Delete(threadId)
    static Thread_Update(threadId, title, updateTimestamp := true) => ThreadRepo.Update(threadId, title, updateTimestamp)

    ; Message operations — delegate to MessageRepo
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

    ; Attachment operations — delegate to AttachmentRepo
    static Attachment_Insert(msgId, attObj) => AttachmentRepo.Insert(msgId, attObj)
    static Attachment_Save(msgId, att) => AttachmentRepo.SaveAttachment(msgId, att)
    static Attachment_GetByMessage(msgId) => AttachmentRepo.GetByMessage(msgId)
    static Attachment_GetByThread(threadId) => AttachmentRepo.GetByThread(threadId)
    static Attachment_DeleteByMessage(msgId) => AttachmentRepo.DeleteByMessage(msgId)
    static Attachment_DeleteByThread(threadId) => AttachmentRepo.DeleteByThread(threadId)
    static Attachment_DeleteOne(attachmentId) => AttachmentRepo.DeleteOne(attachmentId)
    static Attachment_CopyForMessage(srcMsgId, dstMsgId) => AttachmentRepo.CopyForMessage(srcMsgId, dstMsgId)

    ; Usage operations — delegate to UsageRepo
    static Usage_Query(filters) => UsageRepo.Query(filters)
    static CommandUsage_Upsert(data) => UsageRepo.CommandUpsert(data)
    static ChatUsage_Upsert(data) => UsageRepo.ChatUpsert(data)

    ; Search operations — delegate to SearchRepo
    static SearchMessages(query, threadId := "") => SearchRepo.Search(query, threadId)
}
