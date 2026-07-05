; ======================================================
; ChatDB.ahk — Domain wrapper around SQLite for chat persistence
;
; Schema:
;   chat_threads:   thread metadata + active_leaf_id pointer
;   messages:       all messages with parent_id tree + sibling_group branching
;
; All public methods return objects/arrays or throw on failure.
; Internal helpers prefixed with _ are not meant for external use.
; ======================================================

class ChatDB {
    ; ----------------------------------------------------
    ; Database path and connection
    ; ----------------------------------------------------

    static db := unset
    static dbPath := ""
    static isOpen := false

    ; Open (or create) the database. Must be called once before any operations.
    static Open(dbPath := "") {
        if ChatDB.isOpen
            return
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

    ; Close the database connection gracefully
    static Close() {
        if ChatDB.isOpen {
            ChatDB.db.Close()
            ChatDB.db := unset
            ChatDB.isOpen := false
        }
    }

    ; ----------------------------------------------------
    ; Schema creation (idempotent)
    ; ----------------------------------------------------

    static _CreateSchema() {
        ChatDB.db.Exec("CREATE TABLE IF NOT EXISTS chat_threads (id TEXT PRIMARY KEY, title TEXT DEFAULT 'New Chat', created_at TEXT DEFAULT (datetime('now')), updated_at TEXT DEFAULT (datetime('now')), active_leaf_id TEXT);")
        ChatDB.db.Exec("CREATE TABLE IF NOT EXISTS messages (id TEXT PRIMARY KEY, thread_id TEXT NOT NULL, role TEXT NOT NULL, content TEXT NOT NULL, model TEXT, parent_id TEXT, sibling_group TEXT, sibling_index INTEGER DEFAULT 0, is_deleted INTEGER DEFAULT 0, feedback INTEGER, reasoning TEXT DEFAULT '', prompt_tokens INTEGER DEFAULT 0, completion_tokens INTEGER DEFAULT 0, cached_tokens INTEGER DEFAULT 0, total_tokens INTEGER DEFAULT 0, created_at TEXT DEFAULT (datetime('now')));")
        ; Ensure all columns exist (migration for DBs created before new columns were added)
        colCheck := ChatDB.db.Exec("PRAGMA table_info(messages);")
        colNames := Map()
        for row in colCheck.rows
            colNames[row.name] := true

        if !colNames.Has("reasoning") {
            ChatDB._DBLog("[DEBUG] _CreateSchema: adding reasoning column via ALTER TABLE")
            ChatDB.db.Exec("ALTER TABLE messages ADD COLUMN reasoning TEXT DEFAULT '';")
        }
        for colName in ["prompt_tokens", "completion_tokens", "cached_tokens", "total_tokens"] {
            if !colNames.Has(colName) {
                ChatDB._DBLog("[DEBUG] _CreateSchema: adding " colName " column via ALTER TABLE")
                ChatDB.db.Exec("ALTER TABLE messages ADD COLUMN " colName " INTEGER DEFAULT 0;")
            }
        }
        ChatDB.db.Exec("CREATE INDEX IF NOT EXISTS idx_messages_thread ON messages(thread_id, is_deleted);")
        ChatDB.db.Exec("CREATE INDEX IF NOT EXISTS idx_messages_parent ON messages(parent_id);")
        ChatDB.db.Exec("CREATE INDEX IF NOT EXISTS idx_messages_sibling ON messages(sibling_group, sibling_index);")
    }

    ; ----------------------------------------------------
    ; UUID generation (simple, sufficient for desktop use)
    ; ----------------------------------------------------

    static _UUID() {
        ; Format: timestamp_random — unique enough for a single-user desktop app
        return Format("{1:08x}-{2:04x}-{3:04x}-{4:04x}-{5:012x}",
            A_TickCount,
            Random(0, 0xFFFF),
            Random(0, 0xFFFF),
            Random(0, 0xFFFF),
            Random(0, 0xFFFFFFFF))
    }

    ; ----------------------------------------------------
    ; Thread operations
    ; ----------------------------------------------------

    ; Create a new thread. Returns thread id string.
    static Thread_Create(title := "New Chat") {
        id := ChatDB._UUID()
        safeTitle := SQLite.Escape(title)
        ChatDB.db.Exec("INSERT INTO chat_threads (id, title) VALUES('" id "', '" safeTitle "');")
        return id
    }

    ; Get all threads sorted by most recent first. Returns array of objects.
    static Thread_List() {
        table := ChatDB.db.Exec("SELECT id, title, created_at, updated_at FROM chat_threads ORDER BY updated_at DESC")
        threads := []
        for row in table.rows {
            threads.Push({
                id: row.id,
                title: row.title,
                created_at: row.created_at,
                updated_at: row.updated_at
            })
        }
        return threads
    }

    ; Delete a thread and all its messages
    static Thread_Delete(threadId) {
        ChatDB.db.Exec("DELETE FROM messages WHERE thread_id='" threadId "';")
        ChatDB.db.Exec("DELETE FROM chat_threads WHERE id='" threadId "';")
    }

    ; Update thread title and timestamp
    static Thread_Update(threadId, title, updateTimestamp := true) {
        if !threadId
            return
        safeTitle := SQLite.Escape(title)
        if updateTimestamp
            ChatDB.db.Exec("UPDATE chat_threads SET title='" safeTitle "', updated_at=datetime('now') WHERE id='" threadId "';")
        else
            ChatDB.db.Exec("UPDATE chat_threads SET title='" safeTitle "' WHERE id='" threadId "';")
    }

    ; ----------------------------------------------------
    ; Message operations
    ; ----------------------------------------------------

    ; Insert a message. Returns the message id.
    ; msgObj: { thread_id, role, content, model?, parent_id?, sibling_group?, sibling_index?, reasoning? }
    static Msg_Insert(msgObj) {
        id := ChatDB._UUID()
        safeContent := SQLite.Escape(msgObj.content)
        safeModel := msgObj.HasProp("model") && msgObj.model ? SQLite.Escape(msgObj.model) : ""
        safeParent := msgObj.HasProp("parent_id") && msgObj.parent_id ? "'" msgObj.parent_id "'" : "NULL"
        safeSiblingGroup := msgObj.HasProp("sibling_group") && msgObj.sibling_group ? "'" msgObj.sibling_group "'" : "NULL"
        siblingIdx := msgObj.HasProp("sibling_index") ? msgObj.sibling_index : 0
        safeReasoning := msgObj.HasProp("reasoning") && msgObj.reasoning ? SQLite.Escape(msgObj.reasoning) : ""
        safeFeedback := msgObj.HasProp("feedback") && msgObj.feedback ? msgObj.feedback : "NULL"

        ; Token counts (from API response, or 0 for estimated)
        pt := msgObj.HasProp("prompt_tokens") ? msgObj.prompt_tokens : 0
        ct := msgObj.HasProp("completion_tokens") ? msgObj.completion_tokens : 0
        tt := msgObj.HasProp("total_tokens") ? msgObj.total_tokens : 0
        ckt := msgObj.HasProp("cached_tokens") ? msgObj.cached_tokens : 0

        ChatDB.db.Exec("INSERT INTO messages (id, thread_id, role, content, model, parent_id, sibling_group, sibling_index, reasoning, feedback, prompt_tokens, completion_tokens, cached_tokens, total_tokens) VALUES('" id "', '" msgObj.thread_id "', '" msgObj.role "', '" safeContent "', '" safeModel "', " safeParent ", " safeSiblingGroup ", " siblingIdx ", '" safeReasoning "', " safeFeedback ", " pt ", " ct ", " ckt ", " tt ");")

        ; Update thread's active_leaf_id and timestamp
        ChatDB.db.Exec("UPDATE chat_threads SET active_leaf_id='" id "', updated_at=datetime('now') WHERE id='" msgObj.thread_id "';")

        return id
    }

    ; Mark a message as soft-deleted
    static Msg_SoftDelete(msgId) {
        ChatDB.db.Exec("UPDATE messages SET is_deleted=1 WHERE id='" msgId "';")
        ChatDB._TouchThreadByMsg(msgId)
    }

    ; Undo soft-delete — restore a previously deleted message
    static Msg_Undelete(msgId) {
        ; Only act if the message exists and is soft-deleted
        checkTable := ChatDB.db.Exec("SELECT is_deleted, thread_id FROM messages WHERE id='" msgId "';")
        if !checkTable.count || checkTable[1, "is_deleted"] = 0
            return
        ChatDB.db.Exec("UPDATE messages SET is_deleted=0 WHERE id='" msgId "';")
        ; Restore as active leaf
        threadId := checkTable[1, "thread_id"]
        ChatDB.db.Exec("UPDATE chat_threads SET active_leaf_id='" msgId "', updated_at=datetime('now') WHERE id='" threadId "';")
    }

    ; Edit message content in-place (overwrite).
    ; For "edit as branch", use Msg_Insert with sibling_group set.
    static Msg_Edit(msgId, newContent) {
        safeContent := SQLite.Escape(newContent)
        ChatDB.db.Exec("UPDATE messages SET content='" safeContent "' WHERE id='" msgId "';")
        ChatDB._TouchThreadByMsg(msgId)
    }

    ; Set feedback on a message (1 = thumbs up, -1 = thumbs down, 0 / NULL = clear)
    static Msg_SetFeedback(msgId, rating) {
        if rating = 0
            ChatDB.db.Exec("UPDATE messages SET feedback=NULL WHERE id='" msgId "';")
        else
            ChatDB.db.Exec("UPDATE messages SET feedback=" rating " WHERE id='" msgId "';")
    }

    ; Get all messages for a thread (non-deleted). Returns array ordered by the active path.
    static Msg_GetActivePath(threadId) {
        ; 1. Get the active leaf
        leafTable := ChatDB.db.Exec("SELECT active_leaf_id FROM chat_threads WHERE id='" threadId "';")
        if !leafTable.count
            return []
        leafId := leafTable[1, "active_leaf_id"]
        if !leafId
            return []

        ; 2. Load all non-deleted messages for this thread
        allTable := ChatDB.db.Exec("SELECT * FROM messages WHERE thread_id='" threadId "' AND is_deleted=0;")

        ; 3. Build lookup maps
        msgMap := Map()
        childrenMap := Map()
        for row in allTable.rows {
            msgMap[row.id] := {
                id: row.id,
                thread_id: row.thread_id,
                role: row.role,
                content: row.content,
                model: row.model ? row.model : "",
                parent_id: row.parent_id ? row.parent_id : "",
                sibling_group: row.sibling_group ? row.sibling_group : "",
                sibling_index: row.sibling_index,
                feedback: row.feedback ? Integer(row.feedback) : 0,
                reasoning: row.Has("reasoning") && row["reasoning"] ? row["reasoning"] : "",
                total_tokens: row.Has("total_tokens") && row.total_tokens ? Integer(row.total_tokens) : 0,
                cached_tokens: row.Has("cached_tokens") && row.cached_tokens ? Integer(row.cached_tokens) : 0
            }
            childKey := row.parent_id ? row.parent_id : "__root__"
            if !childrenMap.Has(childKey)
                childrenMap[childKey] := []
            childrenMap[childKey].Push(row.id)
        }

        ; 4. Walk from leaf to root
        path := []
        currentId := leafId
        while currentId && msgMap.Has(currentId) {
            path.InsertAt(1, msgMap[currentId])
            currentId := msgMap[currentId].parent_id
        }

        return path
    }

    ; Get sibling messages at a given message's position
    static Msg_GetSiblings(msgId) {
        ; Find the sibling_group for this message
        table := ChatDB.db.Exec("SELECT sibling_group FROM messages WHERE id='" msgId "';")
        if !table.count
            return []
        sg := table[1, "sibling_group"]
        if !sg
            return []  ; no siblings — this message is a singleton

        ; Get all siblings in this group (filter out soft-deleted)
        table2 := ChatDB.db.Exec("SELECT id, role, content, model, sibling_index, is_deleted FROM messages WHERE sibling_group='" sg "' AND is_deleted=0 ORDER BY sibling_index;")
        siblings := []
        for row in table2.rows {
            siblings.Push({
                id: row.id,
                role: row.role,
                content_preview: SubStr(row.content, 1, 80),
                model: row.model ? row.model : "",
                sibling_index: row.sibling_index,
                is_deleted: row.is_deleted
            })
        }
        return siblings
    }

    ; Get the full branch tree for visualization (D4).
    ; Returns a tree structure: [{ id, role, content_preview, children: [...] }]
    static Msg_GetTree(threadId) {
        allTable := ChatDB.db.Exec("SELECT * FROM messages WHERE thread_id='" threadId "' AND is_deleted=0;")

        ; Build node map and children map
        nodeMap := Map()
        childrenMap := Map()
        for row in allTable.rows {
            node := {
                id: row.id,
                role: row.role,
                content_preview: SubStr(row.content, 1, 80),
                model: row.model ? row.model : "",
                parent_id: row.parent_id ? row.parent_id : "",
                sibling_group: row.sibling_group ? row.sibling_group : "",
                sibling_index: row.sibling_index,
                children: []
            }
            nodeMap[row.id] := node
            parentKey := row.parent_id ? row.parent_id : "__root__"
            if !childrenMap.Has(parentKey)
                childrenMap[parentKey] := []
            childrenMap[parentKey].Push(row.id)
        }

        ; Attach children
        for parentKey, childIds in childrenMap {
            if parentKey = "__root__"
                continue
            if nodeMap.Has(parentKey) {
                for cid in childIds {
                    if nodeMap.Has(cid)
                        nodeMap[parentKey].children.Push(nodeMap[cid])
                }
            }
        }

        ; Return root-level nodes (messages with NULL parent_id)
        roots := []
        if childrenMap.Has("__root__") {
            for cid in childrenMap["__root__"] {
                if nodeMap.Has(cid)
                    roots.Push(nodeMap[cid])
            }
        }
        return roots
    }

    ; Duplicate a thread from the beginning up to and including a given message position.
    ; Returns the new thread id.
    static Msg_ForkThread(threadId, upToMsgId) {
        ; 1. Get the active path
        path := ChatDB.Msg_GetActivePath(threadId)
        if !path.Length
            return ""

        ; 2. Find upToMsgId in path
        cutoff := 0
        for i, msg in path {
            if msg.id = upToMsgId {
                cutoff := i
                break
            }
        }
        if !cutoff
            return ""

        ; 3. Create new thread
        newThreadId := ChatDB.Thread_Create("Fork of " threadId)
        idMap := Map()  ; old_id → new_id

        ; 4. Copy messages up to cutoff
        for i, msg in path {
            if i > cutoff
                break

            newId := ChatDB._UUID()
            idMap[msg.id] := newId
            newParentId := msg.parent_id && idMap.Has(msg.parent_id) ? idMap[msg.parent_id] : ""

            safeContent := SQLite.Escape(msg.content)
            safeModel := msg.model ? SQLite.Escape(msg.model) : ""
            safeParent := newParentId ? "'" newParentId "'" : "NULL"
            ; Preserve sibling_group info when forking
            safeSiblingGroup := msg.sibling_group ? "'" msg.sibling_group "'" : "NULL"
            siblingIdx := msg.sibling_index
            safeFeedback := msg.feedback ? msg.feedback : "NULL"
            safeReasoning := msg.HasProp("reasoning") && msg.reasoning ? SQLite.Escape(msg.reasoning) : ""

            ChatDB.db.Exec("INSERT INTO messages (id, thread_id, role, content, model, parent_id, sibling_group, sibling_index, feedback, reasoning) VALUES('" newId "', '" newThreadId "', '" msg.role "', '" safeContent "', '" safeModel "', " safeParent ", " safeSiblingGroup ", " siblingIdx ", " safeFeedback ", '" safeReasoning "');")
        }

        ; 5. Set active leaf
        newLeafId := idMap[path[cutoff].id]
        ChatDB.db.Exec("UPDATE chat_threads SET active_leaf_id='" newLeafId "', updated_at=datetime('now') WHERE id='" newThreadId "';")

        return newThreadId
    }

    ; ----------------------------------------------------
    ; Branch navigation
    ; ----------------------------------------------------

    ; Set the active leaf to a specific message (branch switch)
    static Msg_SetActiveLeaf(threadId, msgId) {
        ; Validate that msgId belongs to this thread
        check := ChatDB.db.Exec("SELECT id FROM messages WHERE id='" msgId "' AND thread_id='" threadId "' AND is_deleted=0;")
        if !check.count
            return
        ChatDB.db.Exec("UPDATE chat_threads SET active_leaf_id='" msgId "', updated_at=datetime('now') WHERE id='" threadId "';")
    }

    ; Switch to a sibling branch (D3). direction: -1 (prev), +1 (next).
    ; Returns { path: [...], siblingInfo: { index, total } }
    static Msg_SwitchBranch(threadId, msgId, direction := 1) {
        siblings := ChatDB.Msg_GetSiblings(msgId)
        if siblings.Length < 2
            return { path: ChatDB.Msg_GetActivePath(threadId), siblingInfo: { index: 1, total: 1 } }

        ; Find current position in the siblings array (0-based)
        currentPos := 0
        for sib in siblings {
            if sib.id = msgId {
                currentPos := A_Index - 1
                break
            }
        }

        ; Calculate next position (wrapping) — Mod(x+N, N) returns 0..N-1
        newPos := Mod(currentPos + direction + siblings.Length, siblings.Length)

        ; Get the sibling at newPos
        newMsgId := siblings[newPos + 1].id

        if newMsgId = msgId
            return { path: ChatDB.Msg_GetActivePath(threadId), siblingInfo: { index: currentPos + 1, total: siblings.Length } }

        ; Find the leaf downstream of the new sibling
        newLeafId := ChatDB._WalkToLeaf(newMsgId)

        ; Set as active leaf
        ChatDB.db.Exec("UPDATE chat_threads SET active_leaf_id='" newLeafId "', updated_at=datetime('now') WHERE id='" threadId "';")

        path := ChatDB.Msg_GetActivePath(threadId)
        return { path: path, siblingInfo: { index: newPos + 1, total: siblings.Length } }
    }

    ; ----------------------------------------------------
    ; Token estimates and cumulative cost for a thread
    ; Uses ~4 chars ≈ 1 token for estimation.
    ; Returns { activePathTokens, contextWindow,
    ;           cumulativePromptTokens, cumulativeCompletionTokens,
    ;           cumulativeTotalTokens, cumulativeCost }
    ; ----------------------------------------------------

    static Msg_GetThreadStats(threadId) {
        ; 1. Active path — for context usage display (use stored tokens, fallback to estimation)
        path := ChatDB.Msg_GetActivePath(threadId)
        ; Use the LAST assistant's total_tokens (API reports cumulative for entire request)
        activePathTokens := 0
        i := path.Length
        while i >= 1 {
            if path[i].total_tokens && path[i].total_tokens > 0 {
                activePathTokens := path[i].total_tokens
                break
            }
            i--
        }
        ; Fallback: estimate from content if no stored tokens (old messages)
        if !activePathTokens {
            for msg in path
                activePathTokens += StrLen(msg.content) > 3 ? Round(StrLen(msg.content) / 4) : 1
        }

        ; 2. ALL non-deleted messages — for cumulative cost (use stored tokens)
        result := {
            activePathTokens: activePathTokens,
            contextWindow: 1048576,
            cumulativePromptTokens: 0,
            cumulativeCompletionTokens: 0,
            cumulativeTotalTokens: 0,
            cumulativeCachedTokens: 0,
            cumulativeCost: 0,
            cumulativeInputCost: 0,
            cumulativeCachedInputCost: 0,
            cumulativeOutputCost: 0,
            pricingUnit: { input: 0, cachedInput: 0, output: 0 }
        }

        ; Track which pricing model was last used for the tooltip
        allTable := ChatDB.db.Exec("SELECT role, prompt_tokens, completion_tokens, total_tokens, cached_tokens, model FROM messages WHERE thread_id='" threadId "' AND is_deleted=0;")
        for row in allTable.rows {
            pt := Integer(row.prompt_tokens ? row.prompt_tokens : 0)
            ct := Integer(row.completion_tokens ? row.completion_tokens : 0)
            tt := Integer(row.total_tokens ? row.total_tokens : 0)
            ckt := Integer(row.cached_tokens ? row.cached_tokens : 0)
            if tt = 0 {
                ; Estimate fallback for messages before token tracking
                tt := pt + ct
            }
            result.cumulativePromptTokens += pt
            result.cumulativeCompletionTokens += ct
            result.cumulativeTotalTokens += tt
            result.cumulativeCachedTokens += ckt

            ; Calculate cost using stored tokens if model is known
            if row.model {
                modelShort := row.model
                slashPos := InStr(modelShort, "/")
                if slashPos > 0
                    modelShort := SubStr(modelShort, slashPos + 1)
                if modelPricing.Has(modelShort) {
                    pricing := modelPricing[modelShort]
                    inputPrice       := pricing.HasOwnProp("input")       ? pricing.input       : 0
                    cachedInputPrice := pricing.HasOwnProp("cachedInput") ? pricing.cachedInput : (inputPrice * 0.1)
                    outputPrice      := pricing.HasOwnProp("output")      ? pricing.output      : 0
                    nonCachedTokens := pt - ckt
                    nonCachedCost := nonCachedTokens * inputPrice / 1000000
                    cachedCost := ckt * cachedInputPrice / 1000000
                    outputCost := ct * outputPrice / 1000000
                    result.cumulativeInputCost += Round(nonCachedCost + cachedCost, 6)
                    result.cumulativeCachedInputCost += Round(cachedCost, 6)
                    result.cumulativeOutputCost += Round(outputCost, 6)
                    result.cumulativeCost += Round(nonCachedCost + cachedCost + outputCost, 6)
                    ; Store pricing for tooltip (use last seen model's pricing)
                    result.pricingUnit := { input: inputPrice, cachedInput: cachedInputPrice, output: outputPrice }
                }
            }
        }
        result.cumulativeCost := Round(result.cumulativeCost, 6)
        result.cumulativeInputCost := Round(result.cumulativeInputCost, 6)
        result.cumulativeCachedInputCost := Round(result.cumulativeCachedInputCost, 6)
        result.cumulativeOutputCost := Round(result.cumulativeOutputCost, 6)

        ; 3. Context window from model pricing (use last assistant's model)
        i := path.Length
        while i >= 1 {
            if path[i].role = "assistant" && path[i].model {
                modelShort := path[i].model
                slashPos := InStr(modelShort, "/")
                if slashPos > 0
                    modelShort := SubStr(modelShort, slashPos + 1)
                if modelPricing.Has(modelShort) && modelPricing[modelShort].HasOwnProp("context") {
                    result.contextWindow := modelPricing[modelShort].context
                    break
                }
            }
            i--
        }
        return result
    }

    ; Walk forward from a message to the leaf following the first child at each step
    static _WalkToLeaf(msgId) {
        currentId := msgId
        loop {
            ; Find child (deterministic: earliest created first)
            childTable := ChatDB.db.Exec("SELECT id FROM messages WHERE parent_id='" currentId "' AND is_deleted=0 ORDER BY created_at LIMIT 1;")
            if !childTable.count
                break
            currentId := childTable[1, "id"]
        }
        return currentId
    }

    ; ----------------------------------------------------
    ; Internal helpers
    ; ----------------------------------------------------

    ; Diagnostic log helper for ChatDB (writes to same file as debugLog in ChatUtils)
    static _DBLog(message) {
        timestamp := FormatTime(, "HH:mm:ss")
        logLine := timestamp " [ChatDB] " message "`n"
        FileAppend(logLine, A_Temp "\LLM_Debug_Log.txt")
    }

    static _TouchThreadByMsg(msgId) {
        table := ChatDB.db.Exec("SELECT thread_id FROM messages WHERE id='" msgId "';")
        if table.count
            ChatDB.db.Exec("UPDATE chat_threads SET updated_at=datetime('now') WHERE id='" table[1, "thread_id"] "';")
    }
}