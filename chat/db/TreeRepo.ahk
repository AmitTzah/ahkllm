; ======================================================
; TreeRepo.ahk — Message tree operations
;
; Branch navigation, tree visualization, fork, stats.
; Extracted from MessageRepo.ahk.
; ======================================================

class TreeRepo {

    static GetActivePath(threadId) {
        leafTable := ChatDB.db.Exec("SELECT active_leaf_id FROM chat_threads WHERE id='" threadId "';")
        if !leafTable.count
            return []
        leafId := leafTable[1, "active_leaf_id"]
        if !leafId
            return []

        allTable := ChatDB.db.Exec("SELECT * FROM messages WHERE thread_id='" threadId "';")

        msgMap := Map()
        for row in allTable.rows {
            msgMap[row.id] := {
                id: row.id, thread_id: row.thread_id, role: row.role,
                content: row.content, model: row.model ? row.model : "",
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
                for cid in childIds {
                    if nodeMap.Has(cid)
                        nodeMap[parentKey].children.Push(nodeMap[cid])
                }
            }
        }

        roots := []
        if childrenMap.Has("__root__") {
            for cid in childrenMap["__root__"] {
                if nodeMap.Has(cid)
                    roots.Push(nodeMap[cid])
            }
        }
        return roots
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

        ; Get original thread title for the fork name
        oldTitle := "New Chat"
        titleRow := ChatDB.db.Exec("SELECT title FROM chat_threads WHERE id='" threadId "';")
        if titleRow.count && titleRow[1, "title"]
            oldTitle := titleRow[1, "title"]

        newThreadId := ThreadRepo.Create("Copy - " oldTitle)

        ; Copy thread-level settings from original to fork
        settings := ThreadRepo.GetSettings(threadId)
        if settings.modelOverride
            ChatDB.db.Exec("UPDATE chat_threads SET model_override='" SQLite.Escape(settings.modelOverride) "' WHERE id='" newThreadId "';")
        if settings.systemOverride
            ChatDB.db.Exec("UPDATE chat_threads SET system_override='" SQLite.Escape(settings.systemOverride) "' WHERE id='" newThreadId "';")
        if settings.reasoningOverride
            ChatDB.db.Exec("UPDATE chat_threads SET reasoning_override='" SQLite.Escape(settings.reasoningOverride) "' WHERE id='" newThreadId "';")
        if settings.temperatureOverride
            ChatDB.db.Exec("UPDATE chat_threads SET temperature_override=" settings.temperatureOverride " WHERE id='" newThreadId "';")
        if settings.assistantId
            ChatDB.db.Exec("UPDATE chat_threads SET assistant_id='" SQLite.Escape(settings.assistantId) "' WHERE id='" newThreadId "';")

        idMap := Map()
        sgMap := Map()  ; old sibling_group → new sibling_group (fresh UUIDs per fork)

        for i, msg in path {
            if i > cutoff
                break

            newId := ChatDB._UUID()
            idMap[msg.id] := newId
            newParentId := msg.parent_id && idMap.Has(msg.parent_id) ? idMap[msg.parent_id] : ""

            safeContent := SQLite.Escape(msg.content)
            safeModel := msg.model ? SQLite.Escape(msg.model) : ""
            safeParent := newParentId ? "'" newParentId "'" : "NULL"
            ; Map old sibling_group to a fresh UUID so fork has independent sibling groups
            safeSiblingGroup := "NULL"
            siblingIdx := msg.sibling_index
            if msg.sibling_group {
                if !sgMap.Has(msg.sibling_group)
                    sgMap[msg.sibling_group] := ChatDB._UUID()
                safeSiblingGroup := "'" sgMap[msg.sibling_group] "'"
            }
            safeFeedback := msg.feedback ? msg.feedback : "NULL"
            safeReasoning := msg.HasProp("reasoning") && msg.reasoning ? SQLite.Escape(msg.reasoning) : ""

            pt := msg.HasProp("prompt_tokens") ? msg.prompt_tokens : 0
            ct := msg.HasProp("completion_tokens") ? msg.completion_tokens : 0
            tt := msg.HasProp("total_tokens") ? msg.total_tokens : 0
            ckt := msg.HasProp("cached_tokens") ? msg.cached_tokens : 0

            ChatDB.db.Exec("INSERT INTO messages (id, thread_id, role, content, model, parent_id, sibling_group, sibling_index, feedback, reasoning, prompt_tokens, completion_tokens, cached_tokens, total_tokens) VALUES('" newId "', '" newThreadId "', '" msg.role "', '" safeContent "', '" safeModel "', " safeParent ", " safeSiblingGroup ", " siblingIdx ", " safeFeedback ", '" safeReasoning "', " pt ", " ct ", " ckt ", " tt ");")
            ; Copy attachments from source message to forked message
            AttachmentRepo.CopyForMessage(msg.id, newId)
        }

        ; Second pass: copy any siblings NOT on the active path so branch nav works
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
                fb := sibRow.feedback ? sibRow.feedback : "NULL"
                sPt := sibRow.prompt_tokens ? sibRow.prompt_tokens : 0
                sCt := sibRow.completion_tokens ? sibRow.completion_tokens : 0
                sTt := sibRow.total_tokens ? sibRow.total_tokens : 0
                sCkt := sibRow.cached_tokens ? sibRow.cached_tokens : 0

                ChatDB.db.Exec("INSERT INTO messages (id, thread_id, role, content, model, parent_id, sibling_group, sibling_index, feedback, reasoning, prompt_tokens, completion_tokens, cached_tokens, total_tokens) VALUES('" newSibId "', '" newThreadId "', '" sibRow.role "', '" safeC "', '" safeM "', " mappedParent ", '" newSg "', " sibRow.sibling_index ", " fb ", '" safeR "', " sPt ", " sCt ", " sCkt ", " sTt ");")
                AttachmentRepo.CopyForMessage(sibRow.id, newSibId)
            }
        }

        newLeafId := idMap[path[cutoff].id]
        ChatDB.db.Exec("UPDATE chat_threads SET active_leaf_id='" newLeafId "', updated_at=datetime('now') WHERE id='" newThreadId "';")
        return newThreadId
    }

    static SetActiveLeaf(threadId, msgId) {
        check := ChatDB.db.Exec("SELECT id FROM messages WHERE id='" msgId "' AND thread_id='" threadId "';")
        if !check.count
            return
        ChatDB.db.Exec("UPDATE chat_threads SET active_leaf_id='" msgId "', updated_at=datetime('now') WHERE id='" threadId "';")
        TreeRepo._SyncActivePathTokens(threadId)
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
        TreeRepo._SyncActivePathTokens(threadId)

        path := TreeRepo.GetActivePath(threadId)
        return { path: path, siblingInfo: { index: newPos + 1, total: siblings.Length } }
    }

    static GetThreadStats(threadId) {
        threadRow := ChatDB.db.Exec("SELECT active_path_tokens FROM chat_threads WHERE id='" threadId "';")
        activePathTokens := threadRow.count ? Integer(threadRow[1, "active_path_tokens"]) : 0

        threadTable := ChatDB.db.Exec("SELECT cumulative_prompt_tokens, cumulative_completion_tokens, cumulative_total_tokens, cumulative_cached_tokens, cumulative_cost, cumulative_input_cost, cumulative_cached_input_cost, cumulative_output_cost FROM chat_threads WHERE id='" threadId "';")
        result := {
            activePathTokens: activePathTokens, contextWindow: 1048576,
            cumulativePromptTokens: threadTable.count ? Integer(threadTable[1, "cumulative_prompt_tokens"]) : 0,
            cumulativeCompletionTokens: threadTable.count ? Integer(threadTable[1, "cumulative_completion_tokens"]) : 0,
            cumulativeTotalTokens: threadTable.count ? Integer(threadTable[1, "cumulative_total_tokens"]) : 0,
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
                    cachedInput: pricing.HasOwnProp("cachedInput") ? pricing.cachedInput : (pricing.HasOwnProp("input") ? pricing.input * 0.1 : 0),
                    output: pricing.HasOwnProp("output") ? pricing.output : 0
                }
            }
        }

        path := TreeRepo.GetActivePath(threadId)
        i := path.Length
        while i >= 1 {
            if path[i].role = "assistant" && path[i].model {
                pricing := TreeRepo._LookupPricing(path[i].model)
                if pricing && pricing.HasOwnProp("context") {
                    result.contextWindow := pricing.context
                    break
                }
            }
            i--
        }
        return result
    }

    static _LookupPricing(modelName) {
        ; Try full "provider/model" key first
        if models.Has(modelName)
            return models[modelName]

        ; Fallback: strip provider prefix and search by short name
        modelShort := ModelParser.StripProvider(modelName)
        for fullKey, m in models {
            if ModelParser.StripProvider(fullKey) = modelShort
                return m
        }
        return ""
    }

    static _WalkToLeaf(msgId) {
        currentId := msgId
        loop {
            childTable := ChatDB.db.Exec("SELECT id FROM messages WHERE parent_id='" currentId "' ORDER BY created_at LIMIT 1;")
            if !childTable.count
                break
            currentId := childTable[1, "id"]
        }
        return currentId
    }

    static _SyncActivePathTokens(threadId) {
        path := TreeRepo.GetActivePath(threadId)
        totalEstimate := 0
        for msg in path {
            totalEstimate += TokenEstimation.Estimate(msg.content)
            if msg.HasProp("reasoning") && msg.reasoning
                totalEstimate += TokenEstimation.Estimate(msg.reasoning)
        }
        ChatDB.db.Exec("UPDATE chat_threads SET active_path_tokens=" totalEstimate " WHERE id='" threadId "';")
    }
}
