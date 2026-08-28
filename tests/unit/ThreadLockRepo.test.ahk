; ======================================================
; ThreadLockRepo.test.ahk - Locked-chat persistence +
; ThreadLockService unit tests
;
; Covers: canonical lock schema, lock CRUD, sidebar title
; redaction, search exclusion, hash verification with
; cooldown, session unlock state, and cascade delete.
; ======================================================

class ThreadLockRepoTest {

    static __New() {
        RegisterTestClass("ThreadLockRepoTest")
    }

    _openDb() {
        if ChatDB.isOpen {
            oldPath := ChatDB.dbPath
            ChatDB.Close()
            try FileDelete(oldPath)
        }
        ChatDB.Open(A_Temp "\test_thread_lock_" A_TickCount "_" Random(1000, 999999) ".db")
    }

    _closeDb() {
        if ChatDB.isOpen {
            dbPath := ChatDB.dbPath
            ChatDB.Close()
            try FileDelete(dbPath)
        }
    }

    _validSalt() {
        return "aabbccdd11223344aabbccdd11223344"
    }

    _validHash() {
        return "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
    }

    Schema_HasLockColumns() {
        this._openDb()
        try {
            version := ChatDB.db.Exec("PRAGMA user_version;")[1, "user_version"]
            if Integer(version) != 0
                throw Error("fresh lock schema must not use migration user_version, got " version)
            hasCol := false
            for row in ChatDB.db.Exec("PRAGMA table_info(chat_threads);").rows
                if row.name = "is_locked"
                    hasCol := true
            if !hasCol
                throw Error("chat_threads.is_locked column missing")
            if !ChatDB.db.Exec("SELECT name FROM sqlite_master WHERE type='table' AND name='chat_locks';").count
                throw Error("chat_locks table missing")
        } finally {
            this._closeDb()
        }
    }

    SetGetRemove_RoundTrip() {
        this._openDb()
        try {
            tid := ChatDB.Thread_Create("Secret")
            if ChatDB.ThreadLock_IsLocked(tid)
                throw Error("fresh thread must not be locked")
            ChatDB.ThreadLock_Set(tid, this._validSalt(), this._validHash(), 600000)
            if !ChatDB.ThreadLock_IsLocked(tid)
                throw Error("thread should be locked after Set")
            lock := ChatDB.ThreadLock_Get(tid)
            if lock.salt != this._validSalt() || lock.hash != this._validHash() || lock.iterations != 600000
                throw Error("lock metadata round-trip mismatch")
            ChatDB.ThreadLock_Remove(tid)
            if ChatDB.ThreadLock_IsLocked(tid)
                throw Error("thread should be unlocked after Remove")
            if ChatDB.ThreadLock_Get(tid) != ""
                throw Error("lock row should be gone after Remove")
        } finally {
            this._closeDb()
        }
    }

    ThreadList_RedactsLockedTitles() {
        this._openDb()
        try {
            ; Session state leaks across tests in one process - start clean.
            ThreadLockService.LockAll()
            lockedId := ChatDB.Thread_Create("Salary negotiation")
            plainId := ChatDB.Thread_Create("Normal chat")
            ; Repo-level Set (no session unlock) - the lock must redact the title.
            ChatDB.ThreadLock_Set(lockedId, this._validSalt(), this._validHash(), 600000)
            rows := ChatDB.Thread_List()
            lockedRow := "", plainRow := ""
            for r in rows {
                if r.id = lockedId
                    lockedRow := r
                if r.id = plainId
                    plainRow := r
            }
            if !lockedRow || lockedRow.title != "Locked chat"
                throw Error("locked title not redacted: " (lockedRow ? lockedRow.title : "missing"))
            if !lockedRow.is_locked
                throw Error("locked row must carry is_locked=1")
            if !plainRow || plainRow.title != "Normal chat" || plainRow.is_locked
                throw Error("unlocked row must keep its title and is_locked=0")
            ; After unlocking in the session the REAL title is shown again so
            ; renaming and the topbar behave normally.
            ThreadLockService.Unlock(lockedId)
            rows := ChatDB.Thread_List()
            unlockedRow := ""
            for r in rows
                if r.id = lockedId
                    unlockedRow := r
            if !unlockedRow || unlockedRow.title != "Salary negotiation"
                throw Error("session-unlocked chat must show its real title: " (unlockedRow ? unlockedRow.title : "missing"))
            if !unlockedRow.is_locked
                throw Error("unlock must not clear the DB lock flag")
        } finally {
            this._closeDb()
        }
    }

