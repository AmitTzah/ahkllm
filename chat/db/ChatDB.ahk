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
#Include AttachmentRepo.ahk

class ChatDB {
    static db := unset
    static dbPath := ""
    static isOpen := false

    ; Open (or create) the database.
    static Open(dbPath := "") {
        if ChatDB.isOpen
            return
        if !dbPath || InStr(dbPath, "LLM-AutoHotkey-Assistant") {
            if IsSet(testMode) && testMode {
                FileAppend("[CRITICAL] ChatDB.Open() attempted production DB path in test mode! Path: '" dbPath "'`n", "*")
                ExitApp(99)
            }
        }
        ChatDB.dbPath := dbPath ? dbPath : A_AppData "\LLM-AutoHotkey-Assistant\chat_history.db"
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

    ; Assistant operations — delegate to AssistantRepo
    static Assistant_Seed() => AssistantRepo.Seed()
    static Assistant_List() => AssistantRepo.List()
    static Assistant_Get(assistantId) => AssistantRepo.Get(assistantId)

    ; Attachment operations — delegate to AttachmentRepo
    static Attachment_Insert(msgId, attObj) => AttachmentRepo.Insert(msgId, attObj)
    static Attachment_Save(msgId, att) => AttachmentRepo.SaveAttachment(msgId, att)
    static Attachment_GetByMessage(msgId) => AttachmentRepo.GetByMessage(msgId)
    static Attachment_GetByThread(threadId) => AttachmentRepo.GetByThread(threadId)
    static Attachment_DeleteByMessage(msgId) => AttachmentRepo.DeleteByMessage(msgId)
    static Attachment_DeleteByThread(threadId) => AttachmentRepo.DeleteByThread(threadId)
    static Attachment_DeleteOne(attachmentId) => AttachmentRepo.DeleteOne(attachmentId)
    static Attachment_CopyForMessage(srcMsgId, dstMsgId) => AttachmentRepo.CopyForMessage(srcMsgId, dstMsgId)

    ; Build WHERE clause for date-based time range filters
    static _WhereDate(range, dateColumn := "date") {
        if range = "day"
            return "WHERE " dateColumn " >= date('now', '-1 day')"
        if range = "month"
            return "WHERE " dateColumn " >= date('now', '-30 days')"
        if range = "thisMonth"
            return "WHERE " dateColumn " >= date('now', 'start of month')"
        if range = "lastMonth"
            return "WHERE " dateColumn " >= date('now', 'start of month', '-1 month') AND " dateColumn " < date('now', 'start of month')"
        return ""
    }

    ; Usage dashboard — query aggregated data
    static Usage_Query(filters) {
        result := { chat: [], commands: [], models: [], providers: [] }

        timeRange := filters.Has("timeRange") ? filters["timeRange"] : "all"
        modelFilter := filters.Has("model") ? filters["model"] : ""
        modelClause := modelFilter ? "AND model='" SQLite.Escape(modelFilter) "'" : ""
        providerFilter := filters.Has("provider") ? filters["provider"] : ""
        providerChatClause := providerFilter ? "AND model LIKE '" SQLite.Escape(providerFilter) "/%'" : ""
        typeFilter := filters.Has("type") ? filters["type"] : "all"

        ; Chat data — from chat_usage table
        if typeFilter != "command" {
            chatWhere := ChatDB._WhereDate(timeRange)
            if modelFilter
                chatWhere .= (chatWhere ? " AND" : "WHERE") " model='" SQLite.Escape(modelFilter) "'"
            if providerFilter
                chatWhere .= (chatWhere ? " AND" : "WHERE") " provider='" SQLite.Escape(providerFilter) "'"

            chatSql := "SELECT date, model, provider, call_count, prompt_tokens, completion_tokens, thinking_tokens, cached_tokens, input_cost, cached_input_cost, output_cost, total_cost, total_response_time_ms, total_ttft_ms FROM chat_usage " chatWhere " ORDER BY date DESC, model"
            chatTable := ChatDB.db.Exec(chatSql)
            for row in chatTable.rows {
                result.chat.Push({
                    date: row.date, model: row.model, provider: row.provider,
                    input_tokens: Integer(row.prompt_tokens),
                    output_tokens: Integer(row.completion_tokens),
                    cached_tokens: Integer(row.cached_tokens),
                    message_count: Integer(row.call_count),
                    thinking_tokens: Integer(row.thinking_tokens),
                    total_cost: Number(row.total_cost),
                    input_cost: Number(row.input_cost),
                    cached_input_cost: Number(row.cached_input_cost),
                    output_cost: Number(row.output_cost),
                    total_response_time_ms: Integer(row.total_response_time_ms),
                    total_ttft_ms: Integer(row.total_ttft_ms)
                })
            }
        }

        ; Command data — only if type includes commands
        if typeFilter != "chat" {
            cmdWhere := ChatDB._WhereDate(timeRange)
            if modelFilter
                cmdWhere .= (cmdWhere ? " AND" : "WHERE") " model='" SQLite.Escape(modelFilter) "'"
            if providerFilter
                cmdWhere .= (cmdWhere ? " AND" : "WHERE") " provider='" SQLite.Escape(providerFilter) "'"

            cmdSql := "SELECT date, model, provider, command_name, call_count, prompt_tokens, completion_tokens, thinking_tokens, cached_tokens, input_cost, cached_input_cost, output_cost, total_cost, total_response_time_ms, total_ttft_ms FROM command_usage " cmdWhere " ORDER BY date DESC"
            cmdTable := ChatDB.db.Exec(cmdSql)
            for row in cmdTable.rows {
                result.commands.Push({
                    date: row.date, model: row.model, provider: row.provider,
                    command_name: row.command_name, call_count: Integer(row.call_count),
                    prompt_tokens: Integer(row.prompt_tokens),
                    completion_tokens: Integer(row.completion_tokens),
                    thinking_tokens: Integer(row.thinking_tokens),
                    cached_tokens: Integer(row.cached_tokens),
                    input_cost: Number(row.input_cost),
                    cached_input_cost: Number(row.cached_input_cost),
                    output_cost: Number(row.output_cost),
                    total_cost: Number(row.total_cost),
                    total_response_time_ms: Integer(row.total_response_time_ms),
                    total_ttft_ms: Integer(row.total_ttft_ms)
                })
            }
        }

        ; Distinct models and providers — always unfiltered (dropdowns need full lists)
        modelsTable := ChatDB.db.Exec("SELECT DISTINCT model FROM chat_usage UNION SELECT DISTINCT model FROM command_usage ORDER BY model")
        for row in modelsTable.rows
            result.models.Push(row.model)

        provTable := ChatDB.db.Exec("SELECT DISTINCT provider FROM chat_usage UNION SELECT DISTINCT provider FROM command_usage ORDER BY provider")
        for row in provTable.rows {
            if row.provider && row.provider != ""
                result.providers.Push(row.provider)
        }

        debugLog("[DASHBOARD] Query — chat=" result.chat.Length " rows, cmd=" result.commands.Length " rows, type=" typeFilter " time=" timeRange)
        return result
    }

    ; Command usage — daily aggregation UPSERT
    static CommandUsage_Upsert(data) {
        date := data.date, model := data.model, provider := data.provider, cmd := data.command_name
        tht := data.HasProp("thinking_tokens") ? data.thinking_tokens : 0
        ckt := data.HasProp("cached_tokens") ? data.cached_tokens : 0
        cci := data.HasProp("cached_input_cost") ? data.cached_input_cost : 0
        lat := data.HasProp("response_time_ms") ? data.response_time_ms : 0
        ttft := data.HasProp("ttft_ms") ? data.ttft_ms : 0
        existing := ChatDB.db.Exec("SELECT call_count FROM command_usage WHERE date='" date "' AND model='" SQLite.Escape(model) "' AND provider='" SQLite.Escape(provider) "' AND command_name='" SQLite.Escape(cmd) "';")
        if existing.count {
            ChatDB.db.Exec("UPDATE command_usage SET call_count=call_count+1, prompt_tokens=prompt_tokens+" data.prompt_tokens ", completion_tokens=completion_tokens+" data.completion_tokens ", thinking_tokens=thinking_tokens+" tht ", cached_tokens=cached_tokens+" ckt ", input_cost=input_cost+" data.input_cost ", cached_input_cost=cached_input_cost+" cci ", output_cost=output_cost+" data.output_cost ", total_cost=total_cost+" data.total_cost ", total_response_time_ms=total_response_time_ms+" lat ", total_ttft_ms=total_ttft_ms+" ttft " WHERE date='" date "' AND model='" SQLite.Escape(model) "' AND provider='" SQLite.Escape(provider) "' AND command_name='" SQLite.Escape(cmd) "';")
        } else {
            ChatDB.db.Exec("INSERT INTO command_usage (date, model, provider, command_name, call_count, prompt_tokens, completion_tokens, thinking_tokens, cached_tokens, input_cost, cached_input_cost, output_cost, total_cost, total_response_time_ms, total_ttft_ms) VALUES('" date "', '" SQLite.Escape(model) "', '" SQLite.Escape(provider) "', '" SQLite.Escape(cmd) "', 1, " data.prompt_tokens ", " data.completion_tokens ", " tht ", " ckt ", " data.input_cost ", " cci ", " data.output_cost ", " data.total_cost ", " lat ", " ttft ");")
        }
    }

    ; Chat usage — daily aggregation UPSERT
    static ChatUsage_Upsert(data) {
        date := data.date, model := data.model, provider := data.provider
        tht := data.HasProp("thinking_tokens") ? data.thinking_tokens : 0
        ckt := data.HasProp("cached_tokens") ? data.cached_tokens : 0
        cci := data.HasProp("cached_input_cost") ? data.cached_input_cost : 0
        lat := data.HasProp("response_time_ms") ? data.response_time_ms : 0
        ttft := data.HasProp("ttft_ms") ? data.ttft_ms : 0
        existing := ChatDB.db.Exec("SELECT call_count FROM chat_usage WHERE date='" date "' AND model='" SQLite.Escape(model) "' AND provider='" SQLite.Escape(provider) "';")
        if existing.count {
            ChatDB.db.Exec("UPDATE chat_usage SET call_count=call_count+1, prompt_tokens=prompt_tokens+" data.prompt_tokens ", completion_tokens=completion_tokens+" data.completion_tokens ", thinking_tokens=thinking_tokens+" tht ", cached_tokens=cached_tokens+" ckt ", input_cost=input_cost+" data.input_cost ", cached_input_cost=cached_input_cost+" cci ", output_cost=output_cost+" data.output_cost ", total_cost=total_cost+" data.total_cost ", total_response_time_ms=total_response_time_ms+" lat ", total_ttft_ms=total_ttft_ms+" ttft " WHERE date='" date "' AND model='" SQLite.Escape(model) "' AND provider='" SQLite.Escape(provider) "';")
        } else {
            ChatDB.db.Exec("INSERT INTO chat_usage (date, model, provider, call_count, prompt_tokens, completion_tokens, thinking_tokens, cached_tokens, input_cost, cached_input_cost, output_cost, total_cost, total_response_time_ms, total_ttft_ms) VALUES('" date "', '" SQLite.Escape(model) "', '" SQLite.Escape(provider) "', 1, " data.prompt_tokens ", " data.completion_tokens ", " tht ", " ckt ", " data.input_cost ", " cci ", " data.output_cost ", " data.total_cost ", " lat ", " ttft ");")
        }
    }
}
