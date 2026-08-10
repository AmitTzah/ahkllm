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

check := A_Args.Length >= 2 ? A_Args[2] : ""
switch check {
    case "fork-offpath": ForkOffpath()
    case "branch-copy-recount": BranchCopyRecount()
    case "backfill-thinking": BackfillThinking()
    case "branch-user-stale": BranchUserStale()
    case "retry-root-assistant": RetryRootAssistant()
    case "walk-to-leaf": WalkToLeafOldest()
    case "command-thinking-short": CommandThinkingShort()
    default:
        Log("UNKNOWN CHECK " check)
}
Finish()
ExitApp(0)
