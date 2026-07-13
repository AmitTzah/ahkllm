# Implementation Plan: Fix Token Usage Tracking + Usage Dashboard

## §1 Overall Project

AutoHotkey v2 desktop application providing hotkey-activated LLM access via a WebView2 chat interface. Supports both persistent chat threads (with branching, attachments, streaming) and inline commands (replace/append text). Uses SQLite for persistence, cURL for API calls. The project has a two-process architecture (Main + ChatWindow sub-process) with IPC via window messages.

## §2 This Feature

Overhauls token tracking across the entire application and adds a full usage dashboard. Replaces character-based token estimation with real API data, introduces per-message token attribution via subtraction, adds a `command_usage` table for non-chat API calls, adds per-message token info tooltips in the chat UI, and builds a WebView-based usage dashboard accessible from both the chat GUI and a quick-access command.

**Scope:**
- New clean `messages` schema with `token_count`, `thinking_tokens`, `cached_tokens`, `latency_ms`
- Renamed thread cumulative counters
- New `command_usage` table for inline command API calls (daily aggregation)
- Per-message token attribution via subtraction on assistant insert
- Thinking tokens extracted from API response and stored separately (not counted in context)
- Per-message token info icon with hover tooltip in chat UI
- Full usage dashboard WebView page with filtering and graphs
- Dashboard accessible from chat GUI (button) and quick-access command (tray menu)
- `active_path_tokens` computed from real `token_count` sums (no estimation)
- `TokenEstimation` class removed entirely

