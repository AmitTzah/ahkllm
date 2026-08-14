; ======================================================
; Lock.ahk - Locked-chat callbacks (unlock + set/change/remove)
;
; Tier-1 app-level chat lock. The WebView derives PBKDF2
; hashes (Web Crypto) from the typed password; only the
; derived hash crosses the IPC boundary. AHK compares it
; constant-time against the stored hash and never sees the
; raw password.
; ======================================================

; Verify a derived hash and, on success, load the thread normally.
handleUnlockThread(parsed) {
    threadId := parsed.Get("threadId", "")
    passwordHash := parsed.Get("passwordHash", "")
    if !threadId || !passwordHash
        throw Error("Unlock requires a thread id and password hash.", "ThreadLockInput")

    block := ThreadLockService.GetBlockRemaining(threadId)
    if block > 0
        throw Error("Too many failed attempts. Try again in " block "s.", "ThreadLockBlocked")
    if !ThreadLockService.VerifyHash(threadId, passwordHash)
        throw Error("Incorrect password.", "ThreadLockFailed")

    ThreadLockService.Unlock(threadId)
    _LoadThreadAndRefreshUI(threadId)
}

; Set / change / remove a chat lock.
handleSetThreadLock(parsed) {
    threadId := parsed.Get("threadId", "")
    mode := parsed.Get("mode", "")
    if !threadId || (mode != "set" && mode != "change" && mode != "remove")
        throw Error("Invalid lock request.", "ThreadLockInput")

    switch mode {
        case "set":
            ThreadLockService.SetPassword(threadId,
                parsed.Get("salt", ""),
                parsed.Get("passwordHash", ""),
                parsed.Get("iterations", 0))
        case "change":
            if !ThreadLockService.VerifyHash(threadId, parsed.Get("currentPasswordHash", ""))
                throw Error("Current password is incorrect.", "ThreadLockFailed")
            ThreadLockService.ChangePassword(threadId,
                parsed.Get("salt", ""),
                parsed.Get("passwordHash", ""),
                parsed.Get("iterations", 0))
        case "remove":
            if !ThreadLockService.VerifyHash(threadId, parsed.Get("currentPasswordHash", ""))
                throw Error("Current password is incorrect.", "ThreadLockFailed")
            ThreadLockService.RemovePassword(threadId)
    }
    _postThreadListRefresh()
}

; Relock a session-unlocked chat immediately (sidebar lock menu -> "Lock Chat").
; Locking must NOT pop the password prompt: it hides the content and redacts
; the title; the prompt appears only when the user OPENS the chat again.
handleLockChatNow(parsed) {
    global activeThreadId
    threadId := parsed.Get("threadId", "")
    if !threadId || !ThreadLockService.IsLocked(threadId)
        throw Error("Chat is not locked.", "ThreadLockInput")
    ThreadLockService.Relock(threadId)
    if activeThreadId = threadId {
        ; The chat the user just locked must not keep its content on screen -
        ; clear the pane back to the empty state (same as dismissing the lock
        ; prompt). Clicking the chat again shows the unlock prompt.
        activeThreadId := ""
        _resetToDefaultSettings()
        postWebMessage("loadThread", "")
        postWebMessage("initChatMode", [])
        postCurrentSettingsToWebView()
        _sendDropdownLabel()
        chatWindow.Title := AppInfo.Name
    }
    _postThreadListRefresh()
}

; Leave the lock prompt without opening the chat. Only meaningful while the
; active thread is locked and not unlocked; otherwise it is a no-op.
handleDismissLockedThread(*) {
    global activeThreadId
    if !activeThreadId
        return
    if ThreadLockService.IsLocked(activeThreadId) && !ThreadLockService.IsUnlockedInSession(activeThreadId) {
        activeThreadId := ""
        _resetToDefaultSettings()
        postWebMessage("loadThread", "")
        postWebMessage("initChatMode", [])
        postCurrentSettingsToWebView()
        _sendDropdownLabel()
        chatWindow.Title := AppInfo.Name
        _postThreadListRefresh()
    }
}

; Lock metadata for the change/remove modal when the thread was never loaded
; (the sidebar lock menu can open the modal without entering the chat).
handleGetThreadLockInfo(parsed) {
    threadId := parsed.Get("threadId", "")
    if !threadId
        return
    lockData := ThreadLockService.GetLockData(threadId)
    postWebMessage("threadLockInfo", {
        threadId: threadId,
        salt: lockData ? lockData.salt : "",
        iterations: lockData ? lockData.iterations : ThreadLockService.DEFAULT_ITERATIONS
    })
}
