; ======================================================
; UsageRepo.ahk — Usage tracking operations
;
; Extracted from ChatDB.ahk. Handles daily usage
; aggregation (chat + command) and dashboard queries.
; ======================================================

class UsageRepo {

    ; Build WHERE clause for date-based time range filters. localToday is the
    ; LOCAL calendar date (usage rows are stored with local dates, and the
    ; dashboard's day chart plots a single local "today" label), so the "day"
    ; filter must use it instead of SQLite's UTC date('now', '-1 day') which
    ; pulled in yesterday and over-reported vs the chart (bug #53).
    static _WhereDate(range, dateColumn := "date", localToday := "") {
        if range = "day" {
            cutoff := localToday ? "'" localToday "'" : "date('now')"
            return "WHERE " dateColumn " >= " cutoff
        }
        if range = "month"
            return "WHERE " dateColumn " >= date('now', '-30 days')"
        if range = "thisMonth"
            return "WHERE " dateColumn " >= date('now', 'start of month')"
        if range = "lastMonth"
            return "WHERE " dateColumn " >= date('now', 'start of month', '-1 month') AND " dateColumn " < date('now', 'start of month')"
        return ""
    }

    ; Usage dashboard — query aggregated data
    static Query(filters) {
        result := { chat: [], commands: [], models: [], providers: [] }
        localToday := FormatTime(, "yyyy-MM-dd")

        timeRange := filters.Has("timeRange") ? filters["timeRange"] : "all"
        modelFilter := filters.Has("model") ? filters["model"] : ""
        modelClause := modelFilter ? "AND model='" SQLite.Escape(modelFilter) "'" : ""
        providerFilter := filters.Has("provider") ? filters["provider"] : ""
        providerChatClause := providerFilter ? "AND model LIKE '" SQLite.Escape(providerFilter) "/%'" : ""
        typeFilter := filters.Has("type") ? filters["type"] : "all"

        ; Chat data — from chat_usage table
        if typeFilter != "command" {
            chatWhere := UsageRepo._WhereDate(timeRange, "date", localToday)
            if modelFilter
                chatWhere .= (chatWhere ? " AND" : "WHERE") " model='" SQLite.Escape(modelFilter) "'"
            if providerFilter
                chatWhere .= (chatWhere ? " AND" : "WHERE") " provider='" SQLite.Escape(providerFilter) "'"

            chatSql := "SELECT date, model, provider, call_count, prompt_tokens, completion_tokens, thinking_tokens, cached_tokens, input_cost, cached_input_cost, output_cost, total_cost, total_response_time_ms, total_ttft_ms FROM chat_usage " chatWhere " ORDER BY date DESC, model"
            chatTable := ChatDB.db.Exec(chatSql)
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
                    total_ttft_ms: Integer(row.total_ttft_ms)
                })
            }
        }

