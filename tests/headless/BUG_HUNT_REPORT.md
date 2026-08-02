# Bug Hunt Report (living document)

> **READ THIS FIRST.** This file is the single source of truth for open bugs. The harness
> manual is `README.md` in this folder. Start here; resume from "Where we left off".

## The lifecycle (which file, when)

**Files in play:**

| File | Touched when |
|---|---|
| `BUG_HUNT_REPORT.md` (this file) | every step — statuses, entries, history, "Where we left off" |
| `verify-bugs.js` | intake: add a scenario; fix cycle: flip an assertion |
| `tests/unit/*` + `tests/run_ahk_tests.ahk` | fix cycle: regression tests |
| production source (`app/`, `chat/`, `webui/`, `api/`, `shared/`) | fix cycle step 2 only |

**Status:** every entry carries exactly one of these:

| Status | Meaning | Set when |
|---|---|---|
| `reported` | Suspected bug written up; not yet reproduced | Phase 1, when the entry is written |
| `verified` | Scenario PASSED — bug reproduced headlessly | Phase 1, after the scenario passes |
| `fix in progress` | Agent is implementing the fix | Phase 2, before editing any code |
| `fix applied` | Code + tests green; waiting for user to verify | Phase 2, before asking the user |
| `awaiting user commit` | User verified; waiting for the commit | Phase 2, before suggesting the commit |
| *(removed)* | User committed → entry deleted, moved to History | Phase 2, after the commit |

Only `verified` bugs are fixed, one at a time, in rank order.

**Scenario line:** every entry references its verifying scenario by id — the scenario
*code* lives in `verify-bugs.js`, not in this file. Run it with
`node tests/headless/verify-bugs.js --scenarios=<id>`. `--check-sync` verifies every
entry's id exists (and that every non-regression scenario has an entry).

**Phase 1 — Intake** (a bug enters and gets verified here):

1. Write the entry in this file (Repro / Expected / Actual / Evidence + scenario id) with
   `Status: reported`. **[file: this file]**
2. Ensure a verifying scenario exists in `verify-bugs.js`; add one if not.
   **[file: `verify-bugs.js`]**
3. Run `node tests/headless/verify-bugs.js --check-sync` (must say OK), then
   `--scenarios=<id>` (must PASS = bug reproduced). **[no file edits]**
