; ======================================================
; UsageFlow.test.ahk — Integration tests for token tracking
;
; Tests end-to-end flows: chat → chat_usage, commands →
; command_usage, dashboard queries, cost tracking.
; ======================================================

class UsageFlowTest {

    static __New() {
        RegisterTestClass("UsageFlowTest")
    }

    _openDb() {
        if ChatDB.isOpen {
            oldPath := ChatDB.dbPath
            ChatDB.Close()
            try FileDelete(oldPath)
        }
        ChatDB.Open(A_Temp "\test_usageflow_" A_TickCount ".db")
    }

    _closeDb() {
        if ChatDB.isOpen {
            dbPath := ChatDB.dbPath
            ChatDB.Close()
            try FileDelete(dbPath)
        }
    }

    ; ----------------------------------------------------
    ; Full chat flow → chat_usage → dashboard query
    ; ----------------------------------------------------

    ChatFlow_PopulatesChatUsage() {
        this._openDb()
        threadId := ChatDB.Thread_Create("Usage Flow")

        ; Simulate a complete exchange with API data
        sysId := ChatDB.Msg_Insert({thread_id: threadId, role: "system", content: "sys"})
        userId := ChatDB.Msg_Insert({thread_id: threadId, role: "user", content: "Hi", parent_id: sysId})
        ChatDB.Msg_Insert({
            thread_id: threadId, role: "assistant", content: "Hello!",
            model: "deepseek/deepseek-v4-flash",
            parent_id: userId,
            token_count: 50, thinking_tokens: 100, cached_tokens: 0,
            response_time_ms: 1500, prompt_tokens: 10
        })

        ; Verify chat_usage has one row with correct aggregation
        date := FormatTime(, "yyyy-MM-dd")
        row := ChatDB.db.Exec("SELECT * FROM chat_usage WHERE date='" date "' AND model='deepseek/deepseek-v4-flash'")
        if row.count != 1
            throw Error("Expected 1 chat_usage row, got " row.count)
        if Integer(row[1,"call_count"]) != 1
            throw Error("Expected call_count=1, got " row[1,"call_count"])
        if Integer(row[1,"prompt_tokens"]) != 10
            throw Error("Expected prompt_tokens=10, got " row[1,"prompt_tokens"])
        if Integer(row[1,"completion_tokens"]) != 150
            throw Error("Expected completion_tokens=150, got " row[1,"completion_tokens"])
        if Integer(row[1,"cached_tokens"]) != 0
            throw Error("Expected cached_tokens=0, got " row[1,"cached_tokens"])

        ; Verify dashboard query returns it
        filters := Map("timeRange", "all", "model", "", "type", "all")
        result := ChatDB.Usage_Query(filters)
        if result.chat.Length != 1
            throw Error("Dashboard: Expected 1 chat row, got " result.chat.Length)

        this._closeDb()
    }

    ; ----------------------------------------------------
    ; Commands + chat together → dashboard shows both
    ; ----------------------------------------------------

    ChatAndCommands_DashboardShowsBoth() {
        this._openDb()

        ; Chat
        ChatDB.ChatUsage_Upsert({
            date: FormatTime(, "yyyy-MM-dd"), model: "deepseek-v4-flash", provider: "deepseek",
            prompt_tokens: 100, completion_tokens: 200, thinking_tokens: 0, cached_tokens: 0,
            input_cost: 0.000014, output_cost: 0.000056, total_cost: 0.000070, response_time_ms: 1000
        })

        ; Command
        ChatDB.CommandUsage_Upsert({
            date: FormatTime(, "yyyy-MM-dd"), model: "deepseek-v4-flash", provider: "deepseek",
            command_name: "Refine",
            prompt_tokens: 50, completion_tokens: 30, thinking_tokens: 0, cached_tokens: 0,
            input_cost: 0.000007, output_cost: 0.0000084, total_cost: 0.0000154, response_time_ms: 800
        })

        ; All types
        all := ChatDB.Usage_Query(Map("timeRange", "all", "model", "", "type", "all"))
        if all.chat.Length != 1 || all.commands.Length != 1
            throw Error("All: Expected 1 chat + 1 cmd, got " all.chat.Length "+" all.commands.Length)

        ; Chat only
        chatOnly := ChatDB.Usage_Query(Map("timeRange", "all", "model", "", "type", "chat"))
        if chatOnly.chat.Length != 1 || chatOnly.commands.Length != 0
            throw Error("Chat: Expected 1 chat + 0 cmd, got " chatOnly.chat.Length "+" chatOnly.commands.Length)

        ; Commands only
        cmdOnly := ChatDB.Usage_Query(Map("timeRange", "all", "model", "", "type", "command"))
        if cmdOnly.chat.Length != 0 || cmdOnly.commands.Length != 1
            throw Error("Cmd: Expected 0 chat + 1 cmd, got " cmdOnly.chat.Length "+" cmdOnly.commands.Length)

        this._closeDb()
    }

