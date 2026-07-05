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
        ChatDB.db.Exec("CREATE TABLE IF NOT EXISTS messages (id TEXT PRIMARY KEY, thread_id TEXT NOT NULL, role TEXT NOT NULL, content TEXT NOT NULL, model TEXT, parent_id TEXT, sibling_group TEXT, sibling_index INTEGER DEFAULT 0, is_deleted INTEGER DEFAULT 0, feedback INTEGER, reasoning TEXT DEFAULT '', created_at TEXT DEFAULT (datetime('now')));")
        ; Ensure reasoning column exists (for DBs created before this column was added)
        colCheck := ChatDB.db.Exec("PRAGMA table_info(messages);")
        hasReasoningCol := false
        for row in colCheck.rows {
            if row.name = "reasoning" {
                hasReasoningCol := true
                break
            }
        }
        if !hasReasoningCol {
            ChatDB._DBLog("[DEBUG] _CreateSchema: adding missing reasoning column via ALTER TABLE")
            ChatDB.db.Exec("ALTER TABLE messages ADD COLUMN reasoning TEXT DEFAULT '';")
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

        ChatDB.db.Exec("INSERT INTO messages (id, thread_id, role, content, model, parent_id, sibling_group, sibling_index, reasoning, feedback) VALUES('" id "', '" msgObj.thread_id "', '" msgObj.role "', '" safeContent "', '" safeModel "', " safeParent ", " safeSiblingGroup ", " siblingIdx ", '" safeReasoning "', " safeFeedback ");")

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
                reasoning: row.Has("reasoning") && row["reasoning"] ? row["reasoning"] : ""
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