; ======================================================
; ThreadLockRepo.ahk - Chat lock persistence
;
; Part of ChatDB split. Stores lock metadata (PBKDF2 salt
; + derived hash) in chat_locks and the user-visible lock
; flag on chat_threads.is_locked. The raw password NEVER
; reaches this layer - the WebView derives the hash and
; only the derived value is persisted.
; ======================================================

class ThreadLockRepo {

    ; True when the thread is locked in the DB (regardless of
    ; session unlock state).
    static IsLocked(threadId) {
        row := ChatDB.db.Query("SELECT is_locked FROM chat_threads WHERE id=?;", threadId)
        return row.count ? Integer(row[1, "is_locked"]) : 0
    }

    ; Lock metadata for a thread ("" when no lock is set).
    static Get(threadId) {
        table := ChatDB.db.Query("SELECT kdf, salt, hash, iterations FROM chat_locks WHERE thread_id=?;", threadId)
        if !table.count
            return ""
        return {
            kdf: table[1, "kdf"],
            salt: table[1, "salt"],
            hash: table[1, "hash"],
            iterations: Integer(table[1, "iterations"])
        }
    }

    ; Create (or replace) the lock and mark the thread locked.
    static Set(threadId, salt, hash, iterations) {
        ChatDB.BeginTransaction()
        try {
        ChatDB.db.Query("INSERT OR REPLACE INTO chat_locks (thread_id, kdf, salt, hash, iterations) VALUES(?, 'pbkdf2-sha256', ?, ?, ?);", threadId, salt, hash, iterations)
        ChatDB.MaybeFault("lock-create-after-metadata")
        ChatDB.db.Query("UPDATE chat_threads SET is_locked=1, updated_at=datetime('now') WHERE id=?;", threadId)
        ChatDB.CommitTransaction()
        ChatDB._MarkPersistentDataChanged()
        } catch Error as e {
            ChatDB.RollbackTransaction()
            throw e
        }
    }

    ; Update the lock credentials (password change).
    static Update(threadId, salt, hash, iterations) {
        ChatDB.BeginTransaction()
        try {
        ChatDB.db.Query("UPDATE chat_locks SET salt=?, hash=?, iterations=? WHERE thread_id=?;", salt, hash, iterations, threadId)
        ChatDB.CommitTransaction()
        ChatDB._MarkPersistentDataChanged()
        } catch Error as e {
            ChatDB.RollbackTransaction()
            throw e
        }
    }

    ; Remove the lock and mark the thread unlocked.
    static Remove(threadId) {
        ChatDB.BeginTransaction()
        try {
        ChatDB.db.Query("DELETE FROM chat_locks WHERE thread_id=?;", threadId)
        ChatDB.db.Query("UPDATE chat_threads SET is_locked=0, updated_at=datetime('now') WHERE id=?;", threadId)
        ChatDB.CommitTransaction()
        ChatDB._MarkPersistentDataChanged()
        } catch Error as e {
            ChatDB.RollbackTransaction()
            throw e
        }
    }
}
