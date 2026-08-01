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
3. Add/extend regression tests. **[files: `tests/unit/*`; also `tests/run_ahk_tests.ahk`
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
  starting the next bug (the worktree must be clean of the previous fix).
- Only one agent edits this document at a time.
- Never delete an entry until the user has actually committed.
- **Doc-set rule:** if you change the harness itself (new probe command, new helper, new
  mock mode), update `README.md`; if you change the workflow itself, update `ARCHITECTURE.md`.
  Never hard-code drift-prone numbers (e.g. test totals) in docs — point at the runner
  instead.
- Only two files must stay in sync: this file and `verify-bugs.js` — `--check-sync`
  enforces it after every edit.

## Current state

- **20 open bugs**, all `verified` headlessly (2026-08-01; 21/21 harness scenarios passed,
  one scenario is the refuted-bug regression check).
- **Where we left off:** no fixes yet — start with bug #1 (Phase 2, step 1: set
  `fix in progress` in its entry).

---

## Open bugs (ranked)

### 1. Chat delete confirmations are broken — the confirm button is a no-op

**Scenario:** 23 (scenario code in verify-bugs.js)

**Status:** verified — open

**Repro:** Open a chat, click the trash icon on a chat in the sidebar (or Delete on a message). A dialog appears — click its confirm button.

**Expected:** the chat/message is deleted.