4. PASS → set `Status: verified`, rank the entry, and update "Current state" (open count).
   FAIL → the bug is not reproducible — delete the entry and add a one-line note to History.
   **But:** if the FAIL message starts with `setup ->`, it is a harness/infrastructure
   failure (app didn't launch, timeout connecting, element missing while preparing) — re-run
   or fix the scenario first; do NOT delete the entry. **[file: this file]**
5. If the bug can't be automated (visual / environment-limited — see README), verify by
   unit/static check or manually and say exactly how in the entry.

**Phase 2 — Fix cycle** (one verified bug at a time; the scenario is re-run only to
confirm the fix, never to re-verify the bug):

1. Pick the entry: normally the highest-ranked `verified` one, unless the user named a
   specific bug ("fix bug #14") — that overrides rank order. Set `Status: fix in progress`
   **before** editing any code. **[file: this file]**
2. Fix the bug in production source. **[files: `app/`, `chat/`, `webui/`, `api/`, `shared/`]**
3. Add/extend regression tests that assert the **fixed** behavior (unit/AHK as appropriate— the flipped scenario is the end-to-end check, but the fix also needs a code-level regression test when feasible; never delete or loosen an existing assertion to make it pass). **[files: `tests/unit/*`; also `tests/run_ahk_tests.ahk`
   if you added an AHK test]**
4. Flip the scenario assertion in `verify-bugs.js` to expect the **fixed** behavior
   (otherwise it fails forever). **[file: `verify-bugs.js`]**
5. Run `--scenarios=<id>` (must PASS = fix works) and the full AHK + JS suites. If it
   FAILs, the fix is incomplete — go back to step 2. **[no file edits]**
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
- **Never trust a Status without re-running the scenario first** — re-verify before
  assuming a bug is still open or already fixed.
- **Never ask the user to verify or commit until the fix has PASSED its scenario
  (flipped assertion) and the full AHK + JS suites** — the headless check always comes
  first, the user's manual check is the final confirmation.
- **A FAIL with `setup ->` in the message is a harness/infrastructure failure, not a
  refutation** — investigate or re-run; never delete an entry because of it.
- **Only one fix may be uncommitted at a time**: wait for the user's commit before
- **Every fix ships with a regression test**: the flipped scenario is the end-to-end
  check, but the fix also needs a unit/AHK test in `tests/unit/*` asserting the fixed
  behavior (unless the bug is visual/environment-limited— then say so in the entry).
  Never delete or loosen an existing assertion to make it pass.
  starting the next bug (the worktree must be clean of the previous fix).
- Only one agent edits this document at a time.
- Never delete an entry until the user has actually committed.
- **Doc-set rule:** if you change the harness itself (new probe command, new helper, new
  mock mode), update `README.md`; if you change the workflow itself, update `ARCHITECTURE.md`.
  Never hard-code drift-prone numbers (e.g. test totals) in docs — point at the runner
  instead.
- Only two files must stay in sync: this file and `verify-bugs.js` — `--check-sync`
  enforces it after every edit.

## Harness safety: avoid the hanging-command trap

**Never launch `AutoHotkey64.exe` directly from a shell (`& AutoHotkey64.exe x.ahk`)
to run ad-hoc scripts.** In this headless environment an AHK process can hang
forever, and a bare launch has no timeout, so the whole command blocks for minutes
and aborted runs leave orphaned `AutoHotkey64.exe` processes behind.

Why it hangs (verified 2026-08-01):

- AHK v2 shows a **modal error dialog** (window class `#32770`, titled with the
  script name) for any unhandled runtime error. Headless, nothing can dismiss it
  — the process hangs indefinitely. Example: plain `Object` has no `Has` method (only
  `Map` does), so `o.Has("type")` on `o := {type:"enabled"}` throws; bracket-indexing
  a plain object (`o[k]`) throws too. Marker-file evidence: the script writes a
  marker before the throwing line and never after; the hung process shows the
  `#32770` dialog.
- Such errors are silent in a hung process: no stderr, no output file, no exit
  code. `#ErrorStdOut` alone did NOT prevent the hang in this environment.
- This environment can also hang AHK at load for unrelated reasons (see probe.ahk),
  which is why every repo probe carries a watchdog.

How to run AHK safely:

1. **Prefer the harness.** Add a scenario to `verify-bugs.js` (it wraps every AHK
   call in `spawnSync` with `/ErrorStdOut` and a 25s timeout) or reuse a probe
   command (`probe.ahk <command> <outFile>`, `probe-thinking.ahk`). Re-verify bugs
   by running the scenario, never by hand.
2. **Any scratch probe must copy the harness skeleton exactly:** `#Requires` (with
   version), `#ErrorStdOut`, `#SingleInstance Off`, `#NoTrayIcon`, an `OnError`
   handler that writes diagnostics and `ExitApp(1)` (this converts a hang into a
   fast, logged failure), a watchdog `SetTimer(Exit, -15000)` for load-time hangs,
   and `try FileAppend` for results.
3. **Always launch with a hard bound** — e.g. .NET `Process.Start` + `WaitForExit(ms)` +
   `Kill()`, or `spawnSync` with `timeout` — never bare `&`.
4. **After any aborted run, kill stray `AutoHotkey64.exe` processes** before
   retrying (`Stop-Process -Name AutoHotkey64 -Force`).
5. Give the shell command itself a `timeout_ms`.

## Current state

- **11 open bugs**, all `verified` headlessly (2026-08-02; 21/21 harness scenarios passed,
  10 regression/refuted checks).
- **Where we left off:** bug #1 ("Close Windows" hotkey ignored by chat window) has a fix in
  place — scenario 8 flipped and PASSing, JS (442) + AHK (413) suites green. Next: user
  manually verifies (repro below), then commit, then close out entry #1.

---

## Bug entry template

Every open bug is one entry in "Open bugs (ranked)" using exactly this shape. When
a bug is fixed and committed, its entry moves to History (one line) — this template
stays so future entries always have the same fields. `--check-sync` enforces that
every entry's scenario id exists in `verify-bugs.js` (and that every
non-regression scenario has an entry).

    ### N. <short bug title>

    **Scenario:** <id> (scenario code in verify-bugs.js)

    **Status:** reported | verified | fix in progress | fix applied | awaiting user commit

    **Repro:** <exact steps a human can follow in the running app>

    **Expected:** <behavior when fixed>

    **Actual:** <behavior today, plus the root cause if known>

    **Evidence:** <file/line references or a one-line explanation of the cause>

    **Verification:** <how the headless scenario proves it — what was clicked/driven
    and what was observed; for non-automatable bugs, the unit/static/manual check
    and exactly how it was done>

Example (shape only, not a real bug):

    ### 1. Example: hotkey does nothing

    **Scenario:** 99 (scenario code in verify-bugs.js)

    **Status:** verified — open

    **Repro:** Settings → Hotkeys → set X → Save → press X.

    **Expected:** the action runs.

    **Actual:** nothing happens — `_ApplyHotkeys` never reads the setting.

    **Evidence:** `Main.ahk:12` wires the hotkey from a hardcoded value.

    **Verification:** headless — pressed X via probe, observed no postMessage.

