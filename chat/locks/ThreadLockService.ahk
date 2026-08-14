; ======================================================
; ThreadLockService.ahk - Chat lock enforcement
;
; Tier-1 app-level lock: a password gates access to a chat
; inside the app. The WebView derives PBKDF2-SHA-256 hashes
; (Web Crypto) and only the derived hash crosses the IPC
; boundary; the raw password never touches AHK or the DB.
;
; This is ACCESS CONTROL, not encryption at rest: chat
; content stays plaintext in chat_history.db. Real
; confidentiality (Tier 2: per-chat AES-GCM) is a separate
; follow-up.
; ======================================================

#Include ..\db\ThreadLockRepo.ahk

class ThreadLockService {
    ; Threads unlocked in THIS ChatWindow process lifetime.
    static sessionUnlocked := Map()

    ; Per-thread failed-attempt tracking: threadId -> { failures, lockedUntil }
    static failedAttempts := Map()

    static MAX_FAILURES := 5
    static COOLDOWN_SECONDS := 30
    static MIN_ITERATIONS := 10000
    static MAX_ITERATIONS := 5000000
    static DEFAULT_ITERATIONS := 600000

    static IsLocked(threadId) => ThreadLockRepo.IsLocked(threadId)

    static IsUnlockedInSession(threadId) => ThreadLockService.sessionUnlocked.Has(threadId)

    ; True when a thread's content must not be exposed to any plaintext sink
    ; (WebView UI, API logs, stream repaint) because it is locked and not
    ; unlocked in this session.
    static ShouldRedactContent(threadId) {
        return threadId && ThreadLockRepo.IsLocked(threadId) &&
            !ThreadLockService.sessionUnlocked.Has(threadId)
    }

    ; Gate used by every content handler: throws when the active thread
    ; is locked and not unlocked in this session.
    static RequireUnlocked(threadId) {
        if threadId && ThreadLockRepo.IsLocked(threadId) && !ThreadLockService.sessionUnlocked.Has(threadId)
            throw Error("This chat is locked. Unlock it before viewing or changing it.", "ThreadLocked")
    }

    static Unlock(threadId) {
        ThreadLockService.sessionUnlocked[threadId] := true
        if ThreadLockService.failedAttempts.Has(threadId)
            ThreadLockService.failedAttempts.Delete(threadId)
    }

    static Relock(threadId) {
        if ThreadLockService.sessionUnlocked.Has(threadId)
            ThreadLockService.sessionUnlocked.Delete(threadId)
    }

    static LockAll() {
        ThreadLockService.sessionUnlocked.Clear()
    }

    static GetLockData(threadId) => ThreadLockRepo.Get(threadId)

    ; Set a fresh lock (thread must currently be unlocked).
    static SetPassword(threadId, salt, hash, iterations) {
        if ThreadLockRepo.IsLocked(threadId)
            throw Error("This chat is already locked.", "ThreadLocked")
        ThreadLockService._ValidateKdfInput(salt, hash, iterations)
        ThreadLockRepo.Set(threadId, salt, hash, iterations)
        ; Keep the chat open after locking it.
        ThreadLockService.sessionUnlocked[threadId] := true
    }

    ; Change the password for an existing lock.
    static ChangePassword(threadId, salt, hash, iterations) {
        ThreadLockService._ValidateKdfInput(salt, hash, iterations)
        ThreadLockRepo.Update(threadId, salt, hash, iterations)
    }

    static RemovePassword(threadId) {
        ThreadLockRepo.Remove(threadId)
        if ThreadLockService.sessionUnlocked.Has(threadId)
            ThreadLockService.sessionUnlocked.Delete(threadId)
    }

    ; Verify a derived hash against the stored lock. Enforces a per-thread
    ; failure counter + cooldown. Returns true on success.
    static VerifyHash(threadId, passwordHash) {
        lockData := ThreadLockRepo.Get(threadId)
        if !lockData
            return false
        if ThreadLockService.GetBlockRemaining(threadId) > 0
            return false
        if ThreadLockService._ConstantTimeEquals(lockData.hash, passwordHash) {
            if ThreadLockService.failedAttempts.Has(threadId)
                ThreadLockService.failedAttempts.Delete(threadId)
            return true
        }
        entry := ""
        if ThreadLockService.failedAttempts.Has(threadId)
            entry := ThreadLockService.failedAttempts[threadId]
        else
            entry := { failures: 0, lockedUntil: 0 }
        entry.failures += 1
        if entry.failures >= ThreadLockService.MAX_FAILURES
            entry.lockedUntil := A_TickCount + ThreadLockService.COOLDOWN_SECONDS * 1000
        ThreadLockService.failedAttempts[threadId] := entry
        return false
    }

    ; Seconds remaining in the cooldown (0 = not blocked).
    static GetBlockRemaining(threadId) {
        if !ThreadLockService.failedAttempts.Has(threadId)
            return 0
        entry := ThreadLockService.failedAttempts[threadId]
        if !entry.lockedUntil
            return 0
        remaining := entry.lockedUntil - A_TickCount
        if remaining <= 0 {
            if ThreadLockService.failedAttempts.Has(threadId)
                ThreadLockService.failedAttempts.Delete(threadId)
            return 0
        }
        return Ceil(remaining / 1000)
    }

    ; KDF input validation (hex lengths + iteration bounds).
    static _ValidateKdfInput(salt, hash, iterations) {
        if !salt || StrLen(salt) != 32 || !RegExMatch(salt, "^[0-9a-fA-F]{32}$")
            throw Error("Invalid lock salt.", "ThreadLockInput")
        if !hash || StrLen(hash) != 64 || !RegExMatch(hash, "^[0-9a-fA-F]{64}$")
            throw Error("Invalid lock hash.", "ThreadLockInput")
        it := Integer(iterations)
        if it < ThreadLockService.MIN_ITERATIONS || it > ThreadLockService.MAX_ITERATIONS
            throw Error("Invalid KDF iteration count.", "ThreadLockInput")
    }

    ; Length-stable comparison - XOR all characters so timing does not
    ; leak the position of the first differing byte.
    static _ConstantTimeEquals(a, b) {
        result := 0
        aLen := StrLen(a)
        bLen := StrLen(b)
        loop Max(aLen, bLen) {
            ca := A_Index <= aLen ? Ord(SubStr(a, A_Index, 1)) : 0
            cb := A_Index <= bLen ? Ord(SubStr(b, A_Index, 1)) : 0
            result |= ca ^ cb
        }
        return result = 0
    }
}