**Actual:** the dialog is the wrong one (the Settings panel's `#confirmModal`), its message shows the raw callback source, and clicking the button only closes the dialog — nothing is deleted.

**Evidence:** `chat-core.js` defines `_showConfirm(message, onYes)`, but `main.js` runs last and overwrites `window._showConfirm` with the Settings version `(title, msg, btnText, onConfirm)`. All chat callers pass `(message, callback)`, so `onConfirm` is undefined.

**Verification:** headless — clicked delete, observed `#confirmModal` with the callback source as its message, clicked `#confirmBtn`, confirmed no `deleteThread` message and the thread survived.

### 2. Command `thinking` settings are dropped after any settings round-trip

**Scenario:** 22 (scenario code in verify-bugs.js)

**Status:** verified — open

**Repro:** Save any setting (so `settings.json` exists), then run a command with a thinking level (e.g. "Refine" with `thinking: {type:"enabled", level:"none"}`).

**Expected:** the configured thinking config is sent (e.g. `thinking:{type:"disabled"}`).

**Actual:** no thinking config is sent — after a round-trip `cmd.thinking` is an AHK `Map`, and `_extractCommandParams` gates on `Map.HasOwnProp("type")`, which is false for Map keys.

**Evidence:** AHK probe + unit tests (`../unit/CommandThinkingMap.test.ahk`): `Map(...).HasOwnProp("type")` → 0; object-literal form works.

**Verification:** headless scenario 22 + 2 AHK unit tests.

### 3. Deleting the active chat leaks its per-thread settings into the next chat

**Scenario:** 1 (scenario code in verify-bugs.js)

**Status:** verified — open

**Repro:** Open a chat using an assistant (or custom model/system prompt/reasoning/temperature/font size), delete it (note: bug #1 blocks the UI path today — post the delete action directly or fix #1 first), then send a new message in the empty chat.

**Expected:** the new chat starts with app defaults.

**Actual:** the new thread inherits the deleted chat's assistant, system prompt, reasoning, temperature, and font size (`handleChatSend` creates the thread without resetting `requestParams`).

**Verification:** headless — new thread had `assistant_id=asst-1`, the pirate system prompt, `reasoning=high`, `temp=0.3`, `font_size=21`.

### 4. "Set as Default Assistant" does nothing

**Scenario:** 2 (scenario code in verify-bugs.js)

**Status:** verified — open

**Repro:** Settings → Assistants → toggle "Set as Default Assistant" → Save → New Chat.

**Expected:** the new chat starts with that assistant.

**Actual:** zero effect — `defaultAssistant` is written but never read by any new-chat flow.

**Verification:** headless — new chat still has `assistantName=""`.

### 5. Removing models/providers in Settings doesn't persist

**Scenario:** 3 (scenario code in verify-bugs.js)

**Status:** verified — open

**Repro:** Settings → Models/Providers → click ✕/Remove on any row → Save → reopen.

**Expected:** the entry is gone.

**Actual:** every removed model/provider reappears — the deep merge in `_HandleSaveSettings` resurrects absent keys.

**Verification:** headless — removed `deepseek/deepseek-chat` + provider `deepseek`, both back in `settings.json` after Save.

### 6. Clearing a hotkey field does nothing — hotkeys can't be disabled

**Scenario:** 4 (scenario code in verify-bugs.js)

**Status:** verified — open

**Repro:** Settings → Hotkeys → clear "Main menu hotkey" → Save → press backtick.

**Expected:** validation rejects the empty value or the hotkey is disabled.

**Actual:** the field saves `""` but the old binding stays live (`_ApplyHotkeys` skips empty values; AHK throws on `Hotkey("", …)`).

**Verification:** headless — `settings.json` saved `""`, backtick still opened the menu.

### 7. New models added in Settings lose reasoning/thinking metadata

**Scenario:** 5 (scenario code in verify-bugs.js)

**Status:** verified — open

**Repro:** Settings → Models → + Add (or Fetch Latest → + Add on a new model) → Save → switch to it.

**Expected:** the Reasoning dropdown shows the model's levels.

**Actual:** only "Model Default" — `models.js save()` drops `compat`/`thinkingLevelMap`/`thinkingOff`/`api`, and new IDs have no default entry to merge from.

**Verification:** headless — dropdown had exactly 1 option; plus JS probe.

### 8. Chat request failure with no output file shows no error and leaves the UI stuck

**Scenario:** 6 (scenario code in verify-bugs.js)

**Status:** verified — open

**Repro:** send a chat message while the provider is unreachable (connection refused/DNS).

**Expected:** an error banner and re-enabled send button.

**Actual:** `_handleStreamError` only posts error/re-enable when the cURL output file exists; connection failures produce no file, so nothing is posted and the UI stays in the Stop state until the user presses Stop.

**Verification:** headless — refused endpoint; no error banner, stuck until Stop.

### 9. Trash retention never auto-purges

**Scenario:** 7 (scenario code in verify-bugs.js)

**Status:** verified — open

**Repro:** set Trash retention to 1 day, trash a chat, wait.

**Expected:** auto-delete after the period.

**Actual:** never — `ThreadRepo.PurgeExpired()` has zero callers.

**Verification:** headless — static caller check + expired trashed thread survived.

### 10. "Close Windows" hotkey setting is ignored by the chat window

**Scenario:** 8 (scenario code in verify-bugs.js)

**Status:** verified — open

**Repro:** change Close Windows to e.g. `~^q` → Save; use it in the chat window.

**Expected:** the new hotkey closes the chat window.

**Actual:** the chat window's close binding is hardcoded `~^w::` in `ChatWindow.ahk` and never reads the setting; the configured hotkey only closes the input window. (Live Ctrl+W itself works — user-verified.)

**Verification:** headless scenario 8 (static trace) + user manual confirmation.

### 11. Suspend banner edits don't take effect until restart

**Scenario:** 12 (scenario code in verify-bugs.js)

**Status:** verified — open

**Repro:** change the suspend banner text → Save → suspend.

**Expected:** the new text.

**Actual:** the old text — the banner GUI is built once at startup.

**Verification:** headless — after saving "NEW BANNER TEXT", the suspended banner still showed "OLD BANNER TEXT".

### 12. "Command Input Window" settings are dead (colors never apply; size/font need restart)

**Scenario:** 13 (scenario code in verify-bugs.js)

**Status:** verified — open

**Repro:** change input-window background/font/color/size → Save → run a showInputBox command.

**Expected:** the new appearance.

**Actual:** background and font color are never applied at all; width/height/font only apply after restart.

**Verification:** headless — after saving width 800, the window opened at 554.

### 13. Title generation resets the topbar folder label to "Unfiled"

**Scenario:** 14 (scenario code in verify-bugs.js)

**Status:** verified — open

**Repro:** move a chat into a folder, send the first message, wait for the auto-title.

**Expected:** the folder name under the title.

**Actual:** "Unfiled" — `ThreadTitleGen.ahk` posts a hardcoded `folder: "Unfiled"`, and the JS stores it into `_threadMeta`.

**Verification:** headless scenario 14 (static trace; end-to-end title-gen isn't automatable here — see README limitations).

### 14. Chat topbar "Export" button does nothing

**Scenario:** 15 (scenario code in verify-bugs.js)

**Status:** verified — open

**Repro:** click the download icon in the chat topbar.

**Expected:** conversation export.

**Actual:** nothing — the button has no id/handler.

**Verification:** headless — click produced no message and no state change.

### 15. API Logs viewer latency column always shows "–"

**Scenario:** 16 (scenario code in verify-bugs.js)

**Status:** verified — open

**Repro:** make any request, open API Logs.

**Expected:** the request duration.

**Actual:** "–" — the viewer reads `entry.latencyMs`; every logger writes `responseTimeMs`.

**Verification:** headless scenario 16.

### 16. System-prompt modal "0 chars" counter never updates

**Scenario:** 17 (scenario code in verify-bugs.js)

**Status:** verified — open

**Repro:** edit a system message and type.

**Expected:** the counter updates.

**Actual:** stays "0 chars" — no code writes to `#charCount`.

**Verification:** headless scenario 17.

### 17. Custom icon picked outside the repo never applies to the chat window

**Scenario:** 18 (scenario code in verify-bugs.js)

**Status:** verified — open

**Repro:** set Icon (active) to an absolute path outside the repo → restart.

**Expected:** the chat window shows it.

**Actual:** `ChatWindow.ahk` builds `A_ScriptDir "\..\" iconOn`, mangling absolute paths (`LoadPicture` returns 0); the tray icon is unaffected.

**Verification:** headless — direct LoadPicture ok, mangled path h=0, window icon unchanged.

### 18. Dashboard "All Time" caps the chart at 365 days (summary shows all time)

**Scenario:** 19 (scenario code in verify-bugs.js)

**Status:** verified — open

**Repro:** have usage older than a year; open Dashboard → All Time.

**Expected:** the chart covers the full history.

**Actual:** summary sums every row, but the chart renders only 365 labels.

**Verification:** headless — summary $6.00 incl. a 400-day-old row; chart 365 labels.

### 19. Right-panel Advanced toggles (Structured Outputs / Code Execution / Web Search) do nothing

**Scenario:** 20 (scenario code in verify-bugs.js)

**Status:** verified — open

**Repro:** toggle them and send.

**Expected:** the request is affected.

**Actual:** only a CSS class toggles; the same `updateModelSettings` payload is posted.

**Verification:** headless — payload unchanged; only visual state changed.

### 20. Reasoning-only responses get no action buttons until reload

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

- 2026-08-01 — "Quick Access → Usage Dashboard does nothing on prewarmed window" — REFUTED:
  the real flow opened the dashboard (the ChatWindow script-window title contains "Chat",
  so the IPC still reaches the process). Scenario 9 kept as a regression check
  (`regression: true`).