        ; Command data — only if type includes commands
        if typeFilter != "chat" {
            cmdWhere := UsageRepo._WhereDate(timeRange, "date", localToday)
            if modelFilter
                cmdWhere .= (cmdWhere ? " AND" : "WHERE") " model='" SQLite.Escape(modelFilter) "'"
            if providerFilter
                cmdWhere .= (cmdWhere ? " AND" : "WHERE") " provider='" SQLite.Escape(providerFilter) "'"

            cmdSql := "SELECT date, model, provider, command_name, call_count, prompt_tokens, completion_tokens, thinking_tokens, cached_tokens, input_cost, cached_input_cost, output_cost, total_cost, total_response_time_ms, total_ttft_ms FROM command_usage " cmdWhere " ORDER BY date DESC"
            cmdTable := ChatDB.db.Exec(cmdSql)
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
                    total_ttft_ms: Integer(row.total_ttft_ms)
                })
            }
        }

        ; Distinct models and providers — always unfiltered (dropdowns need full lists)
        modelsTable := ChatDB.db.Exec("SELECT DISTINCT model FROM chat_usage UNION SELECT DISTINCT model FROM command_usage ORDER BY model")
        for row in modelsTable.rows
            result.models.Push(row.model)

        provTable := ChatDB.db.Exec("SELECT DISTINCT provider FROM chat_usage UNION SELECT DISTINCT provider FROM command_usage ORDER BY provider")
        for row in provTable.rows {
            if row.provider && row.provider != ""
                result.providers.Push(row.provider)
        }

        debugLog("[DASHBOARD] Query — chat=" result.chat.Length " rows, cmd=" result.commands.Length " rows, type=" typeFilter " time=" timeRange)
        return result
    }

    ; Command usage — daily aggregation UPSERT
    static CommandUpsert(data) {
        date := data.date, model := data.model, provider := data.provider, cmd := data.command_name
        tht := data.HasProp("thinking_tokens") ? data.thinking_tokens : 0
        ckt := data.HasProp("cached_tokens") ? data.cached_tokens : 0
        cci := data.HasProp("cached_input_cost") ? data.cached_input_cost : 0
        lat := data.HasProp("response_time_ms") ? data.response_time_ms : 0
        ttft := data.HasProp("ttft_ms") ? data.ttft_ms : 0
        existing := ChatDB.db.Exec("SELECT call_count FROM command_usage WHERE date='" date "' AND model='" SQLite.Escape(model) "' AND provider='" SQLite.Escape(provider) "' AND command_name='" SQLite.Escape(cmd) "';")
        if existing.count {
            ChatDB.db.Exec("UPDATE command_usage SET call_count=call_count+1, prompt_tokens=prompt_tokens+" data.prompt_tokens ", completion_tokens=completion_tokens+" data.completion_tokens ", thinking_tokens=thinking_tokens+" tht ", cached_tokens=cached_tokens+" ckt ", input_cost=input_cost+" data.input_cost ", cached_input_cost=cached_input_cost+" cci ", output_cost=output_cost+" data.output_cost ", total_cost=total_cost+" data.total_cost ", total_response_time_ms=total_response_time_ms+" lat ", total_ttft_ms=total_ttft_ms+" ttft " WHERE date='" date "' AND model='" SQLite.Escape(model) "' AND provider='" SQLite.Escape(provider) "' AND command_name='" SQLite.Escape(cmd) "';")
        } else {
            ChatDB.db.Exec("INSERT INTO command_usage (date, model, provider, command_name, call_count, prompt_tokens, completion_tokens, thinking_tokens, cached_tokens, input_cost, cached_input_cost, output_cost, total_cost, total_response_time_ms, total_ttft_ms) VALUES('" date "', '" SQLite.Escape(model) "', '" SQLite.Escape(provider) "', '" SQLite.Escape(cmd) "', 1, " data.prompt_tokens ", " data.completion_tokens ", " tht ", " ckt ", " data.input_cost ", " cci ", " data.output_cost ", " data.total_cost ", " lat ", " ttft ");")
        }
    }

    ; Chat usage — daily aggregation UPSERT
    static ChatUpsert(data) {
        date := data.date, model := data.model, provider := data.provider
        tht := data.HasProp("thinking_tokens") ? data.thinking_tokens : 0
        ckt := data.HasProp("cached_tokens") ? data.cached_tokens : 0
        cci := data.HasProp("cached_input_cost") ? data.cached_input_cost : 0
        lat := data.HasProp("response_time_ms") ? data.response_time_ms : 0
        ttft := data.HasProp("ttft_ms") ? data.ttft_ms : 0
        existing := ChatDB.db.Exec("SELECT call_count FROM chat_usage WHERE date='" date "' AND model='" SQLite.Escape(model) "' AND provider='" SQLite.Escape(provider) "';")
        if existing.count {
            ChatDB.db.Exec("UPDATE chat_usage SET call_count=call_count+1, prompt_tokens=prompt_tokens+" data.prompt_tokens ", completion_tokens=completion_tokens+" data.completion_tokens ", thinking_tokens=thinking_tokens+" tht ", cached_tokens=cached_tokens+" ckt ", input_cost=input_cost+" data.input_cost ", cached_input_cost=cached_input_cost+" cci ", output_cost=output_cost+" data.output_cost ", total_cost=total_cost+" data.total_cost ", total_response_time_ms=total_response_time_ms+" lat ", total_ttft_ms=total_ttft_ms+" ttft " WHERE date='" date "' AND model='" SQLite.Escape(model) "' AND provider='" SQLite.Escape(provider) "';")
        } else {
            ChatDB.db.Exec("INSERT INTO chat_usage (date, model, provider, call_count, prompt_tokens, completion_tokens, thinking_tokens, cached_tokens, input_cost, cached_input_cost, output_cost, total_cost, total_response_time_ms, total_ttft_ms) VALUES('" date "', '" SQLite.Escape(model) "', '" SQLite.Escape(provider) "', 1, " data.prompt_tokens ", " data.completion_tokens ", " tht ", " ckt ", " data.input_cost ", " cci ", " data.output_cost ", " data.total_cost ", " lat ", " ttft ");")
        }
    }
}
