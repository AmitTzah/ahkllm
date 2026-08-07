; ======================================================
; TreeRepo.ahk — Message tree operations
;
; Branch navigation, tree visualization, fork, stats.
; Extracted from MessageRepo.ahk.
; ======================================================

#Include ..\..\shared\ModelResolver.ahk

class TreeRepo {

    static GetActivePath(threadId) {
        leafTable := ChatDB.db.Exec("SELECT active_leaf_id FROM chat_threads WHERE id='" threadId "';")
        if !leafTable.count
            return []
        leafId := leafTable[1, "active_leaf_id"]
        if !leafId
            return []

        allTable := ChatDB.db.Exec("SELECT id, thread_id, role, content, model, parent_id, sibling_group, sibling_index, reasoning, token_count, thinking_tokens, cached_tokens, response_time_ms, ttft_ms, active_path_tokens, created_at FROM messages WHERE thread_id='" threadId "';")

        msgMap := Map()
        for row in allTable.rows {
            msgMap[row.id] := {
                id: row.id, thread_id: row.thread_id, role: row.role,
                content: row.content, model: row.model ? row.model : "",
                parent_id: row.parent_id ? row.parent_id : "",
                sibling_group: row.sibling_group ? row.sibling_group : "",
                sibling_index: row.sibling_index,
                reasoning: row.Has("reasoning") && row["reasoning"] ? row["reasoning"] : "",
                token_count: row.Has("token_count") && row.token_count ? Integer(row.token_count) : 0,
                thinking_tokens: row.Has("thinking_tokens") && row.thinking_tokens ? Integer(row.thinking_tokens) : 0,
                cached_tokens: row.Has("cached_tokens") && row.cached_tokens ? Integer(row.cached_tokens) : 0,
                response_time_ms: row.Has("response_time_ms") && row.response_time_ms ? Integer(row.response_time_ms) : 0,
                ttft_ms: row.Has("ttft_ms") && row.ttft_ms ? Integer(row.ttft_ms) : 0,
                active_path_tokens: row.Has("active_path_tokens") && row["active_path_tokens"] ? Integer(row["active_path_tokens"]) : 0,
                created_at: row.created_at
            }
        }

        path := []
        currentId := leafId
        while currentId && msgMap.Has(currentId) {
            path.InsertAt(1, msgMap[currentId])
            currentId := msgMap[currentId].parent_id
        }

        return path
    }

    static GetSiblings(msgId) {
        table := ChatDB.db.Exec("SELECT sibling_group, thread_id FROM messages WHERE id='" msgId "';")
        if !table.count
            return []
        sg := table[1, "sibling_group"]
        if !sg
            return []
        tid := table[1, "thread_id"]

        table2 := ChatDB.db.Exec("SELECT id, role, content, model, sibling_index FROM messages WHERE sibling_group='" sg "' AND thread_id='" tid "' ORDER BY sibling_index;")
        siblings := []
        for row in table2.rows {
            siblings.Push({
                id: row.id, role: row.role,
                content_preview: SubStr(row.content, 1, 80),
                model: row.model ? row.model : "",
                sibling_index: row.sibling_index
            })
        }
        return siblings
    }