Entries are ranked by severity/impact (1 = highest); only `verified` bugs are fixed,
one at a time, in rank order.

## Open bugs (ranked)

### 1. "Close Windows" hotkey setting is ignored by the chat window

**Scenario:** 8 (scenario code in verify-bugs.js)

**Status:** fix applied

**Repro:** change Close Windows to e.g. `~^q` → Save; use it in the chat window.

**Expected:** the new hotkey closes the chat window.

**Actual:** the chat window's close binding is hardcoded `~^w::` in `ChatWindow.ahk` and never reads the setting; the configured hotkey only closes the input window. (Live Ctrl+W itself works — user-verified.)

**Verification:** headless — scenario 8 statically confirms ChatWindow now registers the
configured `closeWindowsHotkey` via the new `chat/ChatHotkeys.ahk` (no hardcoded `~^w::`,
empty = disabled, re-registered on settings saves), and asserts the Hotkeys tab no longer
shows the stale "restart required" banner (removed — hotkey changes are live on both the
main script and the chat window); unit tests cover registration, Off/On rotation, disable,
and hide-when-active behavior.

**Manual check:** Settings → Hotkeys → change Close Windows to e.g. `~^q` → Save → with the
chat window focused, press `Ctrl+Q` — it should hide. Reopen and press `Ctrl+W` — it should
no longer close the chat window. Clear the field (empty = disabled) → Save → `Ctrl+W` stays
inactive. The "Hotkey changes require a restart" banner should be gone from the Hotkeys tab.

### 2. Suspend banner edits don't take effect until restart

**Scenario:** 12 (scenario code in verify-bugs.js)

**Status:** verified — open

**Repro:** change the suspend banner text → Save → suspend.

**Expected:** the new text.

**Actual:** the old text — the banner GUI is built once at startup.

**Verification:** headless — after saving "NEW BANNER TEXT", the suspended banner still showed "OLD BANNER TEXT".

### 3. "Command Input Window" settings are dead (colors never apply; size/font need restart)

**Scenario:** 13 (scenario code in verify-bugs.js)

**Status:** verified — open

**Repro:** change input-window background/font/color/size → Save → run a showInputBox command.

**Expected:** the new appearance.

**Actual:** background and font color are never applied at all; width/height/font only apply after restart.

**Verification:** headless — after saving width 800, the window opened at 554.

### 4. Title generation resets the topbar folder label to "Unfiled"

**Scenario:** 14 (scenario code in verify-bugs.js)

**Status:** verified — open

**Repro:** move a chat into a folder, send the first message, wait for the auto-title.

**Expected:** the folder name under the title.

**Actual:** "Unfiled" — `ThreadTitleGen.ahk` posts a hardcoded `folder: "Unfiled"`, and the JS stores it into `_threadMeta`.