    Search_ExcludesLockedThreads() {
        this._openDb()
        try {
            lockedId := ChatDB.Thread_Create("Locked needle title")
            plainId := ChatDB.Thread_Create("Plain needle title")
            ChatDB.ThreadLock_Set(lockedId, this._validSalt(), this._validHash(), 600000)
            ChatDB.Msg_Insert({ thread_id: lockedId, role: "user", content: "confidential needle word", parent_id: "", sibling_group: "", sibling_index: 0 })
            ChatDB.Msg_Insert({ thread_id: plainId, role: "user", content: "public needle word", parent_id: "", sibling_group: "", sibling_index: 0 })
            results := ChatDB.SearchMessages("needle")
            for res in results {
                if res.threadId = lockedId
                    throw Error("search leaked a locked thread")
            }
            foundPlain := false
            for res in results
                if res.threadId = plainId
                    foundPlain := true
            if !foundPlain
                throw Error("search should still find unlocked threads")
            ; Scoped search inside the locked thread must return nothing.
            scoped := ChatDB.SearchMessages("needle", lockedId)
            if scoped.Length
                throw Error("scoped search inside a locked thread leaked results")
        } finally {
            this._closeDb()
        }
    }

    VerifyHash_WrongAndCooldown() {
        this._openDb()
        try {
            tid := ChatDB.Thread_Create("Guarded")
            ChatDB.ThreadLock_Set(tid, this._validSalt(), this._validHash(), 600000)
            if ThreadLockService.VerifyHash(tid, "wrongwrongwrongwrongwrongwrongwrongwrongwrongwrongwrongwrongwrongwrongwrongwrong")
                throw Error("wrong hash must fail")
            if ThreadLockService.GetBlockRemaining(tid) != 0
                throw Error("no cooldown before 5 failures")
            loop 4
                ThreadLockService.VerifyHash(tid, "wrongwrongwrongwrongwrongwrongwrongwrongwrongwrongwrongwrongwrongwrongwrongwrong")
            if ThreadLockService.GetBlockRemaining(tid) <= 0
                throw Error("cooldown must be active after 5 failures")
            ; Blocked: even the CORRECT hash is rejected while cooling down.
            if ThreadLockService.VerifyHash(tid, this._validHash())
                throw Error("verify must fail while cooldown is active")
            ; Reset the cooldown (test shortcut) and confirm success clears state.
            ThreadLockService.failedAttempts.Delete(tid)
            if !ThreadLockService.VerifyHash(tid, this._validHash())
                throw Error("correct hash must verify after cooldown clears")
            if ThreadLockService.failedAttempts.Has(tid)
                throw Error("success must clear the failure counter")
        } finally {
            this._closeDb()
        }
    }

    SessionUnlock_RequireUnlocked() {
        this._openDb()
        try {
            tid := ChatDB.Thread_Create("Session")
            ChatDB.ThreadLock_Set(tid, this._validSalt(), this._validHash(), 600000)
            try {
                ThreadLockService.RequireUnlocked(tid)
                throw Error("RequireUnlocked must throw while locked")
            } catch Error as e {
                if e.What != "ThreadLocked"
                    throw Error("unexpected error: " e.Message)
            }
            ThreadLockService.Unlock(tid)
            if !ThreadLockService.IsUnlockedInSession(tid)
                throw Error("Unlock must register the session unlock")
            ThreadLockService.RequireUnlocked(tid)  ; must not throw now
            ThreadLockService.Relock(tid)
            if ThreadLockService.IsUnlockedInSession(tid)
                throw Error("Relock must clear the session unlock")
            ThreadLockService.Unlock(tid)
            ThreadLockService.LockAll()
            if ThreadLockService.IsUnlockedInSession(tid)
                throw Error("LockAll must clear every session unlock")
        } finally {
            this._closeDb()
        }
    }

