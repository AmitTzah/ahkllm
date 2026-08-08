; ======================================================
; MessageRepo.ahk — Message CRUD operations
; ======================================================

class MessageRepo {

    static Insert(msgObj) {
        id := ChatDB._UUID()
        safeContent := SQLite.Escape(msgObj.content)
        safeModel := msgObj.HasProp("model") && msgObj.model ? SQLite.Escape(msgObj.model) : ""
        safeParent := msgObj.HasProp("parent_id") && msgObj.parent_id ? "'" SQLite.Escape(msgObj.parent_id) "'" : "NULL"
        safeSiblingGroup := msgObj.HasProp("sibling_group") && msgObj.sibling_group ? "'" SQLite.Escape(msgObj.sibling_group) "'" : "NULL"
        siblingIdx := msgObj.HasProp("sibling_index") ? msgObj.sibling_index : 0
        safeReasoning := msgObj.HasProp("reasoning") && msgObj.reasoning ? SQLite.Escape(msgObj.reasoning) : ""

        tc := msgObj.HasProp("token_count") ? msgObj.token_count : 0
        tht := msgObj.HasProp("thinking_tokens") ? msgObj.thinking_tokens : 0
        ckt := msgObj.HasProp("cached_tokens") ? msgObj.cached_tokens : 0
        lat := msgObj.HasProp("response_time_ms") ? msgObj.response_time_ms : 0
        ttft := msgObj.HasProp("ttft_ms") ? msgObj.ttft_ms : 0

        ; Per-message attribution: if this is an assistant with API data,
        ; backfill the user message's token_count via subtraction.
        new_input := 0
        existing_sum := 0
        if msgObj.role = "assistant" && msgObj.HasProp("prompt_tokens") && msgObj.prompt_tokens > 0 {
            new_input := MessageRepo._BackfillUserTokens(msgObj.thread_id, msgObj.prompt_tokens, &existing_sum)
        }

        ; active_path_tokens: total context tokens from root to this message.
        ; Assistants store API prompt_tokens + token_count (ground truth).
        ; User/system messages store parent.active_path_tokens + token_count (prefix sum).
        ; This column is read by GetThreadStats() for the UI token bar ("Context Used").
        activePathTokens := tc
        if msgObj.role = "assistant" && msgObj.HasProp("prompt_tokens") {
            ; Bug #64: thinking tokens occupy the context window too - the
            ; header "Context Used" must be prompt + visible output + thinking.
            activePathTokens := msgObj.prompt_tokens + tc + tht
        } else if msgObj.HasProp("parent_id") && msgObj.parent_id {
            parentRow := ChatDB.db.Exec("SELECT active_path_tokens FROM messages WHERE id='" SQLite.Escape(msgObj.parent_id) "';")
            if parentRow.count
                activePathTokens := Integer(parentRow[1, "active_path_tokens"]) + tc
        }

        ; Bug #107: persist prompt_tokens (API ground truth for assistants) so
        ; _RecomputeActivePath can restore prompt+completion after structural
        ; changes instead of reducing to a visible-token prefix sum.
        promptTotal := msgObj.HasProp("prompt_tokens") ? msgObj.prompt_tokens : new_input
        ChatDB.db.Exec("INSERT INTO messages (id, thread_id, role, content, model, parent_id, sibling_group, sibling_index, reasoning, token_count, prompt_tokens, thinking_tokens, cached_tokens, response_time_ms, ttft_ms, active_path_tokens) VALUES('" id "', '" msgObj.thread_id "', '" msgObj.role "', '" safeContent "', '" safeModel "', " safeParent ", " safeSiblingGroup ", " siblingIdx ", '" safeReasoning "', " tc ", " promptTotal ", " tht ", " ckt ", " lat ", " ttft ", " activePathTokens ");")

        ; Sync FTS5 index
        ChatDB.FTS_Sync(id, msgObj.content)

        inputCost := 0, cachedInputCost := 0, outputCost := 0, totalCost := 0
        if msgObj.HasProp("model") && msgObj.model {
            usage := { promptTokens: promptTotal, completionTokens: tc + tht, totalTokens: promptTotal + tc + tht, cachedTokens: ckt }
            costs := CostCalculator.ComputeTokenCosts(msgObj.model, usage)
            if costs.inputCost != "" {
                inputCost := costs.inputCost
                cachedInputCost := costs.cachedInputCost != "" ? costs.cachedInputCost : 0
                outputCost := costs.outputCost != "" ? costs.outputCost : 0
                totalCost := costs.totalCost != "" ? costs.totalCost : 0
            }
        }

        ChatDB.db.Exec("UPDATE chat_threads SET active_leaf_id='" id "', updated_at=datetime('now'), cumulative_input_tokens=cumulative_input_tokens+" promptTotal ", cumulative_output_tokens=cumulative_output_tokens+" (tc + tht) ", cumulative_cached_tokens=cumulative_cached_tokens+" ckt ", cumulative_cost=cumulative_cost+" totalCost ", cumulative_input_cost=cumulative_input_cost+" inputCost ", cumulative_cached_input_cost=cumulative_cached_input_cost+" cachedInputCost ", cumulative_output_cost=cumulative_output_cost+" outputCost " WHERE id='" msgObj.thread_id "';")

        ; Note: _RecomputeActivePath is NOT called here because Insert already sets
        ; active_path_tokens correctly (API ground truth for assistants, prefix sum for others).
        ; Backfill already updates the user's active_path_tokens directly.
        ; _RecomputeActivePath is only needed after structural changes (delete, edit).

        ; Track chat usage for dashboard (daily aggregation)
        if msgObj.role = "assistant" && msgObj.HasProp("model") && msgObj.model {
            provider := ModelParser.Split(msgObj.model).provider
            if provider = "" {
                ; Fallback: look up provider from UserConfig models map
                for fullKey, m in models {
                    shortKey := ModelParser.StripProvider(fullKey)
                    if shortKey = msgObj.model || ModelParser.StripVersion(shortKey) = ModelParser.StripVersion(msgObj.model) {
                        provider := ModelParser.Split(fullKey).provider
                        break
                    }
                }
            }
            ChatDB.ChatUsage_Upsert({
                date: FormatTime(, "yyyy-MM-dd"),
                model: msgObj.model,
                provider: provider,
                prompt_tokens: promptTotal,
                completion_tokens: tc + tht,
                thinking_tokens: tht,
                cached_tokens: ckt,
                input_cost: inputCost,
                cached_input_cost: cachedInputCost,
                output_cost: outputCost,
                total_cost: totalCost,
                response_time_ms: lat,
                ttft_ms: ttft
            })
        }

        return id
    }

