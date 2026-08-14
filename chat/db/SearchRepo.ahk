; ======================================================
; SearchRepo.ahk - Message search operations
;
; FTS5 full-text search with LIKE fallback.
; Part of ChatDB split. All search logic extracted
; from ChatDB.ahk.
; ======================================================

class SearchRepo {

    ; Two-phase search: FTS5 (word-level, ranked) -> LIKE (substring) -> title search (global only)
    static Search(query, threadId := "") {
        ; Phase 1: FTS5 MATCH (word-level, case-insensitive, ranked)
        results := SearchRepo._FTS5(query, threadId)
        if results.Length > 0
            debugLog("[SEARCH] FTS5 - query='" query "' hits=" results.Length)
        else {
            ; Phase 2: LIKE fallback (substring matches FTS5 misses)
            results := SearchRepo._Like(query, threadId)
            if results.Length > 0
                debugLog("[SEARCH] LIKE fallback - query='" query "' hits=" results.Length)
        }

        ; Title search: only for global (un-scoped) queries
        if !threadId {
            titleResults := SearchRepo._Titles(query)
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

    ; FTS5 MATCH - word-level, case-insensitive, ranked, AND-joined words.
    ; Last word uses prefix matching (*) so partial typing finds results.
    ; "error hand" -> MATCH 'error AND hand*' (matches "handle", "handling")
    static _FTS5(query, threadId := "") {
        words := StrSplit(query, " ")
        ftsExpr := ""
        firstWord := ""
        wordCount := 0
        for w in words {
            trimmed := Trim(w)
            if StrLen(trimmed) = 0
                continue
            wordCount++
            if !firstWord
                firstWord := trimmed
            if StrLen(ftsExpr) > 0
                ftsExpr .= " AND "
            ; Bug #70: FTS5 MATCH treats " + - : ( ) * etc. as operators, so
            ; quote each term to match it literally (a trailing * still does
            ; prefix matching on the quoted term).
            ftsExpr .= SearchRepo._FTS5QuoteTerm(trimmed)
        }
        if !ftsExpr
            return []

        ; Append * to the last word for prefix matching unless the query
        ; already ends with *. (Bug #161: the old guard ALSO skipped the * when
        ; the query ended in an apostrophe, assuming that meant "the last word
        ; is quoted" - but terms are ALWAYS double-quoted by _FTS5QuoteTerm, so
        ; "comp'" lost its prefix match and returned 0 while "comp" worked.)
        lastChar := SubStr(query, -1)
        if lastChar != "*" {
            ; Find the last word and append *
            ftsExpr := RTrim(ftsExpr)
            ftsExpr .= "*"
        }

        ; The FTS expression is BOUND as the MATCH value - SQL quotes cannot
        ; break out, only FTS5's own syntax needs the term quoting above.
        safeFTS := StrReplace(ftsExpr, "'", "''")

        ; Extract a snippet window around the first match (case-insensitive).
        ; FTS5 MATCH is case-insensitive, so use LOWER() for INSTR to match.
        ; Only add "..." prefix/suffix when content is actually truncated.
        ; Bug #183: the snippet is built from the FTS-INDEXED content
        ; (messages_fts.content = m.content + decoded attachment extracted_text,
        ; bug #165) instead of m.content alone, so a hit that exists only in an
        ; attachment previews the matched attachment text, not the message.
        firstWordLower := StrLower(firstWord)
        snippetExpr := "CASE WHEN INSTR(LOWER(fts.content), ?) > 0 THEN"
                     . " CASE WHEN INSTR(LOWER(fts.content), ?) > 31 THEN '...' ELSE '' END"
                     . " || SUBSTR(fts.content, MAX(1, INSTR(LOWER(fts.content), ?) - 30), 100)"
                     . " || CASE WHEN MAX(1, INSTR(LOWER(fts.content), ?) - 30) + 99 < LENGTH(fts.content) THEN '...' ELSE '' END"
                     . " ELSE SUBSTR(fts.content, 1, 100) END"

        sql := "SELECT m.id AS messageId, m.thread_id AS threadId, m.role,"
             . " " snippetExpr " AS contentPreview,"
             . " m.model, m.created_at AS createdAt,"
             . " t.title AS threadTitle"
             . " FROM messages m"
             . " JOIN chat_threads t ON m.thread_id = t.id"
             . " JOIN messages_fts fts ON fts.msg_id = m.id"
             . " WHERE t.is_deleted=0 AND t.is_locked=0 AND m.id IN (SELECT msg_id FROM messages_fts WHERE messages_fts MATCH ?)"
        params := [firstWordLower, firstWordLower, firstWordLower, firstWordLower, safeFTS]
        if threadId {
            sql .= " AND m.thread_id=?"
            params.Push(threadId)
        }
        sql .= " ORDER BY m.created_at DESC"
             . " LIMIT 20"

        return SearchRepo._BuildResults(sql, params*)
    }

    ; Bug #70: wrap an FTS5 term in double quotes (quoted strings match
    ; literally) and escape embedded quotes by doubling them.
    ; sql-lint: ok - the result is a MATCH expression VALUE (bound as a
    ; parameter), never interpolated into the SQL text itself.
    static _FTS5QuoteTerm(term) {
        term := StrReplace(term, '"', '""')
        return '"' term '"'
    }

    ; LIKE '%term%' substring - case-insensitive for ASCII (SQLite LIKE default)
    static _Like(query, threadId := "") {
        likeQuery := SearchRepo._EscapeLike(query)
        ; Extract a snippet window around the first match (case-insensitive).
        ; SQLite LIKE is case-insensitive for ASCII, so use LOWER() for INSTR.
        ; Only add "..." prefix/suffix when content is actually truncated.
        snippetExpr := "CASE WHEN INSTR(LOWER(m.content), LOWER(?)) > 0 THEN"
                     . " CASE WHEN INSTR(LOWER(m.content), LOWER(?)) > 31 THEN '...' ELSE '' END"
                     . " || SUBSTR(m.content, MAX(1, INSTR(LOWER(m.content), LOWER(?)) - 30), 100)"
                     . " || CASE WHEN MAX(1, INSTR(LOWER(m.content), LOWER(?)) - 30) + 99 < LENGTH(m.content) THEN '...' ELSE '' END"
                     . " ELSE SUBSTR(m.content, 1, 100) END"

        sql := "SELECT m.id AS messageId, m.thread_id AS threadId, m.role,"
             . " " snippetExpr " AS contentPreview,"
             . " m.model, m.created_at AS createdAt,"
             . " t.title AS threadTitle"
             . " FROM messages m"
             . " JOIN chat_threads t ON m.thread_id = t.id"
             . " WHERE t.is_deleted=0 AND t.is_locked=0 AND m.content LIKE '%' || ? || '%' ESCAPE '\'"
        params := [query, query, query, query, likeQuery]
        if threadId {
            sql .= " AND m.thread_id=?"
            params.Push(threadId)
        }
        sql .= " ORDER BY m.created_at DESC"
             . " LIMIT 20"

        return SearchRepo._BuildResults(sql, params*)
    }

    ; Title search: find threads whose title matches (LIKE, case-insensitive)
    static _Titles(query) {
        likeQuery := SearchRepo._EscapeLike(query)
        sql := "SELECT NULL AS messageId, t.id AS threadId, 'system' AS role,"
             . " '' AS contentPreview, '' AS model, t.created_at AS createdAt,"
             . " t.title AS threadTitle"
             . " FROM chat_threads t"
             . " WHERE t.is_deleted=0 AND t.is_locked=0"
             . " AND t.title LIKE '%' || ? || '%' ESCAPE '\'"
             . " ORDER BY t.updated_at DESC"
             . " LIMIT 10"

        return SearchRepo._BuildResults(sql, likeQuery)
    }

    ; Bug #69: escape SQL LIKE wildcards so user input is matched literally
    ; (the SQL uses ESCAPE '\', so escape \ first, then % and _).
    static _EscapeLike(value) {
        value := StrReplace(value, "\", "\\")
        value := StrReplace(value, "%", "\%")
        value := StrReplace(value, "_", "\_")
        return value
    }

    ; Convert SQL result rows to search result objects
    static _BuildResults(sql, params*) {
        table := ChatDB.db.Query(sql, params*)
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