    ConstantTimeEquals_Behaves() {
        if !ThreadLockService._ConstantTimeEquals("abc", "abc")
            throw Error("equal strings must compare true")
        if ThreadLockService._ConstantTimeEquals("abc", "abd")
            throw Error("different strings must compare false")
        if ThreadLockService._ConstantTimeEquals("abc", "ab")
            throw Error("different lengths must compare false")
        if !ThreadLockService._ConstantTimeEquals("", "")
            throw Error("empty strings must compare true")
    }

    SetPassword_RejectsInvalidInput() {
        this._openDb()
        try {
            tid := ChatDB.Thread_Create("Input guard")
            try {
                ThreadLockService.SetPassword(tid, "tooshort", this._validHash(), 600000)
                throw Error("bad salt must be rejected")
            } catch Error as e {
                if e.What != "ThreadLockInput"
                    throw Error("unexpected error: " e.Message)
            }
            try {
                ThreadLockService.SetPassword(tid, this._validSalt(), "nothex", 600000)
                throw Error("bad hash must be rejected")
            } catch Error as e {
                if e.What != "ThreadLockInput"
                    throw Error("unexpected error: " e.Message)
            }
            try {
                ThreadLockService.SetPassword(tid, this._validSalt(), this._validHash(), 5)
                throw Error("tiny iteration counts must be rejected")
            } catch Error as e {
                if e.What != "ThreadLockInput"
                    throw Error("unexpected error: " e.Message)
            }
            if ChatDB.ThreadLock_IsLocked(tid)
                throw Error("invalid input must not create a lock")
        } finally {
            this._closeDb()
        }
    }

    ThreadDelete_CascadesLock() {
        this._openDb()
        try {
            tid := ChatDB.Thread_Create("To delete")
            ChatDB.ThreadLock_Set(tid, this._validSalt(), this._validHash(), 600000)
            ChatDB.Thread_Delete(tid)
            if ChatDB.ThreadLock_Get(tid) != ""
                throw Error("deleting a thread must cascade-delete its lock row")
        } finally {
            this._closeDb()
        }
    }

    Fork_InheritsLock() {
        this._openDb()
        try {
            ThreadLockService.LockAll()
            ; Forking a locked chat must produce a locked copy (same password),
            ; or forking would strip the protection from sensitive content.
            lockedId := ChatDB.Thread_Create("Secret Plan")
            u1 := ChatDB.Msg_Insert({ thread_id: lockedId, role: "user", content: "u1", parent_id: "", sibling_group: "", sibling_index: 0 })
            a1 := ChatDB.Msg_Insert({ thread_id: lockedId, role: "assistant", content: "a1", parent_id: u1, model: "deepseek/deepseek-v4-flash", sibling_group: "", sibling_index: 0 })
            ChatDB.ThreadLock_Set(lockedId, this._validSalt(), this._validHash(), 600000)
            forkId := ChatDB.Msg_ForkThread(lockedId, a1)
            if !forkId
                throw Error("fork of a locked chat failed")
            if !ChatDB.ThreadLock_IsLocked(forkId)
                throw Error("fork must inherit is_locked=1")
            lock := ChatDB.ThreadLock_Get(forkId)
            if lock.salt != this._validSalt() || lock.hash != this._validHash() || lock.iterations != 600000
                throw Error("fork must copy the lock credentials")
            ; Forking an unlocked chat must stay unlocked.
            plainId := ChatDB.Thread_Create("Plain chat")
            p1 := ChatDB.Msg_Insert({ thread_id: plainId, role: "user", content: "p1", parent_id: "", sibling_group: "", sibling_index: 0 })
            p2 := ChatDB.Msg_Insert({ thread_id: plainId, role: "assistant", content: "p2", parent_id: p1, model: "deepseek/deepseek-v4-flash", sibling_group: "", sibling_index: 0 })
            plainFork := ChatDB.Msg_ForkThread(plainId, p2)
            if !plainFork
                throw Error("fork of an unlocked chat failed")
            if ChatDB.ThreadLock_IsLocked(plainFork)
                throw Error("fork of an unlocked chat must stay unlocked")
        } finally {
            this._closeDb()
        }
    }
}