    ; Backfill the user message's token_count based on API prompt_tokens.
    ; Returns new_input (tokens the user message contributed).
    ; @param existing_sum — output: sum of existing token_count values in path before backfill
    static _BackfillUserTokens(threadId, promptTokens, &existing_sum := 0) {
        path := TreeRepo.GetActivePath(threadId)
        existing_sum := 0
        for msg in path {
            existing_sum += msg.HasProp("token_count") ? msg.token_count : 0
        }
        new_input := Max(0, promptTokens - existing_sum)

        ; Find the last user message in the path and backfill its token_count.
        ; Only backfill if still 0 — user messages are shared across branches,
        ; and retry/switch must not overwrite the original attribution.
        i := path.Length
        while i >= 1 {
            if path[i].role = "user" {
                currentTC := path[i].HasProp("token_count") ? path[i].token_count : 0
                if currentTC = 0 {
                    ChatDB.db.Exec("UPDATE messages SET token_count=" new_input " WHERE id='" path[i].id "';")
                }
                break
            }
            i--
        }

        return new_input
    }

    static HardDelete(msgId) {
        parentTable := ChatDB.db.Exec("SELECT parent_id, thread_id FROM messages WHERE id='" msgId "';")
        if !parentTable.count
            return
        parentId := parentTable[1, "parent_id"] ? parentTable[1, "parent_id"] : ""
        threadId := parentTable[1, "thread_id"]

        childrenTable := ChatDB.db.Exec("SELECT id FROM messages WHERE parent_id='" msgId "';")
        for row in childrenTable.rows {
            if parentId
                ChatDB.db.Exec("UPDATE messages SET parent_id='" parentId "' WHERE id='" row.id "';")
            else
                ChatDB.db.Exec("UPDATE messages SET parent_id=NULL WHERE id='" row.id "';")
        }

        leafTable := ChatDB.db.Exec("SELECT active_leaf_id FROM chat_threads WHERE id='" threadId "';")
        if leafTable.count && leafTable[1, "active_leaf_id"] = msgId {
            if parentId
                ChatDB.db.Exec("UPDATE chat_threads SET active_leaf_id='" parentId "' WHERE id='" threadId "';")
            else
                ChatDB.db.Exec("UPDATE chat_threads SET active_leaf_id=NULL WHERE id='" threadId "';")
        }

        ; Delete attachments BEFORE the raw DELETE — ON DELETE CASCADE would remove
        ; message_attachments rows before we can read file_path for disk cleanup.
        AttachmentRepo.DeleteByMessage(msgId)
        ChatDB.FTS_Remove(msgId)
        ChatDB.db.Exec("DELETE FROM messages WHERE id='" msgId "';")

        TreeRepo._RecomputeActivePath(threadId)
        ; Bug #65: the deleted message's tokens/cost must drop out of the
        ; header totals - recompute the cumulative counters from the remaining
        ; messages (they were previously left stale and forever inflated).
        MessageRepo._RecomputeCumulativeCounters(threadId)
    }

