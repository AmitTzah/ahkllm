; ======================================================
; UsageRepo.ahk - Usage tracking operations
;
; Extracted from ChatDB.ahk. Handles daily usage
; aggregation (chat + command) and dashboard queries.
; ======================================================

class UsageRepo {

    ; Build WHERE clause for date-based time range filters. localToday is the
    ; LOCAL calendar date (usage rows are stored with local dates, and the
    ; dashboard's day chart plots a single local "today" label), so the "day"
    ; filter must use it instead of SQLite's UTC date('now', '-1 day') which
    ; otherwise local-day ranges can include the wrong UTC date.
    static _WhereDate(range, dateColumn := "date", localToday := "", monthCutoff := "", lastMonthStart := "", monthStart := "") {
        if range = "day" {
            if localToday
                return { sql: "WHERE " dateColumn " >= ?", params: [localToday] }
            return { sql: "WHERE " dateColumn " >= date('now')", params: [] }
        }
        ; Month ranges use local calendar dates because stored dates and chart labels are local.
        ; (rows are stored with local dates and the chart labels are local) -
        ; SQLite's date('now') is UTC and drifts by a day in non-UTC zones.
        if range = "month" {
            if monthCutoff
                return { sql: "WHERE " dateColumn " >= ?", params: [monthCutoff] }
            return { sql: "WHERE " dateColumn " >= date('now', '-30 days')", params: [] }
        }
        if range = "thisMonth" {
            if monthStart
                return { sql: "WHERE " dateColumn " >= ?", params: [monthStart] }
            return { sql: "WHERE " dateColumn " >= date('now', 'start of month')", params: [] }
        }
        if range = "lastMonth" {
            if lastMonthStart && monthStart
                return { sql: "WHERE " dateColumn " >= ? AND " dateColumn " < ?", params: [lastMonthStart, monthStart] }
            return { sql: "WHERE " dateColumn " >= date('now', 'start of month', '-1 month') AND " dateColumn " < date('now', 'start of month')", params: [] }
        }
        return { sql: "", params: [] }
    }

    ; Usage dashboard - query aggregated data
    static Query(filters) {
        result := { chat: [], commands: [], models: [], providers: [] }
        localToday := FormatTime(, "yyyy-MM-dd")
        monthStart := FormatTime(A_Now, "yyyy-MM") "-01"
        lastMonthStart := FormatTime(DateAdd(A_Now, -1, "Months"), "yyyy-MM") "-01"
        monthCutoff := FormatTime(DateAdd(A_Now, -29, "Days"), "yyyy-MM-dd")

        timeRange := filters.Has("timeRange") ? filters["timeRange"] : "all"
        modelFilter := filters.Has("model") ? filters["model"] : ""
        providerFilter := filters.Has("provider") ? filters["provider"] : ""
        typeFilter := filters.Has("type") ? filters["type"] : "all"

        ; Chat data - from chat_usage table
        if typeFilter != "command" {
            chatWhere := UsageRepo._WhereDate(timeRange, "date", localToday, monthCutoff, lastMonthStart, monthStart)
            chatParams := chatWhere.params
            if modelFilter {
                chatWhere.sql .= (chatWhere.sql ? " AND" : "WHERE") " model=?"
                chatParams.Push(modelFilter)
            }
            if providerFilter {
                ; Rows with an empty provider use a reserved filter sentinel.
                ; from settings) render under "" in the chart - the reserved
                ; "__BLANK_PROVIDER__" sentinel (which can never be a real
                ; provider name) scopes the filter to them so they can be
                ; isolated. A provider literally named "__unknown__" is a real
                ; A real provider named "__unknown__" still filters by its own name.
                if providerFilter = "__BLANK_PROVIDER__"
                    chatWhere.sql .= (chatWhere.sql ? " AND" : "WHERE") " (provider='' OR provider IS NULL)"
                else {
                    chatWhere.sql .= (chatWhere.sql ? " AND" : "WHERE") " provider=?"
                    chatParams.Push(providerFilter)
                }
            }

            chatSql := "SELECT date, model, provider, call_count, prompt_tokens, completion_tokens, thinking_tokens, cached_tokens, input_cost, cached_input_cost, output_cost, total_cost, total_response_time_ms, total_ttft_ms, ttft_count FROM chat_usage " chatWhere.sql " ORDER BY date DESC, model"
            chatTable := ChatDB.db.Query(chatSql, chatParams*)
            for row in chatTable.rows {
                result.chat.Push({
                    date: row.date, model: row.model, provider: row.provider,
                    input_tokens: Integer(row.prompt_tokens),
                    output_tokens: Integer(row.completion_tokens),
                    cached_tokens: Integer(row.cached_tokens),
                    message_count: Integer(row.call_count),
                    thinking_tokens: Integer(row.thinking_tokens),
                    total_cost: Number(row.total_cost),
                    input_cost: Number(row.input_cost),
                    cached_input_cost: Number(row.cached_input_cost),
                    output_cost: Number(row.output_cost),
                    total_response_time_ms: Integer(row.total_response_time_ms),
                    total_ttft_ms: Integer(row.total_ttft_ms),
                    ttft_count: Integer(row.ttft_count)
                })
            }
        }

        ; Command data - only if type includes commands
        if typeFilter != "chat" {
            cmdWhere := UsageRepo._WhereDate(timeRange, "date", localToday, monthCutoff, lastMonthStart, monthStart)
            cmdParams := cmdWhere.params
            if modelFilter {
                cmdWhere.sql .= (cmdWhere.sql ? " AND" : "WHERE") " model=?"
                cmdParams.Push(modelFilter)
            }
            if providerFilter {
                ; Use the same reserved empty-provider sentinel for
                ; command rows.
                if providerFilter = "__BLANK_PROVIDER__"
                    cmdWhere.sql .= (cmdWhere.sql ? " AND" : "WHERE") " (provider='' OR provider IS NULL)"
                else {
                    cmdWhere.sql .= (cmdWhere.sql ? " AND" : "WHERE") " provider=?"
                    cmdParams.Push(providerFilter)
                }
            }

            cmdSql := "SELECT date, model, provider, command_name, call_count, prompt_tokens, completion_tokens, thinking_tokens, cached_tokens, input_cost, cached_input_cost, output_cost, total_cost, total_response_time_ms, total_ttft_ms, ttft_count FROM command_usage " cmdWhere.sql " ORDER BY date DESC"
            cmdTable := ChatDB.db.Query(cmdSql, cmdParams*)
            for row in cmdTable.rows {
                result.commands.Push({
                    date: row.date, model: row.model, provider: row.provider,
                    command_name: row.command_name, call_count: Integer(row.call_count),
                    prompt_tokens: Integer(row.prompt_tokens),
                    completion_tokens: Integer(row.completion_tokens),
                    thinking_tokens: Integer(row.thinking_tokens),
                    cached_tokens: Integer(row.cached_tokens),
                    input_cost: Number(row.input_cost),
                    cached_input_cost: Number(row.cached_input_cost),
                    output_cost: Number(row.output_cost),
                    total_cost: Number(row.total_cost),
                    total_response_time_ms: Integer(row.total_response_time_ms),
                    total_ttft_ms: Integer(row.total_ttft_ms),
                    ttft_count: Integer(row.ttft_count)
                })
            }
        }

        ; Distinct models and providers - always unfiltered (dropdowns need full lists)
        modelsTable := ChatDB.db.Query("SELECT DISTINCT model FROM chat_usage UNION SELECT DISTINCT model FROM command_usage ORDER BY model")
        for row in modelsTable.rows
            result.models.Push(row.model)

        provTable := ChatDB.db.Query("SELECT DISTINCT provider FROM chat_usage UNION SELECT DISTINCT provider FROM command_usage ORDER BY provider")
        for row in provTable.rows {
            if row.provider && row.provider != ""
                result.providers.Push(row.provider)
        }

        debugLog("[DASHBOARD] Query - chat=" result.chat.Length " rows, cmd=" result.commands.Length " rows, type=" typeFilter " time=" timeRange)
        return result
    }