    static GetTree(threadId) {
        allTable := ChatDB.db.Exec("SELECT * FROM messages WHERE thread_id='" threadId "';")
        nodeMap := Map(), childrenMap := Map()
        for row in allTable.rows {
            node := {
                id: row.id, role: row.role,
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

        for parentKey, childIds in childrenMap {
            if parentKey = "__root__"
                continue
            if nodeMap.Has(parentKey) {
                ; Sort by sibling_index descending: newest (2/2) on top
                sorted := TreeRepo._SortTreeChildren(childIds, nodeMap)
                for cid in sorted {
                    if nodeMap.Has(cid)
                        nodeMap[parentKey].children.Push(nodeMap[cid])
                }
            }
        }

        roots := []
        if childrenMap.Has("__root__") {
            sortedRoots := TreeRepo._SortTreeChildren(childrenMap["__root__"], nodeMap)
            for cid in sortedRoots {
                if nodeMap.Has(cid)
                    roots.Push(nodeMap[cid])
            }
        }
        return roots
    }

    ; Sort child IDs by sibling_index descending (newest first).
    ; Messages without sibling_group/sibling_index sort after those with.
    static _SortTreeChildren(childIds, nodeMap) {
        result := []
        for cid in childIds
            result.Push(cid)
        ; Bubble sort by sibling_index descending
        loop result.Length - 1 {
            for i, cid in result {
                if i >= result.Length
                    break
                current := nodeMap.Has(cid) ? nodeMap[cid].sibling_index : -1
                next := result.Has(i + 1) && nodeMap.Has(result[i + 1]) ? nodeMap[result[i + 1]].sibling_index : -1
                if current < next {
                    temp := result[i]
                    result[i] := result[i + 1]
                    result[i + 1] := temp
                }
            }
        }
        return result
    }

    static ForkThread(threadId, upToMsgId) {
        path := TreeRepo.GetActivePath(threadId)
        if !path.Length
            return ""

        cutoff := 0
        for i, msg in path {
            if msg.id = upToMsgId {
                cutoff := i
                break
            }
        }
        if !cutoff
            return ""

        newThreadId := TreeRepo._CreateForkThread(threadId)

        ; Copy thread-level settings from original to fork
        TreeRepo._CopyThreadSettings(threadId, newThreadId)

        idMap := Map()
        sgMap := Map()  ; old sibling_group → new sibling_group (fresh UUIDs per fork)

        ; First pass: copy active path messages up to cutoff
        for i, msg in path {
            if i > cutoff
                break
            newId := ChatDB._UUID()
            idMap[msg.id] := newId
            newParentId := msg.parent_id && idMap.Has(msg.parent_id) ? idMap[msg.parent_id] : ""
            safeSiblingGroup := TreeRepo._MapSiblingGroup(msg, &sgMap)
            TreeRepo._InsertForkMessage(newId, newThreadId, msg, newParentId, safeSiblingGroup)
            AttachmentRepo.CopyForMessage(msg.id, newId)
        }

        ; Second pass: copy any siblings NOT on the active path so branch nav works
        TreeRepo._CopyOffPathSiblings(threadId, newThreadId, &idMap, &sgMap)

        newLeafId := idMap[path[cutoff].id]
        ChatDB.db.Exec("UPDATE chat_threads SET active_leaf_id='" newLeafId "', updated_at=datetime('now') WHERE id='" newThreadId "';")

        ; Bug #48: carry the source thread's token/cost counters to the fork so
        ; the token bar does not reset to zero (the per-message
        ; active_path_tokens are copied by _InsertForkMessage).
        srcStats := ChatDB.db.Exec("SELECT cumulative_input_tokens, cumulative_output_tokens, cumulative_cached_tokens, cumulative_cost, cumulative_input_cost, cumulative_cached_input_cost, cumulative_output_cost FROM chat_threads WHERE id='" threadId "';")
        if srcStats.count {
            ChatDB.db.Exec("UPDATE chat_threads SET cumulative_input_tokens=" Integer(srcStats[1, "cumulative_input_tokens"]) ", cumulative_output_tokens=" Integer(srcStats[1, "cumulative_output_tokens"]) ", cumulative_cached_tokens=" Integer(srcStats[1, "cumulative_cached_tokens"]) ", cumulative_cost=" srcStats[1, "cumulative_cost"] ", cumulative_input_cost=" srcStats[1, "cumulative_input_cost"] ", cumulative_cached_input_cost=" srcStats[1, "cumulative_cached_input_cost"] ", cumulative_output_cost=" srcStats[1, "cumulative_output_cost"] " WHERE id='" newThreadId "';")
        }

        ; Bulk FTS sync for all copied messages in the forked thread
        ChatDB.db.Exec("INSERT INTO messages_fts(msg_id, content) SELECT id, content FROM messages WHERE thread_id='" newThreadId "';")

        return newThreadId
    }

    ; Create a new thread for the fork with "Copy - " prefix.
    static _CreateForkThread(originalThreadId) {
        oldTitle := "New Chat"
        titleRow := ChatDB.db.Exec("SELECT title FROM chat_threads WHERE id='" originalThreadId "';")
        if titleRow.count && titleRow[1, "title"]
            oldTitle := titleRow[1, "title"]
        return ThreadRepo.Create("Copy - " oldTitle)
    }

    ; Copy thread-level settings (model, system, reasoning, temperature, assistant) from original to fork.
    static _CopyThreadSettings(sourceThreadId, targetThreadId) {
        settings := ThreadRepo.GetSettings(sourceThreadId)
        if settings.modelOverride
            ChatDB.db.Exec("UPDATE chat_threads SET model_override='" SQLite.Escape(settings.modelOverride) "' WHERE id='" targetThreadId "';")
        if settings.systemOverride
            ChatDB.db.Exec("UPDATE chat_threads SET system_override='" SQLite.Escape(settings.systemOverride) "' WHERE id='" targetThreadId "';")
        if settings.reasoningOverride
            ChatDB.db.Exec("UPDATE chat_threads SET reasoning_override='" SQLite.Escape(settings.reasoningOverride) "' WHERE id='" targetThreadId "';")
        ; Bug #62: temperature 0 is a valid override - AHK treats the numeric
        ; 0 as falsy, so use an explicit empty check (same class as bug #35).
        if settings.temperatureOverride != ""
            ChatDB.db.Exec("UPDATE chat_threads SET temperature_override=" settings.temperatureOverride " WHERE id='" targetThreadId "';")
        if settings.assistantId
            ChatDB.db.Exec("UPDATE chat_threads SET assistant_id='" SQLite.Escape(settings.assistantId) "' WHERE id='" targetThreadId "';")
        ; Also copy per-thread font size and Advanced toggles (Code Execution / Web Search)
        try {
            srcRow := ChatDB.db.Exec("SELECT font_size, advanced_toggles, folder_id FROM chat_threads WHERE id='" SQLite.Escape(sourceThreadId) "';")
            if srcRow.count {
                if srcRow[1, "font_size"] != ""
                    ChatDB.db.Exec("UPDATE chat_threads SET font_size=" Integer(srcRow[1, "font_size"]) " WHERE id='" targetThreadId "';")
                if srcRow[1, "advanced_toggles"] != ""
                    ChatDB.db.Exec("UPDATE chat_threads SET advanced_toggles='" SQLite.Escape(srcRow[1, "advanced_toggles"]) "' WHERE id='" targetThreadId "';")
                ; Bug #58: the fork belongs in the source thread's folder.
                if srcRow[1, "folder_id"] != ""
                    ChatDB.db.Exec("UPDATE chat_threads SET folder_id='" SQLite.Escape(srcRow[1, "folder_id"]) "' WHERE id='" targetThreadId "';")
            }
        }
    }

    ; Map an old sibling_group to a fresh UUID, creating one if needed.
    ; Returns the SQL-safe sibling group string ("'uuid'" or "NULL").
    static _MapSiblingGroup(msg, &sgMap) {
        if msg.sibling_group {
            if !sgMap.Has(msg.sibling_group)
                sgMap[msg.sibling_group] := ChatDB._UUID()
            return "'" sgMap[msg.sibling_group] "'"
        }
        return "NULL"
    }

    ; Insert a single message row into the fork thread.
    static _InsertForkMessage(newId, threadId, msg, parentId, safeSiblingGroup) {
        safeContent := SQLite.Escape(msg.content)
        safeModel := msg.model ? SQLite.Escape(msg.model) : ""
        safeParent := parentId ? "'" parentId "'" : "NULL"
        siblingIdx := msg.sibling_index
        safeReasoning := msg.HasProp("reasoning") && msg.reasoning ? SQLite.Escape(msg.reasoning) : ""

        tc := msg.HasProp("token_count") ? msg.token_count : 0
        tht := msg.HasProp("thinking_tokens") ? msg.thinking_tokens : 0
        ckt := msg.HasProp("cached_tokens") ? msg.cached_tokens : 0
        lat := msg.HasProp("response_time_ms") ? msg.response_time_ms : 0
        ttft := msg.HasProp("ttft_ms") ? msg.ttft_ms : 0
        ; Bug #48: keep the per-message context-token prefix sum so the fork's
        ; token bar ("Context Used") matches the copied conversation.
        apt := msg.HasProp("active_path_tokens") && msg.active_path_tokens != "" ? Integer(msg.active_path_tokens) : 0

        ChatDB.db.Exec("INSERT INTO messages (id, thread_id, role, content, model, parent_id, sibling_group, sibling_index, reasoning, token_count, thinking_tokens, cached_tokens, response_time_ms, ttft_ms, active_path_tokens) VALUES('" newId "', '" threadId "', '" msg.role "', '" safeContent "', '" safeModel "', " safeParent ", " safeSiblingGroup ", " siblingIdx ", '" safeReasoning "', " tc ", " tht ", " ckt ", " lat ", " ttft ", " apt ");")
    }

    ; Copy sibling messages that are NOT on the active path (so branch navigation works in forks).
    static _CopyOffPathSiblings(threadId, newThreadId, &idMap, &sgMap) {
        for oldSg, newSg in sgMap {
            siblings := ChatDB.db.Exec("SELECT * FROM messages WHERE sibling_group='" oldSg "' AND thread_id='" threadId "' ORDER BY sibling_index;")
            for sibRow in siblings.rows {
                if idMap.Has(sibRow.id)
                    continue  ; already copied from active path
                ; Only copy if parent was also copied (within fork range)
                if sibRow.parent_id && !idMap.Has(sibRow.parent_id)
                    continue

                newSibId := ChatDB._UUID()
                idMap[sibRow.id] := newSibId
                mappedParent := sibRow.parent_id && idMap.Has(sibRow.parent_id) ? "'" idMap[sibRow.parent_id] "'" : "NULL"

                safeC := SQLite.Escape(sibRow.content)
                safeM := sibRow.model ? SQLite.Escape(sibRow.model) : ""
                safeR := sibRow.Has("reasoning") && sibRow.reasoning ? SQLite.Escape(sibRow.reasoning) : ""
                sTc := sibRow.token_count ? sibRow.token_count : 0
                sTht := sibRow.thinking_tokens ? sibRow.thinking_tokens : 0
                sCkt := sibRow.cached_tokens ? sibRow.cached_tokens : 0
                sLat := sibRow.response_time_ms ? sibRow.response_time_ms : 0
                sTtft := sibRow.ttft_ms ? sibRow.ttft_ms : 0
                sApt := sibRow.active_path_tokens ? Integer(sibRow.active_path_tokens) : 0

                ChatDB.db.Exec("INSERT INTO messages (id, thread_id, role, content, model, parent_id, sibling_group, sibling_index, reasoning, token_count, thinking_tokens, cached_tokens, response_time_ms, ttft_ms, active_path_tokens) VALUES('" newSibId "', '" newThreadId "', '" sibRow.role "', '" safeC "', '" safeM "', " mappedParent ", '" newSg "', " sibRow.sibling_index ", '" safeR "', " sTc ", " sTht ", " sCkt ", " sLat ", " sTtft ", " sApt ");")
                AttachmentRepo.CopyForMessage(sibRow.id, newSibId)
            }
        }
    }

    static SetActiveLeaf(threadId, msgId) {
        check := ChatDB.db.Exec("SELECT id FROM messages WHERE id='" msgId "' AND thread_id='" threadId "';")
        if !check.count
            return
        ChatDB.db.Exec("UPDATE chat_threads SET active_leaf_id='" msgId "', updated_at=datetime('now') WHERE id='" threadId "';")
        TreeRepo._RecomputeActivePath(threadId)
    }

    static SwitchBranch(threadId, msgId, direction := 1) {
        siblings := TreeRepo.GetSiblings(msgId)
        if siblings.Length < 2
            return { path: TreeRepo.GetActivePath(threadId), siblingInfo: { index: 1, total: 1 } }

        currentPos := 0
        for sib in siblings {
            if sib.id = msgId {
                currentPos := A_Index - 1
                break
            }
        }

        newPos := Mod(currentPos + direction + siblings.Length, siblings.Length)
        newMsgId := siblings[newPos + 1].id

        if newMsgId = msgId
            return { path: TreeRepo.GetActivePath(threadId), siblingInfo: { index: currentPos + 1, total: siblings.Length } }

        newLeafId := TreeRepo._WalkToLeaf(newMsgId)
        ChatDB.db.Exec("UPDATE chat_threads SET active_leaf_id='" newLeafId "', updated_at=datetime('now') WHERE id='" threadId "';")

        path := TreeRepo.GetActivePath(threadId)
        return { path: path, siblingInfo: { index: newPos + 1, total: siblings.Length } }
    }

    ; Returns token/cost stats for the token bar. activePathTokens is read from
    ; the leaf message's active_path_tokens column (O(1) primary key lookup).
    ; The column stores: prompt_tokens + token_count for assistants (API ground truth),
    ; parent + token_count for others (prefix sum). No more thread-level storage
    ; or path summation needed in the common case.
    static GetThreadStats(threadId) {
        ; Read active_path_tokens from the leaf message (O(1))
        threadRow := ChatDB.db.Exec("SELECT active_leaf_id FROM chat_threads WHERE id='" threadId "';")
        activePathTokens := 0
        if threadRow.count && threadRow[1, "active_leaf_id"] {
            leafRow := ChatDB.db.Exec("SELECT active_path_tokens FROM messages WHERE id='" threadRow[1, "active_leaf_id"] "';")
            if leafRow.count
                activePathTokens := Integer(leafRow[1, "active_path_tokens"])
        }

        threadTable := ChatDB.db.Exec("SELECT cumulative_input_tokens, cumulative_output_tokens, cumulative_cached_tokens, cumulative_cost, cumulative_input_cost, cumulative_cached_input_cost, cumulative_output_cost FROM chat_threads WHERE id='" threadId "';")
        ; Determine context window from current model
        contextWin := 1048576
        ; Priority 1: current request model (what user selected)
        if IsSet(requestParams) && requestParams.Has("singleAPIModelName") && requestParams["singleAPIModelName"] {
            pricing := TreeRepo._LookupPricing(requestParams["singleAPIModelName"])
            if pricing && pricing.HasOwnProp("context")
                contextWin := pricing.context
        }
        ; Priority 2: thread model override from DB
        if contextWin = 1048576 {
            threadRow := ChatDB.db.Exec("SELECT model_override FROM chat_threads WHERE id='" threadId "';")
            if threadRow.count && threadRow[1, "model_override"] {
                pricing := TreeRepo._LookupPricing(threadRow[1, "model_override"])
                if pricing && pricing.HasOwnProp("context")
                    contextWin := pricing.context
            }
        }
        ; Priority 3: last assistant message model
        if contextWin = 1048576 {
            path := TreeRepo.GetActivePath(threadId)
            i := path.Length
            while i >= 1 {
                if path[i].role = "assistant" && path[i].model {
                    pricing := TreeRepo._LookupPricing(path[i].model)
                    if pricing && pricing.HasOwnProp("context") {
                        contextWin := pricing.context
                        break
                    }
                }
                i--
            }
        }

        result := {
            activePathTokens: activePathTokens, contextWindow: contextWin,
            cumulativeInputTokens: threadTable.count ? Integer(threadTable[1, "cumulative_input_tokens"]) : 0,
            cumulativeOutputTokens: threadTable.count ? Integer(threadTable[1, "cumulative_output_tokens"]) : 0,
            cumulativeCachedTokens: threadTable.count ? Integer(threadTable[1, "cumulative_cached_tokens"]) : 0,
            cumulativeCost: threadTable.count ? Number(threadTable[1, "cumulative_cost"]) : 0,
            cumulativeInputCost: threadTable.count ? Number(threadTable[1, "cumulative_input_cost"]) : 0,
            cumulativeCachedInputCost: threadTable.count ? Number(threadTable[1, "cumulative_cached_input_cost"]) : 0,
            cumulativeOutputCost: threadTable.count ? Number(threadTable[1, "cumulative_output_cost"]) : 0,
            pricingUnit: { input: 0, cachedInput: 0, output: 0 }
        }

        allTable := ChatDB.db.Exec("SELECT model FROM messages WHERE thread_id='" threadId "' AND model IS NOT NULL AND model != '' LIMIT 1;")
        if allTable.count && allTable[1, "model"] {
            pricing := TreeRepo._LookupPricing(allTable[1, "model"])
            if pricing {
                result.pricingUnit := {
                    input: pricing.HasOwnProp("input") ? pricing.input : 0,
                    ; Bug #63: a stored "" means "not set" - fall back to 10% of
                    ; the input price (a present "" was previously taken as 0).
                    cachedInput: pricing.HasOwnProp("cachedInput") && pricing.cachedInput != "" ? pricing.cachedInput : (pricing.HasOwnProp("input") ? pricing.input * 0.1 : 0),
                    output: pricing.HasOwnProp("output") ? pricing.output : 0
                }
            }
        }

        return result
    }

    static _LookupPricing(modelName) {
        ; Single lookup accepting full or short model ids.
        return ModelResolver.Lookup(models, modelName)
    }

    static _WalkToLeaf(msgId) {
        currentId := msgId
        loop {
            ; Bug #55: pick the same child the tree modal's _findDefaultLeaf
            ; chooses - the LAST entry of the GetTree children array, which is
            ; the NEWEST continuation (min sibling_index, last-inserted among
            ; ties). ORDER BY created_at picked the OLDEST child instead, so
            ; branch-nav/search landed on a stale leaf while the tree modal
            ; showed the newest one.
            childTable := ChatDB.db.Exec("SELECT id FROM messages WHERE parent_id='" currentId "' ORDER BY sibling_index, rowid DESC LIMIT 1;")
            if !childTable.count
                break
            currentId := childTable[1, "id"]
        }
        return currentId
    }

    ; Walk the active path and recompute active_path_tokens as prefix sums
    ; (each msg = previous msg's total + this msg's token_count).
    ; Called after: insert with backfill, hard delete, edit.
    ; This overwrites any API ground truth on assistants with computed prefix
    ; sums — acceptable because the ground truth is stale after structural changes.
    ; The next API call restores ground truth via Insert().
    static _RecomputeActivePath(threadId) {
        path := TreeRepo.GetActivePath(threadId)
        prev := 0
        for msg in path {
            prev += msg.HasProp("token_count") ? msg.token_count : 0
            ChatDB.db.Exec("UPDATE messages SET active_path_tokens=" prev " WHERE id='" msg.id "';")
        }
    }
}
