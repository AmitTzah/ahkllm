; ======================================================
; SearchRepo.ahk — Message search operations
;
; FTS5 full-text search with LIKE fallback.
; Part of ChatDB split. All search logic extracted
; from ChatDB.ahk.
; ======================================================

class SearchRepo {

    ; Two-phase search: FTS5 (word-level, ranked) → LIKE (substring) → title search (global only)
    static Search(query, threadId := "") {
        safeQuery := SQLite.Escape(query)

        ; Phase 1: FTS5 MATCH (word-level, case-insensitive, ranked)
        results := SearchRepo._FTS5(query, threadId)
        if results.Length > 0
            debugLog("[SEARCH] FTS5 — query='" query "' hits=" results.Length)
        else {
            ; Phase 2: LIKE fallback (substring matches FTS5 misses)
            results := SearchRepo._Like(safeQuery, threadId)
            if results.Length > 0
                debugLog("[SEARCH] LIKE fallback — query='" query "' hits=" results.Length)
        }

        ; Title search: only for global (un-scoped) queries
        if !threadId {
            titleResults := SearchRepo._Titles(safeQuery)
            combined := []
            for tr in titleResults
                combined.Push(tr)
            for mr in results
                combined.Push(mr)
            if combined.Length > 20 {
                trimmed := []
                loop 20
                    trimmed.Push(combined[A_Index])
                combined := trimmed
            }
            results := combined
        }

        return results
    }

    ; FTS5 MATCH — word-level, case-insensitive, ranked, AND-joined words.
    ; Last word uses prefix matching (*) so partial typing finds results.
    ; "error hand" → MATCH 'error AND hand*' (matches "handle", "handling")
    static _FTS5(query, threadId := "") {
        words := StrSplit(query, " ")
        ftsExpr := ""
        wordCount := 0
        for w in words {
            trimmed := Trim(w)
            if StrLen(trimmed) = 0
                continue
            wordCount++
            if StrLen(ftsExpr) > 0
                ftsExpr .= " AND "
            ftsExpr .= trimmed
        }
        if !ftsExpr
            return []

        ; Append * to the last word for prefix matching
        ; unless the query already ends with * or the last word is quoted
        lastChar := SubStr(query, -1)
        if lastChar != "*" && lastChar != "'" {
            ; Find the last word and append *
            ftsExpr := RTrim(ftsExpr)
            ftsExpr .= "*"
        }

        ; Escape single quotes and wrap in SQL quotes for MATCH.
        ; SQLite.Escape doubles quotes but doesn't wrap — MATCH needs 'term'.
        safeFTS := StrReplace(ftsExpr, "'", "''")

        ; Two-step: query FTS for matching msg_ids, then messages by ID
        ftsSQL := "SELECT msg_id FROM messages_fts WHERE messages_fts MATCH '" safeFTS "';"
        ftsResults := ChatDB.db.Exec(ftsSQL)
        if ftsResults.count = 0
            return []

        msgIdList := ""
        for rowData in ftsResults.rows {
            if StrLen(msgIdList) > 0
                msgIdList .= ", "
            msgIdList .= "'" rowData.msg_id "'"
        }

        whereClause := "t.is_deleted=0 AND m.id IN (" msgIdList ")"
        if threadId
            whereClause .= " AND m.thread_id='" SQLite.Escape(threadId) "'"

        sql := "SELECT m.id AS messageId, m.thread_id AS threadId, m.role,"
             . " SUBSTR(m.content, 1, 100) AS contentPreview,"
             . " m.model, m.created_at AS createdAt,"
             . " t.title AS threadTitle"
             . " FROM messages m"
             . " JOIN chat_threads t ON m.thread_id = t.id"
             . " WHERE " whereClause
             . " ORDER BY m.created_at DESC"
             . " LIMIT 20"

        return SearchRepo._BuildResults(sql)
    }

    ; LIKE '%term%' substring — case-insensitive for ASCII (SQLite LIKE default)
    static _Like(safeQuery, threadId := "") {
        whereClause := "t.is_deleted=0 AND m.content LIKE '%' || '" safeQuery "' || '%' ESCAPE '\'"
        if threadId
            whereClause .= " AND m.thread_id='" SQLite.Escape(threadId) "'"

        sql := "SELECT m.id AS messageId, m.thread_id AS threadId, m.role,"
             . " SUBSTR(m.content, 1, 100) AS contentPreview,"
             . " m.model, m.created_at AS createdAt,"
             . " t.title AS threadTitle"
             . " FROM messages m"
             . " JOIN chat_threads t ON m.thread_id = t.id"
             . " WHERE " whereClause
             . " ORDER BY m.created_at DESC"
             . " LIMIT 20"

        return SearchRepo._BuildResults(sql)
    }

    ; Title search: find threads whose title matches (LIKE, case-insensitive)
    static _Titles(safeQuery) {
        sql := "SELECT NULL AS messageId, t.id AS threadId, 'system' AS role,"
             . " '' AS contentPreview, '' AS model, t.created_at AS createdAt,"
             . " t.title AS threadTitle"
             . " FROM chat_threads t"
             . " WHERE t.is_deleted=0"
             . " AND t.title LIKE '%' || '" safeQuery "' || '%' ESCAPE '\'"
             . " ORDER BY t.updated_at DESC"
             . " LIMIT 10"

        return SearchRepo._BuildResults(sql)
    }

    ; Convert SQL result rows to search result objects
    static _BuildResults(sql) {
        table := ChatDB.db.Exec(sql)
        results := []
        for row in table.rows {
            results.Push({
                threadId: row.threadId,
                threadTitle: row.threadTitle ? row.threadTitle : "New Chat",
                messageId: row.messageId ? row.messageId : "",
                contentPreview: row.contentPreview ? row.contentPreview : "",
                role: row.role ? row.role : "",
                model: row.model ? row.model : "",
                createdAt: row.createdAt ? row.createdAt : ""
            })
        }
        return results
    }
}
