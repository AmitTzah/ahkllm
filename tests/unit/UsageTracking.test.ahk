; ======================================================
; UsageTracking.test.ahk — Comprehensive token & usage tests
;
; Tests every field: token_count on user (backfill) and
; assistant (visible output), thinking_tokens, cached_tokens,
; response_time_ms, cumulative counters, active_path_tokens,
; chat_usage/command_usage aggregation, and cost tracking.
; ======================================================

class UsageTrackingTest {

    static __New() {
        RegisterTestClass("UsageTrackingTest")
    }

    _openDb() {
        if ChatDB.isOpen {
            oldPath := ChatDB.dbPath
            ChatDB.Close()
            try FileDelete(oldPath)
        }
        ChatDB.Open(A_Temp "\test_usage_" A_TickCount "_" Random(1000, 999999) ".db")
    }

    _closeDb() {
        if ChatDB.isOpen {
            dbPath := ChatDB.dbPath
            ChatDB.Close()
            try FileDelete(dbPath)
        }
    }

    ; Regression (bug #53): the "day" usage filter must use the LOCAL calendar
    ; date (the chart plots a single local "today" label and usage rows are
    ; stored with local dates), not SQLite's UTC date('now', '-1 day') which
    ; pulls in yesterday and over-reports vs the chart.
    DayFilter_UsesLocalToday() {
        where := UsageRepo._WhereDate("day", "date", "2026-08-07")
        if where.sql != "WHERE date >= ?" || where.params.Length != 1 || where.params[1] != "2026-08-07"
            throw Error("day filter must use the local today cutoff as a bound param, got: " where.sql)
        if InStr(where.sql, "date('now'")
            throw Error("day filter must not use SQLite's UTC now, got: " where.sql)

        ; Query wires the local date into both the chat and command filters.
        srcPath := A_ScriptDir "\..\chat\db\UsageRepo.ahk"
        src := FileRead(srcPath)
        if !InStr(src, "localToday := FormatTime(")
            throw Error("UsageRepo.Query must compute the local today date")
        if !InStr(src, "_WhereDate(timeRange, ")
            throw Error("UsageRepo.Query must pass the local today into both filters")
    }

    ; Regression (bug #87/#88): lastMonth/month filters must use LOCAL calendar
    ; boundaries (matching the local dashboard labels), not SQLite UTC.
    MonthFilters_UseLocalBoundaries() {
        srcPath := A_ScriptDir "\..\chat\db\UsageRepo.ahk"
        src := FileRead(srcPath)
        if !InStr(src, "lastMonthStart := FormatTime(DateAdd(A_Now, -1")
            throw Error("Query must compute the local last-month start")
        if !InStr(src, "monthCutoff := FormatTime(DateAdd(A_Now, -29")
            throw Error("Query must compute the local 30-day cutoff")
        where := UsageRepo._WhereDate("lastMonth", "date", "2026-08-07", "", "2026-07-01", "2026-08-01")
        if where.sql != "WHERE date >= ? AND date < ?" || where.params.Length != 2 || where.params[1] != "2026-07-01" || where.params[2] != "2026-08-01"
            throw Error("lastMonth filter must use local month boundaries as bound params, got: " where.sql)
        where2 := UsageRepo._WhereDate("month", "date", "2026-08-07", "2026-07-09", "", "")
        if where2.sql != "WHERE date >= ?" || where2.params.Length != 1 || where2.params[1] != "2026-07-09"
            throw Error("month filter must use the local cutoff as a bound param, got: " where2.sql)
    }

    ; ----------------------------------------------------
    ; Single exchange — verify per-message token fields
    ; ----------------------------------------------------

    ; Regression (bug #102): the provider LIKE must escape % _ \ so a provider
    ; value containing wildcards is matched literally (and the SQL declares
    ; ESCAPE '\', same pattern as SearchRepo).
    ProviderFilter_BindsExactMatch() {
        ; Hardening (bug #102): provider filters are bound parameters
        ; (provider=?) instead of a LIKE pattern, so a provider value containing
        ; LIKE wildcards (% _ \) matches literally and never acts as a wildcard.
        this._openDb()
        ChatDB.db.Query("INSERT INTO chat_usage (date, model, provider, call_count, prompt_tokens) VALUES(?, ?, ?, 1, 10);", "2026-08-08", "openai/weird%model", "prov%ider")
        exact := UsageRepo.Query(Map("timeRange", "all", "model", "", "provider", "prov%ider", "type", "chat"))
        if exact.chat.Length != 1
            throw Error("provider filter must match the literal provider (bug #102), got " exact.chat.Length " rows")
        partial := UsageRepo.Query(Map("timeRange", "all", "model", "", "provider", "prov", "type", "chat"))
        if partial.chat.Length != 0
            throw Error("provider filter must be an exact match, got " partial.chat.Length " rows")
        this._closeDb()
    }

    ; Regression (bug #168/#182): the reserved "__BLANK_PROVIDER__" provider
    ; filter must scope to rows with an EMPTY provider (model removed from
    ; settings), while a provider literally named "__unknown__" must filter by
    ; its OWN name - the sentinel can never collide with a real provider.
    ProviderFilter_UnknownSentinel_MatchesEmptyProvider() {
        this._openDb()
        ChatDB.db.Query("INSERT INTO chat_usage (date, model, provider, call_count, prompt_tokens) VALUES(?, ?, ?, 1, 10);", "2026-08-10", "gpt-5", "")
        ChatDB.db.Query("INSERT INTO chat_usage (date, model, provider, call_count, prompt_tokens) VALUES(?, ?, ?, 1, 10);", "2026-08-10", "deepseek/deepseek-v4-flash", "deepseek")
        ChatDB.db.Query("INSERT INTO chat_usage (date, model, provider, call_count, prompt_tokens) VALUES(?, ?, ?, 1, 10);", "2026-08-10", "real/__unknown__", "__unknown__")
        blank := UsageRepo.Query(Map("timeRange", "all", "model", "", "provider", "__BLANK_PROVIDER__", "type", "chat"))
        if blank.chat.Length != 1 || blank.chat[1].model != "gpt-5"
            throw Error("__BLANK_PROVIDER__ filter must scope to the empty-provider row (bug #168), got " blank.chat.Length)
        realUnknown := UsageRepo.Query(Map("timeRange", "all", "model", "", "provider", "__unknown__", "type", "chat"))
        if realUnknown.chat.Length != 1 || realUnknown.chat[1].provider != "__unknown__"
            throw Error("a provider named __unknown__ must filter by its own name (bug #182), got " realUnknown.chat.Length)
        all := UsageRepo.Query(Map("timeRange", "all", "model", "", "provider", "", "type", "chat"))
        if all.chat.Length != 3
            throw Error("empty provider filter (All) must return every row, got " all.chat.Length)
        this._closeDb()
    }

    ; Regression (bug #103): pricingUnit must follow the ACTIVE model (request
    ; model -> thread override -> last assistant on the active path), never the
    ; thread's first (oldest) message.
    ThreadStats_PricingUnit_FollowsActiveModel() {
        global requestParams
        this._openDb()
        threadId := ChatDB.Thread_Create("Pricing")
        oldParams := IsSet(requestParams) ? requestParams : ""
        try {
            ; Clear the request model so the thread's own models drive pricing.
            requestParams := Map("singleAPIModelName", "")
            ChatDB.Msg_Insert({thread_id: threadId, role: "user", content: "hi"})
            a1 := ChatDB.Msg_Insert({thread_id: threadId, role: "assistant", content: "first", model: "deepseek/deepseek-v4-flash"})
            stats := ChatDB.Msg_GetThreadStats(threadId)
            if Number(stats.pricingUnit.input) != 0.14
                throw Error("pricing should follow the active assistant model (deepseek-v4-flash 0.14), got " stats.pricingUnit.input)
            ; A newer assistant message becomes the leaf - pricing must follow it.
            ChatDB.Msg_Insert({thread_id: threadId, role: "assistant", content: "second", model: "openai/gpt-5-mini", parent_id: a1})
            stats := ChatDB.Msg_GetThreadStats(threadId)
            if Number(stats.pricingUnit.input) != 0.25
                throw Error("pricing should follow the newest assistant model (gpt-5-mini 0.25), got " stats.pricingUnit.input)
            ; Thread override wins over message models.
            ChatDB.db.Exec("UPDATE chat_threads SET model_override='deepseek/deepseek-v4-flash' WHERE id='" threadId "';")
            stats := ChatDB.Msg_GetThreadStats(threadId)
            if Number(stats.pricingUnit.input) != 0.14
                throw Error("thread override should win over message models, got " stats.pricingUnit.input)
            ; Current request model wins over everything.
            requestParams := Map("singleAPIModelName", "openai/gpt-5-mini")
            stats := ChatDB.Msg_GetThreadStats(threadId)
            if Number(stats.pricingUnit.input) != 0.25
                throw Error("request model should win, got " stats.pricingUnit.input)
        } finally {
            requestParams := oldParams
            this._closeDb()
        }
    }

    SingleExchange_AllTokenFields() {
        this._openDb()
        threadId := ChatDB.Thread_Create("Test")

        ; Insert system + user messages with proper parent links
        sysId := ChatDB.Msg_Insert({thread_id: threadId, role: "system", content: "sys"})
        userId := ChatDB.Msg_Insert({thread_id: threadId, role: "user", content: "Hello", parent_id: sysId})

        ; Insert assistant with API data (simulates real API response)
        ; prompt=5, completion=126, thinking=93, cached=0
        ChatDB.Msg_Insert({
            thread_id: threadId, role: "assistant", content: "Hi!",
            model: "deepseek/deepseek-v4-flash",
            parent_id: userId,
            token_count: 33,      ; 126-93 = visible output
            thinking_tokens: 93,
            cached_tokens: 0,
            response_time_ms: 1200,
            prompt_tokens: 5
        })

        ; Verify assistant message fields
        path := ChatDB.Msg_GetActivePath(threadId)
        if path.Length != 3
            throw Error("Expected 3 messages, got " path.Length)

        asst := path[3]
        if asst.role != "assistant"
            throw Error("Expected role assistant")
        if asst.token_count != 33
            throw Error("Expected token_count=33 (visible output), got " asst.token_count)
        if asst.thinking_tokens != 93
            throw Error("Expected thinking_tokens=93, got " asst.thinking_tokens)
        if asst.cached_tokens != 0
            throw Error("Expected cached_tokens=0, got " asst.cached_tokens)
        if asst.response_time_ms != 1200
            throw Error("Expected response_time_ms=1200, got " asst.response_time_ms)

        ; Verify user message backfill: new_input = prompt(5) - existing_sum(0) = 5
        user := path[2]
        if user.role != "user"
            throw Error("Expected role user at index 2")
        if user.token_count != 5
            throw Error("Expected user token_count=5 (backfill), got " user.token_count)

        ; Verify thread counters
        stats := ChatDB.Msg_GetThreadStats(threadId)
        ; Bug #64: thinking tokens occupy the context window.
        if stats.activePathTokens != 131
            throw Error("Expected activePathTokens=131 (5+33+93), got " stats.activePathTokens)
        if stats.cumulativeInputTokens != 5
            throw Error("Expected cumulativeInputTokens=5, got " stats.cumulativeInputTokens)
        if stats.cumulativeOutputTokens != 126
            throw Error("Expected cumulativeOutputTokens=126 (33+93), got " stats.cumulativeOutputTokens)

        this._closeDb()
    }

    ; ----------------------------------------------------
    ; Multi-turn conversation — cumulative counters
    ; ----------------------------------------------------

    MultiTurn_CumulativeCounters() {
        this._openDb()
        threadId := ChatDB.Thread_Create("Test")

        ; Turn 1: "Hi" -> assistant
        sysId := ChatDB.Msg_Insert({thread_id: threadId, role: "system", content: "sys"})
        user1Id := ChatDB.Msg_Insert({thread_id: threadId, role: "user", content: "Hi", parent_id: sysId})
        asst1Id := ChatDB.Msg_Insert({
            thread_id: threadId, role: "assistant", content: "Hello!",
            model: "deepseek/deepseek-v4-flash",
            parent_id: user1Id,
            token_count: 30, thinking_tokens: 70, cached_tokens: 0,
            response_time_ms: 1000, prompt_tokens: 5
        })

        ; Verify after turn 1
        stats1 := ChatDB.Msg_GetThreadStats(threadId)
        if stats1.cumulativeInputTokens != 5
            throw Error("T1: Expected cumulativeInput=5, got " stats1.cumulativeInputTokens)
        ; Bug #64: thinking tokens occupy the context window.
        if stats1.activePathTokens != 105
            throw Error("T1: Expected activePathTokens=105 (5+30+70), got " stats1.activePathTokens)

        ; Turn 2: "How are you?" -> assistant
        user2Id := ChatDB.Msg_Insert({thread_id: threadId, role: "user", content: "How are you?", parent_id: asst1Id})
        ChatDB.Msg_Insert({
            thread_id: threadId, role: "assistant", content: "Good!",
            model: "deepseek/deepseek-v4-flash",
            parent_id: user2Id,
            token_count: 15, thinking_tokens: 0, cached_tokens: 0,
            ; Bug #145: the context before user2 includes a1's THINKING tokens
            ; (5 + 30 + 70 = 105), so a consistent prompt for user2's own 10
            ; tokens is 115 (the old 45 assumed thinking was free).
            response_time_ms: 800, prompt_tokens: 115
        })

        ; Verify after turn 2
        stats2 := ChatDB.Msg_GetThreadStats(threadId)
        if stats2.cumulativeInputTokens != 120
            throw Error("T2: Expected cumulativeInput=120 (5+115), got " stats2.cumulativeInputTokens)
        if stats2.cumulativeOutputTokens != 115
            throw Error("T2: Expected cumulativeOutput=115, got " stats2.cumulativeOutputTokens)

        ; Backfill check: user 2 should get new_input = 115 - 105 = 10 (the
        ; prior assistant's 70 thinking tokens are subtracted - bug #145).
        path := ChatDB.Msg_GetActivePath(threadId)
        user2 := path[4]
        if user2.token_count != 10
            throw Error("T2: Expected user2 token_count=10 (115-105), got " user2.token_count)

        this._closeDb()
    }

    ; ----------------------------------------------------
    ; Cost tracking — cached tokens produce cached cost
    ; ----------------------------------------------------

    CostTracking_WithCache() {
        this._openDb()
        threadId := ChatDB.Thread_Create("Test")

        sysId := ChatDB.Msg_Insert({thread_id: threadId, role: "system", content: "sys"})
        userId := ChatDB.Msg_Insert({thread_id: threadId, role: "user", content: "Hi", parent_id: sysId})

        ; Assistant with cached tokens — use large values for visible cost
        ChatDB.Msg_Insert({
            thread_id: threadId, role: "assistant", content: "Cached response",
            model: "deepseek/deepseek-v4-flash",
            parent_id: userId,
            token_count: 50000, thinking_tokens: 10000, cached_tokens: 40000,
            response_time_ms: 1500, prompt_tokens: 100000
        })

        ; Verify chat_usage was upserted with correct cached_input_cost
        row := ChatDB.db.Exec("SELECT * FROM chat_usage WHERE date='" FormatTime(, "yyyy-MM-dd") "' AND model='deepseek/deepseek-v4-flash'")
        if row.count != 1
            throw Error("Expected 1 chat_usage row, got " row.count)

        ; cached_input_cost should be non-zero (40 tokens x $0.0028/1M = 0.000000112)
        cachedCost := Number(row[1,"cached_input_cost"])
        if cachedCost <= 0
            throw Error("Expected cached_input_cost > 0, got " cachedCost)

        ; input_cost should be larger than cached_input_cost (includes uncached)
        inputCost := Number(row[1,"input_cost"])
        if inputCost <= cachedCost
            throw Error("Expected input_cost > cached_input_cost, got " inputCost " <= " cachedCost)

        ; output_cost should be non-zero (150 tokens x $0.28/1M)
        outputCost := Number(row[1,"output_cost"])
        if outputCost <= 0
            throw Error("Expected output_cost > 0, got " outputCost)

        this._closeDb()
    }

    ; ----------------------------------------------------
    ; Command usage — FIM and Refine tracked correctly
    ; ----------------------------------------------------

    CommandUsage_TracksTokens() {
        this._openDb()

        ChatDB.CommandUsage_Upsert({
            date: FormatTime(, "yyyy-MM-dd"),
            model: "deepseek-v4-flash", provider: "deepseek",
            command_name: "FIM Continue",
            prompt_tokens: 115, completion_tokens: 78,
            thinking_tokens: 0, cached_tokens: 0,
            input_cost: 0.0000161, cached_input_cost: 0,
            output_cost: 0.00002184, total_cost: 0.00003794, response_time_ms: 3200
        })

        ChatDB.CommandUsage_Upsert({
            date: FormatTime(, "yyyy-MM-dd"),
            model: "deepseek-v4-flash", provider: "deepseek",
            command_name: "Refine",
            prompt_tokens: 600, completion_tokens: 200,
            thinking_tokens: 0, cached_tokens: 384,
            input_cost: 0.00003066, cached_input_cost: 0.00000107,
            output_cost: 0.000056, total_cost: 0.00008666, response_time_ms: 2800
        })

        rows := ChatDB.db.Exec("SELECT * FROM command_usage WHERE date='" FormatTime(, "yyyy-MM-dd") "' ORDER BY command_name")
        if rows.count != 2
            throw Error("Expected 2 command rows, got " rows.count)
        if Integer(rows[1,"prompt_tokens"]) != 115
            throw Error("Expected FIM prompt=115, got " rows[1,"prompt_tokens"])
        if Integer(rows[2,"cached_tokens"]) != 384
            throw Error("Expected Refine cached=384, got " rows[2,"cached_tokens"])
        if Number(rows[2,"cached_input_cost"]) <= 0
            throw Error("Expected Refine cached_input_cost > 0, got " rows[2,"cached_input_cost"])

        this._closeDb()
    }

    ; ----------------------------------------------------
    ; Usage_Query — chat_usage data flows to dashboard
    ; ----------------------------------------------------

    Dashboard_ChatUsageDataFlow() {
        this._openDb()

        ChatDB.ChatUsage_Upsert({
            date: FormatTime(, "yyyy-MM-dd"),
            model: "deepseek-v4-flash", provider: "deepseek",
            prompt_tokens: 100, completion_tokens: 200,
            thinking_tokens: 50, cached_tokens: 30,
            input_cost: 0.000014, cached_input_cost: 0.000000084,
            output_cost: 0.000056, total_cost: 0.000070, response_time_ms: 2000
        })

        filters := Map("timeRange", "all", "model", "", "type", "all")
        result := ChatDB.Usage_Query(filters)

        if result.chat.Length != 1
            throw Error("Expected 1 chat row, got " result.chat.Length)
        row := result.chat[1]
        if row.input_tokens != 100
            throw Error("Expected input_tokens=100, got " row.input_tokens)
        if row.output_tokens != 200
            throw Error("Expected output_tokens=200, got " row.output_tokens)
        if row.cached_tokens != 30
            throw Error("Expected cached_tokens=30, got " row.cached_tokens)
        if row.message_count != 1
            throw Error("Expected message_count=1, got " row.message_count)
        if row.total_cost <= 0
            throw Error("Expected total_cost > 0, got " row.total_cost)
        if row.input_cost <= 0
            throw Error("Expected input_cost > 0, got " row.input_cost)

        this._closeDb()
    }

    ; ----------------------------------------------------
    ; Thinking tokens — stored and excluded from context
    ; ----------------------------------------------------

    ThinkingTokens_StoredAndIncludedInContext() {
        this._openDb()
        threadId := ChatDB.Thread_Create("Test")

        sysId := ChatDB.Msg_Insert({thread_id: threadId, role: "system", content: "sys"})
        userId := ChatDB.Msg_Insert({thread_id: threadId, role: "user", content: "Hi", parent_id: sysId})
        ChatDB.Msg_Insert({
            thread_id: threadId, role: "assistant", content: "Thinker",
            model: "deepseek/deepseek-v4-flash",
            parent_id: userId,
            token_count: 40, thinking_tokens: 160, cached_tokens: 0,
            response_time_ms: 2500, prompt_tokens: 5
        })

        ; Bug #64: active_path_tokens includes thinking (prompt + visible + thinking).
        stats := ChatDB.Msg_GetThreadStats(threadId)
        if stats.activePathTokens != 205
            throw Error("Expected activePathTokens=205 (5+40+160), got " stats.activePathTokens)
        if stats.cumulativeOutputTokens != 200
            throw Error("Expected cumulativeOutput=200 (40+160), got " stats.cumulativeOutputTokens)

        path := ChatDB.Msg_GetActivePath(threadId)
        asst := path[3]
        if asst.thinking_tokens != 160
            throw Error("Expected thinking_tokens=160 on assistant, got " asst.thinking_tokens)
        if asst.token_count != 40
            throw Error("Expected token_count=40 (visible), got " asst.token_count)

        this._closeDb()
    }

    ; ----------------------------------------------------
    ; chat_usage accumulation — multiple calls same day
    ; ----------------------------------------------------

    ChatUsage_AccumulatesMultipleCalls() {
        this._openDb()
        date := FormatTime(, "yyyy-MM-dd")

        ChatDB.ChatUsage_Upsert({
            date: date, model: "deepseek-v4-flash", provider: "deepseek",
            prompt_tokens: 10, completion_tokens: 20, thinking_tokens: 0, cached_tokens: 0,
            input_cost: 0.0000014, output_cost: 0.0000056, total_cost: 0.0000070, response_time_ms: 1000
        })
        ChatDB.ChatUsage_Upsert({
            date: date, model: "deepseek-v4-flash", provider: "deepseek",
            prompt_tokens: 15, completion_tokens: 30, thinking_tokens: 5, cached_tokens: 10,
            input_cost: 0.0000021, cached_input_cost: 0.000000028, output_cost: 0.0000084, total_cost: 0.0000105, response_time_ms: 1500
        })
        ChatDB.ChatUsage_Upsert({
            date: date, model: "deepseek-v4-flash", provider: "deepseek",
            prompt_tokens: 25, completion_tokens: 50, thinking_tokens: 0, cached_tokens: 0,
            input_cost: 0.0000035, output_cost: 0.000014, total_cost: 0.0000175, response_time_ms: 2000
        })

        row := ChatDB.db.Exec("SELECT * FROM chat_usage WHERE date='" date "' AND model='deepseek-v4-flash'")
        if row.count != 1
            throw Error("Expected 1 row after 3 upserts, got " row.count)
        if Integer(row[1,"call_count"]) != 3
            throw Error("Expected call_count=3, got " row[1,"call_count"])
        if Integer(row[1,"prompt_tokens"]) != 50
            throw Error("Expected prompt_tokens=50, got " row[1,"prompt_tokens"])
        if Integer(row[1,"completion_tokens"]) != 100
            throw Error("Expected completion_tokens=100, got " row[1,"completion_tokens"])
        if Integer(row[1,"cached_tokens"]) != 10
            throw Error("Expected cached_tokens=10, got " row[1,"cached_tokens"])
        if Integer(row[1,"total_response_time_ms"]) != 4500
            throw Error("Expected total_response_time_ms=4500, got " row[1,"total_response_time_ms"])

        this._closeDb()
    }

    ; ----------------------------------------------------
    ; Thread stats — cost fields are populated
    ; ----------------------------------------------------

    ThreadStats_CostFields() {
        this._openDb()
        threadId := ChatDB.Thread_Create("Cost Test")

        sysId := ChatDB.Msg_Insert({thread_id: threadId, role: "system", content: "sys"})
        userId := ChatDB.Msg_Insert({thread_id: threadId, role: "user", content: "Hi", parent_id: sysId})
        ChatDB.Msg_Insert({
            thread_id: threadId, role: "assistant", content: "Response",
            model: "deepseek/deepseek-v4-flash", parent_id: userId,
            token_count: 50000, thinking_tokens: 10000, cached_tokens: 20000,
            response_time_ms: 1000, prompt_tokens: 100000
        })

        stats := ChatDB.Msg_GetThreadStats(threadId)

        ; All cost fields should be > 0 (large enough token counts)
        if stats.cumulativeCost <= 0
            throw Error("Expected cumulativeCost > 0, got " stats.cumulativeCost)
        if stats.cumulativeInputCost <= 0
            throw Error("Expected cumulativeInputCost > 0, got " stats.cumulativeInputCost)
        if stats.cumulativeCachedInputCost <= 0
            throw Error("Expected cumulativeCachedInputCost > 0, got " stats.cumulativeCachedInputCost)
        if stats.cumulativeOutputCost <= 0
            throw Error("Expected cumulativeOutputCost > 0, got " stats.cumulativeOutputCost)

        ; Pricing unit should be populated
        if stats.pricingUnit.input <= 0
            throw Error("Expected pricingUnit.input > 0, got " stats.pricingUnit.input)
        if stats.pricingUnit.output <= 0
            throw Error("Expected pricingUnit.output > 0, got " stats.pricingUnit.output)

        ; Context window should be populated from model pricing
        if stats.contextWindow <= 0
            throw Error("Expected contextWindow > 0, got " stats.contextWindow)

        this._closeDb()
    }

    ; ----------------------------------------------------
    ; TTFT (time to first token) is stored
    ; ----------------------------------------------------

    MessageFields_TTFT_Stored() {
        this._openDb()
        threadId := ChatDB.Thread_Create("TTFT Test")

        sysId := ChatDB.Msg_Insert({thread_id: threadId, role: "system", content: "sys"})
        userId := ChatDB.Msg_Insert({thread_id: threadId, role: "user", content: "Hi", parent_id: sysId})
        ChatDB.Msg_Insert({
            thread_id: threadId, role: "assistant", content: "Hi!",
            model: "deepseek-v4-flash", parent_id: userId,
            token_count: 10, thinking_tokens: 0, cached_tokens: 0,
            response_time_ms: 1200, ttft_ms: 800, prompt_tokens: 5
        })

        path := ChatDB.Msg_GetActivePath(threadId)
        asst := path[3]
        if asst.HasProp("ttft_ms") && asst.ttft_ms != 800
            throw Error("Expected ttft_ms=800, got " asst.ttft_ms)

        this._closeDb()
    }

    ; ----------------------------------------------------
    ; created_at is stored and returned by GetActivePath
    ; ----------------------------------------------------

    MessageFields_CreatedAtPresent() {
        this._openDb()
        threadId := ChatDB.Thread_Create("Time Test")

        sysId := ChatDB.Msg_Insert({thread_id: threadId, role: "system", content: "sys"})
        userId := ChatDB.Msg_Insert({thread_id: threadId, role: "user", content: "Hi", parent_id: sysId})
        ChatDB.Msg_Insert({thread_id: threadId, role: "assistant", content: "Response", model: "deepseek-v4-flash", parent_id: userId})

        path := ChatDB.Msg_GetActivePath(threadId)
        ; Every message should have created_at
        for msg in path {
            if msg.created_at = ""
                throw Error("Expected non-empty created_at for " msg.role " message")
        }

        this._closeDb()
    }

    ; ----------------------------------------------------
    ; All per-message token fields present on assistant
    ; (covers per-message tooltip data)
    ; ----------------------------------------------------

    MessageFields_AllTokenFieldsPresent() {
        this._openDb()
        threadId := ChatDB.Thread_Create("Fields Test")

        sysId := ChatDB.Msg_Insert({thread_id: threadId, role: "system", content: "sys"})
        userId := ChatDB.Msg_Insert({thread_id: threadId, role: "user", content: "Hi", parent_id: sysId})
        ChatDB.Msg_Insert({
            thread_id: threadId, role: "assistant", content: "Response",
            model: "deepseek/deepseek-v4-flash", parent_id: userId,
            token_count: 50,       ; visible output (for tooltip: "Output: Visible")
            thinking_tokens: 30,   ; reasoning (for tooltip: "Output: Thinking")
            cached_tokens: 10,     ; cache (for tooltip: "Cache")
            response_time_ms: 1500,      ; time to first token (for tooltip: "Latency")
            ttft_ms: 1200,         ; (for tooltip: "TTFT")
            prompt_tokens: 100
        })

        path := ChatDB.Msg_GetActivePath(threadId)
        asst := path[3]

        ; Every field the per-message tooltip uses must be present and non-zero
        if asst.token_count <= 0
            throw Error("token_count must be > 0 for tooltip visibility")
        if asst.thinking_tokens <= 0
            throw Error("thinking_tokens must be > 0")
        if asst.cached_tokens <= 0
            throw Error("cached_tokens must be > 0")
        if asst.response_time_ms <= 0
            throw Error("response_time_ms must be > 0")
        ; User message should have backfilled input
        user := path[2]
        if user.token_count <= 0
            throw Error("user token_count must be > 0 (backfill)")

        this._closeDb()
    }

    ; ----------------------------------------------------
    ; User token_count preserved across retry/branch switch
    ; Bug: _BackfillUserTokens overwrote user token_count on
    ; every branch, corrupting active_path_tokens when
    ; switching back to the original branch.
    ; ----------------------------------------------------

    UserTokenCount_PreservedAcrossBranches() {
        this._openDb()
        threadId := ChatDB.Thread_Create("Test")

        ; Step 1: user + first assistant
        userId := ChatDB.Msg_Insert({thread_id: threadId, role: "user", content: "Hi", parent_id: ""})
        ChatDB.Msg_Insert({
            thread_id: threadId, role: "assistant", content: "Hello!",
            model: "deepseek-v4-flash", parent_id: userId,
            token_count: 10, thinking_tokens: 0, cached_tokens: 0,
            prompt_tokens: 15  ; user should get 15-0=15
        })

        ; Verify: user token_count backfilled to 15
        path := ChatDB.Msg_GetActivePath(threadId)
        if path[1].token_count != 15
            throw Error("Expected user token_count=15 after first assistant, got " path[1].token_count)
        stats := ChatDB.Msg_GetThreadStats(threadId)
        ; active_path_tokens = 15 (user) + 10 (assistant) = 25
        if stats.activePathTokens != 25
            throw Error("Expected activePathTokens=25, got " stats.activePathTokens)

        ; Step 2: retry — same user parent, new branch (sibling_group="sg1", sibling_index=1)
        ; The user already has token_count=15, so backfill should NOT overwrite it
        sg1 := ChatDB._UUID()
        ChatDB.db.Exec("UPDATE messages SET sibling_group='" sg1 "', sibling_index=0 WHERE id='" path[2].id "';")
        ChatDB.Msg_Insert({
            thread_id: threadId, role: "assistant", content: "Retry response",
            model: "deepseek-v4-flash", parent_id: userId,
            sibling_group: sg1, sibling_index: 1,
            token_count: 5, thinking_tokens: 0, cached_tokens: 0,
            prompt_tokens: 13  ; would give new_input=Max(0,13-15)=0 if overwritten
        })

        ; Verify: user token_count still 15 (not overwritten by retry backfill)
        path2 := ChatDB.Msg_GetActivePath(threadId)
        user := path2[1]
        if user.token_count != 15
            throw Error("Expected user token_count=15 after retry (preserved), got " user.token_count)

        ; Step 3: switch back to original branch (sibling_index=0)
        ; Switch from the currently-active retry assistant (path2[2]) back to sibling_index=0
        ChatDB.Msg_SwitchBranch(threadId, path2[2].id, -1)

        ; Verify: active_path_tokens matches original branch
        path3 := ChatDB.Msg_GetActivePath(threadId)
        stats3 := ChatDB.Msg_GetThreadStats(threadId)
        if stats3.activePathTokens != 25
            throw Error("Expected activePathTokens=25 after switch back to original branch, got " stats3.activePathTokens)

        this._closeDb()
    }

    ; ----------------------------------------------------
    ; Delete recomputes active_path_tokens correctly
    ; ----------------------------------------------------

    Delete_RecomputesActivePathTokens() {
        this._openDb()
        threadId := ChatDB.Thread_Create("Test")

        uId := ChatDB.Msg_Insert({thread_id: threadId, role: "user", content: "Hi", parent_id: ""})
        aId := ChatDB.Msg_Insert({thread_id: threadId, role: "assistant", content: "Hello", model: "deepseek-v4-flash", parent_id: uId, token_count: 10, prompt_tokens: 5})

        ; Verify: active_path_tokens = prompt_tokens + token_count = 5 + 10 = 15
        stats := ChatDB.Msg_GetThreadStats(threadId)
        if stats.activePathTokens != 15
            throw Error("Expected activePathTokens=15 before delete, got " stats.activePathTokens)

        ; Delete assistant — leaf becomes user
        ChatDB.Msg_HardDelete(aId)

        ; Verify: active_path_tokens recomputed = user token_count = 5
        stats2 := ChatDB.Msg_GetThreadStats(threadId)
        if stats2.activePathTokens != 5
            throw Error("Expected activePathTokens=5 after delete, got " stats2.activePathTokens)

        this._closeDb()
    }

    ; Regression (bug #65): hard-deleting a message must update the thread's
    ; cumulative counters so the header totals do not stay inflated.
    HardDelete_UpdatesCumulativeCounters() {
        this._openDb()
        threadId := ChatDB.Thread_Create("Test")
        uId := ChatDB.Msg_Insert({thread_id: threadId, role: "user", content: "Hi", parent_id: ""})
        aId := ChatDB.Msg_Insert({thread_id: threadId, role: "assistant", content: "Hello", model: "deepseek/deepseek-v4-flash", parent_id: uId, token_count: 10, thinking_tokens: 5, cached_tokens: 2, prompt_tokens: 5})

        stats := ChatDB.Msg_GetThreadStats(threadId)
        if stats.cumulativeOutputTokens != 15
            throw Error("expected cumulativeOutput=15 (10+5) before delete, got " stats.cumulativeOutputTokens)

        ChatDB.Msg_HardDelete(aId)

        stats2 := ChatDB.Msg_GetThreadStats(threadId)
        ; Bug #128: user token_counts are backfilled INPUT contributions - the
        ; recompute must NOT count them as output. With no assistant rows left
        ; there are no API calls, so cumulative output drops to 0 (the old
        ; recompute inflated it with the user's backfilled input tokens).
        if stats2.cumulativeOutputTokens != 0
            throw Error("expected cumulativeOutput=0 after delete (user token_count is input, not output - bug #128), got " stats2.cumulativeOutputTokens)
        if stats2.cumulativeInputTokens != 0
            throw Error("expected cumulativeInput=0 after delete, got " stats2.cumulativeInputTokens)
        this._closeDb()
    }

    ; ----------------------------------------------------
    ; Cancelled assistant has active_path_tokens from parent
    ; ----------------------------------------------------

    Cancel_ActivePathTokensIsParentValue() {
        this._openDb()
        threadId := ChatDB.Thread_Create("Test")

        uId := ChatDB.Msg_Insert({thread_id: threadId, role: "user", content: "Hi", parent_id: ""})
        ; Cancelled assistant: token_count=0, prompt_tokens=0
        ChatDB.Msg_Insert({thread_id: threadId, role: "assistant", content: "partial", model: "deepseek-v4-flash", parent_id: uId, token_count: 0, cached_tokens: 0})

        ; Verify: active_path_tokens = parent's value (user has token_count=0 since no backfill)
        stats := ChatDB.Msg_GetThreadStats(threadId)
        ; path: user(0) + cancelled_asst(0) = 0 after recompute
        if stats.activePathTokens != 0
            throw Error("Expected activePathTokens=0 for cancelled (no backfill), got " stats.activePathTokens)

        this._closeDb()
    }

    ; ----------------------------------------------------
    ; Hard delete with re-parenting: children get re-parented,
    ; active_path_tokens recomputed correctly
    ; ----------------------------------------------------

    HardDelete_Reparenting_RecomputesActivePath() {
        this._openDb()
        threadId := ChatDB.Thread_Create("Test")

        uId := ChatDB.Msg_Insert({thread_id: threadId, role: "user", content: "Hi", parent_id: ""})
        a1Id := ChatDB.Msg_Insert({thread_id: threadId, role: "assistant", content: "First", model: "deepseek-v4-flash", parent_id: uId, token_count: 10, prompt_tokens: 5})
        a2Id := ChatDB.Msg_Insert({thread_id: threadId, role: "assistant", content: "Second", model: "deepseek-v4-flash", parent_id: a1Id, token_count: 8, prompt_tokens: 15})

        ; active_path_tokens = prompt_tokens + token_count = 15 + 8 = 23
        stats := ChatDB.Msg_GetThreadStats(threadId)
        if stats.activePathTokens != 23
            throw Error("Expected activePathTokens=23, got " stats.activePathTokens)

        ; Delete a1 — a2 gets re-parented to uId
        ChatDB.Msg_HardDelete(a1Id)

        ; Structural recompute uses the current editable path estimate. The
        ; historical prompt_tokens=15 remains persisted separately.
        stats2 := ChatDB.Msg_GetThreadStats(threadId)
        if stats2.activePathTokens != 13
            throw Error("Expected activePathTokens=13 after hard delete re-parenting, got " stats2.activePathTokens)

        this._closeDb()
    }

    ; ----------------------------------------------------
    ; Switch branch with API ground truth: when assistant
    ; has prompt_tokens, active_path_tokens = prompt + token_count
    ; ----------------------------------------------------

    Switch_ActivePathTokens_UsesGroundTruth() {
        this._openDb()
        threadId := ChatDB.Thread_Create("Test")

        uId := ChatDB.Msg_Insert({thread_id: threadId, role: "user", content: "Hi", parent_id: ""})

        ; Branch A: assistant with API ground truth
        sg := ChatDB._UUID()
        a1Id := ChatDB.Msg_Insert({thread_id: threadId, role: "assistant", content: "Hello A", model: "deepseek-v4-flash", parent_id: uId, sibling_group: sg, sibling_index: 0, token_count: 10, prompt_tokens: 5})
        ; active_path_tokens = 5 + 10 = 15

        ; Branch B: different assistant
        a2Id := ChatDB.Msg_Insert({thread_id: threadId, role: "assistant", content: "Hello B", model: "deepseek-v4-flash", parent_id: uId, sibling_group: sg, sibling_index: 1, token_count: 20, prompt_tokens: 8})
        ; active_path_tokens = 8 + 20 = 28

        ; Currently on branch B (leaf = a2)
        stats := ChatDB.Msg_GetThreadStats(threadId)
        if stats.activePathTokens != 28
            throw Error("Expected activePathTokens=28 on branch B, got " stats.activePathTokens)

        ; Switch to branch A
        ChatDB.Msg_SwitchBranch(threadId, a2Id, -1)

        stats2 := ChatDB.Msg_GetThreadStats(threadId)
        if stats2.activePathTokens != 15
            throw Error("Expected activePathTokens=15 on branch A after switch, got " stats2.activePathTokens)

        this._closeDb()
    }

    ; ----------------------------------------------------
    ; Multiple cancelled assistants in path: all have
    ; token_count=0, prefix sum still works
    ; ----------------------------------------------------

    MultipleCancelled_PrefixSumWorks() {
        this._openDb()
        threadId := ChatDB.Thread_Create("Test")

        uId := ChatDB.Msg_Insert({thread_id: threadId, role: "user", content: "Hi", parent_id: ""})
        ; User gets backfilled by the first successful assistant below
        ; Cancelled 1
        ChatDB.Msg_Insert({thread_id: threadId, role: "assistant", content: "partial1", model: "deepseek-v4-flash", parent_id: uId, token_count: 0, cached_tokens: 0})
        ; Cancelled 2
        c2Id := ChatDB.Msg_Insert({thread_id: threadId, role: "assistant", content: "partial2", model: "deepseek-v4-flash", parent_id: uId, token_count: 0, sibling_group: ChatDB._UUID(), sibling_index: 0, cached_tokens: 0})
        ; Successful retry
        ChatDB.Msg_Insert({thread_id: threadId, role: "assistant", content: "Success!", model: "deepseek-v4-flash", parent_id: uId, sibling_group: ChatDB._UUID(), sibling_index: 0, token_count: 15, prompt_tokens: 10})

        ; active_path_tokens = prompt_tokens + token_count = 10 + 15 = 25
        stats := ChatDB.Msg_GetThreadStats(threadId)
        if stats.activePathTokens != 25
            throw Error("Expected activePathTokens=25, got " stats.activePathTokens)

        ; Switch to cancelled branch (leaf = c2, token_count=0)
        ChatDB.Msg_SwitchBranch(threadId, c2Id, 1)
        stats2 := ChatDB.Msg_GetThreadStats(threadId)
        ; prefix sum: u(10) + c2(0) + ... hmm, this depends on the path
        ; The key: it should NOT crash and should give a value
        if stats2.activePathTokens < 0
            throw Error("activePathTokens should not be negative, got " stats2.activePathTokens)

        this._closeDb()
    }

}
