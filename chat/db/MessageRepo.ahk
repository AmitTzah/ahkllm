; ======================================================
; MessageRepo.ahk - Message CRUD operations
; ======================================================

class MessageRepo {

    static Insert(msgObj) {
        id := ChatDB._UUID()
        model := msgObj.HasProp("model") && msgObj.model ? msgObj.model : ""
        parentId := msgObj.HasProp("parent_id") && msgObj.parent_id ? msgObj.parent_id : ""
        siblingGroup := msgObj.HasProp("sibling_group") && msgObj.sibling_group ? msgObj.sibling_group : ""
        siblingIdx := msgObj.HasProp("sibling_index") ? msgObj.sibling_index : 0
        reasoning := msgObj.HasProp("reasoning") && msgObj.reasoning ? msgObj.reasoning : ""

        tc := msgObj.HasProp("token_count") ? msgObj.token_count : 0
        tht := msgObj.HasProp("thinking_tokens") ? msgObj.thinking_tokens : 0
        ckt := msgObj.HasProp("cached_tokens") ? msgObj.cached_tokens : 0
        lat := msgObj.HasProp("response_time_ms") ? msgObj.response_time_ms : 0
        ttft := msgObj.HasProp("ttft_ms") ? msgObj.ttft_ms : 0

        ; Bug #118/#123: branch-edit copies are LOCAL DB duplicates - no API
        ; call happens. They must not backfill user tokens, re-charge the
        ; cumulative counters/costs, or upsert chat_usage (which would show a
        ; fake API request in the dashboard).
        isLocalCopy := msgObj.HasProp("local_copy") && msgObj.local_copy
        apiOutputTokens := msgObj.HasProp("api_output_tokens") ? msgObj.api_output_tokens : (!isLocalCopy && msgObj.role = "assistant" ? tc : 0)

        ; Per-message attribution: if this is an assistant with API data,
        ; backfill the user message's token_count via subtraction.
        new_input := 0
        existing_sum := 0
        if !isLocalCopy && msgObj.role = "assistant" && msgObj.HasProp("prompt_tokens") && msgObj.prompt_tokens > 0 {
            attributionPath := msgObj.HasProp("token_attribution_path") ? msgObj.token_attribution_path : ""
            new_input := MessageRepo._BackfillUserTokens(msgObj.thread_id, msgObj.prompt_tokens, &existing_sum, attributionPath)
        }

        ; active_path_tokens: total context tokens from root to this message.
        ; Assistants store API prompt_tokens + token_count (ground truth).
        ; User/system messages store parent.active_path_tokens + token_count (prefix sum).
        ; This column is read by GetThreadStats() for the UI token bar ("Context Used").
        activePathTokens := tc
        if msgObj.HasProp("active_path_tokens") && msgObj.active_path_tokens != "" {
            ; Local copies carry the source message's context total verbatim.
            activePathTokens := Integer(msgObj.active_path_tokens)
        } else if msgObj.role = "assistant" && msgObj.HasProp("prompt_tokens") {
            ; Bug #64: thinking tokens occupy the context window too - the
            ; header "Context Used" must be prompt + visible output + thinking.
            activePathTokens := msgObj.prompt_tokens + tc + tht
        } else if msgObj.HasProp("parent_id") && msgObj.parent_id {
            parentRow := ChatDB.db.Query("SELECT active_path_tokens FROM messages WHERE id=?;", msgObj.parent_id)
            if parentRow.count
                activePathTokens := Integer(parentRow[1, "active_path_tokens"]) + tc
        }

        ; Persist prompt_tokens as historical API ground truth. It is not used
        ; to rebuild the current editable-path estimate after local changes.
        promptTotal := msgObj.HasProp("prompt_tokens") ? msgObj.prompt_tokens : new_input

        ; Bug #153: snapshot the COSTS at the prices in effect when this API
        ; call was made, so a later price change in Settings never re-prices
        ; historical calls in the thread's cumulative counters.
        inputCost := 0, cachedInputCost := 0, outputCost := 0, totalCost := 0
        if !isLocalCopy && msgObj.HasProp("model") && msgObj.model {
            usage := { promptTokens: promptTotal, completionTokens: tc + tht, totalTokens: promptTotal + tc + tht, cachedTokens: ckt }
            costs := CostCalculator.ComputeTokenCosts(msgObj.model, usage)
            if costs.inputCost != "" {
                inputCost := costs.inputCost
                cachedInputCost := costs.cachedInputCost != "" ? costs.cachedInputCost : 0
                outputCost := costs.outputCost != "" ? costs.outputCost : 0
                totalCost := costs.totalCost != "" ? costs.totalCost : 0
            }
        }
        ChatDB.db.Query("INSERT INTO messages (id, thread_id, role, content, model, parent_id, sibling_group, sibling_index, reasoning, token_count, prompt_tokens, thinking_tokens, cached_tokens, response_time_ms, ttft_ms, active_path_tokens, is_local_copy, api_output_tokens, input_cost, cached_input_cost, output_cost, total_cost) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);", id, msgObj.thread_id, msgObj.role, msgObj.content, model, parentId ? parentId : SQLite.Null, siblingGroup ? siblingGroup : SQLite.Null, siblingIdx, reasoning, tc, promptTotal, tht, ckt, lat, ttft, activePathTokens, isLocalCopy ? 1 : 0, apiOutputTokens, inputCost, cachedInputCost, outputCost, totalCost)

        ; Sync FTS5 index
        ChatDB.FTS_Sync(id, msgObj.content)

        if !msgObj.HasProp("update_active_leaf") || msgObj.update_active_leaf
            ChatDB.db.Query("UPDATE chat_threads SET active_leaf_id=?, updated_at=datetime('now') WHERE id=?;", id, msgObj.thread_id)

        ; Hardening item 3: the thread's cumulative counters are DERIVED from
        ; the messages in exactly one place (_RecomputeCumulativeCounters) -
        ; never accumulated incrementally here - so the thread ledger can never
        ; drift from the per-message token fields (ground truth). Local copies
        ; (no API call) leave the ledger untouched.
        if !isLocalCopy
            MessageRepo._RecomputeCumulativeCounters(msgObj.thread_id)

        ; Note: _RecomputeActivePath is NOT called here because Insert already sets
        ; active_path_tokens correctly (API ground truth for assistants, prefix sum for others).
        ; Backfill already updates the user's active_path_tokens directly.
        ; _RecomputeActivePath is only needed after structural changes (delete, edit).

        ; Track chat usage for dashboard (daily aggregation)
        if !isLocalCopy && msgObj.role = "assistant" && msgObj.HasProp("model") && msgObj.model {
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
                ttft_ms: ttft,
                ttft_measured: msgObj.HasProp("ttft_measured") ? msgObj.ttft_measured : (ttft > 0)
            })
        }

        ChatDB._MarkPersistentDataChanged()
        return id
    }

    ; Backfill the user message's token_count based on API prompt_tokens.
    ; Returns new_input (tokens the user message contributed).
    ; @param existing_sum - output: sum of existing token_count values in path before backfill
    ; @param attributionPath - explicit request-owned path; ordinary inserts
    ; fall back to the visible active path for compatibility.
    static _BackfillUserTokens(threadId, promptTokens, &existing_sum := 0, attributionPath := "") {
        path := IsObject(attributionPath) ? attributionPath : TreeRepo.GetActivePath(threadId)
        existing_sum := 0
        for msg in path {
            existing_sum += msg.HasProp("token_count") ? msg.token_count : 0
            ; Bug #145: assistant token_count holds only VISIBLE output
            ; (thinking is stored separately), so the prior assistant's thinking
            ; tokens must be subtracted too - otherwise they leak into the next
            ; user's backfilled "contribution" and its token popover over-counts.
            if msg.role = "assistant" && msg.HasProp("thinking_tokens")
                existing_sum += msg.thinking_tokens
        }
        new_input := Max(0, promptTokens - existing_sum)

        ; Find the last user message in the path and backfill its token_count.
        ; Only backfill if still 0 - user messages are shared across branches,
        ; and retry/switch must not overwrite the original attribution.
        i := path.Length
        while i >= 1 {
            if path[i].role = "user" {
                currentTC := path[i].HasProp("token_count") ? path[i].token_count : 0
                ; Bug #150: a local branch-edit copy carries the SOURCE
                ; message's backfilled token_count (bug #123 copies it) - when
                ; the branch's own real API response arrives, that stale
                ; attribution must be REPLACED with the branch's real
                ; contribution (otherwise the copy's token popover is wrong
                ; forever).
                isLocalCopy := false
                copyRow := ChatDB.db.Query("SELECT is_local_copy FROM messages WHERE id=?;", path[i].id)
                if copyRow.count && copyRow[1, "is_local_copy"]
                    isLocalCopy := true
                if currentTC = 0 || isLocalCopy {
                    ChatDB.db.Query("UPDATE messages SET token_count=? WHERE id=?;", new_input, path[i].id)
                    ; Bug #157: the backfill must ALSO update the user
                    ; message's active_path_tokens (parent context + own
                    ; contribution). Insert computed it with token_count still
                    ; 0, so forking AT this message under-reported the fork's
                    ; Context Used (the fork leaf carried the parent context
                    ; only) until a later structural recompute.
                    parentApt := i > 1 ? (path[i - 1].HasProp("active_path_tokens") ? path[i - 1].active_path_tokens : 0) : 0
                    ChatDB.db.Query("UPDATE messages SET active_path_tokens=? WHERE id=?;", parentApt + new_input, path[i].id)
                }
                break
            }
            i--
        }

        return new_input
    }

    static HardDelete(msgId, expectedThreadId := "") {
        if expectedThreadId
            parentTable := ChatDB.db.Query("SELECT parent_id, thread_id FROM messages WHERE id=? AND thread_id=?;", msgId, expectedThreadId)
        else
            parentTable := ChatDB.db.Query("SELECT parent_id, thread_id FROM messages WHERE id=?;", msgId)
        if !parentTable.count
            return
        parentId := parentTable[1, "parent_id"] ? parentTable[1, "parent_id"] : ""
        threadId := parentTable[1, "thread_id"]
        ChatDB.BeginTransaction()
        try {

        childrenTable := ChatDB.db.Query("SELECT id FROM messages WHERE parent_id=?;", msgId)
        for row in childrenTable.rows {
            if parentId
                ChatDB.db.Query("UPDATE messages SET parent_id=? WHERE id=?;", parentId, row.id)
            else
                ChatDB.db.Query("UPDATE messages SET parent_id=NULL WHERE id=?;", row.id)
        }
        ChatDB.MaybeFault("delete-after-reparent")

        leafTable := ChatDB.db.Query("SELECT active_leaf_id FROM chat_threads WHERE id=?;", threadId)
        if leafTable.count && leafTable[1, "active_leaf_id"] = msgId {
            if parentId
                ChatDB.db.Query("UPDATE chat_threads SET active_leaf_id=? WHERE id=?;", parentId, threadId)
            else
                ChatDB.db.Query("UPDATE chat_threads SET active_leaf_id=NULL WHERE id=?;", threadId)
        }

        ; Delete attachments BEFORE the raw DELETE - ON DELETE CASCADE would remove
        ; message_attachments rows before we can read file_path for disk cleanup.
        AttachmentRepo.DeleteByMessage(msgId, threadId)
        ChatDB.FTS_Remove(msgId)
        ChatDB.db.Query("DELETE FROM messages WHERE id=?;", msgId)

        TreeRepo._RecomputeActivePath(threadId)
        ; Bug #65: the deleted message's tokens/cost must drop out of the
        ; header totals - recompute the cumulative counters from the remaining
        ; messages (they were previously left stale and forever inflated).
        MessageRepo._RecomputeCumulativeCounters(threadId)
        ChatDB.RequestSpaceReclaim()
        ChatDB.CommitTransaction()
        ChatDB._MarkPersistentDataChanged()
        } catch Error as e {
            ChatDB.RollbackTransaction()
            throw e
        }
    }

    ; Recompute a thread's cumulative counters from its remaining messages
    ; (bug #65), mirroring the per-insert accumulation in Insert().
    ;
    ; Tree-accurate since bug #114: an assistant's prompt contribution is its
    ; stored API prompt_tokens (bug #107 ground truth) - the old code rebuilt a
    ; running sum in rowid (insertion) order, charging off-path branch messages
    ; with tokens from the other branch. When prompt_tokens is missing (legacy
    ; rows) the parent message's active_path_tokens is the context the API call
    ; actually saw. Output/cached only count assistant rows (bug #128) - user
    ; token_counts are backfilled INPUT contributions, never output.
    static _RecomputeCumulativeCounters(threadId) {
        table := ChatDB.db.Query("SELECT id, role, model, parent_id, token_count, prompt_tokens, thinking_tokens, cached_tokens, active_path_tokens, is_local_copy, api_output_tokens, input_cost, cached_input_cost, output_cost, total_cost FROM messages WHERE thread_id=?;", threadId)
        rowMap := Map()
        for row in table.rows {
            rowMap[row.id] := row
        }

        input := 0, output := 0, cached := 0, inputCost := 0, cachedInputCost := 0, outputCost := 0, totalCost := 0
        for row in table.rows {
            ; Only assistant rows represent an API call. User/system token_counts
            ; are backfilled input contributions (bug #128).
            ; Bug #144: local branch-edit copies carry COPIED token metadata
            ; from their source but are not API calls - they must not be
            ; charged to the thread's cumulative counters (which would make
            ; the header disagree with the dashboard).
            if row.role != "assistant" || !row.model || (row.Has("is_local_copy") && row.is_local_copy)
                continue
            tc := row.token_count ? row.token_count : 0
            tht := row.thinking_tokens ? row.thinking_tokens : 0
            ckt := row.cached_tokens ? row.cached_tokens : 0
            promptTotal := row.prompt_tokens ? Integer(row.prompt_tokens) : 0
            if !promptTotal && row.parent_id && rowMap.Has(row.parent_id)
                promptTotal := Integer(rowMap[row.parent_id]["active_path_tokens"])
            ; Bug #153: each assistant row carries the COST SNAPSHOT taken at
            ; insert time (the prices in effect when the API call was made), so
            ; a later price change in Settings never re-prices history. Legacy
            ; rows without a snapshot (all costs 0 but real tokens) fall back to
            ; the current model prices - best effort for pre-fix data.
            rowInputCost := row.Has("input_cost") ? Number(row.input_cost) : 0
            rowCachedInputCost := row.Has("cached_input_cost") ? Number(row.cached_input_cost) : 0
            rowOutputCost := row.Has("output_cost") ? Number(row.output_cost) : 0
            rowTotalCost := row.Has("total_cost") ? Number(row.total_cost) : 0
            if !rowInputCost && !rowCachedInputCost && !rowOutputCost && !rowTotalCost && (promptTotal > 0 || tc + tht > 0 || ckt > 0) {
                usage := { promptTokens: promptTotal, completionTokens: tc + tht, totalTokens: promptTotal + tc + tht, cachedTokens: ckt }
                costs := CostCalculator.ComputeTokenCosts(row.model, usage)
                if costs.totalCost != "" {
                    rowInputCost := costs.inputCost != "" ? costs.inputCost : 0
                    rowCachedInputCost := costs.cachedInputCost != "" ? costs.cachedInputCost : 0
                    rowOutputCost := costs.outputCost != "" ? costs.outputCost : 0
                    rowTotalCost := costs.totalCost
                }
            }
            inputCost += rowInputCost
            cachedInputCost += rowCachedInputCost
            outputCost += rowOutputCost
            totalCost += rowTotalCost
            input += promptTotal
            ; token_count is the current visible text estimate after a local
            ; edit; api_output_tokens remains the historical billed output.
            output += row.api_output_tokens + tht
            cached += ckt
        }
        ChatDB.db.Query("UPDATE chat_threads SET cumulative_input_tokens=?, cumulative_output_tokens=?, cumulative_cached_tokens=?, cumulative_cost=?, cumulative_input_cost=?, cumulative_cached_input_cost=?, cumulative_output_cost=? WHERE id=?;", input, output, cached, totalCost, inputCost, cachedInputCost, outputCost, threadId)
    }

    static Edit(msgId, newContent, expectedThreadId := "") {
        if expectedThreadId
            oldTable := ChatDB.db.Query("SELECT thread_id, role FROM messages WHERE id=? AND thread_id=?;", msgId, expectedThreadId)
        else
            oldTable := ChatDB.db.Query("SELECT thread_id, role FROM messages WHERE id=?;", msgId)
        if !oldTable.count
            return
        threadId := oldTable[1, "thread_id"]
        role := oldTable[1, "role"]

        ChatDB.db.Query("UPDATE messages SET content=? WHERE id=?;", newContent, msgId)
        ChatDB.FTS_Sync(msgId, newContent)
        ; Bug #156/#181: overwrite-editing a message keeps its OLD token_count
        ; in place, so the NEXT user message's backfill subtracts the stale
        ; value and its token popover over-counts. Re-estimate the edited
        ; message's contribution (~1 token per 3 characters - a documented
        ; heuristic; the next API prompt then accounts for it exactly) for
        ; USER messages (backfilled input attribution) and ASSISTANT messages
        ; (their token_count feeds _BackfillUserTokens' existing_sum as
        ; visible output).
        if role = "user" || role = "assistant" {
            estimatedTokens := Max(1, Ceil(StrLen(newContent) / 3))
            ChatDB.db.Query("UPDATE messages SET token_count=? WHERE id=?;", estimatedTokens, msgId)
        }
        MessageRepo._TouchThreadByMsg(msgId)

        if threadId
            TreeRepo._RecomputeActivePath(threadId)
        ; Bug #194: the edited message's token_count changed, so the thread's
        ; CUMULATIVE ledger must be derived again - otherwise the header
        ; keeps the pre-edit output total while the message popover shows the
        ; refreshed count (until the next API call forces a recompute).
        if threadId
            MessageRepo._RecomputeCumulativeCounters(threadId)
        ChatDB._MarkPersistentDataChanged()
    }

    static GetMaxSiblingIndex(siblingGroup) {
        table := ChatDB.db.Query("SELECT MAX(sibling_index) as max_idx FROM messages WHERE sibling_group=?;", siblingGroup)
        return table.count ? Integer(table[1, "max_idx"]) : 0
    }

    static _TouchThreadByMsg(msgId) {
        table := ChatDB.db.Query("SELECT thread_id FROM messages WHERE id=?;", msgId)
        if table.count
            ChatDB.db.Query("UPDATE chat_threads SET updated_at=datetime('now') WHERE id=?;", table[1, "thread_id"])
    }
}