**⚠ Breaking Change:** This feature drops old token columns (`prompt_tokens`, `completion_tokens`, `total_tokens`) from the messages table. Existing chat history databases are incompatible. Users must delete their `chat_history.db` (in `%APPDATA%\LLM-AutoHotkey-Assistant\`) after this update.

## §3 End State Upon Feature Completion

### User Perspective

**Chat UI Token Bar** (unchanged appearance, but data is now exact):
```
🔢 Context Used: 1,234 / 128,000
📊 Tokens ↑ 45.2k  ↓ 12.8k
💾 Cache 3.2k
💲 API Cost $0.15 | Input: $0.1234 | Cached: $0.0012 | Output: $0.0256
```

**Per-Message Token Tooltip** (NEW):
- Each message bubble has a small 📊 icon in its action bar
- Hovering over the icon shows a tooltip
- Hidden when `token_count = 0` (no data — cancelled messages, messages before this feature)
- Present on both active and inactive branches (fork/retry messages have their own data)

*Assistant message tooltip:*
```
┌─────────────────────────────────┐
│ 📊 Token Usage                  │
│                                 │
│ Output:     300 tokens          │
│   ├ Visible:  220 tokens        │
│   └ Thinking:  80 tokens        │
│ Cache:       50 tokens          │
│ Speed:       45 tok/sec         │
│ Latency:     1.2s to first      │
│ Cost:        $0.0045            │
└─────────────────────────────────┘
```

*User message tooltip:*
```
┌─────────────────────────────────┐
│ 📊 Token Usage                  │
│                                 │
│ Input:      150 tokens          │
│ (contribution to context)       │
└─────────────────────────────────┘
```

*System message: no tooltip icon (token_count = 0).*
*Cancelled/partial message: no tooltip icon (token_count = 0).*

**Command Usage** (invisible to user, data foundation for dashboard):
- Every inline command API call saves a row to `command_usage` table
- Includes: command_name, model, provider, prompt_tokens, completion_tokens, thinking_tokens, cached_tokens, costs, latency

**Cancelled Streams:**
- Cancelled messages still save their partial content to DB
- But `token_count`, `thinking_tokens`, `cached_tokens`, `latency_ms` are all 0 (no API data)
- Context Used bar unaffected (no fake data)

### Technical Perspective

**`messages` table — clean schema (replaces old columns):**

| Column | Type | Meaning |
|---|---|---|
| `token_count` | INTEGER | This message's context contribution: for assistant = visible output tokens (completion minus thinking); for user/system = input tokens backfilled by subtraction |
| `thinking_tokens` | INTEGER | Reasoning tokens (assistant only, 0 otherwise). Contributes to billing, NOT context. |
| `cached_tokens` | INTEGER | Cache hit tokens for the API call that produced this assistant (0 for non-assistant) |
| `latency_ms` | INTEGER | Time to first token in ms (assistant only, 0 for non-assistant) |

**Old → New Column Mapping:**

| Old Column | New Column / Action |
|---|---|
| `prompt_tokens` | **Removed.** Replaced by `token_count` on user messages (backfilled via subtraction) |
| `completion_tokens` | **Removed.** Replaced by `token_count + thinking_tokens` on assistant messages |
| `total_tokens` | **Removed.** Now computed as `SUM(token_count)` across path or `input + output` for cumulative |
| `cached_tokens` | **Kept** (same name, same meaning) |
| *(new)* | `token_count` — per-message context contribution |
| *(new)* | `thinking_tokens` — reasoning tokens, billing only |
| *(new)* | `latency_ms` — time to first token |

Columns REMOVED: `prompt_tokens`, `completion_tokens`, `total_tokens` (were cumulative/API-level, not per-message).

**`chat_threads` table — renamed cumulative columns:**

| Old Name | New Name |
|---|---|
| `cumulative_prompt_tokens` | `cumulative_input_tokens` |
| `cumulative_completion_tokens` | `cumulative_output_tokens` |
| `cumulative_cached_tokens` | *(unchanged)* |
| `cumulative_total_tokens` | *(removed — computed as input + output)* |
| `active_path_tokens` | *(unchanged — now SUM of token_count in active path, thinking excluded)* |

**`command_usage` table — NEW (daily aggregation):**

```sql
command_usage (
    date TEXT NOT NULL,               -- '2026-07-11' (YYYY-MM-DD)
    model TEXT NOT NULL,
    provider TEXT NOT NULL,
    command_name TEXT NOT NULL,
    call_count INTEGER DEFAULT 0,
    prompt_tokens INTEGER DEFAULT 0,
    completion_tokens INTEGER DEFAULT 0,
    thinking_tokens INTEGER DEFAULT 0,
    cached_tokens INTEGER DEFAULT 0,
    input_cost REAL DEFAULT 0,
    output_cost REAL DEFAULT 0,
    total_cost REAL DEFAULT 0,
    total_latency_ms INTEGER DEFAULT 0,  -- sum of latencies, for avg: total_latency_ms / call_count
    PRIMARY KEY (date, model, provider, command_name)
)
```

Each command execution UPSERTs: `INSERT ... ON CONFLICT(date, model, provider, command_name) DO UPDATE SET call_count = call_count + 1, prompt_tokens = prompt_tokens + excluded.prompt_tokens, ...`

Max rows: ~73K/year (10 models × 20 commands × 365 days). Dashboard queries are instant.

**Per-Message Attribution Flow:**

```
1. User sends message → INSERT with token_count=0
2. API call completes → returns prompt_tokens=1500, completion_tokens=300,
   completion_tokens_details: {reasoning_tokens: 80}, cached_tokens=50
3. Compute: existing_sum = SUM(token_count) of all messages in active path
4. new_input = Max(0, prompt_tokens - existing_sum)  ← clamped, never negative
5. UPDATE user message: SET token_count = new_input
6. UPDATE thread: cumulative_input_tokens += new_input
7. INSERT assistant: token_count = 220 (300-80), thinking_tokens = 80,
   cached_tokens = 50, latency_ms = firstTokenTime - requestStartTime
8. UPDATE thread: cumulative_output_tokens += 300 (token_count + thinking_tokens),
   cumulative_cached_tokens += 50,
   active_path_tokens = existing_sum + new_input + 220
```

**Why `active_path_tokens` includes the assistant's visible output:**
`active_path_tokens` represents the total context that will be sent in the NEXT API call. The assistant's visible response is now part of the conversation and WILL be re-sent as input in subsequent requests. Thinking tokens are excluded because they are NOT sent back to the API. So: `active_path_tokens = SUM(token_count)` of all path messages = input tokens + visible output tokens. This matches what the next API call's `prompt_tokens` will report.

**active_path_tokens:**

- On `MessageRepo.Insert()` (assistant): set to `existing_sum + new_input + token_count` (no thinking)
- On `SwitchBranch()`: recompute via `_SyncActivePathTokens()` which sums `token_count` across active path
- On `Edit()` / `HardDelete()`: recompute via `_SyncActivePathTokens()`

**Thinking Tokens Extraction:**

SSEParser `ParseLine()` extended in the existing `_computeCompletion()` helper (and the two usage extraction blocks) to extract `completion_tokens_details.reasoning_tokens` (OpenAI format). The result usage object gets a new `thinkingTokens` field (camelCase, matching existing `promptTokens`/`completionTokens` convention).

**JS Message Object Changes:**

`buildStructuredMessagesFromPath()` now includes per-message token data:
```javascript
msgObj.tokenCount = msg.token_count
msgObj.thinkingTokens = msg.thinking_tokens
msgObj.cachedTokens = msg.cached_tokens
msgObj.latencyMs = msg.latency_ms
```

**GetThreadStats Result Object (camelCase for JS):**

The AHK result object from `TreeRepo.GetThreadStats()` returns:
```ahk
result := {
    activePathTokens: ..., contextWindow: ...,
    cumulativeInputTokens: ..., cumulativeOutputTokens: ..., cumulativeCachedTokens: ...,
    cumulativeCost: ..., cumulativeInputCost: ..., cumulativeCachedInputCost: ..., cumulativeOutputCost: ...,
    pricingUnit: { input: ..., cachedInput: ..., output: ... }
}
```

### Edge Cases & Error States

- **First message in thread**: user message gets all `prompt_tokens` attributed (system message stays at 0). Slight overcount (system tokens attributed to user), but subsequent messages are exact via subtraction.
- **Edit makes content shorter, then retry**: `existing_sum` may exceed the new `prompt_tokens`. `new_input = Max(0, prompt_tokens - existing_sum)` clamps to 0. The retry assistant's response updates `active_path_tokens` which reflects the actual measured context.
- **Multiple user messages between assistants**: all new input tokens attributed to the LAST user message (the one that triggered the API call).
- **Branch switch to path with no assistant**: `active_path_tokens = 0`.
- **API doesn't provide thinking_tokens split**: `thinking_tokens = 0`, `token_count = completion_tokens` (visible output slightly overcounted, but billing correct).
- **Cancelled stream**: all token fields = 0, no fake data. `_logCancelledRequest` also sets usage fields to 0 (no estimation).
- **Error response**: no message inserted (unchanged behavior).
- **Inline command with non-streaming API**: `ResponseParser.ParseChatResponse()` already extracts usage. Extended to extract thinking_tokens.
- **Subtraction drift over many turns**: small per-turn errors from system message overcount can accumulate. Mitigated by `Max(0, ...)` clamping and the fact that each API call provides a fresh ground-truth `prompt_tokens`.

## §4 Implementation Steps

### [x] Step 1: Schema Migration — Mechanical Column Renames Only

**Goal:** Rewrite DB schema with new column names. This step does ONLY mechanical renames — no logic changes. All old column references must compile with new names. Fork methods use new columns here (not deferred to Step 4).

**Actions:**
- Rewrite `ChatDB._CreateSchema()` in [`chat/db/ChatDB.ahk`](chat/db/ChatDB.ahk:50):
  - `messages`: replace `prompt_tokens`, `completion_tokens`, `total_tokens` with `token_count`, `thinking_tokens`, `cached_tokens`; add `latency_ms`
  - `chat_threads`: rename `cumulative_prompt_tokens` → `cumulative_input_tokens`, `cumulative_completion_tokens` → `cumulative_output_tokens`; drop `cumulative_total_tokens`
- Add `command_usage` table creation in `ChatDB._CreateSchema()` with the daily-aggregation schema (PRIMARY KEY on date, model, provider, command_name)
- Add `ChatDB.CommandUsage_Upsert()` static method skeleton (body filled in Step 6)
- Mechanical column renames (old → new, no logic changes yet):
  - [`MessageRepo.ahk`](chat/db/MessageRepo.ahk) `Insert()`: `prompt_tokens` → `token_count`, `completion_tokens` → removed (use `token_count + thinking_tokens`), `total_tokens` → removed, `cached_tokens` → `cached_tokens` (same). For now, `token_count` gets the old `completion_tokens` value directly (visible + thinking combined — split added in Step 2+3). `active_path_tokens` line becomes `active_path_tokens = existing_sum + new_input + token_count` but uses placeholder values (real logic in Step 3).
  - [`MessageRepo.ahk`](chat/db/MessageRepo.ahk) `HardDelete()` / `Edit()`: replace `TokenEstimation.Estimate()` calls with placeholder — call `_SyncActivePathTokens()` (the method still uses old estimation in this step, real rewrite in Step 4).
  - [`TreeRepo.ahk`](chat/db/TreeRepo.ahk) `GetActivePath()`: read `token_count`, `thinking_tokens`, `cached_tokens`, `latency_ms` instead of old columns. `SELECT *` → explicit column list.
  - [`TreeRepo.ahk`](chat/db/TreeRepo.ahk) `GetThreadStats()`: result property names `cumulativePromptTokens` → `cumulativeInputTokens`, `cumulativeCompletionTokens` → `cumulativeOutputTokens`, drop `cumulativeTotalTokens` reference.
  - [`TreeRepo.ahk`](chat/db/TreeRepo.ahk) `_SyncActivePathTokens()`: replace `TokenEstimation.Estimate()` with simple `token_count` read (just to compile — full rewrite in Step 4).
  - [`TreeRepo.ahk`](chat/db/TreeRepo.ahk) `_InsertForkMessage()` and `_CopyOffPathSiblings()`: use new columns (`token_count`, `thinking_tokens`, `cached_tokens`, `latency_ms`). Moved here from Step 4 to avoid inter-step breakage.
  - [`StreamCompletion.ahk`](chat/streaming/StreamCompletion.ahk) `_persistStreamResponse()`: change `Msg_Insert` call to use `token_count` and `thinking_tokens` fields (values still come from old `usage` object — real split in Step 2).
  - [`StreamError.ahk`](chat/streaming/StreamError.ahk) `_handleStreamCancelled()`: change `Msg_Insert` call to use new column names with 0 values.

**Unit Tests to Write/Update:**
- [`tests/unit/ChatDB.test.ahk`](tests/unit/ChatDB.test.ahk): Update all column name references. For tests that assert specific `active_path_tokens` numeric values, adjust to match the mechanical rename behavior (will be re-verified in Step 4).

**Integration Tests to Write/Update:**
None — schema changes covered by unit tests.

**Live Smoke Test:**
1. The test runner already uses a test-mode DB path — verify by checking [`tests/test_config.ahk`](tests/test_config.ahk) sets a non-production DB path. If not, add `testMode := true` and a temp DB path.
2. Run `tests\run_all_tests.bat` — verify all tests compile and pass with new column names
3. Verify no "no such column" errors in any test output

**Smoke Test Classification:** Model

**Suggested Commit Message:** refactor(db): migrate messages and threads to clean token schema

---

### [x] Step 2: Extract Thinking Tokens from API Responses

**Goal:** SSEParser and ResponseParser extract `thinkingTokens` from API usage data.

**Actions:**
- Update [`api/SSEParser.ahk`](api/SSEParser.ahk):
  - Extend the existing `_computeCompletion()` helper (already handles Google's total>prompt+completion) to also extract `completion_tokens_details.reasoning_tokens` from `usageObj`
  - In the two usage extraction blocks (OpenAI stream_options chunk at lines 34-45, finish_reason chunk at lines 119-127): add `thinkingTokens: ...` field to the result usage object, computed by the extended helper
  - The result usage object gets `thinkingTokens` (camelCase, matching existing `promptTokens`, `completionTokens`, `totalTokens`, `cachedTokens`)
- Update [`api/ResponseParser.ahk`](api/ResponseParser.ahk) `ParseChatResponse()`:
  - In the usage extraction block (lines 18-32): also extract `completion_tokens_details.reasoning_tokens` → `usage.thinkingTokens`
- Update [`chat/streaming/StreamHandler.ahk`](chat/streaming/StreamHandler.ahk):
  - `_readAndProcessStream()`: the `state.usage` object already gets `chunk.usage` assigned (line 152). Since SSEParser now includes `thinkingTokens`, no additional code needed — just verify passthrough.
  - `_finalizeStreaming()`: `requestParams["_streamUsage"]` now contains `thinkingTokens` — passes through to `saveStreamResponse()` automatically.

**Unit Tests to Write/Update:**
- [`tests/unit/StreamHandler.test.ahk`](tests/unit/StreamHandler.test.ahk): Test thinking token extraction from SSE chunks (verify `thinkingTokens` in usage object after parsing)
- [`tests/unit/LLMRequestBuilder.test.ahk`](tests/unit/LLMRequestBuilder.test.ahk): Test ResponseParser includes `thinkingTokens` in returned usage

**Integration Tests to Write/Update:**
None — covered by unit tests.

**Live Smoke Test:**
Run `tests\run_all_tests.bat` — verify SSEParser and ResponseParser tests pass with thinking token extraction.

**Smoke Test Classification:** Model

**Suggested Commit Message:** feat(api): extract thinking tokens from API usage responses

---

### [x] Step 3: Per-Message Token Attribution in MessageRepo.Insert

**Goal:** `MessageRepo.Insert()` computes per-message token attribution via subtraction when inserting an assistant message.

**Actions:**
- Extract a helper `MessageRepo._BackfillUserTokens(threadId, promptTokens)` in [`chat/db/MessageRepo.ahk`](chat/db/MessageRepo.ahk):
  1. Get active path messages
  2. `existing_sum = SUM(token_count)` for all messages in path
  3. `new_input = Max(0, promptTokens - existing_sum)` (clamped, never negative — handles edit/retry where existing_sum may exceed new prompt)
  4. Find the last user message in the path (walk backward from leaf, find first `role='user'`)
  5. UPDATE that user message: `SET token_count = new_input`
  6. UPDATE thread: `cumulative_input_tokens += new_input`
  7. Return `new_input`
- Update `Insert()` to call `_BackfillUserTokens()` when inserting an assistant with `token_count > 0`:
  - `new_input := MessageRepo._BackfillUserTokens(msgObj.thread_id, promptTokens)`
  - Insert assistant: `token_count = completionTokens - thinkingTokens`, `thinking_tokens = thinkingTokens`, `cached_tokens = cachedTokens`, `latency_ms = latencyMs`
  - Update thread: `cumulative_output_tokens += (token_count + thinking_tokens)`, `cumulative_cached_tokens += cached_tokens`
  - Set `active_path_tokens = existing_sum + new_input + token_count` (assistant visible output IS part of context — it will be sent back in the next API call's prompt)
- Update cost calculation in `Insert()`:
  - Input cost: `new_input * input_price` (from `CostCalculator`, keyed by user's contribution)
  - Output cost: `(token_count + thinking_tokens) * output_price` (all output, thinking included since it's billed)
  - Cached cost: `cached_tokens * cached_input_price`

**Unit Tests to Write/Update:**
- [`tests/unit/ChatDB.test.ahk`](tests/unit/ChatDB.test.ahk):
  - `TokenAttribution_BackfillsUserMessage()`: verify user message gets `token_count > 0` after assistant insert
  - `TokenAttribution_SubtractionIsExact()`: verify `existing_sum + new_input = API prompt_tokens`
  - `TokenAttribution_ThinkingExcludedFromActivePath()`: verify `active_path_tokens` excludes `thinking_tokens`
  - `TokenAttribution_FirstMessageInThread()`: verify first user gets all `prompt_tokens`
  - `TokenAttribution_EditShorterThenRetry_ClampsToZero()`: edit user content shorter, retry → `new_input` clamps to 0

**Integration Tests to Write/Update:**
None — all logic unit-testable.

**Live Smoke Test:**
Run `tests\run_all_tests.bat` — verify all token attribution tests pass with correct values. Specific focus: `ChatDBTest.TokenAttribution_*` tests.

**Smoke Test Classification:** Model

**Suggested Commit Message:** feat(db): per-message token attribution via subtraction

---

### [x] Step 4: Fix active_path_tokens + Clean Up HardDelete/Edit

**Goal:** `_SyncActivePathTokens()` uses real `token_count` sums. `HardDelete()` and `Edit()` call `_SyncActivePathTokens()` instead of estimating.

**Actions:**
- Rewrite [`chat/db/TreeRepo.ahk`](chat/db/TreeRepo.ahk) `_SyncActivePathTokens()`:
  - Walk the active path messages
  - `total := 0`; for each msg: `total += msg.token_count` (thinking excluded — it's already not in token_count)
  - `UPDATE chat_threads SET active_path_tokens = total`
- Update `GetThreadStats()` result property names explicitly (camelCase for JS):
  - `cumulativeInputTokens`, `cumulativeOutputTokens`, `cumulativeCachedTokens`
  - No `cumulativeTotalTokens` (JS computes `input + output`)
- Update [`MessageRepo.ahk`](chat/db/MessageRepo.ahk) `HardDelete()`:
  - After re-parenting children and updating `active_leaf_id`, call `TreeRepo._SyncActivePathTokens(threadId)`
  - Remove the `TokenEstimation.Estimate()` subtraction block
- Update [`MessageRepo.ahk`](chat/db/MessageRepo.ahk) `Edit()`:
  - After updating content and `_TouchThreadByMsg`, call `TreeRepo._SyncActivePathTokens(threadId)`
  - Remove the `TokenEstimation.Estimate()` delta calculation block
- Remove ALL remaining `TokenEstimation` usage from TreeRepo (the `_SyncActivePathTokens` placeholder from Step 1)

**Unit Tests to Write/Update:**
- [`tests/unit/ChatDB.test.ahk`](tests/unit/ChatDB.test.ahk):
  - Update `SwitchBranch_UpdatesActivePathTokens` for token_count-based values (no estimation)
  - New: `ActivePathTokens_ExcludesThinking()` — verify `active_path_tokens` only sums `token_count` (which already excludes thinking)
  - New: `ActivePathTokens_PreservedAcrossSwitches()` — verify each branch keeps its own total after switch+switch back
  - Update `Edit_AdjustsActivePathTokens`: expect recalculation from token_count, not char delta
  - Update `HardDelete_PreservesCumulativeCounters`: cumulative counters unchanged (delete doesn't affect them)

**Integration Tests to Write/Update:**
None.

**Live Smoke Test:**
Run `tests\run_all_tests.bat` — verify switch branch, edit, and delete token tests pass.

**Smoke Test Classification:** Model

**Suggested Commit Message:** fix(db): compute active_path_tokens from real token_count sums

---

### [x] Step 5: Fix Stream Paths + Remove TokenEstimation

**Goal:** Stream completion passes latency/thinking tokens; cancelled streams save 0 (no estimation); `_logCancelledRequest` also uses 0; `TokenEstimation` class deleted.

**Actions:**
- Update [`chat/streaming/StreamCompletion.ahk`](chat/streaming/StreamCompletion.ahk):
  - `saveStreamResponse()` already receives `firstTokenTime` and `requestStartTime` (line 13). Add `latencyMs := firstTokenTime > 0 ? firstTokenTime - requestStartTime : A_TickCount - requestStartTime`
  - Pass `latencyMs` and `thinkingTokens` (from `usage.thinkingTokens`) through to `_persistStreamResponse()`
  - `_persistStreamResponse()` signature becomes: `(content, modelName, reasoning, usage, latencyMs)`
  - `Msg_Insert` call includes `latency_ms: latencyMs`
- Update [`chat/streaming/StreamError.ahk`](chat/streaming/StreamError.ahk):
  - `_handleStreamCancelled()`: remove the `TokenEstimation.Estimate()` block (lines 73-84). Set all token fields to 0 in `Msg_Insert`. Remove `estimated: "true"` from the `_logCancelledRequest` call — just pass 0 for all token fields.
  - `_logCancelledRequest()`: set `usage.prompt_tokens = 0`, `usage.completion_tokens = 0`, `usage.total_tokens = 0`, `usage.prompt_cache_hit_tokens = 0`. Remove the `estimated: "true"` field entirely.
- Delete [`shared/TokenEstimation.ahk`](shared/TokenEstimation.ahk)
- Remove `#Include ..\shared\TokenEstimation.ahk` from [`lib/Config.ahk`](lib/Config.ahk:18)
- Delete [`tests/unit/TokenEstimation.test.ahk`](tests/unit/TokenEstimation.test.ahk)
- Remove `#Include unit\TokenEstimation.test.ahk` from [`tests/run_ahk_tests.ahk`](tests/run_ahk_tests.ahk:103)
- Remove `TokenEstimation` mention from [`tests/test_config.ahk`](tests/test_config.ahk:6)

**Unit Tests to Write/Update:**
- [`tests/unit/StreamError.test.ahk`](tests/unit/StreamError.test.ahk): Verify cancelled messages have `token_count=0`, `thinking_tokens=0`, `cached_tokens=0`, `latency_ms=0`
- [`tests/unit/StreamHandler.test.ahk`](tests/unit/StreamHandler.test.ahk): Verify `latency_ms` and `thinkingTokens` passed through to `_persistStreamResponse`

**Integration Tests to Write/Update:**
None.

**Live Smoke Test:**
1. Run `tests\run_all_tests.bat` — verify stream tests pass with zero tokens on cancel
2. Verify application starts without errors: `findstr /s /i "TokenEstimation" *.ahk *.js` → zero results (class fully removed)

**Smoke Test Classification:** Model

**Suggested Commit Message:** fix(stream): remove token estimation, pass real latency/thinking data

---

### [x] Step 6: Command Usage Tracking (Daily Aggregation)

**Goal:** Inline commands UPSERT daily-aggregated API call data to `command_usage` table.

**Actions:**
- Fill in `ChatDB.CommandUsage_Upsert()` in [`chat/db/ChatDB.ahk`](chat/db/ChatDB.ahk):
  - Accept `{date, model, provider, command_name, prompt_tokens, completion_tokens, thinking_tokens, cached_tokens, input_cost, output_cost, total_cost, latency_ms}`
  - SQLite UPSERT pattern: `SELECT call_count FROM command_usage WHERE date=? AND model=? AND provider=? AND command_name=?`. If row exists: `UPDATE SET call_count+=1, tokens+=new, ...`. If not: `INSERT`.
- Update [`app/InlineRequestRunner.ahk`](app/InlineRequestRunner.ahk):
  - `Run()` already has `commandName`, `providerName`, `singleAPIModelName`. After `_PasteAndLogResponse()`, extract usage from the already-parsed `result.response.usage`, compute costs via `CostCalculator.ComputeTokenCosts(model, usage)`, and call `ChatDB.CommandUsage_Upsert()` with today's date (`FormatTime(, "yyyy-MM-dd")`).

**Unit Tests to Write/Update:**
- [`tests/unit/InlineRequestRunner.test.ahk`](tests/unit/InlineRequestRunner.test.ahk): Test `command_usage` row upserted after successful API call
- [`tests/unit/ChatDB.test.ahk`](tests/unit/ChatDB.test.ahk): Test `CommandUsage_Upsert()` — first call INSERTs, second call UPDATEs (call_count=2, tokens summed)

**Integration Tests to Write/Update:**
None.

**Live Smoke Test:**
Run `tests\run_all_tests.bat` — verify command usage tests pass, especially the upsert (INSERT then UPDATE) behavior.

**Smoke Test Classification:** Model

**Suggested Commit Message:** feat(db): track command API usage with daily aggregation

---

### [x] Step 7: Expose Token Data to WebView

**Goal:** Message objects sent to JS include per-message token fields.

**Actions:**
- Update [`chat/ChatUtils.ahk`](chat/ChatUtils.ahk) `buildStructuredMessagesFromPath()`:
  - Include `tokenCount`, `thinkingTokens`, `cachedTokens`, `latencyMs` in each message object (read from the DB row properties `msg.token_count`, `msg.thinking_tokens`, `msg.cached_tokens`, `msg.latency_ms`)
- [`chat/ChatIPC.ahk`](chat/ChatIPC.ahk) does NOT need changes — it delegates to `_LoadThreadAndRefreshUI()` which calls `buildStructuredMessagesFromPath()`
- Verify [`StreamCompletion.ahk`](chat/streaming/StreamCompletion.ahk) `_handleStreamComplete()`: the `dbMsgData` is built via `buildStructuredMessagesFromPath()` → already includes token fields after the ChatUtils change
- Verify [`StreamError.ahk`](chat/streaming/StreamError.ahk) `_handleStreamCancelled()`: same pattern — `dbMsgData` from `buildStructuredMessagesFromPath()`

**Unit Tests to Write/Update:**
- [`tests/unit/ChatUtils.test.ahk`](tests/unit/ChatUtils.test.ahk): Verify message objects include `tokenCount`, `thinkingTokens`, `cachedTokens`, `latencyMs` fields

**Integration Tests to Write/Update:**
None.

**Live Smoke Test:**
Run `tests\run_all_tests.bat` — verify ChatUtils tests pass and message objects contain token fields.

**Smoke Test Classification:** Model

**Suggested Commit Message:** feat(ipc): expose per-message token data to WebView

---

### [x] Step 8: Per-Message Token Tooltip in Chat UI

**Goal:** Each message has a 📊 icon showing token breakdown on hover.

**Actions:**
- Update [`webui/js/chat/chat-render.js`](webui/js/chat/chat-render.js):
  - In message bubble rendering, add a 📊 icon to the action bar for user and assistant messages where `tokenCount > 0` (not system, not cancelled/zero-token messages)
  - The icon is styled as a small, subtle inline button
- Create new JS module [`webui/js/chat/chat-token-tooltip.js`](webui/js/chat/chat-token-tooltip.js):
  - `renderTokenTooltip(msg)` — generates HTML for the tooltip based on message role:
    - **Assistant**: shows Output (visible + thinking breakdown), Cache, Speed (tok/sec = `(tokenCount + thinkingTokens) / (latencyMs / 1000)`), Latency, Cost
    - **User**: shows Input tokens (contribution to context)
  - `showTokenTooltip(event, msg)` — positions and displays tooltip on hover
  - `hideTokenTooltip()` — hides on mouse leave
- Update [`webui/index.html`](webui/index.html): include `<script src="js/chat/chat-token-tooltip.js"></script>` after chat-render.js
- Update [`webui/css/chat/chat-messages.css`](webui/css/chat/chat-messages.css): add styles for `.token-info-icon` (small, muted) and `.token-tooltip` (absolute positioned, dark bg, rounded)

**Unit Tests to Write/Update:**
- New: [`tests/unit/chat-token-tooltip.test.js`](tests/unit/chat-token-tooltip.test.js): Test `renderTokenTooltip()` HTML generation for assistant (full breakdown) and user (input only) messages

**Integration Tests to Write/Update:**
None — UI component, covered by smoke test.

**Live Smoke Test:**
1. Open chat window, send a message, wait for response
2. Verify 📊 icon appears on the user message. Hover → verify "Input: N tokens" tooltip
3. Verify 📊 icon appears on the assistant message. Hover → verify full breakdown: Output (visible + thinking), Cache, Speed, Latency, Cost
4. Verify system message has no 📊 icon
5. Cancel a streaming response — verify the partial message has no 📊 icon (token_count = 0)
6. Create a retry (branch 2/2), switch between branches — verify both branches' messages show their own token data
7. Verify tooltip disappears on mouse leave

**Smoke Test Classification:** Human

**Suggested Commit Message:** feat(ui): add per-message token usage tooltip

---

### [x] Step 9: Update Token Bar JS for New Counter Names

**Goal:** JS `updateTokenUsage()` uses new cumulative counter names from `GetThreadStats()`.

**Actions:**
- Update [`webui/js/chat/chat-format.js`](webui/js/chat/chat-format.js) `updateTokenUsage()`:
  - `data.cumulativePromptTokens` → `data.cumulativeInputTokens`
  - `data.cumulativeCompletionTokens` → `data.cumulativeOutputTokens`
  - `data.cumulativeTotalTokens` → compute as `(data.cumulativeInputTokens || 0) + (data.cumulativeOutputTokens || 0)` in JS (no longer provided by AHK)
  - `data.cumulativeCachedTokens` → unchanged
- Update `showTokenUsageBar()` if it references old names

**Unit Tests to Write/Update:**
- [`tests/unit/chat-format.test.js`](tests/unit/chat-format.test.js): Update tests for new counter names

**Integration Tests to Write/Update:**
None.

**Live Smoke Test:**
Run `tests\run_all_tests.bat` — verify JS tests pass with new counter names.

**Smoke Test Classification:** Model

**Suggested Commit Message:** refactor(ui): update token bar JS for new counter names

---

### [x] Step 10: Usage Dashboard — AHK Backend

**Goal:** Add AHK endpoint that queries `messages` + `command_usage` tables and returns aggregated usage data as JSON for the dashboard WebView.

**Actions:**
- Add `ChatDB.Usage_Query(filters)` method to [`chat/db/ChatDB.ahk`](chat/db/ChatDB.ahk):
  - Accept filter object: `{timeRange: "all"|"month"|"day", model: "", provider: "", type: "all"|"chat"|"command"}`
  - Chat query: `SELECT DATE(created_at) as date, model, SUM(token_count) as input_tokens, SUM(token_count + thinking_tokens) as output_tokens, SUM(cached_tokens) as cached_tokens, COUNT(*) as message_count FROM messages WHERE role='assistant' [AND date filter] [AND model filter] GROUP BY DATE(created_at), model ORDER BY date`
  - Command query: `SELECT date, model, provider, command_name, call_count, prompt_tokens, completion_tokens, thinking_tokens, cached_tokens, input_cost, output_cost, total_cost, total_latency_ms FROM command_usage [WHERE filters] ORDER BY date`
  - Return combined result as AHK object ready for JSON serialization
- Create [`lib/UsageDashboard.ahk`](lib/UsageDashboard.ahk):
  - Modeled after `ApiLogsViewer.ahk` pattern: creates a persistent WebView2 window
  - `ShowUsageDashboard()` function: creates/activates window, loads `webui/usage-dashboard.html`
  - Registers `OnWebMessageReceived` handler for actions: `getUsageData` (calls `ChatDB.Usage_Query()` with filters, returns JSON), `getModels` (returns distinct models list)
- Register the dashboard in [`Main.ahk`](Main.ahk):
  - Add `ShowUsageDashboard` to the tray menu (similar to "API Logs")
  - Optionally add a hotkey (e.g., `^!U` for Ctrl+Alt+U)
- Add a "📊 Usage" button in the chat UI sidebar or header that triggers `ShowUsageDashboard`:
  - In [`chat/ChatWindow.ahk`](chat/ChatWindow.ahk) or via a WebView message: add IPC message to open the dashboard
  - In [`webui/index.html`](webui/index.html): add a button in the navbar that sends `{action: "openUsageDashboard"}` to AHK

**Unit Tests to Write/Update:**
- [`tests/unit/ChatDB.test.ahk`](tests/unit/ChatDB.test.ahk): Test `Usage_Query()` with various filter combinations — verify correct aggregation and date filtering

**Integration Tests to Write/Update:**
None.

**Live Smoke Test:**
Run `tests\run_all_tests.bat` — verify usage query tests pass.

**Smoke Test Classification:** Model

**Suggested Commit Message:** feat(dashboard): add AHK backend for usage data queries

---

### [x] Step 11: Usage Dashboard — HTML/JS Frontend

**Goal:** Build the WebView dashboard page with filtering controls and Chart.js graphs.

**Actions:**
- Create [`webui/usage-dashboard.html`](webui/usage-dashboard.html):
  - Bootstrap 5 dark theme (same style as chat UI)
  - Filter bar at top: time range dropdown (All Time / Past Month / Past Day), model dropdown (populated dynamically), provider dropdown, type toggle (All / Chat / Commands)
  - Summary cards row: Total Input Tokens, Total Output Tokens, Total Cost, Total API Calls
  - Chart area: 3 charts using Chart.js (bundled locally, no CDN):
    1. **Daily Usage Bar Chart** — tokens per day (input + output stacked bars)
    2. **Model Distribution Pie Chart** — token share per model
    3. **Cost Over Time Line Chart** — cumulative/average cost per day
  - Table below charts: detailed breakdown per model per day
- Create [`webui/js/usage-dashboard.js`](webui/js/usage-dashboard.js):
  - `loadUsageData(filters)` — calls `chrome.webview.postMessage({action: "getUsageData", filters})`, renders charts and table on response
  - `populateFilters()` — loads distinct models/providers on page load
  - Chart initialization and update logic (Chart.js)
- Bundle Chart.js locally: download `chart.min.js` to `webui/Bootstrap/chart.min.js` (or use a lightweight alternative)

**Unit Tests to Write/Update:**
None — pure UI, covered by smoke test.

**Integration Tests to Write/Update:**
None.

**Live Smoke Test:**
1. Open the usage dashboard (from tray menu or chat button)
2. Verify summary cards show token counts and costs
3. Change time range filter → verify charts and table update
4. Select a specific model → verify data filters to that model only
5. Toggle between Chat/Commands/All → verify data changes
6. Verify charts render (bar chart, pie chart, line chart visible with data)

**Smoke Test Classification:** Human

**Suggested Commit Message:** feat(ui): add usage dashboard with charts and filtering

---

### [x] Step 12: Dashboard Polish — Quick Access Command + Final Integration

**Goal:** Dashboard is fully accessible and polished. Quick-access command in the command menu opens the dashboard directly.

**Actions:**
- Add a `"Usage Dashboard"` entry to the command menu in [`UserConfig.ahk`](UserConfig.ahk) that calls `ShowUsageDashboard()`
- Ensure the dashboard window is persistent (close = hide, not destroy) — same pattern as ApiLogsViewer
- Add a refresh button on the dashboard page
- Add cost summary: total cost across all usage, cost per model
- Verify all data flows correctly: chat tokens (from messages table) and command tokens (from command_usage table) appear in the dashboard

**Unit Tests to Write/Update:**
None — integration/UI.

**Integration Tests to Write/Update:**
None.

**Live Smoke Test:**
1. Trigger the dashboard from the quick-access command menu (`Ctrl+`` → "Usage Dashboard")
2. Verify dashboard opens and shows data
3. Trigger from the chat UI button → verify same dashboard window activates (doesn't open a second)
4. Close the dashboard window → open again → verify it's fast (pre-warmed)
5. Send a chat message → verify token counts update after next refresh

**Smoke Test Classification:** Human

**Suggested Commit Message:** feat(dashboard): add quick-access command and final integration

---

## §5 Final Directory Tree

```
ai-automation/
├── shared/
│   └── TokenEstimation.ahk                    (DELETED)
├── api/
│   ├── SSEParser.ahk                          (modified — thinking_tokens extraction)
│   ├── ResponseParser.ahk                     (modified — thinking_tokens extraction)
│   └── CostCalculator.ahk                     (unchanged)
├── app/
│   └── InlineRequestRunner.ahk                (modified — command_usage tracking)
├── chat/
│   ├── ChatUtils.ahk                          (modified — token fields in message objects)
│   ├── ChatWindow.ahk                         (modified — usage dashboard button IPC)
│   ├── streaming/
│   │   ├── StreamHandler.ahk                  (modified — thinking_tokens passthrough)
│   │   ├── StreamCompletion.ahk               (modified — latency_ms, thinking_tokens)
│   │   └── StreamError.ahk                    (modified — remove estimation)
│   └── db/
│       ├── ChatDB.ahk                         (modified — new schema, command_usage, Usage_Query)
│       ├── MessageRepo.ahk                    (modified — per-message attribution)
│       ├── TreeRepo.ahk                       (modified — SUM(token_count) for active_path)
│       ├── ThreadRepo.ahk                     (unchanged)
│       ├── AttachmentRepo.ahk                 (unchanged)
│       └── AssistantRepo.ahk                  (unchanged)
├── lib/
│   ├── Config.ahk                             (modified — remove TokenEstimation, add UsageDashboard)
│   └── UsageDashboard.ahk                     (NEW — WebView2 host for usage dashboard)
├── Main.ahk                                   (modified — tray menu, UsageDashboard registration)
├── UserConfig.ahk                             (modified — "Usage Dashboard" command)
├── webui/
│   ├── index.html                             (modified — include chat-token-tooltip.js, dashboard button)
│   ├── usage-dashboard.html                   (NEW — usage dashboard page)
│   ├── Bootstrap/
│   │   └── chart.min.js                       (NEW — Chart.js bundled locally)
│   ├── css/chat/
│   │   └── chat-messages.css                  (modified — tooltip styles)
│   └── js/
│       ├── usage-dashboard.js                 (NEW — dashboard logic, charts, filtering)
│       └── chat/
│           ├── chat-render.js                 (modified — token icon in action bar)
│           ├── chat-format.js                 (modified — new counter names)
│           └── chat-token-tooltip.js          (NEW — token tooltip rendering)
├── tests/
│   ├── run_ahk_tests.ahk                      (modified — remove TokenEstimation test)
│   ├── test_config.ahk                        (modified — remove TokenEstimation mention)
│   └── unit/
│       ├── ChatDB.test.ahk                    (modified — new column names, attribution tests, Usage_Query tests)
│       ├── StreamHandler.test.ahk             (modified — thinking_tokens tests)
│       ├── StreamError.test.ahk               (modified — zero tokens on cancel)
│       ├── ChatUtils.test.ahk                 (modified — token fields in messages)
│       ├── InlineRequestRunner.test.ahk       (modified — command_usage tests)
│       ├── LLMRequestBuilder.test.ahk         (modified — thinking_tokens tests)
│       ├── chat-format.test.js                (modified — new counter names)
│       ├── chat-token-tooltip.test.js         (NEW — tooltip HTML generation tests)
│       └── TokenEstimation.test.ahk           (DELETED)
└── agent-workspace/
    └── feature/
        ├── plan.md
        └── reference.md
```