    ; Recompute a thread's cumulative counters from its remaining messages
    ; (bug #65), mirroring the per-insert accumulation in Insert(). An
    ; assistant's prompt contribution is reconstructed from the running sum of
    ; prior messages' token_count - the backfill invariant is prompt = existing
    ; sum + backfilled user input, and the backfilled input already sits in the
    ; parent user message's token_count.
    static _RecomputeCumulativeCounters(threadId) {
        table := ChatDB.db.Exec("SELECT role, model, token_count, thinking_tokens, cached_tokens FROM messages WHERE thread_id='" threadId "' ORDER BY rowid;")
        input := 0, output := 0, cached := 0, inputCost := 0, cachedInputCost := 0, outputCost := 0, totalCost := 0
        runningSum := 0
        for row in table.rows {
            tc := row.token_count ? row.token_count : 0
            tht := row.thinking_tokens ? row.thinking_tokens : 0
            ckt := row.cached_tokens ? row.cached_tokens : 0
            if row.role = "assistant" && row.model {
                promptTotal := runningSum
                usage := { promptTokens: promptTotal, completionTokens: tc + tht, totalTokens: promptTotal + tc + tht, cachedTokens: ckt }
                costs := CostCalculator.ComputeTokenCosts(row.model, usage)
                if costs.inputCost != "" {
                    inputCost += costs.inputCost
                    cachedInputCost += costs.cachedInputCost != "" ? costs.cachedInputCost : 0
                    outputCost += costs.outputCost != "" ? costs.outputCost : 0
                    totalCost += costs.totalCost != "" ? costs.totalCost : 0
                }
                input += promptTotal
            }
            output += tc + tht
            cached += ckt
            runningSum += tc
        }
        ChatDB.db.Exec("UPDATE chat_threads SET cumulative_input_tokens=" input ", cumulative_output_tokens=" output ", cumulative_cached_tokens=" cached ", cumulative_cost=" totalCost ", cumulative_input_cost=" inputCost ", cumulative_cached_input_cost=" cachedInputCost ", cumulative_output_cost=" outputCost " WHERE id='" threadId "';")
    }

    static Edit(msgId, newContent) {
        oldTable := ChatDB.db.Exec("SELECT thread_id FROM messages WHERE id='" msgId "';")
        threadId := oldTable.count ? oldTable[1, "thread_id"] : ""

        safeContent := SQLite.Escape(newContent)
        ChatDB.db.Exec("UPDATE messages SET content='" safeContent "' WHERE id='" msgId "';")
        ChatDB.FTS_Sync(msgId, newContent)
        MessageRepo._TouchThreadByMsg(msgId)

        if threadId
            TreeRepo._RecomputeActivePath(threadId)
    }

    static GetMaxSiblingIndex(siblingGroup) {
        table := ChatDB.db.Exec("SELECT MAX(sibling_index) as max_idx FROM messages WHERE sibling_group='" siblingGroup "';")
        return table.count ? Integer(table[1, "max_idx"]) : 0
    }

    static _TouchThreadByMsg(msgId) {
        table := ChatDB.db.Exec("SELECT thread_id FROM messages WHERE id='" msgId "';")
        if table.count
            ChatDB.db.Exec("UPDATE chat_threads SET updated_at=datetime('now') WHERE id='" table[1, "thread_id"] "';")
    }
}
