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
    }

    static Close() {
        if ChatDB.isOpen {
            ChatDB.db.Close()
            ChatDB.db := unset
            ChatDB.isOpen := false
        }
    }

    static _CreateSchema() {
        ChatDB.db.Exec("CREATE TABLE IF NOT EXISTS chat_threads (id TEXT PRIMARY KEY, title TEXT DEFAULT 'New Chat', is_deleted INTEGER DEFAULT 0, deleted_at TEXT, created_at TEXT DEFAULT (datetime('now')), updated_at TEXT DEFAULT (datetime('now')), active_leaf_id TEXT, active_path_tokens INTEGER DEFAULT 0, cumulative_prompt_tokens INTEGER DEFAULT 0, cumulative_completion_tokens INTEGER DEFAULT 0, cumulative_cached_tokens INTEGER DEFAULT 0, cumulative_total_tokens INTEGER DEFAULT 0, cumulative_cost REAL DEFAULT 0, cumulative_input_cost REAL DEFAULT 0, cumulative_cached_input_cost REAL DEFAULT 0, cumulative_output_cost REAL DEFAULT 0, assistant_id TEXT, model_override TEXT, system_override TEXT, reasoning_override TEXT, temperature_override REAL);")
        ChatDB.db.Exec("CREATE TABLE IF NOT EXISTS messages (id TEXT PRIMARY KEY, thread_id TEXT NOT NULL, role TEXT NOT NULL, content TEXT NOT NULL, model TEXT, parent_id TEXT, sibling_group TEXT, sibling_index INTEGER DEFAULT 0, feedback INTEGER, reasoning TEXT DEFAULT '', prompt_tokens INTEGER DEFAULT 0, completion_tokens INTEGER DEFAULT 0, cached_tokens INTEGER DEFAULT 0, total_tokens INTEGER DEFAULT 0, created_at TEXT DEFAULT (datetime('now')));")
        ChatDB.db.Exec("CREATE TABLE IF NOT EXISTS assistants (id TEXT PRIMARY KEY, name TEXT NOT NULL, base_model TEXT NOT NULL, system_prompt TEXT DEFAULT '', reasoning TEXT DEFAULT '', temperature REAL DEFAULT NULL, is_default INTEGER DEFAULT 0, created_at TEXT DEFAULT (datetime('now')));")
        try ChatDB.db.Exec("ALTER TABLE chat_threads ADD COLUMN assistant_id TEXT;")
        try ChatDB.db.Exec("ALTER TABLE chat_threads ADD COLUMN model_override TEXT;")
        try ChatDB.db.Exec("ALTER TABLE chat_threads ADD COLUMN system_override TEXT;")
        try ChatDB.db.Exec("ALTER TABLE chat_threads ADD COLUMN reasoning_override TEXT;")
        try ChatDB.db.Exec("ALTER TABLE chat_threads ADD COLUMN temperature_override REAL;")
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
    static Msg_SetFeedback(msgId, rating) => MessageRepo.SetFeedback(msgId, rating)
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
}