    ; ----------------------------------------------------
    ; Multi-model usage — each tracked separately
    ; ----------------------------------------------------

    MultiModel_SeparateAggregation() {
        this._openDb()
        date := FormatTime(, "yyyy-MM-dd")

        ChatDB.ChatUsage_Upsert({
            date: date, model: "deepseek-v4-flash", provider: "deepseek",
            prompt_tokens: 10, completion_tokens: 20, thinking_tokens: 0, cached_tokens: 0,
            input_cost: 0.0000014, output_cost: 0.0000056, total_cost: 0.0000070, response_time_ms: 500
        })
        ChatDB.ChatUsage_Upsert({
            date: date, model: "gemini-2.5-flash", provider: "google",
            prompt_tokens: 30, completion_tokens: 40, thinking_tokens: 0, cached_tokens: 0,
            input_cost: 0.000009, output_cost: 0.000100, total_cost: 0.000109, response_time_ms: 600
        })

        result := ChatDB.Usage_Query(Map("timeRange", "all", "model", "", "type", "all"))
        if result.chat.Length != 2
            throw Error("Expected 2 models, got " result.chat.Length)

        ; Verify each model has independent data
        for row in result.chat {
            if row.model = "deepseek-v4-flash" {
                if row.input_tokens != 10
                    throw Error("DeepSeek: Expected input=10, got " row.input_tokens)
            } else if row.model = "gemini-2.5-flash" {
                if row.input_tokens != 30
                    throw Error("Gemini: Expected input=30, got " row.input_tokens)
            }
        }

        this._closeDb()
    }

    ; ----------------------------------------------------
    ; Time range filtering — day vs month
    ; ----------------------------------------------------

    TimeRange_FiltersCorrectly() {
        this._openDb()
        date := FormatTime(, "yyyy-MM-dd")

        ChatDB.ChatUsage_Upsert({
            date: date, model: "deepseek-v4-flash", provider: "deepseek",
            prompt_tokens: 10, completion_tokens: 20, thinking_tokens: 0, cached_tokens: 0,
            input_cost: 0.0000014, output_cost: 0.0000056, total_cost: 0.0000070, response_time_ms: 500
        })

        ; Day filter — should include today
        dayResult := ChatDB.Usage_Query(Map("timeRange", "day", "model", "", "type", "all"))
        if dayResult.chat.Length != 1
            throw Error("Day filter: Expected 1 row, got " dayResult.chat.Length)

        ; Month filter — should include today
        monthResult := ChatDB.Usage_Query(Map("timeRange", "month", "model", "", "type", "all"))
        if monthResult.chat.Length != 1
            throw Error("Month filter: Expected 1 row, got " monthResult.chat.Length)

        this._closeDb()
    }

    ; ----------------------------------------------------
    ; Full pipeline: Msg_Insert → chat_usage → cost → dashboard
    ; ----------------------------------------------------

