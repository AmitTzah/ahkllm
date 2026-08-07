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

- **38 verified, 3 reported, 0 fix applied, 0 fix in progress** (2026-08-07). Scenario count is enforced by
  `node tests/headless/e2e-suite.js --check-sync` (do not hard-code it here).
- **Where we left off:** 2026-08-07 — bug #66 FIXED in d72b4f5; next: bug #68 (ProviderResolver legacy prefix match uses substring InStr).
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

**Verification:** headless scenario 63 (noApp) statically checks that GetThreadStats uses HasOwnProp without an empty-string guard.


### 68. ProviderResolver legacy prefix match uses substring InStr, not prefix check - mygpt matches gpt

**Scenario:** 68 (scenario code in e2e-suite.js)

**Status:** verified

**Repro:** configure a custom providerMap prefix `gpt` (default) and use a short-form model id that merely *contains* the substring, e.g. `mygpt-custom` or `agpt-model` (no `provider/` prefix).

**Expected:** legacy short ids should resolve by *prefix* (starts-with) - `mygpt-custom` should fall back to `deepseek` (or remain unmatched), not to the `gpt` provider.

**Actual:** `ProviderResolver.Resolve` loops `for prefix, prov in providerMap` and does `if InStr(modelId, prefix)` - substring anywhere. `mygpt-custom` therefore resolves to the `gpt` ? `openai` provider and is sent to `openai`'s endpoint with the wrong model name, while a legitimate `gpt-4o` and a bogus `mygpt` both hit the same provider.

**Evidence:** `api/ProviderResolver.ahk` `Resolve()` `if InStr(modelId, prefix)` (no `=1` or `SubStr` prefix check).

**Verification:** headless scenario 68 (noApp) asserts `InStr(modelId, prefix)` exists and no `SubStr(...,1,)` or `InStr(...)=1` prefix check exists.

### 69. Search LIKE fallback does not escape % _ \ - searching for % returns all messages

**Scenario:** 69 (scenario code in e2e-suite.js)

**Status:** verified

**Repro:** seed a chat with messages, then use Search (global or scoped) and type `%` (or `_`).

**Expected:** searching for a literal `%` should return only messages that contain `%` (or no results if none do).

**Actual:** the LIKE phase does `m.content LIKE '%' || 'safeQuery' || '%' ESCAPE '\'` where `safeQuery` is only `SQLite.Escape(query)` (doubles `'` ? `''`). `%` and `_` are LIKE wildcards and `\` is the ESCAPE char - none are escaped. `safeQuery = "%"` becomes `LIKE '%%% '`, which matches every row (and `_` matches any single char). The same bug exists in `_Titles` for title search.

**Evidence:** `chat/db/SearchRepo.ahk` `static _Like` and `static _Titles` - `safeQuery := SQLite.Escape(query)` then `LIKE '%' || '" safeQuery "' || '%' ESCAPE '\'` with no `%`/`_`/`\` escaping.

**Verification:** headless scenario 69 (noApp) slices `_Like` and asserts no `StrReplace` for `%`/`_` exists while `ESCAPE '\'` is present.

### 70. Search FTS5 MATCH does not escape special characters - C++ or "hello" breaks the query (empty results)

**Scenario:** 70 (scenario code in e2e-suite.js)

**Status:** verified

**Repro:** seed messages containing `C++`, `hello:world`, or `foo-bar`, then search for `C++` (or a quoted phrase `"hello"`).

**Expected:** FTS5 should treat the query as literal terms or return the LIKE fallback results.

**Actual:** `SearchRepo._FTS5` builds `ftsExpr` as `trimmed` words joined by ` AND ` with a trailing `*`, then only does `safeFTS := StrReplace(ftsExpr, "'", "''")`. FTS5 special characters `"` `(` `)` `:` `-` `+` `*` etc. are not escaped/quoted. `C++` becomes `MATCH 'C++*'` (plus is a FTS5 operator) and throws `fts5: syntax error near "+"`, causing `_FTS5` to return `[]` and the search falls through to LIKE (which then may also mis-handle it). Quoted queries like `"hello"` become `MATCH '"hello"*'` (unbalanced) and also error.

**Evidence:** `chat/db/SearchRepo.ahk` `static _FTS5` - `ftsExpr .= trimmed` raw, `safeFTS := StrReplace(ftsExpr, "'", "''")` only.

**Verification:** headless scenario 70 (noApp) asserts `ftsExpr .= trimmed` exists and no `StrReplace` for `"` or `(` exists.

### 71. Clearing Thread Title Generation model/prompt/maxTokens leaves stale globals [family: #61/#71]

**Scenario:** 71 (scenario code in e2e-suite.js)

**Status:** verified

**Repro:** Settings ? General ? Thread Title Generation ? clear Model (or Prompt / Max Tokens) ? Save ? trigger title generation (send a new chat exchange).

**Expected:** clearing the field should reset to the default (or empty) and title generation should use the default model/prompt or be disabled for that field.

**Actual:** the previous `titleGenModel` / `titleGenSystemPrompt` / `titleGenMaxTokens` value survives. `SettingsApply._ApplyThreadTitles` only assigns when `tt["model"] != ""` (and same for `prompt`, `maxTokens`), so saving `""` leaves the old global. Same root as bugs #33 and #61.

**Evidence:** `app/settings/SettingsApply.ahk` `_ApplyThreadTitles` `if tt.Has("model") && tt["model"] != ""` etc.

**Verification:** headless scenario 71 (noApp) asserts the two `!= ""` guards exist.

### 72. SystemMessageResolver treats UNC \\server\share paths as relative - file not found

**Scenario:** 72 (scenario code in e2e-suite.js)

**Status:** verified

**Repro:** set an assistant or command `systemMessageFile` to a UNC path like `\\server\share\prompt.txt` that exists and is readable, then trigger the assistant/command.