    ; Command usage - daily aggregation UPSERT
    static CommandUpsert(data) {
        date := data.date, model := data.model, provider := data.provider, cmd := data.command_name
        tht := data.HasProp("thinking_tokens") ? data.thinking_tokens : 0
        ckt := data.HasProp("cached_tokens") ? data.cached_tokens : 0
        cci := data.HasProp("cached_input_cost") ? data.cached_input_cost : 0
        lat := data.HasProp("response_time_ms") ? data.response_time_ms : 0
        ttft := data.HasProp("ttft_ms") ? data.ttft_ms : 0
        ttftMeasured := data.HasProp("ttft_measured") ? data.ttft_measured : (data.HasProp("ttft_ms") && data.ttft_ms > 0)
        existing := ChatDB.db.Query("SELECT call_count FROM command_usage WHERE date=? AND model=? AND provider=? AND command_name=?;", date, model, provider, cmd)
        if existing.count {
            ChatDB.db.Query("UPDATE command_usage SET call_count=call_count+1, prompt_tokens=prompt_tokens+?, completion_tokens=completion_tokens+?, thinking_tokens=thinking_tokens+?, cached_tokens=cached_tokens+?, input_cost=input_cost+?, cached_input_cost=cached_input_cost+?, output_cost=output_cost+?, total_cost=total_cost+?, total_response_time_ms=total_response_time_ms+?, total_ttft_ms=total_ttft_ms+?, ttft_count=ttft_count+? WHERE date=? AND model=? AND provider=? AND command_name=?;", data.prompt_tokens, data.completion_tokens, tht, ckt, data.input_cost, cci, data.output_cost, data.total_cost, lat, ttft, ttftMeasured ? 1 : 0, date, model, provider, cmd)
        } else {
            ChatDB.db.Query("INSERT INTO command_usage (date, model, provider, command_name, call_count, prompt_tokens, completion_tokens, thinking_tokens, cached_tokens, input_cost, cached_input_cost, output_cost, total_cost, total_response_time_ms, total_ttft_ms, ttft_count) VALUES(?, ?, ?, ?, 1, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);", date, model, provider, cmd, data.prompt_tokens, data.completion_tokens, tht, ckt, data.input_cost, cci, data.output_cost, data.total_cost, lat, ttft, ttftMeasured ? 1 : 0)
        }
        ChatDB._MarkPersistentDataChanged()
    }