    FullPipeline_InsertToDashboard() {
        this._openDb()
        threadId := ChatDB.Thread_Create("Pipeline")

        ; Two exchanges — use large token counts for visible cost
        sysId := ChatDB.Msg_Insert({thread_id: threadId, role: "system", content: "sys"})
        u1Id := ChatDB.Msg_Insert({thread_id: threadId, role: "user", content: "Q1", parent_id: sysId})
        a1Id := ChatDB.Msg_Insert({
            thread_id: threadId, role: "assistant", content: "A1",
            model: "deepseek/deepseek-v4-flash", parent_id: u1Id,
            token_count: 50000, thinking_tokens: 10000, cached_tokens: 20000,
            response_time_ms: 1000, prompt_tokens: 150000
        })
        u2Id := ChatDB.Msg_Insert({thread_id: threadId, role: "user", content: "Q2", parent_id: a1Id})
        ChatDB.Msg_Insert({
            thread_id: threadId, role: "assistant", content: "A2",
            model: "deepseek/deepseek-v4-flash", parent_id: u2Id,
            token_count: 80000, thinking_tokens: 0, cached_tokens: 10000,
            response_time_ms: 800, prompt_tokens: 250000
        })

        ; Verify chat_usage aggregated both calls
        date := FormatTime(, "yyyy-MM-dd")
        row := ChatDB.db.Exec("SELECT * FROM chat_usage WHERE date='" date "' AND model='deepseek/deepseek-v4-flash'")
        if row.count != 1
            throw Error("Expected 1 chat_usage row, got " row.count)
        if Integer(row[1,"call_count"]) != 2
            throw Error("Expected call_count=2, got " row[1,"call_count"])
        if Integer(row[1,"cached_tokens"]) != 30000
            throw Error("Expected cached_tokens=30000, got " row[1,"cached_tokens"])

        ; Verify cost > 0
        if Number(row[1,"total_cost"]) <= 0
            throw Error("Expected total_cost > 0, got " row[1,"total_cost"])
        if Number(row[1,"cached_input_cost"]) <= 0
            throw Error("Expected cached_input_cost > 0, got " row[1,"cached_input_cost"])

        this._closeDb()
        ; ----------------------------------------------------
        ; Edit → send new branch → cumulative counters + chat_usage
        ; ----------------------------------------------------
    
        EditSend_CumulativeCounters() {
            this._openDb()
            threadId := ChatDB.Thread_Create("Edit Send Test")
            sysId := ChatDB.Msg_Insert({thread_id: threadId, role: "system", content: "sys"})
            uId := ChatDB.Msg_Insert({thread_id: threadId, role: "user", content: "Hello", parent_id: sysId})
            ChatDB.Msg_Insert({
                thread_id: threadId, role: "assistant", content: "Hi!",
                model: "deepseek-v4-flash", parent_id: uId,
                token_count: 100, thinking_tokens: 0, cached_tokens: 0,
                response_time_ms: 1000, prompt_tokens: 50
            })
    
            ; Edit user message content
            ChatDB.Msg_Edit(uId, "Hello edited")
            ; Send new reply on edited branch (different sibling)
            sg := ChatDB._UUID()
            ChatDB.db.Exec("UPDATE messages SET sibling_group='" sg "', sibling_index=0 WHERE id='" uId "';")
            ChatDB.Msg_Insert({
                thread_id: threadId, role: "assistant", content: "Edited reply",
                model: "deepseek-v4-flash", parent_id: uId,
                sibling_group: sg, sibling_index: 1,
                token_count: 50, thinking_tokens: 0, cached_tokens: 20,
                response_time_ms: 500, prompt_tokens: 30
            })
    
            ; chat_usage should have call_count=2 (both assistants, same model/date)
            date := FormatTime(, "yyyy-MM-dd")
            row := ChatDB.db.Exec("SELECT * FROM chat_usage WHERE date='" date "' AND model='deepseek-v4-flash'")
            if Integer(row[1,"call_count"]) != 2
                throw Error("Expected call_count=2 after edit+send, got " row[1,"call_count"])
            if Integer(row[1,"cached_tokens"]) != 20
                throw Error("Expected cached_tokens=20, got " row[1,"cached_tokens"])
            this._closeDb()
        }
    
        ; ----------------------------------------------------
        ; Retry → switch back → costs isolated per branch
        ; ----------------------------------------------------
    
        RetrySwitch_CostPreserved() {
            this._openDb()
            threadId := ChatDB.Thread_Create("Retry Switch Test")
            sysId := ChatDB.Msg_Insert({thread_id: threadId, role: "system", content: "sys"})
            uId := ChatDB.Msg_Insert({thread_id: threadId, role: "user", content: "Q", parent_id: sysId})
    
            ; Branch A: expensive model
            ChatDB.Msg_Insert({
                thread_id: threadId, role: "assistant", content: "A",
                model: "openai/gpt-4.1", parent_id: uId,
                token_count: 200, thinking_tokens: 50, cached_tokens: 0,
                response_time_ms: 2000, prompt_tokens: 500
            })
    
            ; Branch B: cheap model (retry)
            sg := ChatDB._UUID()
            ChatDB.db.Exec("UPDATE messages SET sibling_group='" sg "', sibling_index=0 WHERE id='" uId "';")
            ChatDB.Msg_Insert({
                thread_id: threadId, role: "assistant", content: "B",
                model: "deepseek-v4-flash", parent_id: uId,
                sibling_group: sg, sibling_index: 1,
                token_count: 50, thinking_tokens: 0, cached_tokens: 10,
                response_time_ms: 800, prompt_tokens: 100
            })
    
            ; Both providers should have independent rows
            date := FormatTime(, "yyyy-MM-dd")
            openaiRow := ChatDB.db.Exec("SELECT * FROM chat_usage WHERE date='" date "' AND provider='openai'")
            deepseekRow := ChatDB.db.Exec("SELECT * FROM chat_usage WHERE date='" date "' AND provider='deepseek'")
            if openaiRow.count != 1
                throw Error("Expected 1 openai row, got " openaiRow.count)
            if deepseekRow.count != 1
                throw Error("Expected 1 deepseek row, got " deepseekRow.count)
            ; Costs must be > 0 for both (different pricing models)
            if Number(openaiRow[1,"total_cost"]) <= 0
                throw Error("Expected openai total_cost > 0")
            if Number(deepseekRow[1,"total_cost"]) <= 0
                throw Error("Expected deepseek total_cost > 0")
            this._closeDb()
        }
    
        ; ----------------------------------------------------
        ; Multi-provider — each provider tracked independently
        ; ----------------------------------------------------
    
        MultiProvider_CostTracking() {
            this._openDb()
            date := FormatTime(, "yyyy-MM-dd")
            ; DeepSeek
            ChatDB.ChatUsage_Upsert({
                date: date, model: "deepseek-v4-flash", provider: "deepseek",
                prompt_tokens: 1000, completion_tokens: 500, thinking_tokens: 0, cached_tokens: 0,
                input_cost: 0.00014, output_cost: 0.00014, total_cost: 0.00028,
                response_time_ms: 1000, ttft_ms: 200
            })
            ; OpenAI (higher pricing)
            ChatDB.ChatUsage_Upsert({
                date: date, model: "gpt-4.1", provider: "openai",
                prompt_tokens: 1000, completion_tokens: 500, thinking_tokens: 0, cached_tokens: 0,
                input_cost: 0.003, output_cost: 0.008, total_cost: 0.011,
                response_time_ms: 1500, ttft_ms: 400
            })
    
            ; Provider filter — deepseek only
            dsResult := ChatDB.Usage_Query(Map("timeRange", "all", "model", "", "provider", "deepseek", "type", "all"))
            if dsResult.chat.Length != 1
                throw Error("Provider deepseek: expected 1 row, got " dsResult.chat.Length)
            if dsResult.chat[1].total_cost != 0.00028
                throw Error("DeepSeek cost: expected 0.00028, got " dsResult.chat[1].total_cost)
    
            ; All — both providers
            allResult := ChatDB.Usage_Query(Map("timeRange", "all", "model", "", "type", "all"))
            totalCost := 0.0
            for row in allResult.chat
                totalCost += row.total_cost
            if totalCost != 0.01128
                throw Error("Combined cost: expected 0.01128, got " totalCost)
            this._closeDb()
        }
    
        ; ----------------------------------------------------
        ; Dashboard speed calculation — output / response_time
        ; Verifies: speed = output_tokens / (total_response_time_ms / 1000)
        ; ----------------------------------------------------
    
        Dashboard_SpeedCalculation() {
            this._openDb()
            date := FormatTime(, "yyyy-MM-dd")
            ; 1000 output tokens, 2000ms response time → speed = 500 tok/s
            ChatDB.ChatUsage_Upsert({
                date: date, model: "deepseek-v4-flash", provider: "deepseek",
                prompt_tokens: 100, completion_tokens: 1000, thinking_tokens: 200, cached_tokens: 0,
                input_cost: 0.000014, output_cost: 0.00028, total_cost: 0.000294,
                response_time_ms: 2000, ttft_ms: 300
            })
            ; Command with different timing
            ChatDB.CommandUsage_Upsert({
                date: date, model: "deepseek-v4-flash", provider: "deepseek", command_name: "Refine",
                prompt_tokens: 50, completion_tokens: 500, thinking_tokens: 0, cached_tokens: 0,
                input_cost: 0.000007, output_cost: 0.00014, total_cost: 0.000147,
                response_time_ms: 1000, ttft_ms: 150
            })
    
            result := ChatDB.Usage_Query(Map("timeRange", "all", "model", "", "type", "all"))
            ; Total output = chat(1000) + command(500) = 1500
            ; Total response_time = 2000 + 1000 = 3000ms
            ; Speed = 1500 / 3.0 = 500 tok/s
            totalOutput := 0
            totalResponseTime := 0
            for row in result.chat {
                totalOutput += row.output_tokens
                totalResponseTime += row.total_response_time_ms
            }
            for row in result.commands {
                totalOutput += row.completion_tokens
                totalResponseTime += row.total_response_time_ms
            }
            if totalOutput != 1500
                throw Error("Expected totalOutput=1500, got " totalOutput)
            if totalResponseTime != 3000
                throw Error("Expected totalResponseTime=3000, got " totalResponseTime)
            speed := Round(totalOutput / (totalResponseTime / 1000.0))
            if speed != 500
                throw Error("Expected speed=500 tok/s, got " speed)
            this._closeDb()
        }
    
        ; ----------------------------------------------------
        ; Dashboard TTFT avg — total_ttft_ms / calls
        ; Verifies: avg ttft = total_ttft_ms / total_calls
        ; ----------------------------------------------------
    
        Dashboard_TtftAvgCalculation() {
            this._openDb()
            date := FormatTime(, "yyyy-MM-dd")
            ; Chat: ttft=300ms, call_count=1
            ChatDB.ChatUsage_Upsert({
                date: date, model: "deepseek-v4-flash", provider: "deepseek",
                prompt_tokens: 100, completion_tokens: 200, thinking_tokens: 0, cached_tokens: 0,
                input_cost: 0.000014, output_cost: 0.000056, total_cost: 0.000070,
                response_time_ms: 1000, ttft_ms: 300
            })
            ; Command: ttft=150ms, call_count=1
            ChatDB.CommandUsage_Upsert({
                date: date, model: "deepseek-v4-flash", provider: "deepseek", command_name: "Summarize",
                prompt_tokens: 50, completion_tokens: 100, thinking_tokens: 0, cached_tokens: 0,
                input_cost: 0.000007, output_cost: 0.000028, total_cost: 0.000035,
                response_time_ms: 800, ttft_ms: 150
            })
    
            result := ChatDB.Usage_Query(Map("timeRange", "all", "model", "", "type", "all"))
            totalTtft := 0, totalCalls := 0
            for row in result.chat {
                totalTtft += row.total_ttft_ms
                totalCalls += row.message_count
            }
            for row in result.commands {
                totalTtft += row.total_ttft_ms
                totalCalls += row.call_count
            }
            if totalTtft != 450
                throw Error("Expected totalTtft=450 (300+150), got " totalTtft)
            if totalCalls != 2
                throw Error("Expected totalCalls=2, got " totalCalls)
            avgTtft := Round(totalTtft / totalCalls)
            if avgTtft != 225
                throw Error("Expected avgTtft=225ms (450/2), got " avgTtft)
            this._closeDb()
        }
    
    }

}
