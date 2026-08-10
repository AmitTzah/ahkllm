; probe-bughunt-db.ahk - Deep DB-audit probe (bug hunt, 2026-08-10).
; Runs the REAL ChatDB/repo code against a temp SQLite database and prints
; token-accounting / tree-copy results for scenarios to assert on.
; Usage: AutoHotkey64.exe probe-bughunt-db.ahk <outFile> <check> [args...]
; Checks:
;   fork-offpath        - what a fork at a1 copies when a1 has off-path children
;   branch-copy-recount - cumulative counters after a local_copy + real follow-up
;   backfill-thinking   - user token backfill when prior assistant had thinking
;   branch-user-stale   - branch-copied user message keeps the source token_count
;   fts5-prefix-quote   - FTS5 prefix matching for queries ending in a quote
;   command-empty-models- command with empty APIModels (the "Default" dropdown)
;   fts-attachment-text - searching attachment extracted_text finds nothing
;   empty-model-skip    - assistant rows with empty model are skipped by counters
#Requires AutoHotkey v2.0.18+
#ErrorStdOut
#SingleInstance Off
#NoTrayIcon

global outFile := A_Args.Length >= 1 ? A_Args[1] : A_Temp "\bughunt_db_result.txt"
global logLines := []
Log(m) {
    global logLines
    logLines.Push(m)
}
SetTimer(ExitProbe, -15000)
ExitProbe(*) {
    Log("WATCHDOG fired")
    Finish()
    ExitApp(1)
}
OnError((e, m) => (Log("ERROR: " e.Message "`nSTACK: " (e.HasProp("Stack") ? e.Stack : "none")), Finish(), ExitApp(1)), -1)

#Include ..\..\lib\Config.ahk

; ThreadTitleGen.ahk is normally included by ChatWindow only; the probe chain
; lacks two identifiers its function bodies reference - stub them so the file
; loads standalone (the load-hang rule: every referenced identifier must exist).
#Include ..\..\chat\ThreadTitleGen.ahk
postWebMessage(target, data := unset) {
    return ""
}
_GetFolders() {
    return []
}

; The probe exercises repo functions that reference the chat-window global
; requestParams; define it (and activeThreadId) so the script can load.
global requestParams := Map()
global activeThreadId := ""

; Local copy of Branch.ahk's _setupSiblingGroup (the probe does not load the
; callback chain; the DB-level retry semantics are what this check verifies).
_setupSiblingGroup(msg) {
    sg := msg.sibling_group
    if !sg {
        sg := ChatDB._UUID()
        ChatDB.db.Query("UPDATE messages SET sibling_group=?, sibling_index=0 WHERE id=?;", sg, msg.id)
    }
    return sg
}

Finish() {
    global outFile, logLines
    try FileAppend(Join("`n", logLines), outFile, "UTF-8")
}
Join(sep, arr) {
    out := ""
    for i, v in arr
        out .= (i > 1 ? sep : "") v
    return out
}

OpenDb() {
    dbPath := A_Temp "\bughunt_db_" A_TickCount ".db"
    try FileDelete(dbPath)
    ChatDB.Open(dbPath)
    return dbPath
}
CloseDb(dbPath) {
    ChatDB.Close()
    try FileDelete(dbPath)
    try FileDelete(dbPath "-wal")
    try FileDelete(dbPath "-shm")
}

; ------------------------------------------------------------------
; CHECK 1: fork at a message that has OFF-PATH children of its own.
; Tree: u1 -> a1 (fork point); a1 -> u2 -> a2 (active) and
;       a1 -> u2b -> a2b (off-path alternative continuation).
; ------------------------------------------------------------------
ForkOffpath() {
    dbPath := OpenDb()
    tid := ChatDB.Thread_Create("ForkOffpath")
    u1 := ChatDB.Msg_Insert({thread_id: tid, role: "user", content: "u1"})
    a1 := ChatDB.Msg_Insert({thread_id: tid, role: "assistant", content: "a1", parent_id: u1, model: "deepseek/deepseek-v4-flash", prompt_tokens: 10, token_count: 20, active_path_tokens: 30})
    u2 := ChatDB.Msg_Insert({thread_id: tid, role: "user", content: "u2", parent_id: a1})
    a2 := ChatDB.Msg_Insert({thread_id: tid, role: "assistant", content: "a2", parent_id: u2, model: "deepseek/deepseek-v4-flash", prompt_tokens: 15, token_count: 30})
    u2b := ChatDB.Msg_Insert({thread_id: tid, role: "user", content: "u2b", parent_id: a1, sibling_group: "sg-b", sibling_index: 1})
    a2b := ChatDB.Msg_Insert({thread_id: tid, role: "assistant", content: "a2b", parent_id: u2b, model: "deepseek/deepseek-v4-flash", prompt_tokens: 15, token_count: 30})
    ChatDB.Msg_SetActiveLeaf(tid, a2)

    forkId := ChatDB.Msg_ForkThread(tid, a1)
    rows := ChatDB.db.Query("SELECT role, content FROM messages WHERE thread_id=? ORDER BY created_at;", forkId)
    parts := []
    for r in rows.rows
        parts.Push(r.role "/" r.content)
    Log("FORKOFFPATH msgs=" rows.count " contents=" Join(",", parts))
    Log("FORKOFFPATH activeLeaf=" (ChatDB.db.Query("SELECT active_leaf_id FROM chat_threads WHERE id=?;", forkId)[1, "active_leaf_id"]))
    Log("FORKOFFPATH verdict=" (rows.count = 2 ? "BUG-present(offpath-children-dropped)" : (rows.count = 4 ? "OK-copied" : "unexpected:" rows.count)))
    CloseDb(dbPath)
}

