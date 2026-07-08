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
        ; Safety check: never open production DB in test mode
        if !dbPath || InStr(dbPath, "LLM-AutoHotkey-Assistant") {
            if IsSet(testMode) && testMode {
                FileAppend("[CRITICAL] ChatDB.Open() attempted production DB path in test mode! Path: '" dbPath "'`n", "*")
                ExitApp(99)
            }
        }
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
        ; Create tables (new databases get the latest schema)
        ChatDB.db.Exec("CREATE TABLE IF NOT EXISTS chat_threads (id TEXT PRIMARY KEY, title TEXT DEFAULT 'New Chat', is_deleted INTEGER DEFAULT 0, deleted_at TEXT, created_at TEXT DEFAULT (datetime('now')), updated_at TEXT DEFAULT (datetime('now')), active_leaf_id TEXT, active_path_tokens INTEGER DEFAULT 0, cumulative_prompt_tokens INTEGER DEFAULT 0, cumulative_completion_tokens INTEGER DEFAULT 0, cumulative_cached_tokens INTEGER DEFAULT 0, cumulative_total_tokens INTEGER DEFAULT 0, cumulative_cost REAL DEFAULT 0, cumulative_input_cost REAL DEFAULT 0, cumulative_cached_input_cost REAL DEFAULT 0, cumulative_output_cost REAL DEFAULT 0, assistant_id TEXT, model_override TEXT, system_override TEXT, reasoning_override TEXT, temperature_override REAL);")
        ChatDB.db.Exec("CREATE TABLE IF NOT EXISTS messages (id TEXT PRIMARY KEY, thread_id TEXT NOT NULL, role TEXT NOT NULL, content TEXT NOT NULL, model TEXT, parent_id TEXT, sibling_group TEXT, sibling_index INTEGER DEFAULT 0, feedback INTEGER, reasoning TEXT DEFAULT '', prompt_tokens INTEGER DEFAULT 0, completion_tokens INTEGER DEFAULT 0, cached_tokens INTEGER DEFAULT 0, total_tokens INTEGER DEFAULT 0, created_at TEXT DEFAULT (datetime('now')));")
        ChatDB.db.Exec("CREATE TABLE IF NOT EXISTS assistants (id TEXT PRIMARY KEY, name TEXT NOT NULL, base_model TEXT NOT NULL, system_prompt TEXT DEFAULT '', reasoning TEXT DEFAULT '', temperature REAL DEFAULT NULL, is_default INTEGER DEFAULT 0, created_at TEXT DEFAULT (datetime('now')));")

        ; Add new columns to existing databases (safe — ALTER TABLE ignores if column exists in SQLite)
        try ChatDB.db.Exec("ALTER TABLE chat_threads ADD COLUMN assistant_id TEXT;")
        try ChatDB.db.Exec("ALTER TABLE chat_threads ADD COLUMN model_override TEXT;")
        try ChatDB.db.Exec("ALTER TABLE chat_threads ADD COLUMN system_override TEXT;")
        try ChatDB.db.Exec("ALTER TABLE chat_threads ADD COLUMN reasoning_override TEXT;")
        try ChatDB.db.Exec("ALTER TABLE chat_threads ADD COLUMN temperature_override REAL;")

        ChatDB.db.Exec("CREATE INDEX IF NOT EXISTS idx_messages_thread ON messages(thread_id);")
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

    ; Save per-thread settings (model, assistant, system, reasoning, temperature).
    ; Pass only the fields that changed; NULL or empty = no override.
    static Thread_UpdateSettings(threadId, settings) {
        safeId := SQLite.Escape(threadId)
        parts := []
        if settings.HasOwnProp("assistantId")
            parts.Push("assistant_id = " (settings.assistantId ? "'" SQLite.Escape(settings.assistantId) "'" : "NULL"))
        if settings.HasOwnProp("modelOverride")
            parts.Push("model_override = " (settings.modelOverride ? "'" SQLite.Escape(settings.modelOverride) "'" : "NULL"))
        if settings.HasOwnProp("systemOverride")
            parts.Push("system_override = " (settings.systemOverride ? "'" SQLite.Escape(settings.systemOverride) "'" : "NULL"))
        if settings.HasOwnProp("reasoningOverride")
            parts.Push("reasoning_override = " (settings.reasoningOverride ? "'" SQLite.Escape(settings.reasoningOverride) "'" : "NULL"))
        if settings.HasOwnProp("temperatureOverride")
            parts.Push("temperature_override = " (settings.temperatureOverride != "" ? settings.temperatureOverride : "NULL"))
        if parts.Length {
            setClause := ""
            for i, p in parts
                setClause .= (i > 1 ? ", " : "") p
            ChatDB.db.Exec("UPDATE chat_threads SET " setClause " WHERE id='" safeId "';")
        }
    }

    ; Get per-thread settings. Returns object with current overrides.
    static Thread_GetSettings(threadId) {
        safeId := SQLite.Escape(threadId)
        table := ChatDB.db.Exec("SELECT assistant_id, model_override, system_override, reasoning_override, temperature_override FROM chat_threads WHERE id='" safeId "';")
        if table.count {
            row := table[1]
                return {
                    assistantId: row.assistant_id,
                    modelOverride: row.model_override,
                    systemOverride: row.system_override,
                    reasoningOverride: row.reasoning_override,
                    temperatureOverride: row.temperature_override
                }
        }
        return ""
    }

    ; Seed assistants from UserConfig on startup
    static Assistant_Seed() {
        ChatDB.db.Exec("DELETE FROM assistants;")
        for a in assistants {
            id := ChatDB._UUID()
            safeName := SQLite.Escape(a.name)
            safeModel := SQLite.Escape(a.baseModel)
            safePrompt := SQLite.Escape(a.systemPrompt)
            safeReasoning := SQLite.Escape(a.reasoning)
            temp := a.temperature = "" ? "NULL" : a.temperature
            isDef := a.isDefault ? 1 : 0
            ChatDB.db.Exec("INSERT INTO assistants (id, name, base_model, system_prompt, reasoning, temperature, is_default) VALUES('" id "', '" safeName "', '" safeModel "', '" safePrompt "', '" safeReasoning "', " temp ", " isDef ");")
        }
    }

    ; List all assistant profiles as AHK array of objects
    static Assistant_List() {
        table := ChatDB.db.Exec("SELECT id, name, base_model, system_prompt, reasoning, temperature, is_default FROM assistants ORDER BY is_default DESC, name ASC;")
        result := []
        for row in table.rows {
            result.Push({
                id: row.id,
                name: row.name,
                baseModel: row.base_model,
                systemPrompt: row.system_prompt,
                reasoning: row.reasoning,
                temperature: row.temperature,
                isDefault: row.is_default = 1
            })
        }
        return result
    }

    ; Get a single assistant by ID
    static Assistant_Get(assistantId) {
        safeId := SQLite.Escape(assistantId)
        table := ChatDB.db.Exec("SELECT id, name, base_model, system_prompt, reasoning, temperature, is_default FROM assistants WHERE id='" safeId "';")
        if table.count {
            row := table[1]
            return {
                id: row.id,
                name: row.name,
                baseModel: row.base_model,
                systemPrompt: row.system_prompt,
                reasoning: row.reasoning,
                temperature: row.temperature,
                isDefault: row.is_default = 1
            }
        }
        return ""
    }

    ; Get threads sorted by most recent first.
    ; showTrash: if true, returns ONLY trashed threads; otherwise returns active ones.
    static Thread_List(showTrash := false) {
        query := "SELECT id, title, created_at, updated_at FROM chat_threads WHERE is_deleted=" (showTrash ? 1 : 0)
        query .= " ORDER BY updated_at DESC"
        table := ChatDB.db.Exec(query)
        threads := []
        for row in table.rows {
            ; Find last assistant model for display icon
            model := ""
            modelTable := ChatDB.db.Exec("SELECT model FROM messages WHERE thread_id='" row.id "' AND role='assistant' AND model IS NOT NULL AND model != '' ORDER BY created_at DESC LIMIT 1;")
            if modelTable.count
                model := modelTable[1, "model"]
            threads.Push({
                id: row.id,
                title: row.title,
                created_at: row.created_at,
                updated_at: row.updated_at,
                model: model
            })
        }
        return threads
    }

    ; Trash a thread (soft-delete). Moves to trash with timestamp for auto-purge.
    static Thread_SoftDelete(threadId) {
        ChatDB.db.Exec("UPDATE chat_threads SET is_deleted=1, deleted_at=datetime('now'), updated_at=datetime('now') WHERE id='" threadId "';")
    }

    ; Restore a trashed thread back to active chats.
    static Thread_Restore(threadId) {
        ChatDB.db.Exec("UPDATE chat_threads SET is_deleted=0, deleted_at=NULL, updated_at=datetime('now') WHERE id='" threadId "';")
    }

    ; Permanently delete expired trashed threads and their messages.
    ; Uses trashRetentionDays from UserConfig. Set to 0 to disable auto-purge.
    static Thread_PurgeExpired() {
        if (IsSet(trashRetentionDays) && trashRetentionDays <= 0) || (!IsSet(trashRetentionDays))
            return  ; auto-purge disabled
        ChatDB.db.Exec("DELETE FROM messages WHERE thread_id IN (SELECT id FROM chat_threads WHERE is_deleted=1 AND deleted_at < datetime('now', '-" trashRetentionDays " days'));")
        ChatDB.db.Exec("DELETE FROM chat_threads WHERE is_deleted=1 AND deleted_at < datetime('now', '-" trashRetentionDays " days');")
    }

    ; Permanently delete a thread and all its messages (no recovery).
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

        ; Calculate cost for this message (using same formula as ComputeTokenCosts)
        inputCost := 0
        cachedInputCost := 0
        outputCost := 0
        totalCost := 0
        if msgObj.HasProp("model") && msgObj.model {
            ; Try dual lookup: new models map first, then fallback to modelPricing
            inputPrice := 0, cachedInputPrice := 0, outputPrice := 0
            fullModel := msgObj.model

            if IsSet(models) && models.Has(fullModel) {
                m := models[fullModel]
                inputPrice       := m.HasOwnProp("input")       ? m.input       : 0
                cachedInputPrice := m.HasOwnProp("cachedInput") ? m.cachedInput : (inputPrice * 0.1)
                outputPrice      := m.HasOwnProp("output")      ? m.output      : 0
            } else {
                modelShort := fullModel
                slashPos := InStr(modelShort, "/")
                if slashPos > 0
                    modelShort := SubStr(modelShort, slashPos + 1)
                if IsSet(modelPricing) && modelPricing.Has(modelShort) {
                    pricing := modelPricing[modelShort]
                    inputPrice       := pricing.HasOwnProp("input")       ? pricing.input       : 0
                    cachedInputPrice := pricing.HasOwnProp("cachedInput") ? pricing.cachedInput : (inputPrice * 0.1)
                    outputPrice      := pricing.HasOwnProp("output")      ? pricing.output      : 0
                }
            }

            if inputPrice > 0 || outputPrice > 0 {
                nonCachedTokens := pt - ckt
                nonCachedCost := nonCachedTokens * inputPrice / 1000000
                cachedCost := ckt * cachedInputPrice / 1000000
                outputCost := ct * outputPrice / 1000000
                inputCost := Round(nonCachedCost + cachedCost, 6)
                cachedInputCost := Round(cachedCost, 6)
                totalCost := Round(nonCachedCost + cachedCost + outputCost, 6)
            }
        }

        ; Update thread cumulative counters (these persist even if messages are deleted — tokens already paid for)
        ; For assistant messages, store API-reported total_tokens as the current context usage
        activePathUpdate := msgObj.role = "assistant" && tt > 0 ? "active_path_tokens=" tt "," : ""
        ChatDB.db.Exec("UPDATE chat_threads SET " activePathUpdate "active_leaf_id='" id "', updated_at=datetime('now'), cumulative_prompt_tokens=cumulative_prompt_tokens+" pt ", cumulative_completion_tokens=cumulative_completion_tokens+" ct ", cumulative_cached_tokens=cumulative_cached_tokens+" ckt ", cumulative_total_tokens=cumulative_total_tokens+" tt ", cumulative_cost=cumulative_cost+" totalCost ", cumulative_input_cost=cumulative_input_cost+" inputCost ", cumulative_cached_input_cost=cumulative_cached_input_cost+" cachedInputCost ", cumulative_output_cost=cumulative_output_cost+" outputCost " WHERE id='" msgObj.thread_id "';")

        return id
    }

    ; Hard-delete a message. Re-parents children to the deleted message's parent.
    ; Only moves active_leaf_id if the deleted message was the leaf itself.
    static Msg_HardDelete(msgId) {
        ; 1. Find the deleted message's parent and thread
        parentTable := ChatDB.db.Exec("SELECT parent_id, thread_id FROM messages WHERE id='" msgId "';")
        if !parentTable.count
            return
        parentId := parentTable[1, "parent_id"] ? parentTable[1, "parent_id"] : ""
        threadId := parentTable[1, "thread_id"]

        ; 2. Re-parent all direct children to the deleted message's parent
        childrenTable := ChatDB.db.Exec("SELECT id FROM messages WHERE parent_id='" msgId "';")
        for row in childrenTable.rows {
            if parentId
                ChatDB.db.Exec("UPDATE messages SET parent_id='" parentId "' WHERE id='" row.id "';")
            else
                ChatDB.db.Exec("UPDATE messages SET parent_id=NULL WHERE id='" row.id "';")
        }

        ; 3. If this message was the active leaf, move leaf to its parent
        leafTable := ChatDB.db.Exec("SELECT active_leaf_id FROM chat_threads WHERE id='" threadId "';")
        if leafTable.count && leafTable[1, "active_leaf_id"] = msgId {
            if parentId
                ChatDB.db.Exec("UPDATE chat_threads SET active_leaf_id='" parentId "' WHERE id='" threadId "';")
            else
                ChatDB.db.Exec("UPDATE chat_threads SET active_leaf_id=NULL WHERE id='" threadId "';")
        }

        ; 4. Delete the message — first capture content+reasoning for context adjustment
        contentTable := ChatDB.db.Exec("SELECT content, reasoning FROM messages WHERE id='" msgId "';")
        ChatDB.db.Exec("DELETE FROM messages WHERE id='" msgId "';")

        ; 5. Subtract estimated tokens of deleted message (content + reasoning) from active_path_tokens
        if contentTable.count {
            deletedContent := contentTable[1, "content"]
            estimatedTokens := StrLen(deletedContent) > 3 ? Round(StrLen(deletedContent) / 4) : 1
            ; Include reasoning/thinking blocks if present (they also consume context tokens)
            if contentTable[1].Has("reasoning") && contentTable[1, "reasoning"] {
                reasoningLen := StrLen(contentTable[1, "reasoning"])
                estimatedTokens += reasoningLen > 3 ? Round(reasoningLen / 4) : 1
            }
            ChatDB.db.Exec("UPDATE chat_threads SET active_path_tokens=MAX(0, active_path_tokens-" estimatedTokens "), updated_at=datetime('now') WHERE id='" threadId "';")
        }
    }

    ; Edit message content in-place (overwrite).
    ; Adjusts active_path_tokens for the content change (subtract old, add new).
    static Msg_Edit(msgId, newContent) {
        ; Capture old content before updating
        oldTable := ChatDB.db.Exec("SELECT content, thread_id FROM messages WHERE id='" msgId "';")
        threadId := oldTable.count ? oldTable[1, "thread_id"] : ""
        oldEstimate := 0
        if oldTable.count {
            oldLen := StrLen(oldTable[1, "content"])
            oldEstimate := oldLen > 3 ? Round(oldLen / 4) : 1
        }
        newEstimate := StrLen(newContent) > 3 ? Round(StrLen(newContent) / 4) : 1
        tokenDelta := newEstimate - oldEstimate

        safeContent := SQLite.Escape(newContent)
        ChatDB.db.Exec("UPDATE messages SET content='" safeContent "' WHERE id='" msgId "';")
        ChatDB._TouchThreadByMsg(msgId)

        ; Adjust active_path_tokens on the thread
        if threadId && tokenDelta != 0 {
            if tokenDelta > 0
                ChatDB.db.Exec("UPDATE chat_threads SET active_path_tokens=active_path_tokens+" tokenDelta " WHERE id='" threadId "';")
            else
                ChatDB.db.Exec("UPDATE chat_threads SET active_path_tokens=MAX(0, active_path_tokens" tokenDelta ") WHERE id='" threadId "';")
        }
    }

    ; Set feedback on a message (1 = thumbs up, -1 = thumbs down, 0 / NULL = clear)
    static Msg_SetFeedback(msgId, rating) {
        if rating = 0
            ChatDB.db.Exec("UPDATE messages SET feedback=NULL WHERE id='" msgId "';")
        else
            ChatDB.db.Exec("UPDATE messages SET feedback=" rating " WHERE id='" msgId "';")
    }

    ; Get all messages for a thread. Returns array ordered by the active path.
    static Msg_GetActivePath(threadId) {
        ; 1. Get the active leaf
        leafTable := ChatDB.db.Exec("SELECT active_leaf_id FROM chat_threads WHERE id='" threadId "';")
        if !leafTable.count
            return []
        leafId := leafTable[1, "active_leaf_id"]
        if !leafId
            return []

        ; 2. Load all messages for this thread (is_deleted column removed — all rows are visible)
        allTable := ChatDB.db.Exec("SELECT * FROM messages WHERE thread_id='" threadId "';")

        ; 3. Build lookup map (childrenMap is no longer needed — removed dead code)
        msgMap := Map()
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
                prompt_tokens: row.Has("prompt_tokens") && row.prompt_tokens ? Integer(row.prompt_tokens) : 0,
                completion_tokens: row.Has("completion_tokens") && row.completion_tokens ? Integer(row.completion_tokens) : 0,
                total_tokens: row.Has("total_tokens") && row.total_tokens ? Integer(row.total_tokens) : 0,
                cached_tokens: row.Has("cached_tokens") && row.cached_tokens ? Integer(row.cached_tokens) : 0
            }
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

        ; Get all siblings in this group (is_deleted column removed — all rows are visible)
        table2 := ChatDB.db.Exec("SELECT id, role, content, model, sibling_index FROM messages WHERE sibling_group='" sg "' ORDER BY sibling_index;")
        siblings := []
        for row in table2.rows {
            siblings.Push({
                id: row.id,
                role: row.role,
                content_preview: SubStr(row.content, 1, 80),
                model: row.model ? row.model : "",
                sibling_index: row.sibling_index
            })
        }
        return siblings
    }

    ; Get the full branch tree for visualization (D4).
    ; Returns a tree structure: [{ id, role, content_preview, children: [...] }]
    static Msg_GetTree(threadId) {
        allTable := ChatDB.db.Exec("SELECT * FROM messages WHERE thread_id='" threadId "';")

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

            ; Include token counts to preserve cost data in forked threads
            pt := msg.HasProp("prompt_tokens") ? msg.prompt_tokens : 0
            ct := msg.HasProp("completion_tokens") ? msg.completion_tokens : 0
            tt := msg.HasProp("total_tokens") ? msg.total_tokens : 0
            ckt := msg.HasProp("cached_tokens") ? msg.cached_tokens : 0

            ChatDB.db.Exec("INSERT INTO messages (id, thread_id, role, content, model, parent_id, sibling_group, sibling_index, feedback, reasoning, prompt_tokens, completion_tokens, cached_tokens, total_tokens) VALUES('" newId "', '" newThreadId "', '" msg.role "', '" safeContent "', '" safeModel "', " safeParent ", " safeSiblingGroup ", " siblingIdx ", " safeFeedback ", '" safeReasoning "', " pt ", " ct ", " ckt ", " tt ");")
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
        check := ChatDB.db.Exec("SELECT id FROM messages WHERE id='" msgId "' AND thread_id='" threadId "';")
        if !check.count
            return
        ChatDB.db.Exec("UPDATE chat_threads SET active_leaf_id='" msgId "', updated_at=datetime('now') WHERE id='" threadId "';")
        ; Recalculate active_path_tokens for the new active path
        ChatDB._SyncActivePathTokens(threadId)
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
        ; Recalculate active_path_tokens for the new branch
        ChatDB._SyncActivePathTokens(threadId)

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
        ; 1. Active path — context used by current conversation tree.
        ; Uses a running counter: accurate API total_tokens when assistant arrives,
        ; subtracts estimated tokens when messages are deleted.
        threadRow := ChatDB.db.Exec("SELECT active_path_tokens FROM chat_threads WHERE id='" threadId "';")
        activePathTokens := threadRow.count ? Integer(threadRow[1, "active_path_tokens"]) : 0

        ; 2. Read thread-level cumulative counters (persist across deletes — tokens already paid for)
        threadTable := ChatDB.db.Exec("SELECT cumulative_prompt_tokens, cumulative_completion_tokens, cumulative_total_tokens, cumulative_cached_tokens, cumulative_cost, cumulative_input_cost, cumulative_cached_input_cost, cumulative_output_cost FROM chat_threads WHERE id='" threadId "';")
        cumulativePt := threadTable.count ? Integer(threadTable[1, "cumulative_prompt_tokens"]) : 0
        cumulativeCt := threadTable.count ? Integer(threadTable[1, "cumulative_completion_tokens"]) : 0
        cumulativeTt := threadTable.count ? Integer(threadTable[1, "cumulative_total_tokens"]) : 0
        cumulativeCkt := threadTable.count ? Integer(threadTable[1, "cumulative_cached_tokens"]) : 0

        result := {
            activePathTokens: activePathTokens,
            contextWindow: 1048576,
            cumulativePromptTokens: cumulativePt,
            cumulativeCompletionTokens: cumulativeCt,
            cumulativeTotalTokens: cumulativeTt,
            cumulativeCachedTokens: cumulativeCkt,
            cumulativeCost: threadTable.count ? Number(threadTable[1, "cumulative_cost"]) : 0,
            cumulativeInputCost: threadTable.count ? Number(threadTable[1, "cumulative_input_cost"]) : 0,
            cumulativeCachedInputCost: threadTable.count ? Number(threadTable[1, "cumulative_cached_input_cost"]) : 0,
            cumulativeOutputCost: threadTable.count ? Number(threadTable[1, "cumulative_output_cost"]) : 0,
            pricingUnit: { input: 0, cachedInput: 0, output: 0 }
        }

        ; 3. Find pricing info for tooltip from existing messages
        allTable := ChatDB.db.Exec("SELECT model FROM messages WHERE thread_id='" threadId "' AND model IS NOT NULL AND model != '' LIMIT 1;")
        if allTable.count && allTable[1, "model"] {
            modelShort := allTable[1, "model"]
            slashPos := InStr(modelShort, "/")
            if slashPos > 0
                modelShort := SubStr(modelShort, slashPos + 1)
            if IsSet(modelPricing) && modelPricing.Has(modelShort) {
                pricing := modelPricing[modelShort]
                result.pricingUnit := {
                    input:       pricing.HasOwnProp("input")       ? pricing.input       : 0,
                    cachedInput: pricing.HasOwnProp("cachedInput") ? pricing.cachedInput : (pricing.HasOwnProp("input") ? pricing.input * 0.1 : 0),
                    output:      pricing.HasOwnProp("output")      ? pricing.output      : 0
                }
            }
        }
        ; 4. Context window from model pricing (use last assistant's model)
        path := ChatDB.Msg_GetActivePath(threadId)
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
            childTable := ChatDB.db.Exec("SELECT id FROM messages WHERE parent_id='" currentId "' ORDER BY created_at LIMIT 1;")
            if !childTable.count
                break
            currentId := childTable[1, "id"]
        }
        return currentId
    }

    ; Recalculate active_path_tokens by estimating tokens from all messages in the active path.
    ; Uses the same ~4 chars/1 token rule as Msg_Edit and Msg_HardDelete, ensuring consistency:
    ; delete subtracts estimated tokens → switch away and back → recalculate yields same estimate.
    ; Estimation is lower than API total_tokens (doesn't count system prompt), but the next
    ; assistant response resets active_path_tokens to the accurate API value.
    static _SyncActivePathTokens(threadId) {
        path := ChatDB.Msg_GetActivePath(threadId)
        totalEstimate := 0
        for msg in path {
            len := StrLen(msg.content)
            totalEstimate += len > 3 ? Round(len / 4) : 1
            if msg.HasProp("reasoning") && msg.reasoning {
                rLen := StrLen(msg.reasoning)
                totalEstimate += rLen > 3 ? Round(rLen / 4) : 1
            }
        }
        ChatDB.db.Exec("UPDATE chat_threads SET active_path_tokens=" totalEstimate " WHERE id='" threadId "';")
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