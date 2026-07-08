; ======================================================
; MessageRepo.ahk — Message CRUD operations
;
; Insert, delete, edit, feedback. Tree operations
; delegated to TreeRepo.ahk.
; ======================================================

class MessageRepo {

    static Insert(msgObj) {
        id := ChatDB._UUID()
        safeContent := SQLite.Escape(msgObj.content)
        safeModel := msgObj.HasProp("model") && msgObj.model ? SQLite.Escape(msgObj.model) : ""
        safeParent := msgObj.HasProp("parent_id") && msgObj.parent_id ? "'" msgObj.parent_id "'" : "NULL"
        safeSiblingGroup := msgObj.HasProp("sibling_group") && msgObj.sibling_group ? "'" msgObj.sibling_group "'" : "NULL"
        siblingIdx := msgObj.HasProp("sibling_index") ? msgObj.sibling_index : 0
        safeReasoning := msgObj.HasProp("reasoning") && msgObj.reasoning ? SQLite.Escape(msgObj.reasoning) : ""
        safeFeedback := msgObj.HasProp("feedback") && msgObj.feedback ? msgObj.feedback : "NULL"

        pt := msgObj.HasProp("prompt_tokens") ? msgObj.prompt_tokens : 0
        ct := msgObj.HasProp("completion_tokens") ? msgObj.completion_tokens : 0
        tt := msgObj.HasProp("total_tokens") ? msgObj.total_tokens : 0
        ckt := msgObj.HasProp("cached_tokens") ? msgObj.cached_tokens : 0

        ChatDB.db.Exec("INSERT INTO messages (id, thread_id, role, content, model, parent_id, sibling_group, sibling_index, reasoning, feedback, prompt_tokens, completion_tokens, cached_tokens, total_tokens) VALUES('" id "', '" msgObj.thread_id "', '" msgObj.role "', '" safeContent "', '" safeModel "', " safeParent ", " safeSiblingGroup ", " siblingIdx ", '" safeReasoning "', " safeFeedback ", " pt ", " ct ", " ckt ", " tt ");")

        inputCost := 0, cachedInputCost := 0, outputCost := 0, totalCost := 0
        if msgObj.HasProp("model") && msgObj.model {
            usage := { promptTokens: pt, completionTokens: ct, totalTokens: tt, cachedTokens: ckt }
            costs := CostCalculator.ComputeTokenCosts(msgObj.model, usage)
            if costs.inputCost != "" {
                inputCost := costs.inputCost
                outputCost := costs.outputCost != "" ? costs.outputCost : 0
                totalCost := costs.totalCost != "" ? costs.totalCost : 0
                if ckt > 0 && inputCost > 0
                    cachedInputCost := Round(ckt * inputCost / Max(1, pt) * 0.1, 6)
            }
        }

        activePathUpdate := msgObj.role = "assistant" && tt > 0 ? "active_path_tokens=" tt "," : ""
        ChatDB.db.Exec("UPDATE chat_threads SET " activePathUpdate "active_leaf_id='" id "', updated_at=datetime('now'), cumulative_prompt_tokens=cumulative_prompt_tokens+" pt ", cumulative_completion_tokens=cumulative_completion_tokens+" ct ", cumulative_cached_tokens=cumulative_cached_tokens+" ckt ", cumulative_total_tokens=cumulative_total_tokens+" tt ", cumulative_cost=cumulative_cost+" totalCost ", cumulative_input_cost=cumulative_input_cost+" inputCost ", cumulative_cached_input_cost=cumulative_cached_input_cost+" cachedInputCost ", cumulative_output_cost=cumulative_output_cost+" outputCost " WHERE id='" msgObj.thread_id "';")

        return id
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

        contentTable := ChatDB.db.Exec("SELECT content, reasoning FROM messages WHERE id='" msgId "';")
        ChatDB.db.Exec("DELETE FROM messages WHERE id='" msgId "';")

        if contentTable.count {
            deletedContent := contentTable[1, "content"]
            estimatedTokens := TokenEstimation.Estimate(deletedContent)
            if contentTable[1].Has("reasoning") && contentTable[1, "reasoning"]
                estimatedTokens += TokenEstimation.Estimate(contentTable[1, "reasoning"])
            ChatDB.db.Exec("UPDATE chat_threads SET active_path_tokens=MAX(0, active_path_tokens-" estimatedTokens "), updated_at=datetime('now') WHERE id='" threadId "';")
        }
    }

    static Edit(msgId, newContent) {
        oldTable := ChatDB.db.Exec("SELECT content, thread_id FROM messages WHERE id='" msgId "';")
        threadId := oldTable.count ? oldTable[1, "thread_id"] : ""
        oldEstimate := 0
        if oldTable.count
            oldEstimate := TokenEstimation.Estimate(oldTable[1, "content"])
        newEstimate := TokenEstimation.Estimate(newContent)
        tokenDelta := newEstimate - oldEstimate

        safeContent := SQLite.Escape(newContent)
        ChatDB.db.Exec("UPDATE messages SET content='" safeContent "' WHERE id='" msgId "';")
        MessageRepo._TouchThreadByMsg(msgId)

        if threadId && tokenDelta != 0 {
            if tokenDelta > 0
                ChatDB.db.Exec("UPDATE chat_threads SET active_path_tokens=active_path_tokens+" tokenDelta " WHERE id='" threadId "';")
            else
                ChatDB.db.Exec("UPDATE chat_threads SET active_path_tokens=MAX(0, active_path_tokens" tokenDelta ") WHERE id='" threadId "';")
        }
    }

    static SetFeedback(msgId, rating) {
        if rating = 0
            ChatDB.db.Exec("UPDATE messages SET feedback=NULL WHERE id='" msgId "';")
        else
            ChatDB.db.Exec("UPDATE messages SET feedback=" rating " WHERE id='" msgId "';")
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