; ------------------------------------------------------------------
; CHECK 2: a local_copy branch (assistant "Save as Branch") carries copied
; token metadata. A later REAL exchange recomputes the cumulative counters
; from ALL assistant rows, so the copy's copied prompt_tokens get charged
; a second time (no persisted local_copy flag to exclude them).
; Real API calls: a1 (12/9/4) + a2 (24/5+2/1) => expected 36 input / 16
; output / 5 cached. Buggy: 48 / 25 / 9.
; ------------------------------------------------------------------
BranchCopyRecount() {
    dbPath := OpenDb()
    tid := ChatDB.Thread_Create("BranchCopyRecount")
    u1 := ChatDB.Msg_Insert({thread_id: tid, role: "user", content: "u1"})
    a1 := ChatDB.Msg_Insert({thread_id: tid, role: "assistant", content: "a1", parent_id: u1, model: "deepseek/deepseek-v4-flash", prompt_tokens: 12, token_count: 9, cached_tokens: 4, active_path_tokens: 21})
    ; Assistant branch-edit copy (local_copy, bug #123 copies the metadata):
    ChatDB.Msg_Insert({thread_id: tid, role: "assistant", content: "a1 edited branch", parent_id: u1, sibling_group: "sg-copy", sibling_index: 1, model: "deepseek/deepseek-v4-flash", token_count: 9, prompt_tokens: 12, cached_tokens: 4, active_path_tokens: 21, local_copy: true})
    ; Real follow-up exchange on the copied branch:
    u2 := ChatDB.Msg_Insert({thread_id: tid, role: "user", content: "u2", parent_id: ChatDB.db.Query("SELECT id FROM messages WHERE content='a1 edited branch';").rows[1].id})
    ChatDB.Msg_Insert({thread_id: tid, role: "assistant", content: "a2", parent_id: u2, model: "deepseek/deepseek-v4-flash", prompt_tokens: 24, token_count: 5, thinking_tokens: 2, cached_tokens: 1})

    row := ChatDB.db.Query("SELECT cumulative_input_tokens, cumulative_output_tokens, cumulative_cached_tokens FROM chat_threads WHERE id=?;", tid)
    inp := Integer(row[1, "cumulative_input_tokens"]), outp := Integer(row[1, "cumulative_output_tokens"]), ckt := Integer(row[1, "cumulative_cached_tokens"])
    Log("BRANCHCOPY input=" inp " output=" outp " cached=" ckt)
    Log("BRANCHCOPY verdict=" (inp = 36 && outp = 16 && ckt = 5 ? "OK-real-calls-only" : "BUG-present(double-counted)"))
    CloseDb(dbPath)
}

; ------------------------------------------------------------------
; CHECK 3: user token backfill when the previous assistant reported
; thinking tokens. a1: prompt 12, visible 9, thinking 5 (OpenAI-style
; completion_tokens_details). Real next prompt = 12 + 9 + 5 + 4 (u2) = 30.
; existing_sum = u1.tc(12) + a1.tc(9) = 21 (thinking NOT included), so
; u2.tc = 30 - 21 = 9 instead of its true 4 -> prior thinking leaks in.
; ------------------------------------------------------------------
BackfillThinking() {
    dbPath := OpenDb()
    tid := ChatDB.Thread_Create("BackfillThinking")
    u1 := ChatDB.Msg_Insert({thread_id: tid, role: "user", content: "u1"})
    ChatDB.Msg_Insert({thread_id: tid, role: "assistant", content: "a1", parent_id: u1, model: "deepseek/deepseek-v4-flash", prompt_tokens: 12, token_count: 9, thinking_tokens: 5, cached_tokens: 0})
    p1 := ChatDB.Msg_GetActivePath(tid)
    t1 := []
    for m in p1
        t1.Push(m.role "=" m.token_count)
    Log("BACKFILL pathAfterA1: " Join(",", t1))
    u2 := ChatDB.Msg_Insert({thread_id: tid, role: "user", content: "u2", parent_id: ChatDB.db.Query("SELECT id FROM messages WHERE content='a1';").rows[1].id})
    p2 := ChatDB.Msg_GetActivePath(tid)
    t2 := []
    for m in p2
        t2.Push(m.role "=" m.token_count)
    Log("BACKFILL pathAfterU2: " Join(",", t2))
    ChatDB.Msg_Insert({thread_id: tid, role: "assistant", content: "a2", parent_id: u2, model: "deepseek/deepseek-v4-flash", prompt_tokens: 30, token_count: 6, thinking_tokens: 0, cached_tokens: 0})

    u1tc := Integer(ChatDB.db.Query("SELECT token_count FROM messages WHERE id=?;", u1)[1, "token_count"])
    u2tc := Integer(ChatDB.db.Query("SELECT token_count FROM messages WHERE id=?;", u2)[1, "token_count"])
    Log("BACKFILL u1tc=" u1tc " u2tc=" u2tc " (true u2 contribution = 4; inflated value would be 9)")
    Log("BACKFILL verdict=" (u2tc = 4 ? "OK-accurate" : "BUG-present(thinking-leaks)"))
    CloseDb(dbPath)
}

; ------------------------------------------------------------------
; CHECK 4: "Save as Branch" on a user message copies the source message's
; token_count; the new branch's own API response never re-backfills it
; (skip when nonzero), so the branch copy's popover stays stale forever.
; ------------------------------------------------------------------
BranchUserStale() {
    dbPath := OpenDb()
    tid := ChatDB.Thread_Create("BranchUserStale")
    u1 := ChatDB.Msg_Insert({thread_id: tid, role: "user", content: "u1"})
    ChatDB.Msg_Insert({thread_id: tid, role: "assistant", content: "a1", parent_id: u1, model: "deepseek/deepseek-v4-flash", prompt_tokens: 12, token_count: 9})
    ; u2 real (backfilled): prompt for a2 = 12+9+7 = 28.
    u2 := ChatDB.Msg_Insert({thread_id: tid, role: "user", content: "original follow-up", parent_id: ChatDB.db.Query("SELECT id FROM messages WHERE content='a1';").rows[1].id})
    ChatDB.Msg_Insert({thread_id: tid, role: "assistant", content: "a2", parent_id: u2, model: "deepseek/deepseek-v4-flash", prompt_tokens: 28, token_count: 6})
    u2tc := Integer(ChatDB.db.Query("SELECT token_count FROM messages WHERE id=?;", u2)[1, "token_count"])
    ; Branch-edit copy of u2 with edited content (handleEdit branch mode):
    u2b := ChatDB.Msg_Insert({thread_id: tid, role: "user", content: "edited follow-up (branch)", parent_id: ChatDB.db.Query("SELECT id FROM messages WHERE content='a1';").rows[1].id, sibling_group: "sg-user", sibling_index: 1, token_count: u2tc, active_path_tokens: 21 + u2tc, local_copy: true})
    ; The branch fires a REAL request (mock-style usage prompt 30 / tc 5):
    ChatDB.Msg_Insert({thread_id: tid, role: "assistant", content: "a2b", parent_id: u2b, model: "deepseek/deepseek-v4-flash", prompt_tokens: 30, token_count: 5})
    u2btc := Integer(ChatDB.db.Query("SELECT token_count FROM messages WHERE id=?;", u2b)[1, "token_count"])
    Log("BRANCHUSER srcU2tc=" u2tc " branchU2btc=" u2btc " (branch content differs; backfill skipped because copied tc != 0)")
    Log("BRANCHUSER verdict=" (u2btc = u2tc ? "BUG-present(stale-copied-attribute)" : "OK-rebackfilled"))
    CloseDb(dbPath)
}

; ------------------------------------------------------------------
; CHECK 5: retrying an assistant that has NO parent (thread root, e.g.
; after deleting the root user message). retryAction only moves the active
; leaf to the parent when parentMsg exists, so the retried response is
; inserted with parent = the ORIGINAL assistant (path[last].id) while its
; sibling_group is the original's group -> the retry becomes a CHILD of the
; original instead of a sibling (GetSiblings still lists both).
; ------------------------------------------------------------------
RetryRootAssistant() {
    dbPath := OpenDb()
    tid := ChatDB.Thread_Create("RetryRootAssistant")
    u1 := ChatDB.Msg_Insert({thread_id: tid, role: "user", content: "u1"})
    a1 := ChatDB.Msg_Insert({thread_id: tid, role: "assistant", content: "a1", parent_id: u1, model: "deepseek/deepseek-v4-flash", prompt_tokens: 12, token_count: 9})
    ; Delete the root user message so a1 becomes the thread root:
    ChatDB.Msg_HardDelete(u1)
    ; a1 now has parent NULL and is the leaf. Retry it (the code path that
    ; sets pendingRetrySiblingGroup without moving the leaf):
    path := ChatDB.Msg_GetActivePath(tid)
    if path.Length != 1 || path[1].id != a1
        Log("RETRYROOT setup-unexpected path=" path.Length)
    requestParams["pendingRetrySiblingGroup"] := _setupSiblingGroup(path[1])
    ChatDB.Msg_Insert({
        thread_id: tid, role: "assistant", content: "a1 retried",
        parent_id: path[path.Length].id,
        sibling_group: requestParams["pendingRetrySiblingGroup"],
        sibling_index: MessageRepo.GetMaxSiblingIndex(requestParams["pendingRetrySiblingGroup"]) + 1,
        model: "deepseek/deepseek-v4-flash", prompt_tokens: 12, token_count: 9
    })
    requestParams.Delete("pendingRetrySiblingGroup")
    newRow := ChatDB.db.Query("SELECT parent_id, sibling_group, sibling_index FROM messages WHERE content='a1 retried';")
    parentId := newRow[1, "parent_id"]
    isChild := parentId = a1
    sibCount := ChatDB.db.Query("SELECT COUNT(*) AS c FROM messages WHERE sibling_group=?;", newRow[1, "sibling_group"])[1, "c"]
    Log("RETRYROOT newParentIsOriginal=" (isChild ? 1 : 0) " siblingsInGroup=" sibCount)
    Log("RETRYROOT verdict=" (isChild ? "BUG-present(retry-became-child)" : "OK-sibling"))
    CloseDb(dbPath)
}

; ------------------------------------------------------------------
; CHECK 6: navigating to a message that has MULTIPLE continuations
; (original + retries). _WalkToLeaf picks ORDER BY sibling_index ASC
; (the ORIGINAL, index 0) while the code comments claim it picks the
; NEWEST continuation (retries get HIGHER sibling_index). The tree
; modal's _findDefaultLeaf takes GetTree's LAST child (also min
; sibling_index), so both agree on the ORIGINAL - not the latest retry.
; ------------------------------------------------------------------
WalkToLeafOldest() {
    dbPath := OpenDb()
    tid := ChatDB.Thread_Create("WalkToLeafOldest")
    u1 := ChatDB.Msg_Insert({thread_id: tid, role: "user", content: "u1"})
    a1 := ChatDB.Msg_Insert({thread_id: tid, role: "assistant", content: "a1", parent_id: u1, model: "deepseek/deepseek-v4-flash", prompt_tokens: 10, token_count: 20})
    u2 := ChatDB.Msg_Insert({thread_id: tid, role: "user", content: "u2", parent_id: a1})
    a2 := ChatDB.Msg_Insert({thread_id: tid, role: "assistant", content: "a2 original", parent_id: u2, sibling_group: "sg-walk", sibling_index: 0, model: "deepseek/deepseek-v4-flash", prompt_tokens: 15, token_count: 30})
    a2b := ChatDB.Msg_Insert({thread_id: tid, role: "assistant", content: "a2 retry (newest)", parent_id: u2, sibling_group: "sg-walk", sibling_index: 1, model: "deepseek/deepseek-v4-flash", prompt_tokens: 15, token_count: 30})
    leaf := TreeRepo._WalkToLeaf(u2)
    ; GetTree sorts each parent's children by sibling_index DESCENDING, so the
    ; LAST child in the array is the SMALLEST index = the ORIGINAL message.
    ; (Retries get HIGHER sibling_index: original 0, retry 1, ...)
    childRows := ChatDB.db.Query("SELECT id, sibling_index FROM messages WHERE parent_id=? ORDER BY sibling_index DESC;", u2)
    sorted := []
    for r in childRows.rows
        sorted.Push(r.id)
    lastChild := sorted.Length ? sorted[sorted.Length] : ""
    Log("WALKTOLEAF walkLeaf=" leaf " treeLastChild=" lastChild " original=" a2 " newest=" a2b)
    Log("WALKTOLEAF verdict=" (leaf = a2 && lastChild = a2 ? "BUG-present(lands-on-original)" : "OK-newest"))
    CloseDb(dbPath)
}

; ------------------------------------------------------------------
; CHECK 7: command thinking config with a SHORT model id (no provider
; prefix). LLMRequestBuilder.createJSONRequest gates ApplyThinking on
; models.Has(APIModel) - full-id keys only, so short ids silently drop
; the thinking config (bug #43 fixed the CHAT path via ModelResolver,
; the command path still uses the raw map lookup).
; ------------------------------------------------------------------
CommandThinkingShort() {
    shortJson := LLMRequestBuilder.createJSONRequest("deepseek-v4-flash", "", "hello", "", "", "", false, "enabled", "high")
    fullJson := LLMRequestBuilder.createJSONRequest("deepseek/deepseek-v4-flash", "", "hello", "", "", "", false, "enabled", "high")
    hasThinking := InStr(shortJson, "thinking") || InStr(shortJson, "reasoning_effort")
    fullHasThinking := InStr(fullJson, "thinking") || InStr(fullJson, "reasoning_effort")
    Log("CMDTHINK shortHasThinking=" (hasThinking ? 1 : 0) " fullHasThinking=" (fullHasThinking ? 1 : 0))
    Log("CMDTHINK shortJson=" shortJson)
    Log("CMDTHINK fullJson=" fullJson)
    Log("CMDTHINK verdict=" (hasThinking ? "OK-short-id-applies" : "BUG-present(short-id-drops-thinking)"))
}

; ------------------------------------------------------------------
; CHECK 8: deleting the ROOT user message of a thread sets
; active_leaf_id = NULL even though the thread still has messages
; (the re-parented assistant becomes the root). GetActivePath returns
; [] so the chat UI renders an EMPTY conversation while the DB still
; holds the assistant + its subtree; the next send creates a SECOND
; root because parentId comes from the empty path.
; ------------------------------------------------------------------
RootDeleteLeaf() {
    dbPath := OpenDb()
    tid := ChatDB.Thread_Create("RootDeleteLeaf")
    u1 := ChatDB.Msg_Insert({thread_id: tid, role: "user", content: "u1"})
    a1 := ChatDB.Msg_Insert({thread_id: tid, role: "assistant", content: "a1", parent_id: u1, model: "deepseek/deepseek-v4-flash", prompt_tokens: 12, token_count: 9, active_path_tokens: 21})
    u2 := ChatDB.Msg_Insert({thread_id: tid, role: "user", content: "u2", parent_id: a1})
    a2 := ChatDB.Msg_Insert({thread_id: tid, role: "assistant", content: "a2", parent_id: u2, model: "deepseek/deepseek-v4-flash", prompt_tokens: 30, token_count: 6})

    ChatDB.Msg_HardDelete(u1)
    leaf := ChatDB.db.Query("SELECT active_leaf_id FROM chat_threads WHERE id=?;", tid)[1, "active_leaf_id"]
    path := ChatDB.Msg_GetActivePath(tid)
    msgCount := ChatDB.db.Query("SELECT COUNT(*) AS c FROM messages WHERE thread_id=?;", tid)[1, "c"]
    rootCount := ChatDB.db.Query("SELECT COUNT(*) AS c FROM messages WHERE thread_id=? AND parent_id IS NULL;", tid)[1, "c"]
    Log("ROOTDELETE leafIsNull=" (leaf = "" ? 1 : 0) " pathLen=" path.Length " msgCount=" msgCount " rootCount=" rootCount)
    Log("ROOTDELETE verdict=" (leaf = "" ? "BUG-present(thread-invisible)" : "OK-leaf-kept"))
    CloseDb(dbPath)
}

; ------------------------------------------------------------------
; CHECK 9: "Save as Branch" on an assistant message that has a
; reasoning/thinking block copies the token metadata (bug #123) but NOT
; the reasoning text - the DB row's reasoning column is '' and the
; branch bubble loses the "Thought Process" section while the token
; popover still shows thinking_tokens.
; ------------------------------------------------------------------
BranchDropReasoning() {
    dbPath := OpenDb()
    tid := ChatDB.Thread_Create("BranchDropReasoning")
    u1 := ChatDB.Msg_Insert({thread_id: tid, role: "user", content: "u1"})
    a1 := ChatDB.Msg_Insert({thread_id: tid, role: "assistant", content: "a1 visible", parent_id: u1, model: "deepseek/deepseek-v4-flash", prompt_tokens: 12, token_count: 9, thinking_tokens: 5, reasoning: "THINK-STEP-1`nTHINK-STEP-2", active_path_tokens: 26})
    ; Mirror handleEdit branch mode: same fields the callback passes, no reasoning.
    ChatDB.Msg_Insert({thread_id: tid, role: "assistant", content: "a1 branch", parent_id: u1, sibling_group: "sg-reason", sibling_index: 1, model: "deepseek/deepseek-v4-flash", token_count: 9, prompt_tokens: 12, thinking_tokens: 5, cached_tokens: 0, active_path_tokens: 26, local_copy: true})

    src := ChatDB.db.Query("SELECT reasoning FROM messages WHERE content='a1 visible';")[1, "reasoning"]
    copy := ChatDB.db.Query("SELECT reasoning, thinking_tokens FROM messages WHERE content='a1 branch';")
    copyReason := copy[1, "reasoning"]
    copyThink := Integer(copy[1, "thinking_tokens"])
    Log("BRANCHREASON srcLen=" StrLen(src) " copyLen=" StrLen(copyReason) " copyThinking=" copyThink)
    Log("BRANCHREASON verdict=" (copyReason = "" && copyThink > 0 ? "BUG-present(reasoning-dropped)" : "OK-reasoning-copied"))
    CloseDb(dbPath)
}

; ------------------------------------------------------------------
; CHECK 10: the sidebar thread model badge. ThreadRepo.List picks the
; LAST-INSERTED assistant row (ORDER BY created_at DESC LIMIT 1) instead
; of the ACTIVE path's model, so after switching to a branch whose model
; differs from the most recently inserted assistant, the sidebar badge
; is stale (shows the other branch's model).
; ------------------------------------------------------------------
ThreadListModelStale() {
    dbPath := OpenDb()
    tid := ChatDB.Thread_Create("ThreadListModelStale")
    u1 := ChatDB.Msg_Insert({thread_id: tid, role: "user", content: "u1"})
    a1 := ChatDB.Msg_Insert({thread_id: tid, role: "assistant", content: "a1", parent_id: u1, model: "deepseek/deepseek-v4-flash", prompt_tokens: 10, token_count: 5})
    ; Active continuation (branch A) - model X:
    u2 := ChatDB.Msg_Insert({thread_id: tid, role: "user", content: "u2A", parent_id: a1})
    a2A := ChatDB.Msg_Insert({thread_id: tid, role: "assistant", content: "a2A", parent_id: u2, model: "openai/gpt-5-mini", prompt_tokens: 20, token_count: 8})
    ; Off-path continuation (branch B) - model Y, inserted LATER:
    u2b := ChatDB.Msg_Insert({thread_id: tid, role: "user", content: "u2B", parent_id: a1, sibling_group: "sg-b", sibling_index: 1})
    a2b := ChatDB.Msg_Insert({thread_id: tid, role: "assistant", content: "a2B", parent_id: u2b, model: "google/gemini-2.5-flash", prompt_tokens: 25, token_count: 10})
    ; Active leaf is a2A (branch A); Thread_List model should be openai/gpt-5-mini.
    ChatDB.Msg_SetActiveLeaf(tid, a2A)
    list := ChatDB.Thread_List()
    listedModel := list[1].model
    activeModel := "openai/gpt-5-mini"
    Log("THREADLIST activeModel=" activeModel " listedModel=" listedModel)
    Log("THREADLIST verdict=" (listedModel = activeModel ? "OK-matches-active-path" : "BUG-present(stale-badge)"))
    CloseDb(dbPath)
}

; ------------------------------------------------------------------
; CHECK 11: SwitchBranch wraps both directions and walks to the new
; sibling's leaf (regression sanity - must keep passing).
; ------------------------------------------------------------------
SwitchBranchWrap() {
    dbPath := OpenDb()
    tid := ChatDB.Thread_Create("SwitchBranchWrap")
    u1 := ChatDB.Msg_Insert({thread_id: tid, role: "user", content: "u1"})
    a1 := ChatDB.Msg_Insert({thread_id: tid, role: "assistant", content: "a1", parent_id: u1, model: "deepseek/deepseek-v4-flash", prompt_tokens: 10, token_count: 5})
    ; Three siblings under a1: u2 (idx0), u2b (idx1), u2c (idx2).
    u2 := ChatDB.Msg_Insert({thread_id: tid, role: "user", content: "u2", parent_id: a1, sibling_group: "sg-wrap", sibling_index: 0})
    u2b := ChatDB.Msg_Insert({thread_id: tid, role: "user", content: "u2b", parent_id: a1, sibling_group: "sg-wrap", sibling_index: 1})
    u2c := ChatDB.Msg_Insert({thread_id: tid, role: "user", content: "u2c", parent_id: a1, sibling_group: "sg-wrap", sibling_index: 2})
    ; Deep leaves so walking matters:
    a2c := ChatDB.Msg_Insert({thread_id: tid, role: "assistant", content: "a2c", parent_id: u2c, model: "deepseek/deepseek-v4-flash", prompt_tokens: 15, token_count: 7})
    ChatDB.Msg_SetActiveLeaf(tid, u2)
    r1 := ChatDB.Msg_SwitchBranch(tid, u2, 1)   ; next -> u2b's leaf
    r2 := ChatDB.Msg_SwitchBranch(tid, u2b, 1)  ; next -> u2c's leaf (deep)
    r3 := ChatDB.Msg_SwitchBranch(tid, u2c, 1)  ; wrap -> u2's leaf
    r4 := ChatDB.Msg_SwitchBranch(tid, u2, -1)  ; wrap backwards -> u2c's leaf
    p1 := r1.path[r1.path.Length].id
    p2 := r2.path[r2.path.Length].id
    p3 := r3.path[r3.path.Length].id
    p4 := r4.path[r4.path.Length].id
    ok := (p1 = u2b && p2 = a2c && p3 = u2 && p4 = a2c)
    Log("SWITCHWRAP p1=" p1 " p2=" p2 " p3=" p3 " p4=" p4 " expected=" u2b "," a2c "," u2 "," a2c)
    Log("SWITCHWRAP verdict=" (ok ? "OK-wrap-and-walk" : "BUG-present(switch-navigation)"))
    CloseDb(dbPath)
}

; ------------------------------------------------------------------
; CHECK 12: OVERWRITE-editing a user message changes its content but
; leaves the OLD backfilled token_count in place. The next exchange's
; backfill subtracts that stale value from the new prompt, so the NEXT
; user message's contribution is over/under-counted (stale attribution
; family #145/#150, but on the overwrite path - the edit does not reset
; the attribution for re-measurement).
; u1(12) a1(9) u2(7 backfilled from prompt 28) a2(6); then u2 is edited
; to a 30-token text. The next API prompt is 12+9+30+6+5=62.
; existing_sum = 12+9+7+6 = 34 (u2's stale 7), so u3 gets 62-34=28
; instead of its true 5.
; ------------------------------------------------------------------
EditUserStaleBackfill() {
    dbPath := OpenDb()
    tid := ChatDB.Thread_Create("EditUserStaleBackfill")
    u1 := ChatDB.Msg_Insert({thread_id: tid, role: "user", content: "u1"})
    ChatDB.Msg_Insert({thread_id: tid, role: "assistant", content: "a1", parent_id: u1, model: "deepseek/deepseek-v4-flash", prompt_tokens: 12, token_count: 9})
    u2 := ChatDB.Msg_Insert({thread_id: tid, role: "user", content: "original follow-up", parent_id: ChatDB.db.Query("SELECT id FROM messages WHERE content='a1';").rows[1].id})
    ChatDB.Msg_Insert({thread_id: tid, role: "assistant", content: "a2", parent_id: u2, model: "deepseek/deepseek-v4-flash", prompt_tokens: 28, token_count: 6})
    u2tc := Integer(ChatDB.db.Query("SELECT token_count FROM messages WHERE id=?;", u2)[1, "token_count"])
    ; Overwrite edit: content changes drastically, token_count must NOT stay 7.
    ChatDB.Msg_Edit(u2, "this edited follow-up is now a dramatically longer message with much more text than before")
    ; Next exchange: prompt for a3 = 12 (u1) + 9 (a1) + 30 (u2 NEW) + 6 (a2) + 5 (u3 true) = 62.
    u3 := ChatDB.Msg_Insert({thread_id: tid, role: "user", content: "u3", parent_id: ChatDB.db.Query("SELECT id FROM messages WHERE content='a2';").rows[1].id})
    ChatDB.Msg_Insert({thread_id: tid, role: "assistant", content: "a3", parent_id: u3, model: "deepseek/deepseek-v4-flash", prompt_tokens: 62, token_count: 5})
    u3tc := Integer(ChatDB.db.Query("SELECT token_count FROM messages WHERE id=?;", u3)[1, "token_count"])
    Log("EDITUSER u2tcAfterEdit=" u2tc " u3tc=" u3tc " (true u3 contribution 5)")
    Log("EDITUSER verdict=" (u3tc = 5 ? "OK-rebackfilled" : "BUG-present(stale-overwrite-attribution)"))
    CloseDb(dbPath)
}

; ------------------------------------------------------------------
; CHECK 13: forking AT a USER message. MessageRepo.Insert computes the
; user row's active_path_tokens as parent.apt + token_count at INSERT
; time (token_count is still 0); the later assistant response backfills
; the user's token_count but NEVER updates its active_path_tokens. When
; that user message is used as a FORK POINT, the fork's leaf (the user
; copy) reports the STALE context (parent context only), so the fork's
; header "Context Used" under-reports the user's own contribution.
; ------------------------------------------------------------------
ForkAtUserStaleContext() {
    dbPath := OpenDb()
    tid := ChatDB.Thread_Create("ForkAtUserStaleContext")
    u1 := ChatDB.Msg_Insert({thread_id: tid, role: "user", content: "u1"})
    a1 := ChatDB.Msg_Insert({thread_id: tid, role: "assistant", content: "a1", parent_id: u1, model: "deepseek/deepseek-v4-flash", prompt_tokens: 12, token_count: 9})
    u2 := ChatDB.Msg_Insert({thread_id: tid, role: "user", content: "u2", parent_id: ChatDB.db.Query("SELECT id FROM messages WHERE content='a1';").rows[1].id})
    a2 := ChatDB.Msg_Insert({thread_id: tid, role: "assistant", content: "a2", parent_id: u2, model: "deepseek/deepseek-v4-flash", prompt_tokens: 30, token_count: 6})
    ; u2.tc was backfilled to 30-(12+9)=9; u2.apt should be 12+9+9=30.
    u2row := ChatDB.db.Query("SELECT token_count, active_path_tokens FROM messages WHERE id=?;", u2)
    u2tc := Integer(u2row[1, "token_count"])
    u2apt := Integer(u2row[1, "active_path_tokens"])
    ; Fork AT u2 - the fork's leaf is the u2 copy.
    forkId := ChatDB.Msg_ForkThread(tid, u2)
    stats := ChatDB.Msg_GetThreadStats(forkId)
    forkContext := Integer(stats.activePathTokens)
    Log("FORKATUSER u2tc=" u2tc " u2apt=" u2apt " forkContext=" forkContext " (true context at u2 = 30)")
    Log("FORKATUSER verdict=" (forkContext = 30 ? "OK-accurate" : "BUG-present(stale-fork-context)"))
    CloseDb(dbPath)
}

; ------------------------------------------------------------------
; CHECK 14: FTS5 prefix matching checks the WRONG quote character.
; _FTS5 wraps every term in double quotes (_FTS5QuoteTerm) and appends a
; trailing * for prefix matching UNLESS the RAW query's last char is "*" or
; "'". The "'" check was meant to detect "the last term is quoted", but the
; terms are always double-quoted - so a query whose last character is a
; single quote (e.g. "don't", "comp'") silently loses the prefix match.
; ------------------------------------------------------------------
Fts5PrefixQuote() {
    dbPath := OpenDb()
    tid := ChatDB.Thread_Create("Fts5PrefixQuote")
    u1 := ChatDB.Msg_Insert({thread_id: tid, role: "user", content: "complete the compass calculation"})
    u2 := ChatDB.Msg_Insert({thread_id: tid, role: "user", content: "don't forget the donuts", parent_id: u1})

    ; Prefix query ending in a normal char: "comp" -> "comp"* matches complete/compass.
    hitsPlain := SearchRepo._FTS5("comp", tid)
    plainCount := hitsPlain.Length
    ; Prefix query ending in an apostrophe: "comp'" -> "comp'" exact-match only -
    ; no * is appended because lastChar = "'", so complete/compass are NOT found.
    hitsQuote := SearchRepo._FTS5("comp'", tid)
    quoteCount := hitsQuote.Length
    ; The observable contract: "comp'" must behave like "comp" (prefix match).
    ; It returns 0 because the trailing-' check skips the appended *.
    Log("FTS5PREFIX plain comp hits=" plainCount " comp' hits=" quoteCount)
    Log("FTS5PREFIX verdict=" (quoteCount = 0 && plainCount > 0 ? "BUG-present(quote-ends-prefix)" : "OK-prefix"))
    CloseDb(dbPath)
}

; ------------------------------------------------------------------
; CHECK 15: a command whose APIModels is empty (the UI's "Default" dropdown
; option) sends a model-less request. StrSplit(RegExReplace("", ...), ",")
; yields [""] (one empty entry), ProviderResolver.Resolve("") falls back to
; the deepseek provider with modelName "", and createJSONRequest emits
; {"model": ""} - the API is called with an EMPTY model name instead of the
; app default the "Default" option advertises.
; ------------------------------------------------------------------
CommandEmptyModels() {
    arr := StrSplit(RegExReplace("", "\s+", ""), ",")
    json := LLMRequestBuilder.createJSONRequest("", "", "hello", "", "", "", false)
    prov := ProviderResolver.Resolve("")
    hasEmptyModel := InStr(json, '"model":""')
    ; arr.Length = 0 means processInitialRequest's `for` loop never runs: the
    ; command is a silent NO-OP (no thread, no request, no error). Either way
    ; the "Default" option never substitutes the app default model.
    noop := arr.Length = 0
    Log("CMDEMPTY modelsArrLen=" arr.Length " provider=" prov.providerKey " modelName='" prov.modelName "'")
    Log("CMDEMPTY json=" json)
    Log("CMDEMPTY verdict=" ((noop || hasEmptyModel) ? "BUG-present(default-model-not-substituted)" : "OK-default-substituted"))
}

; ------------------------------------------------------------------
; CHECK 16: FTS5 only indexes message content - attachment extracted_text
; (PDF/office text extraction) is never indexed, so a term that exists ONLY
; inside an attached document cannot be found by Search.
; ------------------------------------------------------------------
FtsAttachmentText() {
    dbPath := OpenDb()
    tid := ChatDB.Thread_Create("FtsAttachmentText")
    u1 := ChatDB.Msg_Insert({thread_id: tid, role: "user", content: "see attached report"})
    ; Attach a PDF whose extracted_text contains the only occurrence of "needle":
    ChatDB.Attachment_Insert(u1, {
        attachment_type: "pdf",
        file_path: "attachments/report.pdf",
        mime_type: "application/pdf",
        original_filename: "report.pdf",
        file_size: 1024,
        extracted_text: "Quarterly results mention the needle keyword only here."
    })
    hits := SearchRepo.Search("needle", tid)
    Log("FTSATT search needle hits=" hits.Length)
    Log("FTSATT verdict=" (hits.Length = 0 ? "BUG-present(extracted-text-unsearchable)" : "OK-indexed"))
    CloseDb(dbPath)
}

; ------------------------------------------------------------------
; CHECK 17: _RecomputeCumulativeCounters skips assistant rows whose model is
; empty (the empty-APIModels command flow inserts real assistant rows with
; model ""), so a BILLED API response with token metadata never counts toward
; the thread's cumulative counters or the usage dashboard.
; ------------------------------------------------------------------
EmptyModelSkip() {
    dbPath := OpenDb()
    tid := ChatDB.Thread_Create("EmptyModelSkip")
    u1 := ChatDB.Msg_Insert({thread_id: tid, role: "user", content: "u1"})
    ; Real API response row produced by the empty-APIModels flow: model "" but
    ; prompt_tokens/token_count present (the API answered and billed).
    ChatDB.Msg_Insert({thread_id: tid, role: "assistant", content: "a1", parent_id: u1, model: "", prompt_tokens: 12, token_count: 9, thinking_tokens: 2, cached_tokens: 4})
    row := ChatDB.db.Query("SELECT cumulative_input_tokens, cumulative_output_tokens, cumulative_cached_tokens FROM chat_threads WHERE id=?;", tid)
    inp := Integer(row[1, "cumulative_input_tokens"]), outp := Integer(row[1, "cumulative_output_tokens"]), ckt := Integer(row[1, "cumulative_cached_tokens"])
    usageCount := ChatDB.db.Query("SELECT COUNT(*) AS c FROM chat_usage;")[1, "c"]
    Log("EMPTYMODEL input=" inp " output=" outp " cached=" ckt " usageRows=" usageCount " (assistant row has 12/9+2/4)")
    Log("EMPTYMODEL verdict=" (inp = 0 && outp = 0 && ckt = 0 && usageCount = 0 ? "BUG-present(empty-model-untracked)" : "OK-counted"))
    CloseDb(dbPath)
}

; ------------------------------------------------------------------
; CHECK 18: forking drops the per-message COST snapshots (bug #10
; follow-up). MessageRepo.Insert snapshots input_cost/cached_input_cost/
; output_cost/total_cost at the prices in effect (bug #153), but
; TreeRepo._InsertForkMessage/_InsertCopiedOffPathMessage copy only token
; fields, so fork rows carry cost 0. _RecomputeCumulativeCounters then
; falls back to the CURRENT model prices for rows with zero costs and real
; tokens - after a Settings price change the fork's header cost disagrees
; with the source thread (which keeps its snapshots).
; ------------------------------------------------------------------
ForkCostSnapshot() {
    dbPath := OpenDb()
    tid := ChatDB.Thread_Create("ForkCostSnapshot")
    u1 := ChatDB.Msg_Insert({thread_id: tid, role: "user", content: "u1"})
    a1 := ChatDB.Msg_Insert({thread_id: tid, role: "assistant", content: "a1", parent_id: u1, model: "deepseek/deepseek-v4-flash", prompt_tokens: 100, token_count: 50, cached_tokens: 20})
    srcRow := ChatDB.db.Query("SELECT cumulative_cost FROM chat_threads WHERE id=?;", tid)
    srcCost := Number(srcRow[1, "cumulative_cost"])
    msgRow := ChatDB.db.Query("SELECT input_cost, cached_input_cost, output_cost, total_cost FROM messages WHERE id=?;", a1)
    snapTotal := Number(msgRow[1, "total_cost"])
    ; Simulate a Settings price change AFTER the API call was made.
    m := models["deepseek/deepseek-v4-flash"]
    m.input := m.input * 2
    m.cachedInput := m.cachedInput * 2
    m.output := m.output * 2
    forkId := ChatDB.Msg_ForkThread(tid, a1)
    forkRow := ChatDB.db.Query("SELECT cumulative_cost FROM chat_threads WHERE id=?;", forkId)
    forkCost := Number(forkRow[1, "cumulative_cost"])
    forkMsgRows := ChatDB.db.Query("SELECT input_cost, cached_input_cost, output_cost, total_cost FROM messages WHERE thread_id=?;", forkId)
    copiedCostSum := 0
    for r in forkMsgRows.rows
        copiedCostSum += Number(r.input_cost) + Number(r.cached_input_cost) + Number(r.output_cost) + Number(r.total_cost)
    Log("FORKCOST srcCost=" srcCost " forkCost=" forkCost " snapshot=" snapTotal " copiedCostSum=" copiedCostSum)
    Log("FORKCOST verdict=" (forkCost != srcCost && copiedCostSum = 0 ? "BUG-present(cost-snapshots-dropped)" : "OK-cost-copied"))
    CloseDb(dbPath)
}

; ------------------------------------------------------------------
; CHECK 19: OVERWRITE-editing an ASSISTANT message leaves its OLD
; token_count in place (MessageRepo.Edit re-estimates only role=user, bug
; #156). The assistant's token_count feeds _BackfillUserTokens' existing_sum,
; so the NEXT user message's backfill subtracts the stale output-token count
; and its token popover over-counts - the same stale-attribution family as
; the user path, on the assistant path.
; a1 reported 12/9; a1 is overwrite-edited to a ~100-token text. The next
; real prompt is u1(12) + NEW a1(100) + u2(4) + a2(6) + u3(5) = 127, but the
; backfill subtracts the stale a1.tc=9: u3 gets 127-(12+9+4+6)=96 not 5.
; ------------------------------------------------------------------
EditAssistantStaleBackfill() {
    dbPath := OpenDb()
    tid := ChatDB.Thread_Create("EditAssistantStaleBackfill")
    u1 := ChatDB.Msg_Insert({thread_id: tid, role: "user", content: "u1"})
    a1 := ChatDB.Msg_Insert({thread_id: tid, role: "assistant", content: "SHORT", parent_id: u1, model: "deepseek/deepseek-v4-flash", prompt_tokens: 12, token_count: 9})
    u2 := ChatDB.Msg_Insert({thread_id: tid, role: "user", content: "u2", parent_id: a1})
    ChatDB.Msg_Insert({thread_id: tid, role: "assistant", content: "a2", parent_id: u2, model: "deepseek/deepseek-v4-flash", prompt_tokens: 25, token_count: 6})
    ; Overwrite edit: assistant content grows dramatically (heuristic ~1 token
    ; per 3 chars -> ~100 tokens for 300 chars).
    longText := ""
    loop 300
        longText .= "x"
    ChatDB.Msg_Edit(a1, longText)
    a1tcAfterEdit := Integer(ChatDB.db.Query("SELECT token_count FROM messages WHERE id=?;", a1)[1, "token_count"])
    u3 := ChatDB.Msg_Insert({thread_id: tid, role: "user", content: "u3", parent_id: ChatDB.db.Query("SELECT id FROM messages WHERE content='a2';").rows[1].id})
    ChatDB.Msg_Insert({thread_id: tid, role: "assistant", content: "a3", parent_id: u3, model: "deepseek/deepseek-v4-flash", prompt_tokens: 127, token_count: 5})
    u3tc := Integer(ChatDB.db.Query("SELECT token_count FROM messages WHERE id=?;", u3)[1, "token_count"])
    Log("EDITASSISTANT a1tcAfterEdit=" a1tcAfterEdit " u3tc=" u3tc " (true u3 contribution 5)")
    Log("EDITASSISTANT verdict=" (u3tc = 5 ? "OK-rebackfilled" : "BUG-present(stale-assistant-attribution)"))
    CloseDb(dbPath)
}

; ------------------------------------------------------------------
; CHECK 20: the "__unknown__" provider-filter sentinel collides with a real
; provider literally named "__unknown__" (user-editable in Settings).
; UsageRepo.Query scopes the sentinel to (provider='' OR provider IS NULL),
; so selecting the filter matches ONLY blank-provider rows - the real
; provider's rows are unreachable through their own name even though the
; providers dropdown lists them (both options carry the same value).
; ------------------------------------------------------------------
UnknownProviderSentinel() {
    dbPath := OpenDb()
    today := FormatTime(, "yyyy-MM-dd")
    ChatDB.ChatUsage_Upsert({date: today, model: "real/__unknown__", provider: "__unknown__", prompt_tokens: 10, completion_tokens: 5, cached_tokens: 0, input_cost: 0.1, cached_input_cost: 0, output_cost: 0.2, total_cost: 0.3, response_time_ms: 100, ttft_ms: 50})
    ChatDB.ChatUsage_Upsert({date: today, model: "blank-model", provider: "", prompt_tokens: 20, completion_tokens: 10, cached_tokens: 0, input_cost: 0.2, cached_input_cost: 0, output_cost: 0.4, total_cost: 0.6, response_time_ms: 200, ttft_ms: 100})
    f := Map()
    f["timeRange"] := "all"
    f["model"] := ""
    f["provider"] := "__unknown__"
    f["type"] := "all"
    res := ChatDB.Usage_Query(f)
    realRows := 0, blankRows := 0
    for r in res.chat {
        if r.provider = "__unknown__"
            realRows++
        if r.provider = ""
            blankRows++
    }
    hasSentinelInList := false
    for p in res.providers
        if p = "__unknown__"
            hasSentinelInList := true
    Log("UNKNOWNPROV realRows=" realRows " blankRows=" blankRows " providersListHas__unknown__=" (hasSentinelInList ? 1 : 0) " totalChatRows=" res.chat.Length)
    Log("UNKNOWNPROV verdict=" (realRows = 0 && blankRows > 0 && hasSentinelInList ? "BUG-present(sentinel-collision)" : "OK-distinct"))
    CloseDb(dbPath)
}

; ------------------------------------------------------------------
; CHECK 21: search result snippets for attachment-text hits show the
; message content, not the match. Bug #165 made extracted_text searchable
; (the message IS found), but SearchRepo._FTS5 builds contentPreview from
; m.content only - for a term that exists only in an attachment the preview
; is the message's own text, unrelated to the match.
; ------------------------------------------------------------------
FtsAttachmentSnippet() {
    dbPath := OpenDb()
    tid := ChatDB.Thread_Create("FtsAttachmentSnippet")
    u1 := ChatDB.Msg_Insert({thread_id: tid, role: "user", content: "see attached report"})
    ChatDB.Attachment_Insert(u1, {
        attachment_type: "pdf",
        file_path: "attachments/report.pdf",
        mime_type: "application/pdf",
        original_filename: "report.pdf",
        file_size: 1024,
        extracted_text: "Quarterly results mention the needle keyword only here."
    })
    hits := SearchRepo.Search("needle", tid)
    found := hits.Length
    preview := found ? hits[1].contentPreview : ""
    previewHasMatch := InStr(preview, "needle") > 0
    Log("FTSATTNEEDLE hits=" found " preview='" preview "' previewHasMatch=" (previewHasMatch ? 1 : 0))
    Log("FTSATTNEEDLE verdict=" (found > 0 && !previewHasMatch ? "BUG-present(snippet-not-the-match)" : (found > 0 ? "OK-snippet-match" : "OK-no-hits")))
    CloseDb(dbPath)
}

; ------------------------------------------------------------------
; CHECK 22: Thread_List performs a per-thread active-path walk (bug #12
; follow-up). For EVERY listed thread it issues one leaf lookup plus one
; SELECT per ancestor until the nearest assistant - a classic N+1 that makes
; sidebar refresh latency scale with thread count x path depth. Also
; verifies a dangling active_leaf_id (hard-deleted message) and a trashed
; thread do not throw or hang the walk.
; ------------------------------------------------------------------
; Query-counting proxy: a CLASS instance (real methods) so method calls bind
; `this` correctly (plain-object function properties get the receiver prepended
; as an argument in AHK v2, which would corrupt the SQL parameter list).
class ThreadListQueryCounter {
    static count := 0
    static real := ""
    Exec(statement, args*) {
        ThreadListQueryCounter.count++
        return ThreadListQueryCounter.real.Exec(statement, args*)
    }
    Query(statement, args*) {
        ThreadListQueryCounter.count++
        return ThreadListQueryCounter.real.Query(statement, args*)
    }
}

ThreadListNplus1() {
    dbPath := OpenDb()
    loop 300 {
        tid := ChatDB.Thread_Create("N1T" A_Index)
        u1 := ChatDB.Msg_Insert({thread_id: tid, role: "user", content: "u1"})
        a1 := ChatDB.Msg_Insert({thread_id: tid, role: "assistant", content: "a1", parent_id: u1, model: "deepseek/deepseek-v4-flash", prompt_tokens: 10, token_count: 5})
        ; Active leaf = the USER message (last message sent, waiting for the
        ; response/failed) - the badge walk must climb u2 -> a1 (2 queries).
        u2 := ChatDB.Msg_Insert({thread_id: tid, role: "user", content: "u2", parent_id: a1})
        ChatDB.Msg_SetActiveLeaf(tid, u2)
    }
    ; A thread whose active_leaf_id points at a hard-deleted message.
    dtid := ChatDB.Thread_Create("DanglingLeaf")
    dmsg := ChatDB.Msg_Insert({thread_id: dtid, role: "user", content: "x"})
    ChatDB.db.Query("UPDATE chat_threads SET active_leaf_id='ghost-missing-id' WHERE id=?;", dtid)
    ; A trashed thread that must be excluded from the list.
    ttid := ChatDB.Thread_Create("Trashed")
    ChatDB.Thread_SoftDelete(ttid)

    realDb := ChatDB.db
    ThreadListQueryCounter.count := 0
    ThreadListQueryCounter.real := realDb
    ChatDB.db := ThreadListQueryCounter()
    list := ChatDB.Thread_List()
    ChatDB.db := realDb
    queryCount := ThreadListQueryCounter.count

    listedDangling := 0, listedTrashed := 0
    for t in list {
        if t.id = dtid
            listedDangling++
        if t.id = ttid
            listedTrashed++
    }
    Log("THREADLIST threads=" list.Length " queries=" queryCount " perThread=" Round(queryCount / 300, 1) " listedDangling=" listedDangling " listedTrashed=" listedTrashed)
    ; The dangling-leaf thread IS a real thread (it must still be listed - the
    ; walk just must not throw/hang); the trashed thread must be excluded.
    Log("THREADLIST verdict=" (queryCount > 305 && listedDangling = 1 && listedTrashed = 0 ? "BUG-present(nplus1-walk)" : "OK-bounded"))
    CloseDb(dbPath)
}

; ------------------------------------------------------------------
; CHECK 23: hard-delete-mid-stream leaves DANGLING message rows (bug #172
; "by-design trace"): the stream completes into the captured thread id after
; ThreadRepo.Delete removed the thread, and messages has no FK on thread_id.
; Verify they never leak into FTS results or the thread map, and decide
; whether the dashboard row (a genuinely billed call) is a leak.
; ------------------------------------------------------------------
DanglingMidstreamRows() {
    dbPath := OpenDb()
    tid := ChatDB.Thread_Create("MidStream")
    u1 := ChatDB.Msg_Insert({thread_id: tid, role: "user", content: "u1"})
    ChatDB.Msg_Insert({thread_id: tid, role: "assistant", content: "a1", parent_id: u1, model: "deepseek/deepseek-v4-flash", prompt_tokens: 12, token_count: 9})
    ; User deletes the thread while the request is in flight.
    ChatDB.Thread_Delete(tid)
    ; The completion handler persists into the captured thread id (bug #159
    ; semantics) - the row is now dangling.
    orphanId := ChatDB.Msg_Insert({thread_id: tid, role: "assistant", content: "late completion", model: "deepseek/deepseek-v4-flash", prompt_tokens: 30, token_count: 15, cached_tokens: 5})
    dangling := ChatDB.db.Query("SELECT COUNT(*) AS c FROM messages WHERE thread_id NOT IN (SELECT id FROM chat_threads);")[1, "c"]
    ftsRows := ChatDB.db.Query("SELECT COUNT(*) AS c FROM messages_fts WHERE msg_id=?;", orphanId)[1, "c"]
    searchHits := SearchRepo.Search("late completion").Length
    listed := 0
    for t in ChatDB.Thread_List()
        if t.id = tid
            listed++
    usageRows := ChatDB.db.Query("SELECT COUNT(*) AS c FROM chat_usage WHERE model='deepseek/deepseek-v4-flash';")[1, "c"]
    Log("DANGLING rows=" dangling " ftsRows=" ftsRows " searchHits=" searchHits " threadMapListed=" listed " usageRows=" usageRows)
    Log("DANGLING verdict=" (dangling > 0 && ftsRows = 1 && searchHits = 0 && listed = 0 && usageRows = 1 ? "OK-invisible-except-billed-usage" : "BUG-present(leak)"))
    CloseDb(dbPath)
}

; ------------------------------------------------------------------
; CHECK 24: the v6 migration backfill (bug #10 follow-up) must apply
; exactly ONCE per DB - PRAGMA user_version=6 guards the one-time re-price
; of legacy rows. After a price change, a reopen must NOT re-run the
; backfill (the costs stay at the first-open prices).
; ------------------------------------------------------------------
MigrationBackfillGuard() {
    dbPath := A_Temp "\bughunt_mig_" A_TickCount ".db"
    try FileDelete(dbPath)
    ; Build a v5-era schema (messages WITHOUT the v6 cost columns) so the
    ; migration path really runs; user_version=5.
    raw := SQLite(dbPath)
    raw.Exec("PRAGMA journal_mode=WAL;")
    raw.Exec("CREATE TABLE IF NOT EXISTS chat_threads (id TEXT PRIMARY KEY, title TEXT DEFAULT 'New Chat', is_deleted INTEGER DEFAULT 0, deleted_at TEXT, created_at TEXT DEFAULT (datetime('now')), updated_at TEXT DEFAULT (datetime('now')), active_leaf_id TEXT, cumulative_input_tokens INTEGER DEFAULT 0, cumulative_output_tokens INTEGER DEFAULT 0, cumulative_cached_tokens INTEGER DEFAULT 0, cumulative_cost REAL DEFAULT 0, cumulative_input_cost REAL DEFAULT 0, cumulative_cached_input_cost REAL DEFAULT 0, cumulative_output_cost REAL DEFAULT 0, assistant_id TEXT, model_override TEXT, system_override TEXT, reasoning_override TEXT, temperature_override REAL, font_size INTEGER DEFAULT 17, advanced_toggles TEXT DEFAULT '', folder_id TEXT);")
    raw.Exec("CREATE TABLE IF NOT EXISTS messages (id TEXT PRIMARY KEY, thread_id TEXT NOT NULL, role TEXT NOT NULL, content TEXT NOT NULL, model TEXT, parent_id TEXT, sibling_group TEXT, sibling_index INTEGER DEFAULT 0, reasoning TEXT DEFAULT '', token_count INTEGER DEFAULT 0, prompt_tokens INTEGER DEFAULT 0, thinking_tokens INTEGER DEFAULT 0, cached_tokens INTEGER DEFAULT 0, response_time_ms INTEGER DEFAULT 0, ttft_ms INTEGER DEFAULT 0, active_path_tokens INTEGER DEFAULT 0, is_local_copy INTEGER DEFAULT 0, created_at TEXT DEFAULT (datetime('now')));")
    raw.Exec("INSERT INTO messages (id, thread_id, role, content, model, prompt_tokens, token_count, thinking_tokens, cached_tokens) VALUES ('legacy1','t1','assistant','x','deepseek/deepseek-v4-flash',100,50,0,20);")
    raw.Exec("INSERT INTO chat_threads (id, title, active_leaf_id) VALUES ('t1','Legacy','legacy1');")
    raw.Exec("PRAGMA user_version = 5;")
    raw.Close()

    ; First open: v6 migration backfills costs at CURRENT prices.
    ChatDB.Open(dbPath)
    c1 := ChatDB.db.Query("SELECT input_cost, cached_input_cost, output_cost, total_cost FROM messages WHERE id='legacy1';")
    v1 := ChatDB.db.Exec("PRAGMA user_version;")[1, "user_version"]
    cost1 := Number(c1[1, "total_cost"])
    ChatDB.Close()

    ; Double the price, reopen: the user_version guard must prevent a
    ; second backfill (costs stay at the first-open prices).
    m := models["deepseek/deepseek-v4-flash"]
    m.input := m.input * 2
    m.cachedInput := m.cachedInput * 2
    m.output := m.output * 2
    ChatDB.Open(dbPath)
    c2 := ChatDB.db.Query("SELECT input_cost, cached_input_cost, output_cost, total_cost FROM messages WHERE id='legacy1';")
    v2 := ChatDB.db.Exec("PRAGMA user_version;")[1, "user_version"]
    cost2 := Number(c2[1, "total_cost"])
    ChatDB.Close()
    try FileDelete(dbPath)
    try FileDelete(dbPath "-wal")
    try FileDelete(dbPath "-shm")

    Log("MIGBACK v1=" v1 " v2=" v2 " cost1=" cost1 " cost2=" cost2)
    Log("MIGBACK verdict=" (v1 = 6 && v2 = 6 && cost1 > 0 && cost1 = cost2 ? "OK-guard" : "BUG-present(re-priced-or-migrated-twice)"))
}

; ------------------------------------------------------------------
; CHECK 25: ProviderResolver.Resolve falls back to the HARDCODED "deepseek"
; provider (`providers["deepseek"]`) when no prefix matches - a missing-key
; Map index THROWS in AHK v2. The Settings Providers UI lets the user REMOVE
; the deepseek provider (at least one provider must remain, so deleting
; deepseek while keeping e.g. openai is allowed); any model whose prefix is
; not covered by the remaining providers then crashes every request.
; ------------------------------------------------------------------
ProviderResolveDeletedDeepseek() {
    global providers, providerMap
    providers := Map()
    providers["openai"] := {displayName: "OpenAI", endpoint: "https://api.openai.com/v1", fimEndpoint: "https://api.openai.com/v1", authEnvVar: "OPENAI_API_KEY", authMode: "env", apiKey: "", collapseThinking: false}
    providerMap := Map("openai", "openai")
    r1 := ""
    try {
        r1 := ProviderResolver.Resolve("deepseek/deepseek-v4-flash").providerKey
    } catch Error as e {
        r1 := "THREW:" e.Message
    }
    r2 := ""
    try {
        r2 := ProviderResolver.Resolve("openai/gpt-4").providerKey
    } catch Error as e {
        r2 := "THREW:" e.Message
    }
    threw1 := InStr(r1, "THREW") > 0
    Log("PROVRES deletedDeepseekThrew=" (threw1 ? 1 : 0) " openaiControl=" r2)
    Log("PROVRES verdict=" (threw1 && r2 = "openai" ? "BUG-present(fallback-crash)" : "OK-fallback"))
}

; ------------------------------------------------------------------
; CHECK 26: settings round-trip edge cases - model ids containing commas and
; double quotes survive Save -> Load -> ApplyToGlobals and bind correctly in
; the dashboard provider/model filters; blank cachedInput/context values
; round-trip (costs still fall back via CostCalculator); providers with all
; prefixes cleared apply without error.
; ------------------------------------------------------------------
SettingsEdgeRoundtrip() {
    tmp := A_Temp "\bughunt_settings_" A_TickCount ".json"
    SettingsPersistence.settingsPath := tmp
    try FileDelete(tmp)
    settings := Map()
    providers := Map()
    providers["openai"] := Map("displayName", "OpenAI", "endpoint", "https://api.openai.com/v1", "fimEndpoint", "", "authEnvVar", "OPENAI_API_KEY", "authMode", "env", "apiKey", "", "collapseThinking", false, "prefixes", [])
    settings["providers"] := providers
    models := Map()
    models["openai/gpt-5,beta"] := Map("provider", "openai", "input", 1.5, "cachedInput", "", "output", 3, "context", "")
    models["openai/gpt-`"q`"x"] := Map("provider", "openai", "input", 2, "cachedInput", 0, "output", 4, "context", 0)
    settings["models"] := models
    saved := SettingsHandler.Save(settings)
    loaded := SettingsHandler.Load()
    applyErr := ""
    try {
        SettingsHandler.ApplyToGlobals(loaded)
    } catch Error as e {
        applyErr := e.Message
    }
    hasComma := loaded.Has("models") && loaded["models"].Has("openai/gpt-5,beta")
    hasQuote := loaded.Has("models") && loaded["models"].Has("openai/gpt-`"q`"x")
    ; Blank cachedInput must keep falling back to 10% of input (bug #29).
    c1 := CostCalculator.ComputeTokenCosts("openai/gpt-5,beta", {promptTokens: 1000000, completionTokens: 500000, cachedTokens: 200000, totalTokens: 1500000})
    cachedFallback := c1.cachedInputCost != "" && c1.cachedInputCost > 0
    ; Dashboard filter binding with a comma-containing model id.
    dbPath := OpenDb()
    today := FormatTime(, "yyyy-MM-dd")
    ChatDB.ChatUsage_Upsert({date: today, model: "openai/gpt-5,beta", provider: "openai", prompt_tokens: 10, completion_tokens: 5, cached_tokens: 0, input_cost: 0, cached_input_cost: 0, output_cost: 0, total_cost: 0, response_time_ms: 1, ttft_ms: 1})
    qf := Map()
    qf["timeRange"] := "all"
    qf["model"] := "openai/gpt-5,beta"
    qf["provider"] := "openai"
    qf["type"] := "all"
    qres := ChatDB.Usage_Query(qf)
    filterHits := qres.chat.Length
    CloseDb(dbPath)
    Log("SETTINGSEDGE saved=" (saved ? 1 : 0) " applyErr='" applyErr "' commaId=" (hasComma ? 1 : 0) " quoteId=" (hasQuote ? 1 : 0) " cachedFallback=" (cachedFallback ? 1 : 0) " filterHits=" filterHits)
    Log("SETTINGSEDGE verdict=" (saved && !applyErr && hasComma && hasQuote && cachedFallback && filterHits = 1 ? "OK-roundtrip" : "BUG-present(edge-case)"))
    try FileDelete(tmp)
}

; ------------------------------------------------------------------
; CHECK 27: cross-process startup race. Opens the SAME db path as a fresh
; connection and runs the REAL ChatDB._CreateSchema (schema + migrations +
; FTS rebuild) then closes - invoked CONCURRENTLY by two harness-spawned AHK
; processes to stress the WAL/busy_timeout path the app's Main + ChatWindow
; hit at startup. Caller passes the db path as arg 3.
; ------------------------------------------------------------------
OpenRace() {
    dbPath := A_Args.Length >= 3 ? A_Args[3] : ""
    if !dbPath {
        Log("OPENRACE no-db-path")
        return
    }
    ChatDB.Open(dbPath)
    ; Force the FTS repair path when counts mismatch (the caller seeds
    ; messages without FTS rows, so both processes race the rebuild).
    ChatDB.Close()
    Log("OPENRACE done")
}

; ------------------------------------------------------------------
; CHECK 28 (REFUTED lead): ThreadTitleGen._TitleGen_ParseResponse must never
; throw on a malformed / partial provider response (truncated JSON from a
; network hiccup, proxy timeout, or provider bug). The parser wraps jsongo in
; a BARE try with no catch - probe-verified that a bare try block in AHK v2
; SWALLOWS exceptions (continues after the block), so the function returns an
; empty title instead of crashing the SetTimer callback. Regression check:
; malformed JSON and an empty-completion shape both parse gracefully, and a
; normal response still yields the title.
; ------------------------------------------------------------------
TitleGenParseGraceful() {
    q := Chr(34)
    ; Realistic truncated title response (partial JSON body).
    raw := "{" q "choices" q ": [{" q "mes"
    threw := false
    try {
        r := _TitleGen_ParseResponse(raw)
    } catch Error as e {
        threw := true
    }
    emptyTitle := r.HasProp("title") && r.title = ""
    ; Control: a normal response still parses to a title.
    raw2 := "{" q "choices" q ": [{" q "message" q ": {" q "content" q ": " q "Hello Title" q "}}]}"
    r2 := _TitleGen_ParseResponse(raw2)
    ; Control 2: an empty-completion shape (choices[0].message without
    ; content) must ALSO be graceful - it already is (no throw).
    raw3 := "{" q "choices" q ": [{" q "message" q ": {}}]}"
    threw3 := false
    try {
        r3 := _TitleGen_ParseResponse(raw3)
    } catch Error as e {
        threw3 := true
    }
    Log("TITLEGENPARSE threw=" (threw ? 1 : 0) " controlTitle='" r2.title "' emptyCompletionThrew=" (threw3 ? 1 : 0))
    Log("TITLEGENPARSE verdict=" (!threw && !threw3 && emptyTitle && r2.title = "Hello Title" ? "OK-graceful" : "BUG-present(parse-throws)"))
}

check := A_Args.Length >= 2 ? A_Args[2] : ""
switch check {
    case "fork-offpath": ForkOffpath()
    case "branch-copy-recount": BranchCopyRecount()
    case "backfill-thinking": BackfillThinking()
    case "branch-user-stale": BranchUserStale()
    case "retry-root-assistant": RetryRootAssistant()
    case "walk-to-leaf": WalkToLeafOldest()
    case "command-thinking-short": CommandThinkingShort()
    case "root-delete-leaf": RootDeleteLeaf()
    case "branch-drop-reasoning": BranchDropReasoning()
    case "thread-list-model-stale": ThreadListModelStale()
    case "switch-branch-wrap": SwitchBranchWrap()
    case "edit-user-stale-backfill": EditUserStaleBackfill()
    case "fork-at-user-stale-context": ForkAtUserStaleContext()
    case "fts5-prefix-quote": Fts5PrefixQuote()
    case "command-empty-models": CommandEmptyModels()
    case "fts-attachment-text": FtsAttachmentText()
    case "empty-model-skip": EmptyModelSkip()
    case "fork-cost-snapshot": ForkCostSnapshot()
    case "edit-assistant-stale-backfill": EditAssistantStaleBackfill()
    case "unknown-provider-sentinel": UnknownProviderSentinel()
    case "fts-attachment-snippet": FtsAttachmentSnippet()
    case "thread-list-nplus1": ThreadListNplus1()
    case "dangling-midstream-rows": DanglingMidstreamRows()
    case "migration-backfill-guard": MigrationBackfillGuard()
    case "provider-resolve-deleted-deepseek": ProviderResolveDeletedDeepseek()
    case "settings-edge-roundtrip": SettingsEdgeRoundtrip()
    case "open-race": OpenRace()
    case "titlegen-parse-throw": TitleGenParseGraceful()
    default:
        Log("UNKNOWN CHECK " check)
}
Finish()
ExitApp(0)