**Expected:** the file is read from the UNC path (absolute path used as-is, like `C:\` paths).

**Actual:** the resolver only checks `InStr(filePath, ":")` to detect absolute paths. UNC paths have no colon, so they are treated as relative and searched in `A_ScriptDir\`, `..\`, `default-settings\system-messages\`, and `AppData\system-messages\` - none match, so `FileRead` fails and the resolver falls back to the inline `systemMessage` (or empty) with an error. The UNC file is never read.

**Evidence:** `shared/SystemMessageResolver.ahk` `Resolve()` `if !InStr(filePath, ":")` - no `\\` check.

**Verification:** headless scenario 72 (noApp) asserts `InStr(filePath, ":")` exists and no `\\` handling exists.

### 73. GoogleChatCompletions disabled thinking config for Gemini 2.x omits include_thoughts (inconsistent with enabled)

**Scenario:** 73 (scenario code in e2e-suite.js)

**Status:** verified

**Repro:** select a Gemini 2.x model (e.g. `google/gemini-2.0-flash`) and set Thinking Level to the disabled option (or to Model Default where `ApplyDefaults` is not used), then send a request and inspect the JSON payload (`requestFile`).

**Expected:** disabled payload should be symmetric with enabled: `extra_body.google.thinking_config = {include_thoughts:false, thinking_budget:0}` or at least consistently include `include_thoughts`.

**Actual:** `GoogleChatCompletions.ThinkingConfig` (enabled) always sets `include_thoughts:true` plus a budget/level, but `DisabledConfig` for 2.x returns only `{thinking_budget:0}` with no `include_thoughts` field. The API may therefore still return thoughts or behave inconsistently between enabled/disabled.

**Evidence:** `api/handlers/GoogleChatCompletions.ahk` `DisabledConfig()` `return {thinking_budget:0}` vs `ThinkingConfig()` `tc := {include_thoughts:true}`.

**Verification:** headless scenario 73 (noApp) slices `DisabledConfig` and asserts `thinking_budget:0` present and `include_thoughts` absent.

### 74. SettingsApply leaves providerMap stale when all prefixes are cleared

**Scenario:** 74 (scenario code in e2e-suite.js)

**Status:** verified

**Repro:** Settings ? Providers ? edit every provider to remove all `prefixes` entries (or set a provider to have an empty prefixes array) ? Save ? check provider resolution for a legacy short id like `deepseek-v4-flash`.

**Expected:** clearing prefixes should clear `providerMap` (or rebuild it empty) so legacy short ids no longer resolve to that provider.

**Actual:** `SettingsApply._ApplyProviders` builds `newProviderMap` from the saved providers' `prefixes`, then does `if newProviderMap.Count >0` `providerMap := newProviderMap`. When all prefixes are cleared, `Count` is 0, so the assignment is skipped and the old `providerMap` (from startup defaults or previous save) remains live. Legacy short ids continue to resolve to the old provider even though the settings show no prefixes.

**Evidence:** `app/settings/SettingsApply.ahk` `_ApplyProviders` `if newProviderMap.Count >0` `providerMap := newProviderMap`.

**Verification:** headless scenario 74 (noApp) asserts the `Count >0` guard exists and no `else` clear exists.

### 75. GoogleChatCompletions budget table matches via substring InStr, not exact family check

**Scenario:** 75 (scenario code in e2e-suite.js)

**Status:** verified

**Repro:** use a custom model id that merely *contains* a budget-table substring, e.g. `my2.5-pro-custom` or `test2.5-flash-lite`, with thinking Level `high`.

**Expected:** `_BudgetTable` should match only the intended Gemini family (e.g. `2.5-pro` family), or fall back to generic.

**Actual:** `_BudgetTable` uses `if InStr(modelId, "2.5-pro")` substring checks. Any model id containing that substring - even `my2.5-pro` or `foo2.5-pro-bar` - will match the first table (`minimal 128 - high 32768`) even though it is not a Gemini 2.5-pro model, giving a wrong thinking budget.

**Evidence:** `api/handlers/GoogleChatCompletions.ahk` `_BudgetTable` `if InStr(modelId, "2.5-pro")` etc.

**Verification:** headless scenario 75 (noApp) asserts `InStr(modelId, "2.5-pro")` exists.

### 76. initChatMode guard `!activeThreadId` prevents thread switch when WebView already holds a thread

**Scenario:** 76 (scenario code in e2e-suite.js)

**Status:** verified

**Repro:** open thread A, then via IPC or direct `initChatMode({messages:..., threadId:"B"})` where `activeThreadId` already equals `A` (e.g. rapid switch, fork, or programmatic load).

**Expected:** `activeThreadId` should update to `B` so subsequent `updateScopedSearchState`, `onSearchCrossThreadLoaded`, and new-message sends target B.

**Actual:** `webui/js/chat/chat-core.js` `initChatMode` does `if (data && data.threadId && !activeThreadId) { activeThreadId = data.threadId; }`. When `activeThreadId` is already truthy (`"A"`), the assignment is skipped, so the WebView stays on `A` while the message list shows `B`'s messages - `activeThreadId` is stale. Subsequent scoped search, token-bar updates, and `chatSend` will use the wrong thread id.

**Evidence:** `webui/js/chat/chat-core.js` `initChatMode` guard `!activeThreadId`.

**Verification:** headless scenario 76 (noApp) asserts the `!activeThreadId` guard and `activeThreadId = data.threadId` assignment exist.

### 77. Empty Send (no text, no attachments) with existing chat history triggers an unexpected retry

**Scenario:** 77 (scenario code in e2e-suite.js)

**Status:** verified

**Repro:** open a chat that already has messages (e.g. last message is an assistant response), clear the input (`input.value = ""`), click Send (or press Enter).

**Expected:** no action - empty input should be a no-op (like most chat UIs) or show a hint.

**Actual:** `webui/js/chat/chat-input.js` `onChatSend` trims input to `""`, finds `message` falsy and `attachments` empty, then falls through to `if (chatMessages && chatMessages.length>0) { var lastMsg = chatMessages[chatMessages.length-1]; if (lastMsg.role==="assistant") retryLastAssistantMessage(...) ; else if (lastMsg.role==="user") Ipc.postToHost('retry') }`. An empty Send therefore re-fires the last assistant message (or resends the last user message) instead of doing nothing - a single accidental click/Enter duplicates a request and burns tokens/cost.

**Evidence:** `webui/js/chat/chat-input.js` `onChatSend` empty-input branch with `retryLastAssistantMessage` and `Ipc.postToHost('retry')`.

**Verification:** headless scenario 77 (noApp) asserts the empty-input `chatMessages.length` branch and `retry` post exist.

### 78. Right-rail temperature 0 displays as "Default" instead of 0.0 - falsy check hides 0

**Scenario:** 78 (scenario code in e2e-suite.js)

**Status:** verified

**Repro:** set per-thread temperature to 0 (right-rail slider to 0.0 ? Save), reload the thread or switch away and back, then read the right-rail Temperature value.

**Expected:** the rail shows `0.0` and the slider sits at 0, with the reset ` - ` visible.

**Actual:** the rail shows `Default` and the slider snaps to `1.0` with `temp-default` class, as if no override were set. `webui/js/chat/model-picker/model-picker-config.js` `populateCurrentSettings` does `var hasTemp = settings.temperature && settings.temperature !== ""` - `0` / `"0"` is falsy, so `hasTemp` is false and the `else` branch (Default) runs. The stored override is still `0` (via `TemperatureOverride` in DB and `requestParams`), so the API request correctly sends `temperature:0`, but the UI lies about it. Same root as bug #35 (falsy `0`).

**Evidence:** `webui/js/chat/model-picker/model-picker-config.js` `hasTemp = settings.temperature && ...`.

**Verification:** headless scenario 78 (noApp) asserts the `&&` falsy guard exists.

### 79. Settings file with UTF-8 BOM fails to load - settings silently reset to defaults

**Scenario:** 79 (scenario code in e2e-suite.js)

**Status:** verified

**Repro:** write `%APPDATA%\AhkLLM\settings.json` with a UTF-8 BOM (many Windows editors do), restart the app.

**Expected:** settings load normally - the app itself writes with BOM, so the loader must tolerate it.

**Actual:** `app/settings/SettingsPersistence.ahk` `Load()` does `raw := FileRead(path, "UTF-8")` then `parsed := jsongo.Parse(raw)` with no BOM stripping. `jsongo` chokes on leading `\uFEFF`, the `catch` returns an empty `Map()`, and the app falls back to `DefaultSettings` - all custom settings are lost. The harness README notes the BOM issue and `seed.readJsonFile` strips it, but the production loader does not.

**Evidence:** `app/settings/SettingsPersistence.ahk` `Load()` - no BOM handling before `jsongo.Parse`.

**Verification:** headless scenario 79 (noApp) asserts `FileRead` + direct `jsongo.Parse` without BOM handling.

### 80. ThreadRepo SoftDelete/Restore/Delete/Update interpolate threadId without SQLite.Escape - SQL injection via crafted id

**Scenario:** 80 (scenario code in e2e-suite.js)

**Status:** verified

**Repro:** craft a thread id containing a single quote (e.g. `bad'id`) and call any thread mutator that interpolates it - `SoftDelete`, `Restore`, `Delete`, or `Update` (e.g. via a malicious `threadId` posted over IPC or a hand-edited DB).

**Expected:** all SQL statements should use `SQLite.Escape(threadId)` like `UpdateSettings`/`GetSettings` do.

**Actual:** `ThreadRepo.SoftDelete`, `Restore`, `Delete`, and `Update` do `WHERE id='" threadId "'` with no escaping. A `threadId` containing `'` breaks the string literal and can inject arbitrary SQL (e.g. `bad'id'; DROP TABLE chat_threads; --` would terminate the `UPDATE` and execute a second statement, depending on the SQLite wrapper's multi-statement handling). `UpdateSettings` and `GetSettings` correctly use `safeId := SQLite.Escape(threadId)`.

**Evidence:** `chat/db/ThreadRepo.ahk` `SoftDelete` `WHERE id='" threadId "'` (no `SQLite.Escape`); same for `Restore`, `Delete`, `Update`.

**Verification:** headless scenario 80 (noApp) asserts `SQLite.Escape(threadId)` absent in `SoftDelete` and `WHERE id='" threadId "'` present.

### 81. Branch _setupSiblingGroup UPDATE interpolates msg.id without escaping - SQL injection via crafted message id

**Scenario:** 81 (scenario code in e2e-suite.js)

**Status:** verified

**Repro:** craft a message id containing `'` (e.g. via a hand-edited DB or a malicious `retry` payload that references `messageId`) and trigger a retry that needs a new sibling group (assistant without `sibling_group`).

**Expected:** the `UPDATE messages SET sibling_group=... WHERE id='...'` should use `SQLite.Escape(msg.id)`.

**Actual:** `chat/callbacks/Branch.ahk` `_setupSiblingGroup` does `WHERE id='" msg.id "'` with no escaping. Same injection class as #80.

**Evidence:** `chat/callbacks/Branch.ahk` `_setupSiblingGroup` `WHERE id='" msg.id "'`.

**Verification:** headless scenario 81 (noApp) asserts `SQLite.Escape(msg.id)` absent and `WHERE id='" msg.id "'` present.

### 82. Usage dashboard provider/model filter dropdown XSS - option values not escaped

**Scenario:** 82 (scenario code in e2e-suite.js)

**Status:** verified

**Repro:** set a provider `displayName` or model id to `"><img src=x onerror=alert(1)>` via Settings ? Providers/Models ? Save, then open Usage Dashboard.

**Expected:** the filter dropdowns show the name as inert text.

**Actual:** `webui/js/usage-dashboard.js` `populateFilters` does `provSel.innerHTML += '<option value="'+p+'">'+p+'</option>'` and `modSel.innerHTML += '<option value="'+m+'">'+m+'</option>'` with no `escHtml`. A provider/model name containing HTML is parsed as HTML and its event handlers execute in the WebView (same `chrome.webview.postMessage` access as #57).

**Evidence:** `webui/js/usage-dashboard.js` `populateFilters` raw `innerHTML` for `p` and `m`.

**Verification:** headless scenario 82 (noApp) asserts raw `innerHTML` with `p`/`m` and no `escHtml(p)` exists.

### 83. Thread-map "who" label XSS - model name not escaped in right-panel nav list

**Scenario:** 83 (scenario code in e2e-suite.js)

**Status:** verified

**Repro:** set a custom model id to `"><img src=x onerror=...>` (or have an assistant with such a model), send a message with that model, then look at the right-panel Thread Map.

**Expected:** the `who` label shows the model name as text.

**Actual:** `webui/js/chat/chat-threadmap.js` `renderNavList` does `var who = msg.model || 'Assistant'; item.innerHTML = '<span class="who">' + who + '</span>...' ` with no `escHtml(who)`. The model string is interpreted as HTML. `createMessageBubble` correctly uses `escHtml` for the model in the header, but the thread map does not.

**Evidence:** `webui/js/chat/chat-threadmap.js` `renderNavList` `+ who +` without `escHtml`.

**Verification:** headless scenario 83 (noApp) asserts `+ who +` raw and no `escHtml(who)` exists.

### 84. API Logs Viewer `esc()` does not escape single quote - `title` attribute break and potential XSS

**Scenario:** 84 (scenario code in e2e-suite.js)

**Status:** verified

**Repro:** craft an API log entry where `endpoint` contains a single quote (e.g. `https://example.com/'onmouseover='alert(1)` via a custom provider endpoint), then open API Logs Viewer and hover the Endpoint cell.

**Expected:** the `title` attribute shows the endpoint as inert text.

**Actual:** `webui/api-logs.html` `esc()` does `String(s).replace(/[&<>"]/g, ...)` - it escapes `& < > "` but not `'`. The log table builds `<td class="endpoint-cell" title="' + esc(entry.endpoint||'') + '">'`. A `'` closes the `title='...'` attribute early, breaking the HTML and allowing an unescaped attribute injection. The cell text itself is inside `esc()`, but the attribute is not.

**Evidence:** `webui/api-logs.html` `function esc(s)` regex `/[&<>"]/`.

**Verification:** headless scenario 84 (noApp) asserts `esc` regex missing `'` and `&#39;` absent.

### 86. FIM fallback `renderMarkdown` XSS - `md.render` with `html:true` for non-chat content

**Scenario:** 86 (scenario code in e2e-suite.js)

**Status:** reported — duplicate of #57, static check only (same `html:true` root)

**Repro:** trigger a Fill-In-the-Middle (FIM) request that returns HTML like `<img src=x onerror=...>` (e.g. via a FIM command with a mock LLM), then view the fallback rendering (`#content` when `isChatMode` is false).

**Expected:** content is rendered as inert text, even in FIM fallback mode.

**Actual:** `webui/js/chat/chat-core.js` `renderMarkdown` does `var result = md.render(contentToRender); var contentElement = document.getElementById('content'); if (contentElement) contentElement.innerHTML = result;` with `md` configured `html:true` in `webui/js/main.js`. No sanitization, same root as #57 but for the non-chat `content` path. **Duplicate of #57 — fix together; scenario kept as reported.**

**Evidence:** `webui/js/chat/chat-core.js` `renderMarkdown` `md.render` + `innerHTML`; `webui/js/main.js` `markdownit({ html:true })`.

**Verification:** headless scenario 86 (noApp) asserts `md.render` with `html:true` and `contentElement.innerHTML = result` exist.

### 87. Usage dashboard "Last Month" SQL uses UTC `date('now')` while chart labels use local `new Date()` - timezone drift

**Scenario:** 87 (scenario code in e2e-suite.js)

**Status:** verified

**Repro:** set system timezone to UTC+9 (e.g. Asia/Tokyo), seed usage rows for last month's first day in local time, open Dashboard ? Last Month.

**Expected:** chart labels and SQL summary cover the same local last-month window.

**Actual:** `chat/db/UsageRepo.ahk` `_WhereDate("lastMonth")` returns `WHERE date >= date('now','start of month','-1 month') AND date < date('now','start of month')` - `date('now')` is UTC. `webui/js/usage-dashboard.js` `getDateRangeLabels("lastMonth")` builds labels from local `new Date()`. In UTC+9, local last month 01 00:00 is still previous UTC day, so the SQL window and chart labels are off by one day and the summary total mismatches the chart.

**Evidence:** `chat/db/UsageRepo.ahk` `_WhereDate` `date('now','start of month',...)`; `webui/js/usage-dashboard.js` `getDateRangeLabels` `new Date()` local.

**Verification:** headless scenario 87 (noApp) asserts UTC `date('now')` in `UsageRepo` and local `new Date()` in dashboard exist.

### 88. Usage dashboard "Last 30 Days" SQL uses UTC while chart uses local - same timezone drift as Last Month

**Scenario:** 88 (scenario code in e2e-suite.js)

**Status:** verified

**Repro:** same as #87 but select  - Last 30 Days -  (range `month`) in Dashboard.

**Expected:** SQL and chart cover the same 30-day window in local time.

**Actual:** `_WhereDate("month")` is `WHERE date >= date('now','-30 days')` (UTC), while `getDateRangeLabels("month")` does `days=30` from local `today`. Same UTC vs local drift as #87 and #53 (which was for `day`). The fix for #42 (chart labels `localDateKey`) did not fix the SQL side.

**Evidence:** `chat/db/UsageRepo.ahk` `date('now','-30 days')`; `webui/js/usage-dashboard.js` `days=30` + `new Date()`.

**Verification:** headless scenario 88 (noApp) asserts both UTC and local patterns exist.

### 89. CurlBuilder interpolates API key with `"` into `-H "Authorization: Bearer ..."` without escaping - header break / injection

**Scenario:** 89 (scenario code in e2e-suite.js)

**Status:** verified

**Repro:** set any provider `apiKey` (direct mode) to contain a double quote, e.g. `sk-"test`, save, then trigger any LLM request (chat or command).

**Expected:** the key is shell-escaped or the header is built via a safe API, not via string interpolation.

**Actual:** `api/CurlBuilder.ahk` `Build`/`BuildStream`/`BuildFIM` do `'-H "Authorization: Bearer ' providerInfo.apiKey '" '` with no `StrReplace` or `SQLite.Escape` for `"`. A key containing `"` closes the `"` early, breaking the cURL command line (`Authorization: Bearer sk-` + `"` + `test` + `"` ? header is `sk-` and `test` becomes a stray argument). A key like `sk-" && echo pwned && "` could inject a second command when the `Run` goes through `cmd` (stream path does, via `2>`).

**Evidence:** `api/CurlBuilder.ahk` three builders interpolate `providerInfo.apiKey` into `"`-quoted header with no escaping.

**Verification:** headless scenario 89 (noApp) asserts `Authorization: Bearer` + `apiKey` exists and no `Escape`/`StrReplace` for `apiKey` exists.

### 90. SettingsMerge.Override iterates over `incoming` without `IsObject` guard - empty string corrupts settings

**Scenario:** 90 (scenario code in e2e-suite.js)

**Status:** verified

**Repro:** send a `saveSettings` IPC with `data: ""` (empty string) instead of an object - e.g. via a crafted `chrome.webview.postMessage` or a WebView bug.

**Expected:** `Override` should guard `if !IsObject(incoming)` or check `incoming is Map`, and ignore non-Map payloads.

**Actual:** `app/settings/SettingsMerge.ahk` `Override(incoming, base)` does `for k, v in incoming` with no `IsObject` check. In AHK, `for k, v in ""` iterates over the string - s characters (`k=1, v='"'`, `k=2, v='{'`  - ), so `result["1"] := '"'`, `result["2"] := '{'` etc. The merged settings Map gets polluted with numeric string keys and single-character values, then `SettingsPersistence.Save` writes a corrupted `settings.json`.

**Evidence:** `app/settings/SettingsMerge.ahk` `Override` `for k, v in incoming` with no `IsObject` guard.

**Verification:** headless scenario 90 (noApp) asserts `for k, v in incoming` exists and no `IsObject(incoming)` guard exists.

### 91. InputWindow `validateInputAndHide` treats `"0"` as empty - `!value` falsy check

**Scenario:** 91 (scenario code in e2e-suite.js)

**Status:** verified

**Repro:** trigger any command with `showInputBox: true` (e.g. Quick Ask), type `0` (single zero) in the popup, press Enter or click Send.

**Expected:** the input `0` is accepted and sent as `{{input}}` (or as `inputText`).

**Actual:** `app/InputWindow.ahk` `validateInputAndHide` does `if !this.EditControl.Value { MsgBox "Please enter a message..." ; return false }`. In AHK, `! "0"` is `true` because `"0"` is falsy (same as `0` and `""`), so typing `0` is considered empty and the popup stays open with the  - Please enter a message -  box. The same `!value` pattern appears in `CommandState.onCommandInputSend` via `validateInputAndHide`.

**Evidence:** `app/InputWindow.ahk` `if !this.EditControl.Value`.

**Verification:** headless scenario 91 (noApp) asserts `if !this.EditControl.Value` exists.

### 92. Models `ensureFullId` ignores provider dropdown when id already contains `/` - stale provider prefix

**Scenario:** 92 (scenario code in e2e-suite.js)

**Status:** verified

**Repro:** Settings ? Models ? pick any model with full id like `openai/gpt-4` (display shows `gpt-4`), change the Provider dropdown from `openai` to `google`, then Save and check `settings.json`.

**Expected:** the saved full id should be `google/gpt-4` (provider from dropdown + stripped id).

**Actual:** `webui/js/settings/sections/models.js` `ensureFullId(id, provider)` does `if (id.indexOf('/') >=0) return id; return provider ? provider+'/'+id : id`. When `id` already contains `/` (because the row was rendered from a full id like `openai/gpt-4` but the input shows only `gpt-4` - wait, actually `_mainRowHtml` does `stripProvider(id)` for display, so the input value is `gpt-4` without prefix, but `_readRowValues` reads `id` as `tr.querySelector('[data-field="id"]').value` which is `gpt-4` (no slash), and `values.provider` is `google`, so `ensureFullId("gpt-4", "google")` would correctly return `google/gpt-4`. However, in the *refresh modal* (`_rightRowHtml`), the id input has `data-full-id="openai/gpt-4"` and the `saveRefresh` path does `var id = idEl.getAttribute('data-full-id') || idEl.value` - it prefers `data-full-id` (stale `openai/gpt-4`) over the current `value` (`gpt-4`), so changing the provider dropdown there does not update the saved id. The bug is in `saveRefresh`, not `ensureFullId` for the main table, but the `ensureFullId` early-return for `id` containing `/` is still a latent bug if a user types a full id manually.

**Evidence:** `webui/js/settings/sections/models.js` `ensureFullId` `if (id.indexOf('/') >=0) return id`.

**Verification:** headless scenario 92 (noApp) asserts `ensureFullId` early-return for `/` exists.

### 93. SettingsDefaults `GetDefaults` shallow-copies `Map` values [latent] - mutating snapshot corrupts pristine defaults

**Scenario:** 93 (scenario code in e2e-suite.js)

**Status:** reported — latent design flaw (no active caller mutates the snapshot in place)

**Repro:** call `SettingsDefaults.GetDefaults()` twice, mutate the first result - s `models` Map (e.g. `m1["models"]["openai/gpt-4"] := deleted`), then call `GetDefaults()` again and read `models`.

**Expected:** each `GetDefaults()` returns an independent deep copy of the pristine defaults, so mutating one does not affect the next.

**Actual:** `GetDefaults` when captured does `snapshot := Map(); for k, v in _initialDefaults snapshot[k] := v` - `v` is a `Map` (e.g. `models` Map), so `snapshot["models"]` shares the *same* Map object as `_initialDefaults["models"]`. Mutating `snapshot["models"]` mutates the cached pristine copy, corrupting future `GetDefaults()` and `Reset to Defaults`.

**Evidence:** `app/settings/SettingsDefaults.ahk` `GetDefaults` `snapshot[k] := v` without `CloneMap`.

**Verification:** headless scenario 93 (noApp) asserts `snapshot[k] := v` shallow copy exists. Latent: no production caller currently mutates `GetDefaults()["models"]` in place, so not user-visible today; keep as hardening. Fix by deep-cloning Map values (`_CloneMap`).

### 94. SettingsDefaults `_DefaultsAssistants` generates a new UUID on every `GetDefaults()` - defaults not stable

**Scenario:** 94 (scenario code in e2e-suite.js)

**Status:** reported — overstated (UUID churn does not occur after CacheInitialDefaults; shallow copy preserves same array)

**Repro:** call `SettingsDefaults.GetDefaults()` twice and compare `assistants[1].id` (or `commands` via `_CommandToMap` which also uses `UUID` for missing ids, but assistants always does).

**Expected:** the default `assistants` list should have stable ids (e.g. from `DefaultSettings.ahk` or a fixed seed), so `Reset to Defaults` and diffing are deterministic.

**Actual:** `_DefaultsAssistants` does `asstList.Push(Map("id", SettingsPersistence._UUID(), "name", a.name, ...))` for every assistant on *every* `GetDefaults()` call. Before `CacheInitialDefaults` each call would generate fresh UUIDs; after caching, `GetDefaults()` shallow-copies the cached array — no churn in normal runtime, so the bug is overstated. Keep as low-priority hardening for stable ids.

**Evidence:** `app/settings/SettingsDefaults.ahk` `_DefaultsAssistants` `SettingsPersistence._UUID()` inside the loop.

**Verification:** headless scenario 94 (noApp) asserts `SettingsPersistence._UUID()` inside `_DefaultsAssistants` exists — but this only proves the code *could* generate UUIDs, not that `GetDefaults()` churns after caching (it does not). Keep as low-priority hardening (stable ids).

### 95. Usage dashboard model heading XSS — model id not escaped in section header

**Scenario:** 95 (scenario code in e2e-suite.js)

**Status:** verified

**Repro:** set a model id to `"><img src=x onerror=alert(1)>` via Settings → Models → Save, then open Usage Dashboard with data for that model.

**Expected:** the model-section heading shows the id as inert text.

**Actual:** `webui/js/usage-dashboard.js` `renderModelSections` does `div.innerHTML = ''<h6>''+model+''</h6>...'` with no `escHtml(model)`. The model string is parsed as HTML and handlers execute (same `chrome.webview.postMessage` access as #57/#82).

**Evidence:** `webui/js/usage-dashboard.js:259` `div.innerHTML = ''<h6>''+model+''</h6>''`.

**Verification:** headless scenario 95 (noApp) asserts raw `div.innerHTML = ''<h6>''+model` exists and no `escHtml(model)` in the section.

### 96. AttachmentRepo inserts/queries interpolate msgId/threadId without SQLite.Escape — SQL injection

**Scenario:** 96 (scenario code in e2e-suite.js)

**Status:** verified

**Repro:** craft a message id containing `''` (e.g. `bad''id`) via hand-edited DB or malicious IPC `messageId`, then call any AttachmentRepo path (Insert, GetByMessage, DeleteByMessage, CopyForMessage) or ChatDB FTS_Sync.

**Expected:** all statements should use `SQLite.Escape(msgId)` / `SQLite.Escape(threadId)`.

**Actual:** `chat/db/AttachmentRepo.ahk` `Insert` does `VALUES(''id'', ''msgId''`, `GetByMessage`/`DeleteByMessage` do `WHERE message_id=''msgId''`, `GetByThread`/`DeleteByThread` do `WHERE m.thread_id=''threadId''`, and `chat/db/ChatDB.ahk` `FTS_Sync`/`FTS_Remove` do `WHERE msg_id=''msgId''` — none escape. A `'` breaks the literal and can inject SQL (same class as #80/#81).

**Evidence:** `AttachmentRepo.ahk` `Insert`/`GetByMessage`/`DeleteByMessage`/`CopyForMessage` and `ChatDB.ahk` `FTS_Sync` — `''" msgId "''` without `SQLite.Escape`.

**Verification:** headless scenario 96 (noApp) asserts `WHERE message_id=''msgId''` exists and no `SQLite.Escape(msgId)` in `Insert`.

### 97. SettingsPersistence.Save is non-atomic — FileDelete then FileAppend leaves empty file on failure

**Scenario:** 97 (scenario code in e2e-suite.js)

**Status:** verified

**Repro:** save settings when disk is full / file locked (or kill the process between the two calls).

**Expected:** save should be atomic (write to temp file then `FileMove`/`Rename`).

**Actual:** `app/settings/SettingsPersistence.ahk` `Save` does `try FileDelete(path)` then `FileAppend(jsonStr, path, "UTF-8")` with no temp file. If `FileAppend` fails (disk full, permission, crash), the original `settings.json` is already deleted — settings are lost and next load falls back to defaults (same silent-reset as BOM bug #79).

**Evidence:** `SettingsPersistence.ahk` `Save` — `FileDelete` + `FileAppend` without atomic rename.

**Verification:** headless scenario 97 (noApp) asserts `FileDelete(path)` and `FileAppend(jsonStr, path` both exist and no temp-file rename exists.

### 98. StreamHandler _finalizeStreaming leaks state on cancel — no _cleanupStreamState after _handleStreamCancelled

**Scenario:** 98 (scenario code in e2e-suite.js)

**Status:** verified

**Repro:** start a stream, then press Stop/Cancel before completion and start another request without restarting the app.

**Expected:** `_finalizeStreaming` should always clean up `requestParams _stream*` keys.

**Actual:** `chat/streaming/StreamHandler.ahk` `_finalizeStreaming` does `wasCancelled := ...; if wasCancelled { _handleStreamCancelled(); return }` — returns without calling `_cleanupStreamState()`. The `_streamContent`/`_streamPID`/etc. keys remain in `requestParams`, polluting the next `sendStreamingRequest` (which overwrites most but not all) and leaving `IsSet` checks stale.

**Evidence:** `StreamHandler.ahk` `_finalizeStreaming` — `wasCancelled` branch `return` without `_cleanupStreamState`; the non-cancel path does `_handleStreamComplete` + `_cleanupStreamState`.

**Verification:** headless scenario 98 (noApp) asserts `wasCancelled` branch has `_handleStreamCancelled` + `return` but no `_cleanupStreamState` before `return`.

---

### 99. MessageRepo.Insert builds parent_id / sibling_group without SQLite.Escape — SQL injection via crafted ids

**Scenario:** 99 (scenario code in e2e-suite.js)

**Status:** verified

**Repro:** insert a message with crafted `parent_id` containing `''` (e.g. `bad''id` via IPC `parent_id` or hand-edited DB), or craft `sibling_group` similarly, then insert a child message.

**Expected:** `parent_id` and `sibling_group` literals should be escaped with `SQLite.Escape`.

**Actual:** `MessageRepo.Insert` does `safeParent := msgObj.HasProp("parent_id") && msgObj.parent_id ? "''" msgObj.parent_id "''" : "NULL"` and same for `sibling_group` — no `SQLite.Escape`. A `''` breaks the literal and can inject SQL (same class as #80/#81/#96, but this path was not yet covered — the INSERT that creates every user/assistant message).

**Evidence:** `chat/db/MessageRepo.ahk:11` `safeParent := ... "'" msgObj.parent_id "'"` without `SQLite.Escape`; `chat/db/MessageRepo.ahk:12` `safeSiblingGroup` same.

**Verification:** headless scenario 99 (noApp) asserts the two raw `"'\" msgObj.parent_id \"'\""` lines exist and no `SQLite.Escape(msgObj.parent_id)` / `sibling_group` escapes exist nearby.

### 100. LLMRequestBuilder._FixStreamBoolean uses global StrReplace — user message containing `"stream":1` is corrupted

**Scenario:** 100 (scenario code in e2e-suite.js)

**Status:** verified

**Repro:** send a chat or command request where the user message contains the substring `"stream":1` (e.g. paste a JSON snippet), then check the request written to the temp file / sent to the API.

**Expected:** JSON serialization should encode booleans correctly without string replacement on the whole payload.

**Actual:** `LLMRequestBuilder._FixStreamBoolean` does global `StrReplace(jsonStr, ''"stream":1'', ''"stream":true'')` (and similarly for `0`/`include_usage`/`include_thoughts`). The replace runs on the entire JSON string, so any occurrence inside `content`, `systemMessage`, or other string fields is also rewritten, corrupting the payload (e.g. user JSON snippet `"stream":1` becomes `"stream":true` before it is sent).

**Evidence:** `api/LLMRequestBuilder.ahk` `static _FixStreamBoolean(jsonStr)` — four `StrReplace` calls on the whole JSON string; also called from `LLMRequestBuilder.createJSONRequest` and `appendToChatHistory`.

**Verification:** headless scenario 100 (noApp) asserts `_FixStreamBoolean` exists and contains `StrReplace(jsonStr, ...stream...`.

### 101. SettingsApply._ApplyCommands _SetIfTruthy drops `false` — clearing stream/isFIM/showInputBox never persists

**Scenario:** 101 (scenario code in e2e-suite.js)

**Status:** verified

**Repro:** Settings → Commands → edit a command that has `stream` enabled, uncheck `Stream Response` (set to `false`) → Save → reopen Settings → the toggle is back on.

**Expected:** saving `false` should persist as `false` (the command should run non-streaming).

**Actual:** `SettingsApply._ApplyCommands` builds each command with `SettingsApply._SetIfTruthy(cmd, c, "stream")` (and `isFIM`, `showInputBox`, `expandNewlines`, `includeImageContext`), where `_SetIfTruthy` is `if c.Has(key) && c[key] cmd.%key% := c[key]`. A `false` value is falsy, so the assignment is skipped and the key is omitted from the new `commands` global; the next save round-trip loses the `false`. Same for `maxContextWords` via `_SetIfNonZero` (0 dropped) and `tags` via `Length>0`.

**Evidence:** `app/settings/SettingsApply.ahk` `_SetIfTruthy` `if c.Has(key) && c[key]` and calls for `"stream"`, `"isFIM"`, `"showInputBox"`; `_SetIfNonZero` for `maxContextWords`.

**Verification:** headless scenario 101 (noApp) asserts `_SetIfTruthy` helper exists with `c.Has(key) && c[key]` and is called for `"stream"`.

### 102. UsageRepo provider LIKE does not escape `%` `_` `\` — provider filter `%` matches all models

**Scenario:** 102 (scenario code in e2e-suite.js)

**Status:** verified

**Repro:** open Usage Dashboard, select a provider filter value containing `%` (crafted via hand-edited `settings.json` or direct `UsageRepo.Query` call with `provider="%"`), query dashboard.

**Expected:** `providerFilter` should be wildcard-escaped before `LIKE`.

**Actual:** `UsageRepo.Query` does `providerChatClause := providerFilter ? "AND model LIKE ''" SQLite.Escape(providerFilter) "/%''" : ""` — `SQLite.Escape` only doubles `'`, it does not escape `%`/`_`/`\` for `LIKE ESCAPE`. The dashboard also uses `LIKE` without `ESCAPE` handling for provider, so `%` becomes a wildcard and returns all rows (same class as #69, but provider path was not yet reported).

**Evidence:** `chat/db/UsageRepo.ahk` `providerChatClause` line with `LIKE` and `SQLite.Escape(providerFilter)` but no `StrReplace` for `%`.

**Verification:** headless scenario 102 (noApp) asserts `providerChatClause := providerFilter ? "AND model LIKE` exists and no wildcard escape exists.

### 103. TreeRepo.GetThreadStats pricingUnit picks the first message''s model, not the thread''s active model

**Scenario:** 103 (scenario code in e2e-suite.js)

**Status:** verified

**Repro:** create a thread with mixed models (e.g. assistant message from `openai/gpt-4` then later assistant from `anthropic/claude-3`), then check the token-bar `pricingUnit` (input/cached/output per 1M) shown in the header.

**Expected:** pricing should reflect the thread''s effective model (active leaf or `model_override`), not an arbitrary earlier message.

**Actual:** `TreeRepo.GetThreadStats` does `allTable := ChatDB.db.Exec("SELECT model FROM messages WHERE thread_id=''" threadId "'' AND model IS NOT NULL AND model != '''' LIMIT 1;")` — picks the *first* message with a model (by insertion order), regardless of which model is active. A thread that switched models will report the wrong per-token prices and cost estimates until all early messages are deleted.

**Evidence:** `chat/db/TreeRepo.ahk:363` `SELECT model ... LIMIT 1`.

**Verification:** headless scenario 103 (noApp) asserts the `LIMIT 1` first-model query exists.


### 107. TreeRepo._RecomputeActivePath recomputes active_path as prefix sum, losing prompt_tokens for assistants

**Scenario:** 107 (scenario code in e2e-suite.js)

**Status:** verified

**Repro:** create a thread with an assistant message that has `prompt_tokens=100` + `token_count=20` (active_path=120), then delete a middle message and check the leaf''s `active_path_tokens`.

**Expected:** after structural change the leaf should still reflect prompt+completion (or be recomputed from API ground truth).

**Actual:** `_RecomputeActivePath` does `prev := 0; for msg in path { prev += token_count; UPDATE ... active_path_tokens=prev }` — it sums only `token_count` (visible tokens), ignoring `prompt_tokens`. After delete/edit the assistant''s 100 prompt tokens are lost, header “Context Used” drops from 120 to ~20.

**Evidence:** `chat/db/TreeRepo.ahk` `static _RecomputeActivePath` — loop `prev += msg.HasProp("token_count") ? msg.token_count : 0` without `prompt_tokens`.

**Verification:** headless scenario 107 (noApp) asserts the function contains `prev +=` with `token_count` and no `prompt_tokens` in its 600-char body.

### 108. main.js IPC fallback calls arbitrary `window[target]` without allowlist

**Scenario:** 108 (scenario code in e2e-suite.js)

**Status:** verified

**Repro:** from a compromised WebView (XSS via #57/#86), post a message with `target="eval"` and `data="alert(1)"` via `chrome.webview.postMessage`; or have AHK send an undeclared `target` to the WebView.

**Expected:** only declared `IPCMessages` targets should be dispatched; unknown targets should be dropped after logging.

**Actual:** `webui/js/main.js` `handleWebMessage` `default:` case does `if (typeof window[target] === "function") window[target](...data)` — any global (e.g. `eval`, `fetch`, `location`) is invocable. `IPCMessages.validate` only `console.error`s, it doesn''t block the dispatch, so the allowlist is bypassed.

**Evidence:** `webui/js/main.js` `default:` → `window[target](...data)`.

**Verification:** headless scenario 108 (noApp) asserts `window[target]` fallback exists.

### 109. Sidebar `folderId` and 15+ remaining ChatDB call sites interpolate raw ids without `SQLite.Escape`

**Scenario:** 109 (scenario code in e2e-suite.js)

**Status:** verified

**Repro:** send a crafted `sidebarAction` IPC with `subAction:"deleteFolder"` and `folderId:"bad''id"` (e.g. via hand-edited WebView postMessage or compromised extension), or call any `ChatDB` path with `threadId`/`msgId` containing `''` via hand-edited DB.

**Expected:** all `WHERE id="..."` interpolations should use `SQLite.Escape`.

**Actual:** 15+ call sites still do raw `WHERE id="''" threadId "''"` / `msgId` / `params["folderId"]` without `SQLite.Escape`: `chat/callbacks/Sidebar.ahk:143` `DELETE FROM chat_folders WHERE id="''" params["folderId"] "''"`, `chat/db/MessageRepo.ahk` 5× `WHERE id="''" msgId "''"`, `chat/db/TreeRepo.ahk` 8× `WHERE id="''" threadId "''"`, `chat/db/AttachmentRepo.ahk` 2× `WHERE id="''" attachmentId "''"`, etc. Same class as #80/#81/#96/#99 but uncovered locations — hand-edited or IPC-crafted `''` breaks literal and injects SQL.

**Evidence:** `chat/callbacks/Sidebar.ahk:143` without `SQLite.Escape`; `chat/db/MessageRepo.ahk:131,157,163,167,181` etc. raw `msgId`.

**Verification:** headless scenario 109 (noApp) asserts `Sidebar.ahk` contains `params["folderId"]` in `DELETE FROM chat_folders` without `SQLite.Escape`, and `MessageRepo.ahk` has ≥3 raw `WHERE id="''" msgId` occurrences.

### 110. Chat streaming temp files with API keys not deleted after success — credential leak in `%TEMP%`

**Scenario:** 110 (scenario code in e2e-suite.js)

**Status:** verified

**Repro:** send any chat request (streaming), then check `%TEMP%` for `ChatWindow_cURL_*.txt` and `ChatWindow_Req_*.json`.

**Expected:** temp files should be deleted after the request completes (like the cancel path does via `deleteTempFiles()`).

**Actual:** `ChatRequestBuilder._WriteRequestFiles` writes `ChatWindow_Req_*.json` + `ChatWindow_cURL_*.txt` (containing `Authorization: Bearer <apiKey>`) to `A_Temp`, and `StreamHandler.sendStreamingRequest` writes the cURL command file. On success `StreamCompletion._handleStreamComplete` never calls `deleteTempFiles()` — only `_handleStreamCancelled` (in `StreamError.ahk`) does. Successful streams leave Bearer tokens on disk indefinitely; error path also leaks.

**Evidence:** `chat/streaming/StreamCompletion.ahk` `_handleStreamComplete` has no `deleteTempFiles`; `chat/streaming/StreamError.ahk` `_handleStreamCancelled` does; `api/CurlBuilder.ahk` `Build`/`BuildStream` embed `providerInfo.apiKey`.

**Verification:** headless scenario 110 (noApp) asserts `StreamCompletion.ahk` has no `deleteTempFiles` in `_handleStreamComplete`, `StreamError.ahk` does in cancel, and `CurlBuilder.ahk` contains `providerInfo.apiKey`.

### 111. ApiLogger LogRequest overwrites log file non-atomically — crash corrupts `LLM_API_Log.json`

**Scenario:** 111 (scenario code in e2e-suite.js)

**Status:** verified

**Repro:** send a chat/command request that triggers `ApiLogger.LogRequest`, then kill the app mid-write (or have disk full).

**Expected:** log write should be atomic (write to temp then rename), like settings should be.

**Actual:** `ApiLogger.LogRequest` does `FileOpen(this.logFilePath, "w", "UTF-8-RAW").Write(jsongo.Stringify(logs))` — direct overwrite without temp file. Crash or power loss mid-write leaves truncated JSON, next `ReadLogs` fails to parse and returns `[]`, losing all history. Same class as #97 but for API logs.

**Evidence:** `api/ApiLogger.ahk` `LogRequest` — `FileOpen(..., "w").Write` without `FileMove` temp.

**Verification:** headless scenario 111 (noApp) asserts `FileOpen(this.logFilePath, "w"` exists and no atomic rename exists.

### 112. CurlBuilder does not validate empty endpoint — malformed cURL with no URL

**Scenario:** 112 (scenario code in e2e-suite.js)

**Status:** verified

**Repro:** configure a provider with empty `endpoint` (e.g. add provider via Settings → Providers → leave Chat Endpoint blank → Save), then send a chat request with that provider''s model.

**Expected:** request builder should return early with “No endpoint configured” error (like missing API key does via `_ShowApiKeyError`).

**Actual:** `CurlBuilder.Build` does `return ''cURL.exe ... -X POST '' . providerInfo.endpoint . '' '' . ''-H ...''` without checking `endpoint`. Empty endpoint yields `cURL.exe -s ... -X POST  -H "Authorization: …"` with double-space and no URL — cURL exits with “no URL specified” (stderr), but the error is not surfaced as a user-friendly “endpoint missing” banner; the UI appears stuck or shows raw cURL stderr.

**Evidence:** `api/CurlBuilder.ahk` `Build`/`BuildStream`/`BuildFIM` all concatenate `providerInfo.endpoint` without `if !endpoint` guard.

**Verification:** headless scenario 112 (noApp) asserts `providerInfo.endpoint` is used without empty check.

## History (append-only)

Entries move here when a bug is closed (user committed) or refuted. Add one line per
closure; never rewrite past entries.

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