    ; Chat usage - daily aggregation UPSERT
    static ChatUpsert(data) {
        date := data.date, model := data.model, provider := data.provider
        tht := data.HasProp("thinking_tokens") ? data.thinking_tokens : 0
        ckt := data.HasProp("cached_tokens") ? data.cached_tokens : 0
        cci := data.HasProp("cached_input_cost") ? data.cached_input_cost : 0
        lat := data.HasProp("response_time_ms") ? data.response_time_ms : 0
        ttft := data.HasProp("ttft_ms") ? data.ttft_ms : 0
        ttftMeasured := data.HasProp("ttft_measured") ? data.ttft_measured : (data.HasProp("ttft_ms") && data.ttft_ms > 0)
        existing := ChatDB.db.Query("SELECT call_count FROM chat_usage WHERE date=? AND model=? AND provider=?;", date, model, provider)
        if existing.count {
            ChatDB.db.Query("UPDATE chat_usage SET call_count=call_count+1, prompt_tokens=prompt_tokens+?, completion_tokens=completion_tokens+?, thinking_tokens=thinking_tokens+?, cached_tokens=cached_tokens+?, input_cost=input_cost+?, cached_input_cost=cached_input_cost+?, output_cost=output_cost+?, total_cost=total_cost+?, total_response_time_ms=total_response_time_ms+?, total_ttft_ms=total_ttft_ms+?, ttft_count=ttft_count+? WHERE date=? AND model=? AND provider=?;", data.prompt_tokens, data.completion_tokens, tht, ckt, data.input_cost, cci, data.output_cost, data.total_cost, lat, ttft, ttftMeasured ? 1 : 0, date, model, provider)
        } else {
            ChatDB.db.Query("INSERT INTO chat_usage (date, model, provider, call_count, prompt_tokens, completion_tokens, thinking_tokens, cached_tokens, input_cost, cached_input_cost, output_cost, total_cost, total_response_time_ms, total_ttft_ms, ttft_count) VALUES(?, ?, ?, 1, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);", date, model, provider, data.prompt_tokens, data.completion_tokens, tht, ckt, data.input_cost, cci, data.output_cost, data.total_cost, lat, ttft, ttftMeasured ? 1 : 0)
        }
        ChatDB._MarkPersistentDataChanged()
    }
}
