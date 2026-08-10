# Bug Hunt Report (living document)

> **READ THIS FIRST.** This file is the single source of truth for open bugs. The harness
> manual is `README.md` in this folder. Start here; resume from "Where we left off".
>
> Optional: to confirm a `fix applied` entry is real before committing, stash the fix and
> re-run the repro (see "Verifying a fix with git stash" in the harness README).

## The lifecycle (which file, when)

**Files in play:**

| File | Touched when |
|---|---|
| `BUG_HUNT_REPORT.md` (this file) | every step â€” statuses, entries, history, "Where we left off" |
| `e2e-suite.js` + `scenarios/*.js` | intake: add a scenario; fix cycle: flip an assertion |
| `tests/unit/*` + `tests/run_ahk_tests.ahk` | fix cycle: regression tests |
| production source (`app/`, `chat/`, `webui/`, `api/`, `shared/`) | fix cycle step 2 only |

**Status:** every entry carries exactly one of these:

| Status | Meaning | Set when |
|---|---|---|
| `reported` | Suspected bug written up; not yet reproduced | Phase 1, when the entry is written |
| `verified` | Scenario PASSED â€” bug reproduced headlessly | Phase 1, after the scenario passes |
| `fix in progress` | Agent is implementing the fix | Phase 2, before editing any code |
| `fix applied` | Code + tests green; waiting for user to verify | Phase 2, before asking the user |
| `awaiting user commit` | User verified; waiting for the commit | Phase 2, before suggesting the commit |
| *(removed)* | User committed â†’ entry deleted, moved to History | Phase 2, after the commit |

Only `verified` bugs are fixed, one at a time, in rank order.

**Scenario line:** every entry references its verifying scenario by id â€” the scenario
*code* lives in `scenarios/*.js` (runner: `e2e-suite.js`), not in this file. Run it with
`node tests/headless/e2e-suite.js --scenarios=<id>`. `--check-sync` verifies every
entry's id exists (and that every non-regression scenario has an entry).

**Phase 1 â€” Intake** (a bug enters and gets verified here):

1. Write the entry in this file (Repro / Expected / Actual / Evidence + scenario id) with
   `Status: reported`. **[file: this file]**
2. Ensure a verifying scenario exists in `scenarios/*.js`; add one if not.
   **[file: `tests/headless/scenarios/`]**
3. Run `node tests/headless/e2e-suite.js --check-sync` (must say OK), then
   `--scenarios=<id>` (must PASS = bug reproduced). **[no file edits]**
4. PASS â†’ set `Status: verified`, rank the entry, and update "Current state" (open count).
   FAIL â†’ the bug is not reproducible â€” delete the entry and add a one-line note to History.
   **But:** if the FAIL message starts with `setup ->`, it is a harness/infrastructure
   failure (app didn't launch, timeout connecting, element missing while preparing) â€” re-run
   or fix the scenario first; do NOT delete the entry. **[file: this file]**
5. If the bug can't be automated (visual / environment-limited â€” see README), verify by
   unit/static check or manually and say exactly how in the entry.

**Phase 2 â€” Fix cycle** (one verified bug at a time; the scenario is re-run only to
confirm the fix, never to re-verify the bug):

1. Pick the entry: normally the highest-ranked `verified` one, unless the user named a
   specific bug ("fix bug #14") â€” that overrides rank order. Set `Status: fix in progress`
   **before** editing any code. **[file: this file]**
2. Fix the bug in production source. **[files: `app/`, `chat/`, `webui/`, `api/`, `shared/`]**
3. Add/extend regression tests that assert the **fixed** behavior (unit/AHK as appropriateâ€” the flipped scenario is the end-to-end check, but the fix also needs a code-level regression test when feasible; never delete or loosen an existing assertion to make it pass). **[files: `tests/unit/*`; also `tests/run_ahk_tests.ahk`
   if you added an AHK test]**
4. Flip the scenario assertion in `scenarios/*.js` to expect the **fixed** behavior
   (otherwise it fails forever). **[file: `tests/headless/scenarios/`]**
5. Run `--scenarios=<id>` (must PASS = fix works) and the full AHK + JS suites. If it
   FAILs, the fix is incomplete â€” go back to step 2. **[no file edits]**
6. **Gate:** only after step 5 passes (scenario PASS + suites green) set
   `Status: fix applied`, then ask the user to verify manually using the repro steps.
   **[file: this file]**
7. Set `Status: awaiting user commit`, suggest a commit message from
   `git status`/`git diff` (cover ALL uncommitted changes). **Do not commit yourself.**
   **[file: this file]**
8. After the user commits: delete the entry, add one line to History (with the commit),
   update "Current state" (open count) and "Where we left off", re-rank. **[file: this file]**
9. Run `--check-sync` (must say OK). **[no file edits]**

**Rules that keep this document resumable:**

- Update "Where we left off" after **every step** (one line: what was done, what's next).
  That is the resume point if a task is closed midway.
- Write each status change **before** the work it describes (interruption guard).
- **Never trust a Status without re-running the scenario first** â€” re-verify before
  assuming a bug is still open or already fixed.
- **Never ask the user to verify or commit until the fix has PASSED its scenario
  (flipped assertion) and the full AHK + JS suites** â€” the headless check always comes
  first, the user's manual check is the final confirmation.
- **A FAIL with `setup ->` in the message is a harness/infrastructure failure, not a
  refutation** â€” investigate or re-run; never delete an entry because of it.
- **Only one fix may be uncommitted at a time**: wait for the user's commit before
- **Every fix ships with a regression test**: the flipped scenario is the end-to-end
  check, but the fix also needs a unit/AHK test in `tests/unit/*` asserting the fixed
  behavior (unless the bug is visual/environment-limitedâ€” then say so in the entry).
  Never delete or loosen an existing assertion to make it pass.
  starting the next bug (the worktree must be clean of the previous fix).
- Only one agent edits this document at a time.
- Never delete an entry until the user has actually committed.
- **Doc-set rule:** if you change the harness itself (new probe command, new helper, new
  mock mode), update `README.md`; if you change the workflow itself, update `ARCHITECTURE.md`.
  Never hard-code drift-prone numbers (e.g. test totals) in docs â€” point at the runner
  instead.
- Only two files must stay in sync: this file and `e2e-suite.js` â€” `--check-sync`
  enforces it after every edit.

## Harness safety: avoid the hanging-command trap

**Never launch `AutoHotkey64.exe` directly from a shell (`& AutoHotkey64.exe x.ahk`)
to run ad-hoc scripts.** In this headless environment an AHK process can hang
forever, and a bare launch has no timeout, so the whole command blocks for minutes
and aborted runs leave orphaned `AutoHotkey64.exe` processes behind.

Why it hangs (verified 2026-08-01):

- AHK v2 shows a **modal error dialog** (window class `#32770`, titled with the
  script name) for any unhandled runtime error. Headless, nothing can dismiss it
  â€” the process hangs indefinitely. Example: plain `Object` has no `Has` method (only
  `Map` does), so `o.Has("type")` on `o := {type:"enabled"}` throws; bracket-indexing
  a plain object (`o[k]`) throws too. Marker-file evidence: the script writes a
  marker before the throwing line and never after; the hung process shows the
  `#32770` dialog.
- Such errors are silent in a hung process: no stderr, no output file, no exit
  code. `#ErrorStdOut` alone did NOT prevent the hang in this environment.
- This environment can also hang AHK at load for unrelated reasons (see probe.ahk),
  which is why every repo probe carries a watchdog.

How to run AHK safely:

1. **Prefer the harness.** Add a scenario to `scenarios/*.js` (it wraps every AHK
   call in `spawnSync` with `/ErrorStdOut` and a 25s timeout) or reuse a probe
   command (`probe.ahk <command> <outFile>`, `probe-thinking.ahk`). Re-verify bugs
   by running the scenario, never by hand.
2. **Any scratch probe must copy the harness skeleton exactly:** `#Requires` (with
   version), `#ErrorStdOut`, `#SingleInstance Off`, `#NoTrayIcon`, an `OnError`
   handler that writes diagnostics and `ExitApp(1)` (this converts a hang into a
   fast, logged failure), a watchdog `SetTimer(Exit, -15000)` for load-time hangs,
   and `try FileAppend` for results.
3. **Always launch with a hard bound** â€” e.g. .NET `Process.Start` + `WaitForExit(ms)` +
   `Kill()`, or `spawnSync` with `timeout` â€” never bare `&`.
4. **Never blanket-kill `AutoHotkey64.exe` processes.** No
   `Stop-Process -Name AutoHotkey64 -Force`, no `taskkill /IM AutoHotkey64.exe`.
   The user runs their own AHK scripts on this machine, and a blanket kill closes
   ALL of them. This is the #1 way agents have destroyed unrelated user scripts.
5. **After any aborted run, clean up with the targeted command instead:**
   `node tests/headless/e2e-suite.js --cleanup`. It closes ONLY this repo's
   app processes (`Main.ahk`, `chat/ChatWindow.ahk` - matched by process command
   line, which works even when the user started the app on their own desktop
   that this sandbox cannot see, plus script-window title; killed by PID) and
   prints what it closed; every other AHK script keeps running. If it prints
   `Closed 0` but the profile is still locked (EPERM when isolating), or
   `AutoHotkey64.exe` processes linger with no recognizable cmdline/script
   window (load-time hang / modal error dialog), they are NOT identifiable as
   app scripts - do NOT kill them by guessing; report it and let the user close
   their own scripts.
6. Give the shell command itself a `timeout_ms`.

## Current state

- **11 verified, 0 reported, 0 fix applied, 0 fix in progress** (2026-08-10). Scenario count is enforced by
  `node tests/headless/e2e-suite.js --check-sync` (do not hard-code it here).
- **Where we left off:** 2026-08-10 - #1-#21 FIXED + committed (9a8f209, c502d8a, f05f9b2, 6444459, c097c05,
  25f7181, 2e4bc23, 0058836, 31056dd, 4e426f3, a046cda, 04e64e3, 4b41ce7, 1f9b377, d9d3bda, 17150ab, f7ef637,
  f1ea763, a447e0e, 519322b, next commit). Next: bug #22 (a command with the "Default" model silently does
  NOTHING - the dropdown's Default option is never substituted with the app default model).
---

## Bug entry template

Every open bug is one entry in "Open bugs (ranked)" using exactly this shape. When
a bug is fixed and committed, its entry moves to History (one line) â€” this template
stays so future entries always have the same fields. `--check-sync` enforces that
every entry's scenario id exists in `scenarios/*.js`, assembled by `e2e-suite.js` (and that every
non-regression scenario has an entry).

    ### N. <short bug title>

    **Scenario:** <id> (scenario code in e2e-suite.js)

    **Status:** reported | verified | fix in progress | fix applied | awaiting user commit

    **Repro:** <exact steps a human can follow in the running app>

    **Expected:** <behavior when fixed>

    **Actual:** <behavior today, plus the root cause if known>

    **Evidence:** <file/line references or a one-line explanation of the cause>

    **Verification:** <how the headless scenario proves it â€” what was clicked/driven
    and what was observed; for non-automatable bugs, the unit/static/manual check
    and exactly how it was done>