**Verification:** headless scenario 14 (static trace; end-to-end title-gen isn't automatable here — see README limitations).

### 5. Chat topbar "Export" button does nothing

**Scenario:** 15 (scenario code in verify-bugs.js)

**Status:** verified — open

**Repro:** click the download icon in the chat topbar.

**Expected:** conversation export.

**Actual:** nothing — the button has no id/handler.

**Verification:** headless — click produced no message and no state change.

### 6. API Logs viewer latency column always shows "–"

**Scenario:** 16 (scenario code in verify-bugs.js)

**Status:** verified — open

**Repro:** make any request, open API Logs.

**Expected:** the request duration.

**Actual:** "–" — the viewer reads `entry.latencyMs`; every logger writes `responseTimeMs`.

**Verification:** headless scenario 16.

### 7. System-prompt modal "0 chars" counter never updates

**Scenario:** 17 (scenario code in verify-bugs.js)

**Status:** verified — open

**Repro:** edit a system message and type.

**Expected:** the counter updates.

**Actual:** stays "0 chars" — no code writes to `#charCount`.

**Verification:** headless scenario 17.

### 8. Custom icon picked outside the repo never applies to the chat window

**Scenario:** 18 (scenario code in verify-bugs.js)

**Status:** verified — open

**Repro:** set Icon (active) to an absolute path outside the repo → restart.

**Expected:** the chat window shows it.

**Actual:** `ChatWindow.ahk` builds `A_ScriptDir "\..\" iconOn`, mangling absolute paths (`LoadPicture` returns 0); the tray icon is unaffected.

**Verification:** headless — direct LoadPicture ok, mangled path h=0, window icon unchanged.

### 9. Dashboard "All Time" caps the chart at 365 days (summary shows all time)

**Scenario:** 19 (scenario code in verify-bugs.js)

**Status:** verified — open

**Repro:** have usage older than a year; open Dashboard → All Time.

**Expected:** the chart covers the full history.

**Actual:** summary sums every row, but the chart renders only 365 labels.

**Verification:** headless — summary $6.00 incl. a 400-day-old row; chart 365 labels.

### 10. Right-panel Advanced toggles (Structured Outputs / Code Execution / Web Search) do nothing

**Scenario:** 20 (scenario code in verify-bugs.js)

**Status:** verified — open

**Repro:** toggle them and send.

**Expected:** the request is affected.

**Actual:** only a CSS class toggles; the same `updateModelSettings` payload is posted.

**Verification:** headless — payload unchanged; only visual state changed.

### 11. Reasoning-only responses get no action buttons until reload

**Scenario:** 21 (scenario code in verify-bugs.js)

**Status:** verified — open

**Repro:** a model returns reasoning with empty final content.

**Expected:** the completed bubble has Copy/Retry/etc.

**Actual:** the message is not added to `chatMessages` and no actions render until reload.

**Verification:** headless scenario 21.

---

## History (append-only)

Entries move here when a bug is closed (user committed) or refuted. Add one line per
closure; never rewrite past entries.

- 2026-08-02 — "New models added in Settings lose reasoning/thinking metadata" — FIXED in aa9b263: `models.js` now parses `api`/`compat`/`thinkingLevelMap`/`thinkingOff` from fetched raw entries, stashes them on rows, and re-emits them on save (previously only default ids survived via the defaults merge); scenario 5 kept as a regression check (`regression: true`) + unit tests.
- 2026-08-02 — "Chat request failure with no output file shows no error and leaves the UI stuck" — FIXED in 53aa3e4: `_handleStreamError` now always posts `showError` + `setChatButtonsEnabled(true)` (using cURL stderr when the output file never exists) instead of gating the error/re-enable on the output file; scenario 6 flipped to a regression check (`regression: true`) + StreamError unit test.
- 2026-08-02 — "Trash retention never auto-purges" — FIXED in e9741f5: `Main.ahk` now calls `ChatDB.Thread_PurgeExpired()` at startup, on an hourly timer, and on settings updates (retention changes apply immediately); scenario 7 flipped to a regression check (`regression: true`) + ChatDB purge unit test.
- 2026-08-01 — "Quick Access → Usage Dashboard does nothing on prewarmed window" — REFUTED:
  the real flow opened the dashboard (the ChatWindow script-window title contains "Chat",
  so the IPC still reaches the process). Scenario 9 kept as a regression check
  (`regression: true`).
- 2026-08-01 — "Chat delete confirmations are broken — the confirm button is a no-op" — FIXED in fdf1dd5: chat-side confirm helper renamed to `_showChatConfirm` so it no longer collides with the Settings `window._showConfirm`; scenario 23 flipped to assert the fixed behavior.
- 2026-08-01 — "Command `thinking` settings are dropped after any settings round-trip" — FIXED in c7cae37: `_extractCommandParams` now reads Map-form thinking via Has()/[] (HasOwnProp is false for Map keys); scenario 22 flipped to assert Map and object forms both survive.
- 2026-08-01 — "Deleting the active chat leaks its per-thread settings into the next chat" — FIXED in 76be0ba: deleteThread/deleteThreadForever/emptyTrash now reset requestParams and refresh the UI when the active thread is removed; scenario 1 flipped + dispatch regression tests for active vs inactive deletion.
- 2026-08-01 — "New chats ignore the configured `New Chats Start With` default" — FIXED in 3e36eeb: added the General-tab dropdown (App Default / assistants / models) stored as top-level `newChatStartsWith`, removed the "Set as Default Assistant" toggle, renamed the runtime baseline `chatDefaultModel` — `appDefaultModel`, and applied the default in newChat/handleChatSend; scenario 2 flipped + JS/AHK regression tests.
- 2026-08-02 — "Removing models/providers in Settings doesn't persist" — FIXED in 04d76dd: save applies each section payload per top-level key (`SettingsMerge.Override`) and load treats the saved models/providers lists as authoritative (`SettingsMerge.MergeAuthoritativeList`), so removals survive both Save and reload/reopen; scenario 3 extended to hide+reopen Settings + regression tests.
- 2026-08-02 — "Clearing a hotkey field does nothing — hotkeys can't be disabled" — FIXED in 00bb503: empty hotkey now means disabled — `_ApplyHotkeys` applies the empty value (clears the global) and `_registerAllHotkeys` skips empty bindings (old binding turned Off first); scenario 4 flipped + regression tests + "leave empty to disable" UI hints.
