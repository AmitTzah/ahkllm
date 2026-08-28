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
#Include ThreadLockRepo.ahk
#Include ..\..\shared\AppInfo.ahk

class ChatDB {
    static db := unset
    static dbPath := ""
    static isOpen := false
    static _transactionDepth := 0
    static _deferredFileDeletes := []
    static _createdFiles := []
    static _reclaimRequested := false

    ; Notify the Main-owned BackupManager, or forward the notification when
    ; this facade is running inside ChatWindow.
    static _MarkPersistentDataChanged() => BackupManager.MarkPersistentDataChanged()

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
        ; This file-reclamation mode must be selected before journal setup or
        ; any table is created on a fresh database.
        ChatDB.db.Exec("PRAGMA auto_vacuum=INCREMENTAL;")
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
            if ChatDB._transactionDepth
                ChatDB.RollbackTransaction()
            ChatDB.db.Close()
            ChatDB.db := unset
            ChatDB.isOpen := false
        }
    }

    ; Structural mutations use one DB transaction. Files referenced by rows are
    ; deleted only after COMMIT, so a rollback can never restore a row whose
    ; physical attachment was already removed.
    static BeginTransaction() {
        if ChatDB._transactionDepth
            throw Error("nested ChatDB transaction")
        ChatDB.db.Exec("BEGIN;")
        ChatDB._transactionDepth := 1
        ChatDB._deferredFileDeletes := []
        ChatDB._createdFiles := []
        ChatDB._reclaimRequested := false
    }

    static CommitTransaction() {
        if !ChatDB._transactionDepth
            return
        ChatDB.db.Exec("COMMIT;")
        ChatDB._transactionDepth := 0
        reclaim := ChatDB._reclaimRequested
        pending := ChatDB._deferredFileDeletes
        ChatDB._deferredFileDeletes := []
        ChatDB._createdFiles := []
        ChatDB._reclaimRequested := false
        ChatDB._DeleteCommittedOrphanFiles(pending)
        if reclaim
            ChatDB._ReclaimSpace()
    }

    static RollbackTransaction() {
        if !ChatDB._transactionDepth
            return
        created := ChatDB._createdFiles
        try ChatDB.db.Exec("ROLLBACK;")
        ChatDB._transactionDepth := 0
        ChatDB._deferredFileDeletes := []
        ChatDB._createdFiles := []
        ChatDB._reclaimRequested := false
        ChatDB._DeleteRolledBackFiles(created)
    }

    static RequestSpaceReclaim() {
        if ChatDB._transactionDepth
            ChatDB._reclaimRequested := true
    }

    ; Reclaim only substantial free space after a permanent purge. Incremental
    ; vacuum avoids the long full-database rewrite on every message delete;
    ; the WAL checkpoint also prevents the deleted pages remaining in -wal.
    static _ReclaimSpace() {
        try {
            pageCount := ChatDB.db.Exec("PRAGMA page_count;")
            freeCount := ChatDB.db.Exec("PRAGMA freelist_count;")
            pages := pageCount.count ? Integer(pageCount[1, "page_count"]) : 0
            free := freeCount.count ? Integer(freeCount[1, "freelist_count"]) : 0
            if free < 256 || free * 4 < pages
                return
            ChatDB.db.Exec("PRAGMA incremental_vacuum(" free ");")
            ChatDB.db.Exec("PRAGMA wal_checkpoint(TRUNCATE);")
        } catch Error as e {
            debugLog("[DB] Space reclaim skipped: " e.Message)
        }
    }

    static DeferFileDelete(filePath) {
        if !ChatDB._transactionDepth
            return false
        for existing in ChatDB._deferredFileDeletes
            if existing = filePath
                return true
        ChatDB._deferredFileDeletes.Push(filePath)
        return true
    }

    ; Register an attachment file created during the current transaction. If
    ; a later attachment or DB step fails, rollback removes the file too.
    static TrackCreatedFile(filePath) {
        if !ChatDB._transactionDepth || !filePath
            return
        for existing in ChatDB._createdFiles
            if existing = filePath
                return
        ChatDB._createdFiles.Push(filePath)
    }

    static _DeleteRolledBackFiles(filePaths) {
        for filePath in filePaths {
            refs := ChatDB.db.Query("SELECT COUNT(*) AS c FROM message_attachments WHERE file_path=?;", filePath)
            if (!refs.count || Integer(refs[1, "c"]) = 0)
                try FileDelete(AppInfo.DataDir "\" filePath)
        }
    }

    static _DeleteCommittedOrphanFiles(filePaths) {
        for filePath in filePaths {
            refs := ChatDB.db.Query("SELECT COUNT(*) AS c FROM message_attachments WHERE file_path=?;", filePath)
            if (!refs.count || Integer(refs[1, "c"]) = 0)
                try FileDelete(AppInfo.DataDir "\" filePath)
        }
    }

    ; Bounded fault seam used by the persistence audit. It is inert unless a
    ; probe/test explicitly sets the named stage.
    static MaybeFault(stage) {
        global persistenceFaultStage
        if IsSet(persistenceFaultStage) && persistenceFaultStage = stage {
            persistenceFaultStage := ""
            throw Error("injected persistence failure: " stage)
        }
    }

    static _CreateSchema() {
        ChatDB.db.Exec("CREATE TABLE IF NOT EXISTS chat_folders (id TEXT PRIMARY KEY, name TEXT NOT NULL);")
        ChatDB.db.Exec("CREATE TABLE IF NOT EXISTS chat_threads (id TEXT PRIMARY KEY, title TEXT DEFAULT 'New Chat', is_deleted INTEGER DEFAULT 0, deleted_at TEXT, created_at TEXT DEFAULT (datetime('now')), updated_at TEXT DEFAULT (datetime('now')), active_leaf_id TEXT, cumulative_input_tokens INTEGER DEFAULT 0, cumulative_output_tokens INTEGER DEFAULT 0, cumulative_cached_tokens INTEGER DEFAULT 0, cumulative_cost REAL DEFAULT 0, cumulative_input_cost REAL DEFAULT 0, cumulative_cached_input_cost REAL DEFAULT 0, cumulative_output_cost REAL DEFAULT 0, assistant_id TEXT, model_override TEXT, system_override TEXT, reasoning_override TEXT, temperature_override REAL, system_override_set INTEGER DEFAULT 0, reasoning_override_set INTEGER DEFAULT 0, temperature_override_set INTEGER DEFAULT 0, font_size INTEGER DEFAULT 17, folder_id TEXT, is_locked INTEGER DEFAULT 0, advanced_toggles TEXT DEFAULT '', FOREIGN KEY (folder_id) REFERENCES chat_folders(id) ON DELETE SET NULL);")
        ChatDB.db.Exec("CREATE TABLE IF NOT EXISTS messages (id TEXT PRIMARY KEY, thread_id TEXT NOT NULL, role TEXT NOT NULL, content TEXT NOT NULL, model TEXT, parent_id TEXT, sibling_group TEXT, sibling_index INTEGER DEFAULT 0, reasoning TEXT DEFAULT '', token_count INTEGER DEFAULT 0, prompt_tokens INTEGER DEFAULT 0, thinking_tokens INTEGER DEFAULT 0, cached_tokens INTEGER DEFAULT 0, response_time_ms INTEGER DEFAULT 0, ttft_ms INTEGER DEFAULT 0, active_path_tokens INTEGER DEFAULT 0, is_local_copy INTEGER DEFAULT 0, api_output_tokens INTEGER DEFAULT 0, input_cost REAL DEFAULT 0, cached_input_cost REAL DEFAULT 0, output_cost REAL DEFAULT 0, total_cost REAL DEFAULT 0, created_at TEXT DEFAULT (datetime('now')), FOREIGN KEY (thread_id) REFERENCES chat_threads(id) ON DELETE CASCADE);")
        ChatDB.db.Exec("CREATE TABLE IF NOT EXISTS chat_locks (thread_id TEXT PRIMARY KEY REFERENCES chat_threads(id) ON DELETE CASCADE, kdf TEXT NOT NULL DEFAULT 'pbkdf2-sha256', salt TEXT NOT NULL, hash TEXT NOT NULL, iterations INTEGER NOT NULL DEFAULT 600000);")
        ChatDB.db.Exec("CREATE TABLE IF NOT EXISTS message_attachments (id TEXT PRIMARY KEY, message_id TEXT NOT NULL, attachment_type TEXT NOT NULL, file_path TEXT NOT NULL, mime_type TEXT, original_filename TEXT, file_size INTEGER DEFAULT 0, extracted_text TEXT DEFAULT '', created_at TEXT DEFAULT (datetime('now')), FOREIGN KEY (message_id) REFERENCES messages(id) ON DELETE CASCADE);")
        ChatDB.db.Exec("CREATE TABLE IF NOT EXISTS command_usage (date TEXT NOT NULL, model TEXT NOT NULL, provider TEXT NOT NULL, command_name TEXT NOT NULL, call_count INTEGER DEFAULT 1, prompt_tokens INTEGER DEFAULT 0, completion_tokens INTEGER DEFAULT 0, thinking_tokens INTEGER DEFAULT 0, cached_tokens INTEGER DEFAULT 0, input_cost REAL DEFAULT 0, cached_input_cost REAL DEFAULT 0, output_cost REAL DEFAULT 0, total_cost REAL DEFAULT 0, total_response_time_ms INTEGER DEFAULT 0, total_ttft_ms INTEGER DEFAULT 0, ttft_count INTEGER DEFAULT 0, PRIMARY KEY (date, model, provider, command_name));")
        ChatDB.db.Exec("CREATE TABLE IF NOT EXISTS chat_usage (date TEXT NOT NULL, model TEXT NOT NULL, provider TEXT NOT NULL, call_count INTEGER DEFAULT 1, prompt_tokens INTEGER DEFAULT 0, completion_tokens INTEGER DEFAULT 0, thinking_tokens INTEGER DEFAULT 0, cached_tokens INTEGER DEFAULT 0, input_cost REAL DEFAULT 0, cached_input_cost REAL DEFAULT 0, output_cost REAL DEFAULT 0, total_cost REAL DEFAULT 0, total_response_time_ms INTEGER DEFAULT 0, total_ttft_ms INTEGER DEFAULT 0, ttft_count INTEGER DEFAULT 0, PRIMARY KEY (date, model, provider));")
        ChatDB.db.Exec("CREATE INDEX IF NOT EXISTS idx_attachments_message ON message_attachments(message_id);")
        ChatDB.db.Exec("CREATE INDEX IF NOT EXISTS idx_messages_thread ON messages(thread_id);")
        ChatDB.db.Exec("CREATE INDEX IF NOT EXISTS idx_messages_parent ON messages(parent_id);")
        ChatDB.db.Exec("CREATE INDEX IF NOT EXISTS idx_messages_sibling ON messages(sibling_group, sibling_index);")

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

    ; Chat lock operations - delegate to ThreadLockRepo
    static ThreadLock_IsLocked(threadId) => ThreadLockRepo.IsLocked(threadId)
    static ThreadLock_Get(threadId) => ThreadLockRepo.Get(threadId)
    static ThreadLock_Set(threadId, salt, hash, iterations) => ThreadLockRepo.Set(threadId, salt, hash, iterations)
    static ThreadLock_Update(threadId, salt, hash, iterations) => ThreadLockRepo.Update(threadId, salt, hash, iterations)
    static ThreadLock_Remove(threadId) => ThreadLockRepo.Remove(threadId)

    ; Message operations - delegate to MessageRepo
    static Msg_Insert(msgObj) => MessageRepo.Insert(msgObj)
    static Msg_HardDelete(msgId, expectedThreadId := "") => MessageRepo.HardDelete(msgId, expectedThreadId)
    static Msg_Edit(msgId, newContent, expectedThreadId := "") => MessageRepo.Edit(msgId, newContent, expectedThreadId)
    static Msg_GetActivePath(threadId) => TreeRepo.GetActivePath(threadId)
    static Msg_GetPathToLeaf(threadId, leafId) => TreeRepo.GetPathToLeaf(threadId, leafId)
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
    static Attachment_DeleteByMessage(msgId, expectedThreadId := "") => AttachmentRepo.DeleteByMessage(msgId, expectedThreadId)
    static Attachment_DeleteByThread(threadId) => AttachmentRepo.DeleteByThread(threadId)
    static Attachment_DeleteOne(attachmentId, expectedThreadId := "") => AttachmentRepo.DeleteOne(attachmentId, expectedThreadId)
    static Attachment_CopyForMessage(srcMsgId, dstMsgId, excludeAttachmentIds := "") => AttachmentRepo.CopyForMessage(srcMsgId, dstMsgId, excludeAttachmentIds)

    ; Usage operations - delegate to UsageRepo
    static Usage_Query(filters) => UsageRepo.Query(filters)
    static CommandUsage_Upsert(data) => UsageRepo.CommandUpsert(data)
    static ChatUsage_Upsert(data) => UsageRepo.ChatUpsert(data)

    ; Search operations - delegate to SearchRepo
    static SearchMessages(query, threadId := "") => SearchRepo.Search(query, threadId)
}