Example (shape only, not a real bug):

    ### 1. Example: hotkey does nothing

    **Scenario:** 99 (scenario code in e2e-suite.js)

    **Status:** verified â€” open

    **Repro:** Settings â†’ Hotkeys â†’ set X â†’ Save â†’ press X.

    **Expected:** the action runs.

    **Actual:** nothing happens â€” `_ApplyHotkeys` never reads the setting.

    **Evidence:** `Main.ahk:12` wires the hotkey from a hardcoded value.

    **Verification:** headless â€” pressed X via probe, observed no postMessage.

Entries are ranked by severity/impact (1 = highest); only `verified` bugs are fixed,
one at a time, in rank order.

## Open bugs (ranked)

**Ranked (1 = highest):**

### 1. A command with the "Default" model (empty APIModels) silently does NOTHING - the dropdown's Default option is never substituted with the app default model

**Scenario:** 162 (scenario code in scenarios/misc.js)

**Status:** fix in progress

**Repro:** Settings -> Commands -> set a command's API Model to "Default" (the first dropdown option, tooltip: "or Default for the chat default model"). Run the command.

**Expected:** The command uses the app default model (the tooltip's promise).

**Actual:** `onCommandSelected`/`onCommandInputSend` pass `cmd.APIModels` raw (empty string for Default) into `processInitialRequest`, which does `StrSplit(RegExReplace("", "\s+", ""), ",")`. AHK's `StrSplit("")` returns an EMPTY array, so the `for i, fullAPIModelName in APIModelsArr` loop never runs: no thread is created (chat mode), no inline request is fired, no error is shown - the command is a silent no-op. The UI-side `_defaultModel` computed in commands-core.js is never substituted. (If an empty string ever reached `createJSONRequest`, `ProviderResolver.Resolve("")` falls back to deepseek and emits `{"model":""}` - a model-less request.)

**Evidence:** `app/RequestProcessor.ahk` (processInitialRequest StrSplit + for-loop), `app/menu/CommandMenu.ahk` (passes cmd.APIModels raw), `webui/js/settings/sections/commands/commands-render.js` (empty "Default" option), `webui/js/settings/sections/commands/commands-core.js` (_defaultModel computed but never used for substitution).

**Verification:** headless scenario 162 (probe, real code): `StrSplit("")` -> 0 entries (loop no-op) AND `createJSONRequest("")` -> `{"messages":[...],"model":""}` - the Default option never substitutes the app default.

### 2. Models tab: pasting a "$"-prefixed price (e.g. "$0.5") and blurring silently zeroes it - the blur handler parseFloat's the raw string (NaN -> 0) and stores 0 as data-price-raw; blank blur also saves 0

**Scenario:** 164 (scenario code in scenarios/settings.js)

**Status:** verified

**Repro:** Settings -> Models -> focus a price field, paste "$0.5" (or "$0.1400" copied from a pricing page), blur, Save. Also try clearing the field and blurring.

**Expected:** "$0.5" parses as 0.5; a blank field stays blank (falls back to the app's blank-price semantics), not 0.

**Actual:** `_wirePriceInput`'s blur handler does `parseFloat(input.value) || 0` with no `$` stripping (only `_parsePrice` strips `$`, and only when no raw value is stored). `parseFloat("$0.5")` is NaN -> 0, and the 0 is written to `data-price-raw`, so the price is permanently zeroed even if the user re-types the number later. The same `|| 0` collapses an EMPTY field to 0 (a blank price is saved as 0 instead of staying blank), and a "1.5k"-style suffix silently becomes 1.5.

**Evidence:** `webui/js/settings/sections/models.js` (_wirePriceInput blur: `parseFloat(input.value) || 0`; _parsePrice prefers the stored raw).

**Verification:** headless scenario 164 (vm, real models.js): input display $0.50 -> focus -> paste "$0.5" -> blur -> saved input=0 (raw=0, display "").

### 3. Usage CSV export is unquoted - a model/provider name containing a comma (both user-editable in Settings) produces a malformed CSV with shifted columns

**Scenario:** 163 (scenario code in scenarios/usage-tokens.js)

**Status:** verified

**Repro:** Give a model id (or provider display name) a comma - e.g. "openai/gpt-5,beta" in Settings -> Models -> Save. Open Usage Dashboard -> Export.

**Expected:** RFC-4180 CSV: fields containing commas (or quotes) are quoted, so the row keeps 12 columns and spreadsheet/parser imports read the numbers correctly.

**Actual:** `exportBtn` joins each row's fields with `Array.join(',')` and never quotes or escapes. A comma inside the model or provider name splits the row into extra fields, shifting every following column one position left - the numeric columns (input/output/costs/calls) are misread by any CSV consumer.

**Evidence:** `webui/js/usage-dashboard.js` (exportBtn handler joins with commas, no quoting).

**Verification:** headless scenario 163 (vm, real usage-dashboard.js): chat row with model "openai/gpt-5,beta" -> exported row splits into 13 fields (header has 12), no quoting.

### 4. Search cannot find attachment extracted_text - FTS5/LIKE only index message content, so a term inside an attached PDF/office file is unsearchable

**Scenario:** 165 (scenario code in scenarios/misc.js)

**Status:** verified

**Repro:** Attach a PDF/office file whose extracted text contains a distinctive term; the message text itself does not. Search for the term.

**Expected:** The term inside the attached document's extracted_text should surface the message (the extracted text is part of the conversation context - ChatRequestBuilder sends it to the API).

**Actual:** `SearchRepo.Search` (FTS5 + LIKE + title fallback) only queries `messages.content`; `message_attachments.extracted_text` is never indexed (FTS_Sync only receives message content) and never searched. The search UI says "Search chats..." with no indication that attachment text is excluded, so a user searching for something only present in an attached document finds nothing.

**Evidence:** `chat/db/SearchRepo.ahk` (all queries against messages only), `chat/db/ChatDB.ahk` (FTS_Sync indexes message content only), `chat/ChatRequestBuilder.ahk` (extracted_text is part of the API context).

**Verification:** headless scenario 165 (probe, real SearchRepo): attachment extracted_text contains "needle" only -> `Search("needle", tid)` returns 0 hits.

### 5. Assistant "isDefault" is a dead setting - persisted and carried everywhere but never read for any behavior, and the Assistants settings UI has no field to change it

**Scenario:** 166 (scenario code in scenarios/misc.js)

**Status:** verified

**Repro:** Open Settings -> Assistants. Note there is no "Default" control. Inspect any code path that could use an assistant's isDefault flag.

**Expected:** Either isDefault drives the default-assistant behavior (like the old "Set as Default Assistant" toggle it replaced) or it is removed as dead metadata.

**Actual:** `isDefault` is written in DefaultSettings.ahk (default assistant: true), carried through SettingsApply._ApplyAssistants (bug #122 fixed the save round-trip), and preserved by assistants.js - but NOTHING reads it for behavior. The actual default comes from the top-level `newChatStartsWith` setting (General tab), which the History shows replaced the "Set as Default Assistant" toggle; `isDefault` was left behind as dead metadata with no UI to view or change it.

**Evidence:** grep of production code: isDefault appears only in DefaultSettings.ahk, SettingsApply.ahk, assistants.js (write/carry), never in a condition/behavior; `webui/js/settings/sections/general.js` wires newChatStartsWith.

**Verification:** headless scenario 166 (noApp static): behavior-reader scan of AssistantRepo/ChatSettings/SettingsApply/CommandMenu/ThreadSettings/model-picker finds only carry-only references; assistants.js has no isDefault UI field.

### 6. A failed (or usage-less) title-generation API call is never tracked in the usage dashboard - _TitleGen_TrackUsage returns early when promptTokens <= 0 although the billed call happened

**Scenario:** 167 (scenario code in scenarios/misc.js)

**Status:** verified

**Repro:** Trigger title generation while the title API call fails (or returns without usage). Open Usage Dashboard -> commands section.

**Expected:** Every title-generation API call (the mock/cost is billed) appears in the dashboard, with the response time recorded even when no title was produced.

**Actual:** `generateThreadTitle` always calls `_TitleGen_TrackUsage(...)` after the request, but `_TitleGen_TrackUsage` returns early when `promptTokens <= 0`. A failed/usage-less response leaves promptTokens at 0, so no `CommandUsage_Upsert` row is written - the billed call and its latency never reach the dashboard (the API log does record it, so the call is known).

**Evidence:** `chat/ThreadTitleGen.ahk` (_TitleGen_TrackUsage `if promptTokens <= 0 return`; _TitleGen_ParseResponse defaults to 0 on failure).

**Verification:** headless scenario 167 (noApp static): the TrackUsage call exists after the request and the early-return guard is present with no failure fallback.

### 7. Usage dashboard rows with an empty provider (model removed from settings, MessageRepo provider fallback fails) render in the chart under "" but are absent from the provider filter dropdown

**Scenario:** 168 (scenario code in scenarios/usage-tokens.js)

**Status:** verified

**Repro:** Use a model whose provider cannot be resolved (e.g. a short-id model no longer present in Settings, or a renamed/legacy id) so `MessageRepo.Insert` stores `provider: ""` in chat_usage. Open Usage Dashboard.

**Expected:** The row's cost is attributable - either listed under a real provider or visible/selectable in the provider filter.

**Actual:** The chart's provider-mode key is `c.provider || extractProvider(c.model)` = "" for such rows (they render under an empty/blank key), while `populateFilters` builds the dropdown only from the backend's distinct provider list (which excludes ""), so the empty-provider cost can never be isolated or filtered; "All Providers" shows it but no provider selection can scope to it.

**Evidence:** `chat/db/MessageRepo.ahk` (provider fallback leaves "" when the model is unknown), `webui/js/usage-dashboard.js` (renderMainChart key `c.provider||extractProvider(c.model)`; populateFilters iterates `allData.providers` only).

**Verification:** headless scenario 168 (vm, real usage-dashboard.js): row provider="" + backend providers ['deepseek'] -> filter dropdown has no '' option while the chart key would be ''.

### 8. Branch navigation never refreshes the sidebar thread list - handleBranchSwitch bumps updated_at but posts no threadList, so the sidebar order (and the #155 model badge) stay stale after a branch switch

**Scenario:** 174 (scenario code in scenarios/chat-tree.js)

**Status:** verified

**Repro:** Have two threads A (newer) and B (older, with two branches). Open B and click "Next branch" on the branched assistant. Look at the sidebar order.

**Expected:** B just became the most recently active thread, so it should move to the top (and its model badge should reflect the active branch).

**Actual:** `ChatDB.Msg_SwitchBranch` bumps `updated_at=datetime('now')` (the DB is correct), but `handleBranchSwitch` only posts `updateChatView` + `updateBranchInfo` + `postThreadStats` - never `_postThreadListRefresh()`. The sidebar keeps its previous order (and the previously rendered model badge from ThreadRepo.List, bug #155) until some other action (send/delete/rename/refresh) reposts the thread list. The `datetime('now')` second granularity also means rapid sends/switches within one second tie and order arbitrarily by rowid on the next refresh.

**Evidence:** `chat/callbacks/Branch.ahk` (handleBranchSwitch posts no threadList), `chat/db/TreeRepo.ahk` (SwitchBranch sets updated_at), `chat/db/ThreadRepo.ahk` (List ORDER BY updated_at DESC, second-granular datetime).

**Verification:** headless scenario 174 (live): B's updated_at bumped (2026-08-10 11:22:49 -> 11:22:52) after Next branch, but the sidebar order stays A,B - no refresh was posted.

### 9. Streamed content is corrupted when a poll boundary splits a UTF-8 multibyte character - the File.Pos byte seek resumes inside a character and inserts U+FFFD replacement chars into the persisted content

**Scenario:** 160 (scenario code in scenarios/misc.js)

**Status:** verified

**Repro:** Stream a response whose content contains a multibyte character (accented Latin, Greek, CJK) while the 100ms poll timer reads the cURL output file at a moment the file write split the character.

**Expected:** The persisted content equals the sent content byte-for-byte.

**Actual:** `_readFileChunk` opens the output with `UTF-8-RAW`, seeks with `file.Pos` (byte position) and resumes at the previous EOF. When the poll boundary lands inside a multibyte character, AHK's decoder returns U+FFFD for the split sequence on BOTH sides: the first read yields "ab\uFFFD", the resumed read "\uFFFDcd", and the joined content "ab\uFFFD\uFFFDcd" is permanently mangled (11 UTF-8 bytes instead of 6) before it reaches SSEParser. Whole characters read in one poll round-trip fine, so the corruption is timing-dependent.

**Evidence:** `chat/streaming/StreamHandler.ahk` (_readFileChunk FileOpen UTF-8-RAW + file.Pos byte seek).

**Verification:** headless scenario 160 (probe mirroring the exact File calls): whole read OK; split read produces replacement chars (probe verdict BUG-present(split-mangles)).

### 10. Search FTS5 loses prefix matching when the query ends in an apostrophe - the trailing-* guard checks the wrong quote character (terms are always double-quoted)

**Scenario:** 161 (scenario code in scenarios/misc.js)

**Status:** verified

**Repro:** Search for a partial word where the query string ends in `'` (e.g. "comp'"), where the same word without the apostrophe finds results.

**Expected:** "comp'" behaves like "comp" (prefix match on the last word - the code's comment says prefix matching is intentional).

**Actual:** `SearchRepo._FTS5` wraps every term in double quotes via `_FTS5QuoteTerm`, then appends `*` for prefix matching UNLESS the raw query's last char is `*` or `'`. The `'` check was meant to detect "the last word is quoted" (comment), but terms are ALWAYS double-quoted - so a query whose last character is an apostrophe (e.g. "comp'") skips the `*` and matches only the literal token "comp'": "comp" finds "complete"/"compass" (1 hit), "comp'" finds 0.

**Evidence:** `chat/db/SearchRepo.ahk` (_FTS5 lastChar check `!= "*" && != "'"`; _FTS5QuoteTerm always double-quotes).

**Verification:** headless scenario 161 (probe, real SearchRepo): `_FTS5("comp")` hits=1 vs `_FTS5("comp'")` hits=0.

### 11. Cross-thread search navigation race - _pendingSearchScrollMsgId is consumed by ANY thread's initChatMode, so navigating to another thread (or a failed load) silently drops or misroutes the search navigation

**Scenario:** 175 (scenario code in scenarios/misc.js)

**Status:** verified

**Repro:** Search globally, click a result in thread A, and immediately click thread B (or let A's load fail) before the navigation completes.

**Expected:** The search navigation lands on the clicked message in thread A regardless of what the user does in between.

**Actual:** The cross-thread search click sets `_pendingSearchScrollMsgId = messageId` and posts loadThread(A). `initChatMode` (called on EVERY thread load) consumes the pending id unconditionally: if the user opened thread B first, B's initChatMode posts `navigateToMessage(A's msg)` while activeThreadId=B - AHK's `Msg_SetActiveLeaf(B, A-msg)` then fails (the message is not in B), so the navigation is silently dropped and the search scroll never happens. If A's load fails entirely, the pending id survives and the NEXT unrelated thread load consumes it, posting a spurious navigation for a message that isn't in that thread.

**Evidence:** `webui/js/chat/chat-search.js` (_pendingSearchScrollMsgId set on cross-thread click; onSearchCrossThreadLoaded consumes it), `webui/js/chat/chat-core.js` (initChatMode calls onSearchCrossThreadLoaded for every thread), `chat/callbacks/Sidebar.ahk` (navigateToMessage -> Msg_SetActiveLeaf rejects cross-thread ids).

**Verification:** headless scenario 175 (vm, real chat-search.js + chat-core.js): pending "m-A-1" consumed by thread B's initChatMode (navigateToMessage posted with activeThreadId=t-B); a failed load leaves the pending for thread C (spurious navigateToMessage("m-A-2")).

## History (append-only)

Entries move here when a bug is closed (user committed) or refuted. Add one line per
closure; never rewrite past entries.
- 2026-08-10 - "Reasoning-only streams report ttft_ms=0 (the first-token timer only stamps content chunks, never reasoning)" - FIXED: _processChunk now stamps firstTokenTime on reasoning chunks too, so reasoning-only streams record a real TTFT (popover/dashboard/API-log latency all use it); scenario 170 flipped to a regression check + StreamHandler unit test.
- 2026-08-10 - "Cancelling a stream AFTER switching threads writes the partial response into the WRONG thread" - FIXED: _handleStreamCancelled now persists the cancelled partial into the thread captured at send time (_streamThreadId) like the completion path (bug #159), and _cleanupStreamState is now idempotent (Has-guarded deletes so a missing/partial stream state cannot crash the cancel path); scenario 171 flipped to a regression check + StreamError unit test.
- 2026-08-10 - "Retry failure hides the original response (bubble gone + error banner until reload; DB row intact)" - FIXED: retryLastAssistantMessage now remembers the removed messages (_retryRemovedMessages) and the global showError path restores them on a failed retry (cleared on success/cancel via stream.js), so the original response stays visible; scenario 169 flipped to a regression check + chat-input/stream-state unit tests.
- 2026-08-10 - "Hard-deleting / empty-trashing the streaming thread mid-stream silently DROPS the completed response" - FIXED: the send-time thread capture (bug #159) keeps the completion persisting into the removed thread's id (a dangling trace row) and usage-tracking the billed call instead of skipping the insert when activeThreadId is cleared; scenario 172 flipped to a regression check + StreamHandler unit test.
- 2026-08-10 - "A mid-stream failure with no usage chunk crashes the completion handler (CostCalculator reads usage.promptTokens unguarded) - UI stuck with a misleading Request failed banner" - FIXED: CostCalculator.ComputeTokenCosts now guards promptTokens/completionTokens like cachedTokens (empty usage returns empty costs), and _handleStreamComplete's catch re-enables the input/cursor, so a usage-less partial completes cleanly and the thread stays usable; scenario 173 flipped to a regression check + CostCalculator unit test.
- 2026-08-10 - "Switching threads while a request is streaming persists the response into the WRONG thread" - FIXED: sendStreamingRequest now captures the sending thread (_streamThreadId) and the completion handler (saveStreamResponse/_persistStreamResponse/_maybeGenerateTitle/_handleStreamComplete) uses it instead of the current activeThreadId, so navigation mid-stream never redirects the response to the newly-active thread; scenario 159 flipped to a regression check + StreamHandler unit test.
- 2026-08-10 - "Models tab: focusing and blurring the Context field corrupts 128K -> 128 (the blur handler parseInt's the DISPLAY string)" - FIXED: models.js now parses the context display with a k/M-aware parser (_parseContextString) on blur, so the suffix round-trips and the saved context keeps its full value; scenario 158 flipped to a regression check + models unit test.
- 2026-08-10 - "Forking AT a user message under-reports the fork's Context Used (the user row's active_path_tokens never includes its own backfilled token_count)" - FIXED: _BackfillUserTokens now also updates the backfilled user message's active_path_tokens (parent context + own contribution), so a fork at that message reports the full context; scenario 157 flipped to a regression check + ChatDB unit test.
- 2026-08-10 - "Overwrite-editing a USER message keeps its OLD backfilled token_count, so the NEXT user message's backfill subtracts the stale value and its token popover over-counts" - FIXED: Msg_Edit now refreshes an edited user message's token_count from the new content (~1 token per 3 chars, a documented heuristic), so the next backfill subtracts the NEW value; scenario 156 flipped to a regression check + ChatDB unit test.
- 2026-08-10 - "Sidebar thread model badge is stale after a branch switch (ThreadRepo.List shows the LAST-INSERTED assistant model, not the ACTIVE path's model)" - FIXED: ThreadRepo.List now walks from the active leaf to the nearest assistant for the badge model, so the sidebar follows the branch currently open; scenario 155 flipped to a regression check + ChatDB unit test.
- 2026-08-10 - "Save as Branch on an assistant message drops the reasoning/thinking CONTENT (the branch copy keeps thinking_tokens but the DB reasoning column is empty)" - FIXED: handleEdit's branch-mode insert now carries the source message's reasoning, so the branch keeps the Thought Process block together with the thinking tokens (matching fork copies); scenario 154 flipped to a regression check + BranchFlow unit test.
- 2026-08-10 - "Changing a model price in Settings re-prices the thread's HISTORICAL cumulative cost in the header while the dashboard keeps the original per-call costs" - FIXED: messages now snapshot their input/cached/output/total costs at insert time (schema v6, legacy rows backfilled once) and _RecomputeCumulativeCounters sums those snapshots instead of re-pricing every assistant row with the current model prices, so the header matches the dashboard after a price change; scenario 153 flipped to a regression check + ChatDB unit test.
- 2026-08-10 - "A failed title-generation request permanently disables auto-titles for that thread (the bug #140 dispatch guard is never cleared on failure)" - FIXED: generateThreadTitle now clears _titleGenRequestedThreads on the no-title path, so a transient failure is retryable while the duplicate-request guard still applies to in-flight/success cases; scenario 151 flipped to a regression check + ThreadTitleGen unit test.
- 2026-08-10 - "Save as Branch on a USER message keeps the ORIGINAL message's token attribution forever (the branch copy is never re-backfilled)" - FIXED: _BackfillUserTokens now re-backfills LOCAL copies (is_local_copy=1) even when their copied token_count is non-zero, so the branch's own API call replaces the stale attribution, and _updateUserTokenCount applies a 0 contribution to the UI; scenario 150 flipped to a regression check + ChatDB/stream-state unit tests.
- 2026-08-10 - "Command requests with SHORT model ids (no provider prefix) silently drop the thinking config" - FIXED: LLMRequestBuilder.createJSONRequest now resolves model metadata via ModelResolver.Lookup (the chat path's fix from bug #43), so short-id commands carry their thinking/reasoning config; scenario 149 flipped to a regression check + LLMRequestBuilder unit test.
- 2026-08-10 - "Navigating to a message with multiple retry continuations lands on the ORIGINAL (oldest) continuation, not the most recent retry" - FIXED: TreeRepo._WalkToLeaf now orders children by sibling_index DESC (retries get HIGHER indexes) and the tree modal's _findDefaultLeaf takes the FIRST child of the DESC-sorted children array, so navigation lands on the newest retry; scenario 148 flipped to a regression check + ChatDB/chat-branching unit tests.
- 2026-08-10 - "User message token backfill leaks the previous assistant's THINKING tokens into the next user's contribution (token popover over-counts)" - FIXED: _BackfillUserTokens now subtracts assistant thinking_tokens (token_count holds only visible output) when computing the next user's contribution; scenario 145 flipped to a regression check + ChatDB/UsageTracking unit tests (the UsageTracking multi-turn fixture was corrected to a thinking-consistent prompt).
- 2026-08-10 - "Retrying an assistant that has no parent (root message, e.g. after deleting the root user message) creates the retry as a CHILD of the original instead of a sibling" - FIXED: retryAction flags a root retry (pendingRetryIsRoot) and _persistStreamResponse inserts the new response with parent_id NULL (same sibling group), so the retry becomes a proper root SIBLING instead of a child of the original; scenario 147 flipped to a regression check + ChatDB unit test.
- 2026-08-10 - "Save as Branch" after removing an attachment deletes the attachment from the ORIGINAL message (the source branch loses it permanently)" - FIXED: handleEdit now applies deferred attachment removal only in overwrite mode; branch mode copies the source attachments EXCLUDING the removed ones (Attachment_CopyForMessage gains an exclude list), so the original keeps its attachment while the new branch is created without it; scenario 146 flipped to a regression check + BranchFlow/AttachmentRepo unit tests.
- 2026-08-10 - "Forking at a message drops OFF-PATH children of the fork point itself (existing alternative continuations are not copied)" - FIXED: TreeRepo._CopyOffPathSiblings now excludes only the ACTIVE continuation child of the fork point (previously every child of the fork point was skipped), so an already-existing off-path branch under the fork point is copied with its subtree; scenario 143 flipped to a regression check + ChatDB fork unit test.
- 2026-08-10 - "Save as Branch" on an assistant message double-counts the copied token metadata in the thread cumulative counters after the next real exchange (header vs dashboard disagree)" - FIXED: messages now persist an is_local_copy flag (schema v5) and _RecomputeCumulativeCounters skips local copies, so a branch-edit copy's COPIED tokens are never charged again and the header matches the dashboard; scenario 144 flipped to a regression check + ChatDB unit tests.

- 2026-08-10 - "Command empty APIModels sends a model-less request" - PARTIALLY REFUTED: AHK's `StrSplit("")` returns an EMPTY array, so processInitialRequest's loop never runs and the command is a silent NO-OP (no request at all) - tracked as #162; `createJSONRequest("")` would emit `{"model":""}` if it were ever reached. `_RecomputeCumulativeCounters` skipping empty-model assistant rows (lead 13) is REFUTED as unreachable: no current flow can insert a real assistant row with model "" (the empty-model command no-ops first; cancel/error paths always carry a model). The probe check `empty-model-skip` in probe-bughunt-db.ahk documents the latent hazard only.
- 2026-08-10 - "GetThreadStats contextWindow=0 for models with blank context" - REFUTED (intended): the header's `cw ? ' / ' + formatCompact(cw) : ''` deliberately omits the "/ total" suffix when the model has no configured context; the 1,048,576 fallback in GetThreadStats applies only when the context key is entirely absent. A blank context means "unknown total" and hiding it is consistent with the UI.
- 2026-08-10 - "Settings leftovers (hotkeys.reload/suspend, collapseThinking, commands fields, empty SetFont, icons browse path)" - REFUTED: Main.ahk registers `SettingsService.RegisterHook("hotkeys", _registerAllHotkeys)`, so reload/suspend re-register live (bug #4/#8 family); `collapseThinking` is applied per reasoning chunk from the current providers global; commands field round-trips were fixed in #101 (scenario 101 regression); an empty `SetFont` face is valid (falls back to the default font); icon path resolution was fixed in #18.
- 2026-08-10 - "Tree modal with multiple roots (layout / Current marker)" - REFUTED: running the REAL `_layoutTreeNodes` in a vm with two root assistants (delete-root-user + retry shape) lays them out with the SIBLING_GAP cushion (y=60 and y=220, no overlap) and marks only the active root "(Current)" - the root-gap handling the lead suspected is present and correct.
- 2026-08-10 - "handleModelSettingsUpdate with empty model + no assistant resets singleAPIModelName to appDefaultModel" - REFUTED: `ThreadSettings.ToThreadSettingsMessage` always sends the current effective model, `populateCurrentSettings` mirrors it into `_currentSettings.model`, and `_sendAllSettings` only sends model "" when an ASSISTANT is active (where the `activeAssistantId` guard prevents the reset). The appDefaultModel fallback fires only in the genuinely-default state and cannot overwrite a thread's model override during a side-setting edit.
- 2026-08-10 - "Msg_Edit mid-path + fork leaves stale active_path_tokens (lead 22)" - REFUTED as a separate bug: a fork at an edited user message is the intersection of two already-tracked bugs - #156 (overwrite edit never resets the user's stale token_count) and #157 (fork-at-user copies the stale active_path_tokens). No new code path beyond those two.

- 2026-08-08 - "Cancelling a stream mid-response records a fake API request and inflates the thread's cumulative input tokens (header and usage dashboard disagree)" - FIXED: _handleStreamCancelled now inserts the cancelled partial as local_copy, so MessageRepo.Insert never upserts chat_usage (no fake API request) and never recomputes the cumulative counters from the un-billed parent context; scenario 133 flipped to a regression check + StreamError unit tests.

- 2026-08-08 - "Follow-up messages drop the image context of earlier attached images from the API request (multi-turn vision loses the image after the first exchange)" - FIXED: ChatRequestBuilder._ProcessAttachmentsForPath now attaches EVERY user message's attachments (images + file contexts) to its API content part, so follow-up requests keep the earlier image context (the old _ProcessAttachmentsForLastUser only processed the last user message); scenario 142 flipped to a regression check + ChatRequestBuilder unit test.

- 2026-08-08 - "Retrying the first exchange fires a second title-generation request (duplicate API call while the title is still 'New Chat')" - FIXED: ThreadTitleGen keeps a per-thread dispatched-request guard (_titleGenRequestedThreads) and _maybeGenerateTitle skips re-triggering, so a retry of the first exchange no longer fires a second title request; scenario 140 flipped to a regression check + ThreadTitleGen unit tests.

- 2026-08-08 - "Changing the 'Active Icon' (iconOn) in Settings is not re-applied to the already-open chat window (stale until restart)" - FIXED: new chat/ChatWindowIcon.ahk re-applies the window icon (WM_SETICON) from the current iconOn global at startup AND via a SettingsService chatWindowIcon hook, so Active Icon edits apply to the open chat window live (mirrors the tray-icon pattern); scenario 138 flipped to a regression check + ChatWindowIcon unit tests.

- 2026-08-08 - "Forking a chat drops the deeper branches below off-path siblings" - FIXED in f0490c7: TreeRepo._CopyOffPathSiblings now walks the full descendant subtrees of copied off-path siblings (children of the fork point are excluded - they are the source thread's continuation beyond the fork), so the fork is a faithful copy of the conversation tree; scenario 113 flipped to a regression check + ChatDB fork unit test.

- 2026-08-08 - "Hard-deleting a message in a branched tree miscalculates cumulative token counters" - FIXED in 664f960: MessageRepo._RecomputeCumulativeCounters is now tree-accurate - it sums each assistant's stored API prompt_tokens (falling back to the parent's active_path_tokens for legacy rows) and counts output/cached only on assistant rows, so a branched delete no longer charges off-path branches with the other branch's tokens (and user input token_counts no longer leak into output - the same fix closes #128); scenario 114 flipped to a regression check + ChatDB/UsageTracking unit tests.

- 2026-08-08 - "Lowering Trash Retention in Settings does not purge expired trash (the settings-update purge hook fails at runtime)" - FIXED in f5ac7f5: SettingsService.RegisterHook("purgeExpired", ...) now registers the plain zero-arg TrashRetentionPurge wrapper instead of the bare static-method reference ChatDB.Thread_PurgeExpired, which AHK v2 cannot invoke via fn.Call() ("Missing a required parameter" - probe-verified, even .Bind() throws); lowering retention now purges expired trash immediately; scenario 120 flipped to a regression check + SettingsHandler unit test.

- 2026-08-08 - "GetActivePath/GetTree/_RecomputeCumulativeCounters still interpolate raw thread_id (missed #109-class escape)" - FIXED in 6eb143d: TreeRepo.GetActivePath/GetTree now route threadId through SQLite.Escape (the _RecomputeCumulativeCounters site was already escaped by the #114 rewrite), closing the last raw-id interpolation class; scenario 115 flipped to a regression check + ChatDB unit test (crafted `bad'thread` round-trips GetActivePath/GetTree).

- 2026-08-08 - "ThreadRepo.Delete double-escapes the thread id - crafted-id threads orphan their attachments" - FIXED in 4dc8557: ThreadRepo.Delete now passes the RAW threadId to AttachmentRepo.DeleteByThread (which escapes it internally), so a crafted-id thread's messages AND attachment rows/files are all removed; scenario 116 flipped to a regression check + ChatDB unit test.

- 2026-08-08 - "Deleting a message that holds the same attachment file twice orphans the file on disk" - FIXED in 32ad2c2: AttachmentRepo.DeleteByMessage/DeleteByThread/DeleteOne now batch-delete the rows first and check the file refcount AFTER (refs=0 removes the file, refs>=1 keeps it), so duplicate rows on one message no longer orphan the file while cross-thread/forks sharing still holds (audit #131 green); scenarios 117 + 131 pass + AttachmentRepo unit tests.

- 2026-08-08 - ""Save as Branch" on an assistant message records a fake API request in the usage dashboard" - FIXED in 77ae619: branch-edit copies are inserted with local_copy: true, so MessageRepo.Insert never upserts chat_usage or re-charges the cumulative counters/costs for them (no API call happened); scenario 118 flipped to a regression check + ChatDB unit test (live audits 119/127 stay green).

- 2026-08-08 - "Saving Settings silently wipes assistant temperature and isDefault (Assistants tab save() only emits the card fields)" - FIXED in 994eb5a: assistants.js save() re-emits the preserved temperature/isDefault from the card dataset and SettingsApply._ApplyAssistants carries isDefault into the runtime globals, so the save round-trip no longer resets assistant temperature to Model Default; scenario 122 flipped to a regression check + assistants-settings JS + SettingsHandler AHK unit tests.

- 2026-08-08 - ""Save as Branch" on an assistant message drops the copy's token metadata (header Context Used falls back to the parent, token popover is blank)" - FIXED in 0d96955: Edit.ahk branch mode now copies the source message's token metadata (token_count/prompt_tokens/thinking/cached/active_path_tokens) into the local_copy insert - captured inside the loop because AHK v2 for-loop variables are not valid after it - and seed.js seeds prompt_tokens like the app schema; scenario 123 flipped to a regression check + ChatDB unit test.

- 2026-08-08 - "Conversation tree modal says "Viewing active path" but counts every node in the tree (off-path branches included)" - FIXED in c1c6387: renderChatTree now labels the subtitle with _countActivePathNodes (the highlighted path) instead of _countTreeNodes (the whole tree); scenario 124 flipped to a regression check + chat-branching unit test.

- 2026-08-08 - "Branch position labels (x/y) go stale after deleting a sibling - they use the raw sibling_index, not the position among remaining branches" - FIXED in 5cee451: buildStructuredMessagesFromPath now labels each branch by its 1-based POSITION in the siblings array (raw sibling_index+1 went stale after a delete and grew with every retry), and the updateBranchInfo IPC got a real WebView implementation; scenario 125 flipped to a regression check + ChatUtils/chat-branching unit tests.

- 2026-08-08 - "Forking mid-conversation copies the source thread's FULL cumulative token/cost counters even though the fork only contains the prefix" - FIXED in be76b6e: ForkThread now recomputes the fork's cumulative counters from its own messages (MessageRepo._RecomputeCumulativeCounters) instead of copying the source thread's ledger verbatim - the per-message active_path_tokens are still copied, preserving bug #48's context part; scenario 126 flipped to a regression check, scenario 48 updated to the same semantics + ChatDB fork unit test.

- 2026-08-08 - "Hard-deleting a message inflates the thread's cumulative OUTPUT tokens (user messages' backfilled input token_count is counted as output)" - FIXED in 664f960 (with #114): _RecomputeCumulativeCounters counts output/cached only on assistant rows, so user token_counts (backfilled INPUT contributions) never inflate cumulative output after a hard delete; scenario 128 flipped to a regression check + ChatDB unit test (UsageTracking regression updated at #114, closed by 7ab4282).

- 2026-08-08 - "Empty Trash / deleteThreadForever leaves stale messages_fts rows (thread-level delete skips FTS cleanup, unlike HardDelete)" - FIXED in 5af8b5d: ThreadRepo.Delete/PurgeExpired now call ChatDB.FTS_Remove for every deleted message before the raw DELETEs, so the FTS index stays in sync in-session (same guarantee as HardDelete, bug #65); scenario 129 flipped to a regression check + ChatDB unit tests.

- 2026-08-08 - "Saving Settings wipes a custom (unlisted) "Response Font" - the select has no matching option so save() emits an empty value" - FIXED in 2e8c4f4: ui-theme.js now records the stored font on each fixed-option select at load() and save() falls back to it when the select has no matching option (the #39 pattern), so custom Response Font / Input Window / Suspend Banner font faces survive a Settings save; scenario 130 flipped to a regression check + ui-theme unit tests.

- 2026-08-07 - "Usage dashboard model heading XSS — model id not escaped in section header" - FIXED in 53a5290: renderModelSections now escapes the model heading with escHtml(model); scenario 95 flipped to a regression static check + usage-dashboard unit test.

- 2026-08-08 - "AttachmentRepo inserts/queries interpolate msgId/threadId without SQLite.Escape — SQL injection" - FIXED in 0bb1d2f: AttachmentRepo now escapes msgId/threadId in Insert/GetByMessage/GetByThread/DeleteByMessage/DeleteOne/CopyForMessage and ChatDB FTS_Sync/FTS_Remove, so crafted ids stay literal (same class as #80/#81); scenario 96 flipped to a regression static check + ChatDB unit test (crafted `bad'id` round-trips through attachment CRUD and FTS).

- 2026-08-08 - "SettingsPersistence.Save is non-atomic — FileDelete then FileAppend leaves empty file on failure" - FIXED in 122ef51: Save now writes settings.json.tmp and renames it over the target (FileMove + file-state verification, since FileMove's return value is unreliable in this AHK build), so a crash/failure mid-write can no longer destroy the original settings.json; scenario 97 flipped to a regression static check + SettingsHandler unit tests (round-trip, replace-not-append, failure cleans temp and returns false).

- 2026-08-08 - "StreamHandler _finalizeStreaming leaks state on cancel — no _cleanupStreamState after _handleStreamCancelled" - FIXED in 8702a42 (hardening): _finalizeStreaming's wasCancelled branch now calls _cleanupStreamState() explicitly before returning (idempotent — _handleStreamCancelled already cleaned up internally), so every exit path guarantees the _stream* keys are cleared and no stale state can leak into the next send; scenario 98 flipped to a regression static check + StreamHandler unit test.

- 2026-08-08 - "MessageRepo.Insert builds parent_id / sibling_group without SQLite.Escape — SQL injection via crafted ids" - FIXED in 13be371: Insert now escapes parent_id and sibling_group (and the active-path parent lookup inside Insert), so crafted ids stay literal; scenario 99 flipped to a regression static check + ChatDB unit test (crafted `bad'parent`/`sib'group` round-trip through Insert).

- 2026-08-08 - "LLMRequestBuilder._FixStreamBoolean uses global StrReplace — user message containing `"stream":1` is corrupted" - FIXED in 7cf0328: _FixStreamBoolean is now quote-aware — it scans the JSON and rewrites only real stream/include_usage/include_thoughts key:value tokens outside string literals (no more global StrReplace over the whole payload); scenario 100 flipped to a regression static check + LLMRequestBuilder unit tests (user prompt with a `{"stream":1}` snippet survives verbatim while the real top-level stream still becomes true).

- 2026-08-08 - "SettingsApply._ApplyCommands _SetIfTruthy drops `false` — clearing stream/isFIM/showInputBox never persists" - FIXED in 0f42fdc: the command copy helpers (_SetIfTruthy/_SetIfNonZero/_SetIfNonEmptyTags) now assign whenever the key exists, so false toggles, maxContextWords 0 and explicitly empty tags survive the save round-trip; scenario 101 flipped to a regression static check + SettingsHandler unit test (ApplyToGlobals keeps stream/isFIM/showInputBox/expandNewlines/includeImageContext=false, maxContextWords=0, tags=[]).

- 2026-08-08 - "UsageRepo provider LIKE does not escape `%` `_` `\` — provider filter `%` matches all models" - FIXED in 8533a7a (hardening): the latent providerChatClause LIKE now escapes `\` `%` `_` via a new UsageRepo._EscapeLike and declares ESCAPE '\' (same pattern as SearchRepo #69); scenario 102 flipped to a regression static check + UsageTracking unit test. (The executed chat/command queries already matched provider exactly, so the wildcard LIKE was latent.)

- 2026-08-08 - "TreeRepo.GetThreadStats pricingUnit picks the first message's model, not the thread's active model" - FIXED in 24089f9: GetThreadStats now resolves pricing via a shared TreeRepo._ResolvePricing (current request model -> thread model_override -> last assistant on the active path) used for BOTH the context window and pricingUnit, so the token bar's per-token prices follow the active model; scenario 103 flipped to a regression static check + UsageTracking unit test (pricing follows the newest assistant, thread override, then request model).

- 2026-08-08 - "TreeRepo._RecomputeActivePath recomputes active_path as prefix sum, losing prompt_tokens for assistants" - FIXED in 634ffca: prompt_tokens is now persisted on every message (schema migration + Insert + fork copies) and _RecomputeActivePath keeps the assistant's API ground truth (prompt + visible + thinking) instead of reducing to a visible-token prefix sum, so Context Used no longer drops after delete/edit; scenario 107 flipped to a regression static check + ChatDB unit tests (ground truth survives recompute; hard-delete re-parenting test updated to expect ground truth).

- 2026-08-08 - "main.js IPC fallback calls arbitrary `window[target]` without allowlist" - FIXED in 38d8292: handleWebMessage now routes the two legacy targets (updateTopbarTitle/updateBranchInfo) via explicit cases and the default case only logs unknown targets — the dynamic window[target](...data) invocation is gone, so a crafted IPC target can no longer invoke arbitrary globals; scenario 108 flipped to a regression static check + main.js unit tests (legacy targets route explicitly; a decoy global is never invoked for an unknown target).

- 2026-08-08 - "Sidebar `folderId` and 15+ remaining ChatDB call sites interpolate raw ids without `SQLite.Escape`" - FIXED in 6aa4798: every remaining raw id interpolation now uses SQLite.Escape — Sidebar (rename/delete/move folder + renameThread), Edit.ahk, MessageRepo (Insert thread_id/role, HardDelete, Edit, GetMaxSiblingIndex, _TouchThreadByMsg, backfill), TreeRepo (GetActivePath, GetSiblings, SetActiveLeaf, SwitchBranch, GetThreadStats, _ResolvePricing, _WalkToLeaf, forks), ThreadRepo (thread listing, PurgeExpired coerces retention to Integer), SearchRepo FTS id list, ChatUtils/ThreadTitleGen/StreamCompletion; scenario 109 flipped to a regression static check + ChatDB unit test (crafted `bad'thread`/`bad'msg` round-trip SetActiveLeaf + HardDelete).

- 2026-08-08 - "Chat streaming temp files with API keys not deleted after success — credential leak in `%TEMP%`" - FIXED in ef41e48: _handleStreamComplete (success) and _handleStreamError (error) now call deleteTempFiles() after their reads, matching the cancel path, and deleteTempFiles is defensive about missing requestParams keys; scenario 110 flipped to a regression static check + StreamHandler unit test (success/error/cancel all delete temp files).

- 2026-08-08 - "ApiLogger LogRequest overwrites log file non-atomically — crash corrupts `LLM_API_Log.json`" - FIXED in 193ed5b: LogRequest and TrimToLimit now write through a new ApiLogger._WriteLogs helper (temp file + FileMove with file-state verification, same pattern as settings #97), so a crash mid-write cannot leave truncated JSON; scenario 111 flipped to a regression static check + LLMRequestBuilder unit test (round-trip, no temp leftover).

- 2026-08-08 - "CurlBuilder does not validate empty endpoint — malformed cURL with no URL" - FIXED in 23d462c: CurlBuilder.Build/BuildStream/BuildFIM now return "" when the endpoint is empty (no URL-less cURL command can be produced) and ChatRequestBuilder + sendStreamingRequest surface a friendly "No endpoint configured" error via the new _ShowEndpointError helper; scenario 112 flipped to a regression static check + LLMRequestBuilder unit test (empty endpoint returns "", FIM endpoint still preferred when configured).

- 2026-08-07 - "SettingsDefaults `_DefaultsAssistants` generates a new UUID on every `GetDefaults()` - defaults not stable" - REFUTED (overstated): UUIDs are generated only when the defaults are first built; after CacheInitialDefaults, GetDefaults returns the cached snapshot, so ids are stable in normal runtime; scenario 94 converted to a regression check for snapshot stability.

- 2026-08-07 - "SettingsDefaults `GetDefaults` shallow-copies `Map` values [latent] - mutating snapshot corrupts pristine defaults" - FIXED in 182c6ce (hardening): GetDefaults now deep-clones nested Maps/Arrays via a new _DeepClone helper, so callers cannot corrupt the cached pristine defaults by mutating a snapshot; scenario 93 flipped to a regression static check + SettingsHandler unit test.

- 2026-08-07 - "Models `ensureFullId` ignores provider dropdown when id already contains `/` - stale provider prefix" - FIXED in 3925a32: ensureFullId now strips any embedded prefix and rebuilds the full id from the selected provider (keeps the id as-is when no provider is chosen); the refresh-modal data-full-id precedence was already fixed by bug #40; scenario 92 flipped to a regression static check + models-pricing-refresh unit test.

- 2026-08-07 - "InputWindow `validateInputAndHide` treats `\"0\"` as empty - `!value` falsy check" - FIXED in b7dfb20: validateInputAndHide now treats only empty/whitespace as empty (Trim(...) = \"\"), so a single \"0\" is accepted; scenario 91 flipped to a regression static check + InputWindow unit tests.

- 2026-08-07 - "SettingsMerge.Override iterates over `incoming` without `IsObject` guard - empty string corrupts settings" - FIXED in b20131d: Override now normalizes non-object incoming payloads to an empty Map before merging; scenario 90 flipped to a regression static check + SettingsHandler unit test.

- 2026-08-07 - "CurlBuilder interpolates API key with `\"` into `-H \"Authorization: Bearer ...\"` without escaping - header break / injection" - FIXED in 0a72a67: Build/BuildStream/BuildFIM now pass the key through CurlBuilder._SafeApiKey (strips \" % & | < > ^) before embedding it in the header; scenario 89 flipped to a regression static check + LLMRequestBuilder unit test.

- 2026-08-07 - "Usage dashboard \"Last 30 Days\" SQL uses UTC while chart uses local - same timezone drift as Last Month" - FIXED with bug #87 (fad0f52): the month filter now uses a local monthCutoff (FormatTime(DateAdd(A_Now,-29))) instead of UTC date('now','-30 days'); scenario 88 flipped to a regression static check.

- 2026-08-07 - "Usage dashboard \"Last Month\" SQL uses UTC `date('now')` while chart labels use local `new Date()` - timezone drift" - FIXED in fad0f52: _WhereDate now takes local month boundaries (monthStart/lastMonthStart/monthCutoff computed via FormatTime/DateAdd) for lastMonth/thisMonth/month, matching the local chart labels; scenario 87 flipped to a regression static check + UsageTracking unit test.

- 2026-08-07 - "FIM fallback `renderMarkdown` XSS - `md.render` with `html:true` for non-chat content" - REFUTED (duplicate of #57, which was FIXED in 05e2ccb: markdown-it html:false covers the FIM fallback path too); scenario 86 converted to a regression check for the non-chat renderMarkdown path.

- 2026-08-07 - "API Logs Viewer `esc()` does not escape single quote - `title` attribute break and potential XSS" - FIXED in 2bb8435: esc() now escapes single quotes (&#39;) in addition to & < > \", so title attributes cannot be broken; scenario 84 flipped to a regression static check + api-logs-viewer unit test.

- 2026-08-07 - "Thread-map \"who\" label XSS - model name not escaped in right-panel nav list" - FIXED in e5e45b6: renderNavList now escapes the who label with escHtml(who) like the snippet; scenario 83 flipped to a regression static check + chat-sidebar unit test.

- 2026-08-07 - "Usage dashboard provider/model filter dropdown XSS - option values not escaped" - FIXED in fceb5a1: populateFilters now escapes provider/model option values and labels with a local escHtml helper; scenario 82 flipped to a regression static check + usage-dashboard unit test.

- 2026-08-07 - "Branch _setupSiblingGroup UPDATE interpolates msg.id without escaping - SQL injection via crafted message id" - FIXED in 21b5cd1: _setupSiblingGroup now escapes msg.id with SQLite.Escape before the UPDATE; scenario 81 flipped to a regression static check + ChatDB unit test.

- 2026-08-07 - "ThreadRepo SoftDelete/Restore/Delete/Update interpolate threadId without SQLite.Escape - SQL injection via crafted id" - FIXED in f499225: SoftDelete/Restore/Delete/Update now escape threadId with SQLite.Escape (and AttachmentRepo.DeleteByThread too), so crafted ids cannot inject SQL; scenario 80 flipped to a regression static check + ChatDB unit test.

- 2026-08-07 - "Settings file with UTF-8 BOM fails to load - settings silently reset to defaults" - FIXED in 608a7a7: SettingsPersistence.Load now strips a leading UTF-8 BOM (Chr(0xFEFF)) before jsongo.Parse, so BOM'd settings files load instead of silently resetting; scenario 79 flipped to a regression static check + SettingsHandler unit test.

- 2026-08-07 - "Right-rail temperature 0 displays as \"Default\" instead of 0.0 - falsy check hides 0" - FIXED in 5389f74: populateCurrentSettings now keeps a stored 0 and uses explicit empty checks (temperature !== '' && !== undefined && !== null) instead of a truthiness check, so the rail shows 0.0; scenario 78 flipped to a regression static check + model-picker unit test.

- 2026-08-07 - "Empty Send (no text, no attachments) with existing chat history triggers an unexpected retry" - FIXED in 8c651dd: onChatSend now returns early when the input is empty and there are no attachments, so an accidental click/Enter no longer retries the last assistant/user message and burns tokens; scenario 77 flipped to a regression static check + chat-input unit test.

- 2026-08-07 - "initChatMode guard `!activeThreadId` prevents thread switch when WebView already holds a thread" - FIXED in f4cd45f: initChatMode now assigns activeThreadId whenever a threadId is provided (the old !activeThreadId guard left it stale on switches, so sends/search targeted the wrong thread); scenario 76 flipped to a regression static check + chat-core unit test.

- 2026-08-07 - "GoogleChatCompletions budget table matches via substring InStr, not exact family check" - FIXED in b1e1fc0: _BudgetTable now matches the Gemini family (gemini-2.5-pro / gemini-2.5-flash-lite / gemini-2.5-flash / gemini-2.0-flash) instead of any substring, so custom ids like my2.5-pro fall back to the generic table; scenario 75 flipped to a regression static check + LLMRequestBuilder unit test.

- 2026-08-07 - "SettingsApply leaves providerMap stale when all prefixes are cleared" - FIXED in bcd199a: _ApplyProviders now rebuilds providerMap whenever the saved providers define prefixes explicitly (an empty set clears the stale map), while providers without a prefixes key still keep the UserConfig mapping; scenario 74 flipped to a regression static check + SettingsHandler unit test.

- 2026-08-07 - "GoogleChatCompletions disabled thinking config for Gemini 2.x omits include_thoughts (inconsistent with enabled)" - FIXED in d8c0096: DisabledConfig now returns {include_thoughts:false, thinking_budget:0} for Gemini 2.x, symmetric with the enabled config; scenario 73 flipped to a regression static check + LLMRequestBuilder unit test.

- 2026-08-07 - "SystemMessageResolver treats UNC \\server\\share paths as relative - file not found" - FIXED in d58d2bf: Resolve now treats paths starting with \\ or / as absolute (no drive-letter colon required), so UNC/rooted system-message files are read as-is; scenario 72 flipped to a regression static check + UserConfig unit test.

- 2026-08-07 - "Clearing Thread Title Generation model/prompt/maxTokens leaves stale globals [family: #61/#71]" - FIXED in 0f06b9a: SettingsApply._ApplyThreadTitles now assigns the saved value whenever the key exists (empty string included), so clearing title-gen fields resets the stale globals; scenario 71 flipped to a regression static check + SettingsHandler unit test.

- 2026-08-07 - "Search FTS5 MATCH does not escape special characters - C++ or \"hello\" breaks the query (empty results)" - FIXED in ab3ef6b: SearchRepo._FTS5 now quotes each term (_FTS5QuoteTerm, doubling embedded quotes) so FTS5 special characters match literally and the trailing * still does prefix matching; scenario 70 flipped to a regression static check + ChatDB unit test.

- 2026-08-07 - "Search LIKE fallback does not escape % _ \\ - searching for % returns all messages" - FIXED in e452650: new SearchRepo._EscapeLike escapes \\ % _ (used by _Like and _Titles) so user input is matched literally; scenario 69 flipped to a regression static check + ChatDB unit test.

- 2026-08-07 - "ProviderResolver legacy prefix match uses substring InStr, not prefix check - mygpt matches gpt" - FIXED in a368b2a: Resolve now matches legacy short ids by PREFIX (SubStr(...) = prefix) instead of substring InStr, so mygpt-custom no longer resolves to the gpt provider; scenario 68 flipped to a regression static check + LLMRequestBuilder unit test.

- 2026-08-07 - "Header tooltip typo \"Culminative\" (should be \"Cumulative\") and mismatched semantics" - FIXED in d72b4f5: the updateTokenUsage tooltip now reads \"Cumulative Input/output token usage across all conversation branches\"; scenario 66 flipped to a regression static check + chat-format unit test.

- 2026-08-07 - "Hard-deleting a message leaves cumulative token/cost counters stale - header stays inflated" - FIXED in 12f3a8a: MessageRepo._RecomputeCumulativeCounters rebuilds the thread's cumulative input/output/cached/cost counters from the remaining messages (mirroring Insert's per-message accumulation) and HardDelete calls it, so the header totals drop with the deleted message; scenario 65 flipped to a regression static check + UsageTracking/ChatDB unit tests (old preserve-counters test updated to the fixed semantics).

- 2026-08-07 - "Header \"Context Used\" excludes thinking tokens - underreports context window usage" - FIXED in f9769f7: MessageRepo now stores active_path_tokens = prompt + visible + thinking for assistants, and TreeRepo._RecomputeActivePath adds thinking_tokens to the prefix sums, so the header Context Used matches the tooltip/dashboard totals; scenario 64 flipped to a regression static check + ChatDB/UsageTracking unit tests (existing thinking-token expectations updated).

- 2026-08-07 - "Token-bar pricing unit shows 0 for cached input when the model stores \"\" instead of falling back to 10%" - FIXED in d7af83c: TreeRepo.GetThreadStats now treats a stored cachedInput of \"\" as missing and falls back to 10% of the input price; scenario 63 flipped to a regression static check + ChatDB unit test.

- 2026-08-07 - "Forking a chat with temperature 0 drops the override (reset to Default)" - FIXED in 2110b67: TreeRepo._CopyThreadSettings now uses an explicit empty check (temperatureOverride != "") so a stored 0 is copied to the fork; scenario 62 flipped to a regression static check + ChatDB fork unit test.

- 2026-08-07 - "Clearing the Suspend Banner text (and other UI fields) has no effect [family: #61/#71 stale global on clear]" - FIXED in 4b609f2: SettingsApply._ApplyUI/_ApplyInputWindow/_ApplySuspendBanner now assign the saved value whenever the key exists (empty string included) instead of skipping empties, so clearing a field resets the stale global; scenario 61 flipped to a regression static check + SettingsHandler unit test. (#71's _ApplyThreadTitles uses the same pattern and is fixed in its own cycle.)

- 2026-08-07 - "Forking a chat drops the thread's folder (the copy lands in Unfiled)" - FIXED in 6a0c98b: TreeRepo._CopyThreadSettings now copies folder_id alongside the other thread-level settings, so forks stay in the source folder; scenario 58 flipped to a regression check + ChatDB fork unit test.

- 2026-08-07 - "Chat message content is rendered as raw HTML with no sanitization (embedded HTML/scripts execute in the WebView)" - FIXED in 05e2ccb: markdown-it is now configured with html:false, so raw HTML in messages is escaped and rendered as inert text (was html:true, letting inline event handlers run with chrome.webview.postMessage access); scenario 57 flipped to a regression check + main.js unit test. (#86 is a duplicate of this bug and will be refuted when reached.)

- 2026-08-07 - "Stopping a stream before the first token shows an error banner instead of a clean cancel" - FIXED in 4fe5245: _finalizeStreaming now checks _streamCancelled BEFORE the empty-content branch, so a user Stop before the first token finalizes as a clean cancellation (_handleStreamCancelled posts streamCancelled) instead of the misleading API-key error banner; scenario 56 flipped to a regression static check + StreamHandler unit test.

- 2026-08-07 - "Branch switch / search navigation land on the OLDEST continuation of a message while the tree modal lands on the newest" - FIXED in 6e87641: TreeRepo._WalkToLeaf now picks the same child the tree modal's _findDefaultLeaf chooses (ORDER BY sibling_index, rowid DESC = newest continuation) instead of the oldest by created_at; scenario 55 flipped to a regression check + ChatDB unit test.

- 2026-08-07 - "Dashboard \"Last 24 Hours\" spans two calendar days" - FIXED in 74c589d: UsageRepo._WhereDate now takes the LOCAL today date (FormatTime) for the \"day\" range, so the summary counts the same local calendar day the chart plots (usage rows are stored with local dates); scenario 53 flipped to a regression check + UsageTracking unit test. (The month/lastMonth ranges still use UTC - tracked as #87/#88.)

- 2026-08-07 - "Usage dashboard double-counts thinking tokens for command usage" - FIXED in f9f34ea: renderSummary and renderModelSections now count command_usage.completion_tokens once (it already includes thinking, matching chat's output_tokens) instead of adding thinking_tokens again; scenario 52 flipped to a regression check + usage-dashboard unit test.

- 2026-08-07 - "Forking a chat resets the token/cost stats (active_path_tokens and cumulative counters are not copied or recomputed)" - FIXED in 4bdfc51: TreeRepo.GetActivePath now selects active_path_tokens, _InsertForkMessage/_CopyOffPathSiblings copy it per message, and ForkThread carries the source thread's cumulative counters to the fork, so the token bar keeps context + cost; scenario 48 flipped to a regression check + ChatDB fork unit test.

- 2026-08-07 - "Canceling a message edit leaves removed attachments hidden in the UI but still in the DB (they get sent anyway)" - FIXED in 5597ff1: the edit Cancel handler now restores wrappers of deferred-removed attachments, clears _removedAttachmentIds, and resets _editingMessageId, so cancel is a clean rollback; scenario 49 flipped to a regression check + chat-branching unit test.

- 2026-08-07 - "Command \"Stream Response\" + pasteMode replace/append silently produces no output" - FIXED in 1979523: InlineRequestRunner now builds its non-FIM request with stream=false (was passing the command's stream flag, so the API answered SSE the single-shot parser could not read); scenario 46 flipped to a regression static check + InlineRequestRunner unit test.

- 2026-08-07 - "Refresh-models modal discards edits to a model id (stale data-full-id wins on Save)" - FIXED in fa86b1c: saveRefresh and _rightPanelIds now prefer the live input value over the stale data-full-id attribute (the provider column still supplies the prefix), so renames in the refresh modal survive; scenario 40 flipped to a regression check + models-pricing-refresh unit tests.

- 2026-08-07 - "Tray \"New Chat\" ignores the \"New Chats Start With\" default" - FIXED in 4d9228b: new _applyNewChatDefaultToFreshThread applies the configured assistant/model + default font size to fresh (message-less, settings-less) threads; LoadThreadIntoUI now calls it, so tray/command-line-spawned chats start with the configured default; scenario 41 flipped to a regression static check + ChatSettings unit tests (fresh thread gets default, configured thread untouched).

- 2026-08-07 - "System-message modal silently clears a custom (unlisted) system-message file on Save" - FIXED in 0218d75: populateSysMsgModal records the stored file on the modal and the Save handler falls back to it when the select has no matching option (selectedIndex=-1), so a custom file survives opening + saving; scenario 39 flipped to a regression check + sysmsg-modal unit tests (preserve custom file, explicit \"(none)\" still clears).

- 2026-08-07 - "\"Response Font\" setting is not applied to chat messages until Settings is opened" - FIXED in 13a4cec: Dispatch now re-pushes the merged appSettings on the webViewReady handshake and after every successful save, so ui-theme.js applies --chat-font-family (and other UI CSS vars) at startup and live; scenario 45 flipped to a regression check + ChatDispatch unit tests.

- 2026-08-07 - "Chat window title stays stale after renaming a thread and switching to another" - FIXED in eb54326: _LoadThreadAndRefreshUI now sets chatWindow.Title from the active thread (was only renameThread), so the title bar follows thread switches; scenario 38 flipped to a regression check + ChatUtils unit test.

- 2026-08-07 - "Tray menu item changes don't apply until restart" - FIXED in 5701466: new app/TrayMenu.ahk rebuilds A_TrayMenu from the current trayMenuItems global at startup and via a SettingsService trayMenu hook, so Menu Items edits apply live; scenario 37 flipped to a regression static check + TrayMenu unit tests.

- 2026-08-07 - "Command temperature/reasoning are dropped when the command model equals the app default" - FIXED in a1e086e: processInitialRequest now persists temperature/reasoning/system overrides unconditionally (only modelOverride is gated by `fullAPIModelName != appDefaultModel`); scenario 36 flipped to a regression static check + RequestProcessor AHK unit test.

- 2026-08-07 - "Temperature override of 0 is dropped when the thread reloads (right rail shows Default)" - FIXED in b3a50f8: ThreadSettings.ComputeEffective now tracks hasTemperatureOverride so a stored 0 is a valid override (assistant temperature only applies when there is no per-thread override); scenario 35 flipped to a live regression check (sse-success asserting temperature 0 in the request) + ChatSettings AHK unit tests (ComputeEffective and restore path).

- 2026-08-07 - "Tray icon changes don't apply until restart" - FIXED in fb7fce8: new app/TrayIcon.ahk re-applies the tray icon from the current icons globals (honoring suspend state) at startup and via a SettingsService hook, so icon edits apply live; scenario 34 flipped to regression check (regression: true) + TrayIcon unit tests.

- 2026-08-07 - "Clearing the chat-window icon setting still loads the default custom icon" - FIXED in 10549ec: SettingsApply._ApplyIcons now applies empty strings (was skipped, kept DefaultSettings); scenario 33 flipped to regression check (regression: true) + SettingsHandler unit test.

- 2026-08-07 - "Forking a chat drops the per-thread font size and Advanced toggles" - FIXED in 1dd7ee8: TreeRepo._CopyThreadSettings now copies font_size and advanced_toggles (was only model/system/reasoning/temperature/assistant); scenario 44 flipped to regression check (regression: true) + ChatDB fork unit test.

- 2026-08-07 - "Font-size +/- buttons use a stale 17px base after a thread with a custom size loads" - FIXED in bf7d0aa: UiControls now exposes syncFontSize() and model-picker-config calls it when applying per-thread font size; scenario 31 flipped to regression check (regression: true) + ui-controls unit test.

- 2026-08-07 - "Deleting a message confirms "data is preserved" but hard-deletes it" - FIXED in 6877a5e: webui/js/chat/chat-branching.js deleteMessage now says "This permanently deletes the message and cannot be undone." (was lie "data is preserved"); scenario 30 flipped to regression check (regression: true) + chat-branching unit test.

- 2026-08-07 - "Blank cached-input price costs 0 instead of the advertised 10% fallback" - FIXED in d2c4d79: CostCalculator._ResolvePricing now falls back to inputPrice*0.1 for blank/zero/empty cachedInput (was only missing); scenario 29 flipped to regression check (regression: true) + CostCalculator unit tests.

- 2026-08-05 - "Usage dashboard chart date labels shift a day in UTC+x timezones (toISOString on local dates)" - FIXED in 8df50b4: getDateRangeLabels() keys labels by the LOCAL date (localDateKey) instead of toISOString(); scenario 42 flipped to a regression check (regression: true).
- 2026-08-05 - "Thinking config is silently dropped for short-form model ids (no provider prefix)" - FIXED in cc3db48: ChatRequestBuilder/ThreadSettings resolve model metadata through ModelResolver.Lookup (short ids now match, thinking kept); scenario 43 flipped to a regression check (regression: true) + unit tests.
- 2026-08-05 - "Vision gate rejects images/screenshots for short-form model ids (no provider prefix)" - FIXED in cc3db48: AttachmentUtils.HasVision resolves through ModelResolver.Lookup; scenario 51 flipped to a regression check (regression: true) + unit tests.

- 2026-08-03 - "Chat-header token bar contract on branch switch" - REFUTED: the
  header honors its tooltips (Context Used follows the active path 65->80 while
  cumulative cost/totals stay); scenario 54 kept as a regression check.
- 2026-08-03 - "Composer Tools dropdown switches do nothing (dead toggles)" - REFUTED: the composer Tools toggles (Web Search / Code Execution / Calculator) are intentional stubs for a future feature (user-confirmed); scenario 32 removed.
- 2026-08-03 - "Sidebar inline rename saves on Escape instead of canceling" - REFUTED: WebView2 does not dispatch blur when the focused input is removed from the DOM, so Escape cancels the rename and no renameThread is posted. Scenario 28 kept as a regression check (regression: true).
- 2026-08-03 - "Reasoning-only responses get no action buttons until reload" - FIXED in ff6a6c3: onStreamDone now persists the assistant message and adds action buttons when thinking was streamed with empty final content (mirrors the existing cancelStreaming guard); scenario 21 flipped to a regression check (regression: true) + stream-state unit test.
- 2026-08-03 - "Right-panel Advanced toggles (Code Execution / Web Search) do nothing" - FIXED in aafa4ed (+247d6c5): Structured Outputs removed entirely; Code Execution / Web Search are persisted stubs (state round-trips through updateModelSettings/requestParams/thread DB, no response_format/tools sent); scenario 20 flipped to a regression check (regression: true) + ChatSettings/request-builder AHK + JS unit tests.
- 2026-08-02 â€” "Dashboard 'All Time' caps the chart at 365 days (summary shows all time)" â€” FIXED in 35770c0: `getDateRangeLabels()` now handles the `all` range explicitly, spanning oldest-recorded-date through today (365-day fallback when empty) so the chart matches the summary; scenario 19 flipped to a regression check (`regression: true`) + usage-dashboard unit tests.
- 2026-08-02 â€” "Custom icon picked outside the repo never applies to the chat window" â€” FIXED in 6a8a0db: new `chat/ChatIconResolver.ahk` resolves icon paths (absolute/UNC paths used as-is, repo-relative ones prefixed with `A_ScriptDir "\..\"`) so ChatWindow loads icons picked outside the repo; scenario 18 flipped to a regression check (`regression: true`) + ChatIconResolver unit tests.
- 2026-08-02 â€” "New models added in Settings lose reasoning/thinking metadata" â€” FIXED in aa9b263: `models.js` now parses `api`/`compat`/`thinkingLevelMap`/`thinkingOff` from fetched raw entries, stashes them on rows, and re-emits them on save (previously only default ids survived via the defaults merge); scenario 5 kept as a regression check (`regression: true`) + unit tests.
- 2026-08-02 â€” "Chat request failure with no output file shows no error and leaves the UI stuck" â€” FIXED in 53aa3e4: `_handleStreamError` now always posts `showError` + `setChatButtonsEnabled(true)` (using cURL stderr when the output file never exists) instead of gating the error/re-enable on the output file; scenario 6 flipped to a regression check (`regression: true`) + StreamError unit test.
- 2026-08-02 â€” "Trash retention never auto-purges" â€” FIXED in e9741f5: `Main.ahk` now calls `ChatDB.Thread_PurgeExpired()` at startup, on an hourly timer, and on settings updates (retention changes apply immediately); scenario 7 flipped to a regression check (`regression: true`) + ChatDB purge unit test.
- 2026-08-02 â€” "Close Windows hotkey setting is ignored by the chat window" â€” FIXED in 0660294: new `chat/ChatHotkeys.ahk` registers the configured `closeWindowsHotkey` in the chat process at startup and after settings saves (empty = disabled), replacing the hardcoded `~^w::`; the stale "restart required" Hotkeys banner was removed (hotkey changes are live on both processes); scenario 8 flipped to a regression check (`regression: true`) + ChatHotkeys unit tests.
- 2026-08-02 â€” "Suspend banner edits don't take effect until restart" â€” FIXED in 5957786: new `app/SuspendBanner.ahk` exposes `_rebuildSuspendBanner()`, which Main now calls at startup and on settings updates (destroying the old GUI, rebuilding from current settings, re-showing when already suspended); scenario 12 flipped to a regression check (`regression: true`) + SuspendBanner unit tests.
- 2026-08-02 â€” "Command Input Window settings are dead (colors never apply; size/font need restart)" â€” FIXED in a35233a: `InputWindow` constructor now applies background + font color, and new `_rebuildInputWindow()` (called at startup and on settings updates) rebuilds the GUI from current settings; scenario 13 flipped to a regression check (`regression: true`) + InputWindow unit tests.
- 2026-08-02 â€” "Title generation makes sidebar folder groups disappear until re-entry" â€” FIXED in a5bd97c: `ThreadTitleGen.ahk` now posts `threadList` as `{ threads, folders }` (reusing `_GetFolders()`) so folder sections stay rendered, and posts the thread's real folder name in `updateTopbarTitle` instead of hardcoded "Unfiled"; scenario 14 flipped to a regression check (`regression: true`) + extended unit test.
- 2026-08-02 â€” "Chat topbar 'Export' button does nothing" â€” FIXED in 71a1294: the button got `id="export-chat-btn"` and `exportChat()` (reusing `getMessageText`) downloads the conversation as a title-named `.txt`; scenario 15 flipped to a regression check (`regression: true`) + unit tests.
- 2026-08-02 â€” "API Logs viewer latency column always shows 'â€“'" â€” FIXED in b1f0386: the viewer now renders `responseTimeMs` (the field every logger writes) instead of the never-written `latencyMs`; scenario 16 flipped to a regression check (`regression: true`) + inline-viewer unit tests.
- 2026-08-02 â€” "Input window text invisible: Edit field stays white against the dark background" â€” FIXED in c13d15c: the Edit control now gets its own `Background` option (it doesn't inherit `Gui.BackColor`), and the default design is light (white field + black text) to match the app theme; scenarios 24 + 25 flipped to regression checks (`regression: true`) + a rendered-pixel probe.
- 2026-08-02 â€” "System-prompt modal '0 chars' counter never updates" â€” FIXED in 6d81eaa: the chat right-rail system prompt modal now updates `#charCount` on input and when opened; scenario 17 flipped to a regression check (`regression: true`) + unit test.
- 2026-08-01 â€” "Quick Access â†’ Usage Dashboard does nothing on prewarmed window" â€” REFUTED:
  the real flow opened the dashboard (the ChatWindow script-window title contains "Chat",
  so the IPC still reaches the process). Scenario 9 kept as a regression check
  (`regression: true`).
- 2026-08-01 â€” "Chat delete confirmations are broken â€” the confirm button is a no-op" â€” FIXED in fdf1dd5: chat-side confirm helper renamed to `_showChatConfirm` so it no longer collides with the Settings `window._showConfirm`; scenario 23 flipped to assert the fixed behavior.
- 2026-08-01 â€” "Command `thinking` settings are dropped after any settings round-trip" â€” FIXED in c7cae37: `_extractCommandParams` now reads Map-form thinking via Has()/[] (HasOwnProp is false for Map keys); scenario 22 flipped to assert Map and object forms both survive.
- 2026-08-01 â€” "Deleting the active chat leaks its per-thread settings into the next chat" â€” FIXED in 76be0ba: deleteThread/deleteThreadForever/emptyTrash now reset requestParams and refresh the UI when the active thread is removed; scenario 1 flipped + dispatch regression tests for active vs inactive deletion.
- 2026-08-01 â€” "New chats ignore the configured `New Chats Start With` default" â€” FIXED in 3e36eeb: added the General-tab dropdown (App Default / assistants / models) stored as top-level `newChatStartsWith`, removed the "Set as Default Assistant" toggle, renamed the runtime baseline `chatDefaultModel` â€” `appDefaultModel`, and applied the default in newChat/handleChatSend; scenario 2 flipped + JS/AHK regression tests.
- 2026-08-02 â€” "Removing models/providers in Settings doesn't persist" â€” FIXED in 04d76dd: save applies each section payload per top-level key (`SettingsMerge.Override`) and load treats the saved models/providers lists as authoritative (`SettingsMerge.MergeAuthoritativeList`), so removals survive both Save and reload/reopen; scenario 3 extended to hide+reopen Settings + regression tests.
- 2026-08-02 â€” "Clearing a hotkey field does nothing â€” hotkeys can't be disabled" â€” FIXED in 00bb503: empty hotkey now means disabled â€” `_ApplyHotkeys` applies the empty value (clears the global) and `_registerAllHotkeys` skips empty bindings (old binding turned Off first); scenario 4 flipped + regression tests + "leave empty to disable" UI hints.
- 2026-08-04 - "Commands lose their system prompt after a settings save: bare system-message filenames cannot be resolved by the command path" - FIXED in 6f7ae77: CommandMenu._resolveSystemMessage now searches default-settings/system-messages/ + AppData like the assistant path; scenario 50 flipped to a regression check (`regression: true`) + UserConfig AHK unit test.
- 2026-08-04 - "Opening Settings wipes the right-rail per-thread settings" - FIXED in f64a59d: main.js routes only the chat-sidebar partial `currentSettings` payload through `populateCurrentSettings`; the full merged settings object goes only to `SettingsPanel.onSettingsReceived` (discriminator: `Array.isArray(data.commands)`); scenario 26 flipped to a regression check (`regression: true`) + main.js routing unit test.
- 2026-08-04 - "System-message files referenced by their legacy `system-messages/` path are never resolved" - CLOSED as won't-fix (single-user, no migration): the path only exists in profiles saved before commit 0229368 moved the files into default-settings/; the user corrected their one profile manually. Scenario 59 removed (no regression check kept).
- 2026-08-04 - "Per-thread system prompt / temperature edits are discarded on reload when an assistant is active" - FIXED in a30ae19: `_restoreThreadSettings` now applies the assistant's system message / reasoning / temperature ONLY when the thread has no per-thread override for that field, so per-thread edits survive reloads and reach the API request; scenario 47 flipped to a regression check (`regression: true`) + ChatSettings AHK unit tests (overrides win; assistant defaults still apply when no override).
- 2026-08-04 - "Typing a system prompt directly into the right-rail field never reaches the API request (the field is display-only)" - FIXED in 50d4111: `#sysMsgMini` now has an input listener that updates `_currentSettings.systemMessage` and posts the debounced `updateModelSettings` (mirrors the modal Save path); scenario 60 flipped to a regression check (`regression: true`) + model-picker-config unit test.
- 2026-08-04 - "Commands Advanced card collapses when you click inside it to edit a field" - FIXED in b31a6b9: the Advanced toggle listener moved from the whole `.cmd-advanced-wrap` to the `.cmd-advanced-toggle` header, so clicks inside fields no longer collapse the card; scenario 27 flipped to a regression check (`regression: true`) + commands-advanced-toggle unit test.


