; probe-bughunt-db.ahk - Deep DB-audit probe (bug hunt, 2026-08-10).
; Runs the REAL ChatDB/repo code against a temp SQLite database and prints
; token-accounting / tree-copy results for scenarios to assert on.
; Usage: AutoHotkey64.exe probe-bughunt-db.ahk <outFile> <check> [args...]
; Checks:
;   fork-offpath        - what a fork at a1 copies when a1 has off-path children
;   branch-copy-recount - cumulative counters after a local_copy + real follow-up
;   backfill-thinking   - user token backfill when prior assistant had thinking
;   branch-user-stale   - branch-copied user message keeps the source token_count
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
OnError((e, m) => (Log("ERROR: " e.Message), Finish(), ExitApp(1)), -1)

#Include ..\..\lib\Config.ahk

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
    default:
        Log("UNKNOWN CHECK " check)
}
Finish()
ExitApp(0)
