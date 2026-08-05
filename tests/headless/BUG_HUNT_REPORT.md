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
| `BUG_HUNT_REPORT.md` (this file) | every step — statuses, entries, history, "Where we left off" |
| `e2e-suite.js` + `scenarios/*.js` | intake: add a scenario; fix cycle: flip an assertion |
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
*code* lives in `scenarios/*.js` (runner: `e2e-suite.js`), not in this file. Run it with
`node tests/headless/e2e-suite.js --scenarios=<id>`. `--check-sync` verifies every
entry's id exists (and that every non-regression scenario has an entry).

**Phase 1 — Intake** (a bug enters and gets verified here):

1. Write the entry in this file (Repro / Expected / Actual / Evidence + scenario id) with
   `Status: reported`. **[file: this file]**
2. Ensure a verifying scenario exists in `scenarios/*.js`; add one if not.
   **[file: `tests/headless/scenarios/`]**
3. Run `node tests/headless/e2e-suite.js --check-sync` (must say OK), then
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
4. Flip the scenario assertion in `scenarios/*.js` to expect the **fixed** behavior
   (otherwise it fails forever). **[file: `tests/headless/scenarios/`]**
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
- Only two files must stay in sync: this file and `e2e-suite.js` — `--check-sync`
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

1. **Prefer the harness.** Add a scenario to `scenarios/*.js` (it wraps every AHK
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

- **23 verified, 0 fix applied, 0 fix in progress** (2026-08-05). Scenario count is enforced by
  `node tests/headless/e2e-suite.js --check-sync` (do not hard-code it here).
- **Where we left off:** architecture branch `arch/robust-ipc-settings` steps 1-5 landed
  (typed IPC contract 8df50b4, correlation ids/acks 0a0ab9c, SettingsService +
  threadSettings/appSettings split 5c6a5f6, ThreadSettings consolidation 58bf6f3,
  shared ModelResolver/SystemMessageResolver cc3db48). Bug #42 closed (fixed in
  8df50b4); #43/#51 closed (fixed in cc3db48); entries moved to History with
  scenarios 42/43/51 flipped to regression checks. All 56 e2e scenarios pass
  (run in batches) plus the full AHK and JS suites. Next per the fix cycle:
  bug #29, then the rest in rank order, one at a time, each with a flipped
  scenario + code-level regression test. Harness cleanup is PID-targeted: use
  `node tests/headless/e2e-suite.js --cleanup` after aborted runs and NEVER
  blanket-kill `AutoHotkey64.exe` (see "Harness safety" above).

---

## Bug entry template

Every open bug is one entry in "Open bugs (ranked)" using exactly this shape. When
a bug is fixed and committed, its entry moves to History (one line) — this template
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

    **Verification:** <how the headless scenario proves it — what was clicked/driven
    and what was observed; for non-automatable bugs, the unit/static/manual check
    and exactly how it was done>

Example (shape only, not a real bug):

    ### 1. Example: hotkey does nothing

    **Scenario:** 99 (scenario code in e2e-suite.js)

    **Status:** verified — open

    **Repro:** Settings → Hotkeys → set X → Save → press X.

    **Expected:** the action runs.

    **Actual:** nothing happens — `_ApplyHotkeys` never reads the setting.

    **Evidence:** `Main.ahk:12` wires the hotkey from a hardcoded value.

    **Verification:** headless — pressed X via probe, observed no postMessage.

Entries are ranked by severity/impact (1 = highest); only `verified` bugs are fixed,
one at a time, in rank order.

## Open bugs (ranked)

### 29. Blank cached-input price costs 0 instead of the advertised 10% fallback

**Scenario:** 29 (scenario code in e2e-suite.js)

**Status:** verified

**Repro:** Settings -> Models -> add a model (or edit one) -> leave "Cached" blank
-> Save -> send a request with cached-token usage and check the cost.

**Expected:** the Models table hint says "Cached input defaults to 10% of input if
blank", so a blank Cached price should cost 10% of the input price.

**Actual:** the advertised fallback never applies. `CostCalculator._ResolvePricing`
only falls back to `inputPrice * 0.1` when the property is entirely MISSING; the
settings round-trip always writes a `cachedInput` key. Two failure modes, same root
cause:
- UI-blank (saved as `0` by the pricing input's focus/blur): cached tokens cost $0
  instead of 10% of input (usage bar / dashboard under-report cached cost).
- Legacy/hand-edited entry with `cachedInput: ""`: `cachedTokens * "" / 1000000`
  THROWS AHK's "Expected a Number but got an empty string". In the chat flow that
  exception propagates out of `MessageRepo.Insert`, so the streamed assistant
  message is never persisted and `streamDone` never posts (UI stuck in Stop state).

**Evidence:** `api/CostCalculator.ahk` `_ResolvePricing`:
`cachedInputPrice := m.HasOwnProp("cachedInput") ? m.cachedInput : (inputPrice * 0.1)`;
`app/settings/SettingsApply.ahk` `_ApplyModels` always sets `cachedInput` (to `""`
when the saved entry lacks it).

**Verification:** headless scenario 29 (noApp) runs `probe-cost.ahk`, which computes
token costs for a model missing `cachedInput` (control = 1.0 fallback works) and for
a model with `cachedInput: ""` (throws "Expected a Number but got an empty string").

### 30. Deleting a message confirms "data is preserved" but hard-deletes it

**Scenario:** 30 (scenario code in e2e-suite.js)

**Status:** verified

**Repro:** in a chat, click the trash icon on any message bubble; read the
confirmation; click Delete.

**Expected:** either the confirmation honestly says the deletion is permanent, or
the delete preserves the message data.

**Actual:** the confirmation says "This removes it from the current view but data
is preserved", but confirming calls `ChatDB.Msg_HardDelete` — the message row,
its attachments, and its FTS index entry are permanently removed. Users who
believe the message is recoverable can lose content with no undo.

**Evidence:** `webui/js/chat/chat-branching.js` `deleteMessage()` shows the
"data is preserved" copy; `chat/callbacks/Edit.ahk` `handleDelete()` calls
`ChatDB.Msg_HardDelete(msgId)` (permanent delete + re-parenting).

**Verification:** headless scenario 30 seeds a two-message thread, clicks Delete
on the user message, reads the dialog text (contains "data is preserved"), confirms,
and queries the DB — the message row is gone.

### 31. Font-size +/- buttons use a stale 17px base after a thread with a custom size loads

**Scenario:** 31 (scenario code in e2e-suite.js)

**Status:** verified

**Repro:** set a per-thread font size (e.g. 20px via the topbar + button) and
switch to that thread from another chat, then click the topbar + button again.

**Expected:** the + button increases the thread's current size (20px -> 21px).

**Actual:** clicking + jumps the display to 18px. `UiControls.initFontControls()`
reads `--chat-font-size` once at page load and caches 17; `populateCurrentSettings`
later applies the thread's stored size (20px) to the CSS var and the display, but
never resyncs the cached base — every +/- click counts from 17, so the font can
jump downward while the user is trying to increase it.

**Evidence:** `webui/js/ui-controls.js` `initFontControls()` caches
`getComputedStyle(...).getPropertyValue('--chat-font-size')` at load;
`webui/js/chat/model-picker/model-picker-config.js` `populateCurrentSettings()`
sets `--chat-font-size` without updating that cached value.

**Verification:** headless scenario 31 seeds a thread with `font_size=20`, loads it
(display shows 20px), clicks `#btn-font-inc`, and observes the display becomes 18px
instead of 21px.

### 44. Forking a chat drops the per-thread font size and Advanced toggles

**Scenario:** 44 (scenario code in e2e-suite.js)

**Status:** verified

**Repro:** set a custom chat font size (topbar +/â€“) and/or Advanced toggles
(Code Execution / Web Search) in a thread, then click Fork on any message.

**Expected:** the forked thread inherits the per-thread settings — same font size
and same toggle states.

**Actual:** the fork starts at the defaults (17px, toggles off).
`TreeRepo._CopyThreadSettings` copies model/system/reasoning/temperature/assistant
but never `font_size` or `advanced_toggles`, even though both are per-thread
columns that every other settings path reads and writes (`Thread_UpdateSettings`,
`ThreadRepo.GetSettings`).

**Evidence:** `chat/db/TreeRepo.ahk` `_CopyThreadSettings()` contains no
`font_size` / `advanced_toggles` UPDATE; `chat/db/ThreadRepo.ahk` `GetSettings()`
returns both fields.

**Verification:** headless scenario 44 seeds a thread with `font_size=20` and
`advanced_toggles` JSON, forks it from the UI, and queries the new thread:
`font_size=17` and `advanced_toggles=''`, while the topbar font display shows
17px instead of 20px.

### 33. Clearing the chat-window icon setting still loads the default custom icon

**Scenario:** 33 (scenario code in e2e-suite.js)

**Status:** verified

**Repro:** Settings -> Icons -> clear both icon paths -> Save -> look at the chat
window title-bar/taskbar icon.

**Expected:** with no icon configured, the chat window keeps the plain window icon
(the app only loads an icon when `iconOn` is non-empty).

**Actual:** the window still shows `icons\IconOn.ico`. `SettingsApply._ApplyIcons`
only assigns the globals when the saved value is non-empty, so saving an empty
`icons.iconOn` leaves the `DefaultSettings.ahk` value (`icons\IconOn.ico`) in the
`iconOn` global and `ChatWindow.ahk` loads it — clearing the icon can never take
effect, not even after a restart.

**Evidence:** `app/settings/SettingsApply.ahk` `_ApplyIcons` skips `""` values;
`DefaultSettings.ahk` `iconOn := "icons\IconOn.ico"`; `chat/ChatWindow.ahk`
`if iconOn != "" hIcon := LoadPicture(ResolveIconPath(iconOn), ...)`.

**Verification:** headless scenario 33 seeds `icons: {iconOn:'', iconOff:''}`,
launches the app, and probes the chat window icon via `WM_GETICON` — the rendered
pixels match IconOn.ico's fingerprint (`customApplied=1`), proving the cleared
setting is ignored.

### 34. Tray icon changes don't apply until restart

**Scenario:** 34 (scenario code in e2e-suite.js)

**Status:** verified

**Repro:** Settings -> Icons -> pick a different tray icon -> Save -> look at the
system tray.

**Expected:** the tray icon changes immediately (like the fixed Suspend-banner and
Input-window settings that rebuild on every settings update).

**Actual:** the tray keeps the old icon until the app is restarted. `TraySetIcon(iconOn)`
runs once at Main startup (and again only when suspend is toggled); the
`WM_SETTINGS_UPDATED` handler reloads globals, hotkeys, the suspend banner, and the
input window, but never re-applies the tray icon.

**Evidence:** `Main.ahk` startup `TraySetIcon(iconOn)`; the `WM_SETTINGS_UPDATED`
OnMessage handler has no `TraySetIcon` call (visual — cannot be asserted by the
headless harness, hence the static scenario).

**Verification:** headless scenario 34 (noApp) statically scans `Main.ahk`:
`TraySetIcon(iconOn)` exists at startup but not inside the `WM_SETTINGS_UPDATED`
handler. Final visual confirmation requires a human looking at the tray after
changing the icon.

### 35. Temperature override of 0 is dropped when the thread reloads (right rail shows Default)

**Scenario:** 35 (scenario code in e2e-suite.js)

**Status:** verified

**Repro:** set the chat right-rail temperature slider to 0.0, then switch to
another chat and back (or restart the app) and look at the temperature slider.

**Expected:** the slider shows 0.0 and the next request uses temperature 0.

**Actual:** the override is silently lost — the rail shows "Default" (slider 1.0)
and requests use the model default. `_restoreThreadSettings` gates restoration
with `if settings.temperatureOverride`, and AHK treats the numeric 0 as falsy, so
the saved 0 override is never applied back to `requestParams`. A later right-rail
save then overwrites `temperature_override` with NULL, wiping it permanently.

**Evidence:** `chat/ChatSettings.ahk` `_restoreThreadSettings()`:
`if settings.temperatureOverride requestParams["temperatureOverride"] := settings.temperatureOverride`;
`chat/db/ThreadRepo.ahk` `GetSettings()` returns the raw numeric column
(0 when set), and `_ClearRequestOverrides()` empties the override on every load.

**Verification:** headless scenario 35 seeds a thread with
`temperature_override = 0`, loads it in the real app, and observes the right-rail
temperature shows "Default" / slider 1.0 instead of 0.0.

### 36. Command temperature/reasoning are dropped when the command model equals the app default

**Scenario:** 36 (scenario code in e2e-suite.js)

**Status:** verified

**Repro:** create a chat-mode command whose API Model is the app default
(`deepseek/deepseek-v4-flash`), set a Temperature (e.g. 0) or a Thinking level,
save, then trigger the command and watch the request.

**Expected:** the command's temperature and thinking level are sent to the API.

**Actual:** they are silently dropped. `processInitialRequest` persists
per-thread settings (`temperatureOverride`, `reasoningOverride`, ...) only inside
`if fullAPIModelName != appDefaultModel`, so a command using the default model
never writes those overrides — the thread loads with defaults and the fired
request uses the model default temperature and no thinking config. (The system
message survives because it is stored as a system message row, not an override.)

**Evidence:** `app/RequestProcessor.ahk` — `ChatDB.Thread_UpdateSettings(threadId,
{ ... temperatureOverride: temperature, reasoningOverride: ... })` is nested in
`if fullAPIModelName != appDefaultModel`.

**Verification:** headless scenario 36 (noApp) statically scans
`app/RequestProcessor.ahk` and asserts the temperature/reasoning overrides live
inside the `!= appDefaultModel` gate — proving default-model commands skip them.

### 37. Tray menu item changes don't apply until restart

**Scenario:** 37 (scenario code in e2e-suite.js)

**Status:** verified

**Repro:** Settings -> Menu Items -> add/remove/rename a Tray item -> Save -> open
the tray menu.

**Expected:** the tray menu shows the new items immediately (the Quick Access
submenu is rebuilt on every open).

**Actual:** the tray keeps the startup entries until the app restarts. `Main.ahk`
populates `A_TrayMenu` once at startup from `trayMenuItems`; the
`WM_SETTINGS_UPDATED` handler reloads the globals but never rebuilds the tray menu.

**Evidence:** `Main.ahk` `A_TrayMenu.Delete()` / `A_TrayMenu.Add(...)` at startup
only; the `WM_SETTINGS_UPDATED` handler has no `A_TrayMenu` call.

**Verification:** headless scenario 37 (noApp) statically scans `Main.ahk`:
`A_TrayMenu.Add` exists at startup but not in the `WM_SETTINGS_UPDATED` handler.
Final visual confirmation requires a human opening the tray after saving.

### 38. Chat window title stays stale after renaming a thread and switching to another

**Scenario:** 38 (scenario code in e2e-suite.js)

**Status:** verified

**Repro:** open a chat, rename it from the sidebar (or the topbar rename button),
then click a different chat in the sidebar and look at the window title bar.

**Expected:** the title bar shows the active thread ("Chat - <current title>").

**Actual:** the title bar keeps the previously renamed thread's title.
`chatWindow.Title` is only set at startup and in the `renameThread` handler
(`chat/callbacks/Sidebar.ahk`); `_LoadThreadAndRefreshUI` never updates it, so
switching threads leaves the stale title (and before any rename it just shows
"Chat" / the generic app title).

**Evidence:** `chat/ChatWindow.ahk` `responseWindow.Title := "LLM AutoHotkey Assistant"`;
`chat/callbacks/Sidebar.ahk` `renameThread` sets `chatWindow.Title := "Chat - " title`;
`chat/ChatUtils.ahk` `_LoadThreadAndRefreshUI()` never touches the window title.

**Verification:** headless scenario 38 seeds two threads, renames the first via
the sidebar, switches to the second, and probes the window title (WinGetTitle):
the topbar shows the second thread's title while the window title still contains
the renamed first thread's title.

### 45. "Response Font" setting is not applied to chat messages until Settings is opened

**Scenario:** 45 (scenario code in e2e-suite.js)

**Status:** verified

**Repro:** Settings â†’ UI & Theme â†’ set Response Font to something other than
Inter (e.g. Georgia) â†’ Save â†’ close Settings â†’ look at the message text.

**Expected:** messages render in the configured font immediately, and keep it
after every restart.

**Actual:** messages keep the default font until the user opens Settings again.
`ui-theme.js` applies `--chat-font-family` only inside `load()`, which runs when
the Settings panel receives the full settings payload. At app start (and after a
save until Settings is reopened) the WebView never receives the CSS var, so the
saved Response Font is silently ignored.

**Evidence:** `webui/js/settings/sections/ui-theme.js` sets
`--chat-font-family` only in `load()`; `SettingsApply._ApplyUI` only updates the
AHK global `responseWindowFontFace` â€” nothing applies it to the WebView.

**Verification:** headless scenario 45 seeds `ui.responseFont: "Georgia"`,
launches, loads a thread, and reads the computed font-family of a rendered
message â€” it is the default Inter stack; after opening Settings it becomes
Georgia.

### 39. System-message modal silently clears a custom (unlisted) system-message file on Save

**Scenario:** 39 (scenario code in e2e-suite.js)

**Status:** verified

**Repro:** Settings -> Commands -> select a command whose System Message uses a
file NOT in the hardcoded App Defaults list (e.g. `default-settings/system-messages/my-prompt.txt`
created in AppData per the UI hint) -> click Edit next to System Message -> click
Save without changing anything -> look at the command's System Message label.

**Expected:** the file reference is preserved (opening and saving a modal should
never silently change the value).

**Actual:** the file reference is cleared to empty and the label becomes
"(none)". `populateSysMsgModal` sets `#smFileSelect` from the stored value, and
the fallback only strips the directory prefix; the select's options are a
hardcoded list of 7 app-default files (the "Your Files" optgroup is never
populated), so any other file leaves `selectedIndex = -1` / `value = ""`. The
Save handler writes `fileSelect.value` back, wiping `systemMessageFile`. The
command then runs without its system prompt (falls back to empty inline).

**Evidence:** `webui/js/settings/sections/sysmsg-modal.js` `populateSysMsgModal()`
sets `fileSelect.value = opts.systemMessageFile` with a prefix-strip fallback and
the Save handler does `sysMsgFile = fileSelect ? fileSelect.value : ''`;
`webui/index.html` `#smFileSelect` contains only the app-default filenames.

**Verification:** headless scenario 39 seeds a command with
`systemMessageFile: "default-settings/system-messages/my-custom-prompt.txt"`, opens the modal
(select ends with `selectedIndex=-1`), clicks Save, and observes the command's
`systemMessageFile` becomes `""` and the label "(none)".

### 41. Tray "New Chat" ignores the "New Chats Start With" default

**Scenario:** 41 (scenario code in e2e-suite.js)

**Status:** verified

**Repro:** set General -> New Chats Start With to an assistant (or model), then
right-click the tray icon -> New Chat, and look at the chat's model/assistant.

**Expected:** the new chat starts with the configured default (same as the
sidebar "+ New Chat" button, which applies `_applyNewChatDefault()` and the
default font size).

**Actual:** the tray-created chat starts with the raw app-default model and no
assistant. `Main.ahk`'s tray item calls `openChatWindow(ChatDB.Thread_Create())`
directly; the loaded-thread path (`notifyLoadThread` -> `LoadThreadIntoUI` ->
`_LoadThreadAndRefreshUI`) never calls `_applyNewChatDefault()` nor writes the
default font size. Only `_HandleThreadAction`'s `newChat` case applies them.

**Evidence:** `Main.ahk` `A_TrayMenu.Add("📝 New Chat", (*) => openChatWindow(ChatDB.Thread_Create()))`;
`chat/ChatIPC.ahk` `LoadThreadIntoUI` / `chat/ChatUtils.ahk` `_LoadThreadAndRefreshUI`
contain no `_applyNewChatDefault` call; `chat/callbacks/Sidebar.ahk` `newChat`
does.

**Verification:** headless scenario 41 (noApp) statically scans `Main.ahk`,
`Sidebar.ahk`, `ChatIPC.ahk`, and `ChatUtils.ahk`: the tray lambda creates the
thread directly while the loader path never applies the start-with default.

### 40. Refresh-models modal discards edits to a model id (stale `data-full-id` wins on Save)

**Scenario:** 40 (scenario code in e2e-suite.js)

**Status:** verified

**Repro:** Settings -> Models -> Fetch Latest Models -> in the "Your Models"
panel edit a model's id field -> Save.

**Expected:** the edited id is saved to the models table.

**Actual:** the edit is silently discarded. `saveRefresh()` reads
`idEl.getAttribute('data-full-id') || idEl.value`; the `data-full-id` attribute
was stamped when the row was built and is never updated as the user types, so it
always wins over the visible (edited) value. Renames in the refresh modal are
impossible.

**Evidence:** `webui/js/settings/sections/models.js` `_rightRowHtml()` writes
`data-full-id`; `saveRefresh()` reads `data-full-id` first; no input listener
updates it.

**Verification:** headless scenario 40 opens the refresh modal, changes the first
row's id to "renamed-model-id", clicks Save, and observes the models table still
shows the original id.

### 46. Command "Stream Response" + pasteMode replace/append silently produces no output

**Scenario:** 46 (scenario code in e2e-suite.js)

**Status:** verified

**Repro:** create a command with Paste Mode replace (or append) and Stream
Response ON, then trigger it with a text selection.

**Expected:** the response is pasted, or at least a clear error is shown.

**Actual:** nothing is pasted and no error is shown. `LLMRequestBuilder.
createJSONRequest` writes `"stream": true` into the request body whenever the
command's stream flag is set, but `InlineRequestRunner` always executes the
request with the single-shot `CurlBuilder.Build` and parses the whole output file
as one JSON document (`jsongo.Parse` + `ResponseParser.ParseChatResponse`). A
streaming API answers with SSE (`data:` lines), which cannot be parsed as one JSON
document, so `success=false` and the response is silently discarded (only a debug
log line is written).

**Evidence:** `api/LLMRequestBuilder.ahk` `createJSONRequest()` â€”
`if stream { requestObj.stream := true }` with no pasteMode check;
`app/InlineRequestRunner.ahk` `_BuildAndWriteRequest()` / `_ExecuteCurlAndParse()`
use `CurlBuilder.Build` + `jsongo.Parse` with no SSE handling.

**Verification:** headless scenario 46 (noApp) statically scans the three files
and asserts the stream flag is added to the body for any pasteMode while the
inline runner uses the non-streaming single-shot parse path (no SSEParser) â€”
proving a replace/append + stream command sends an SSE-mode request it cannot
read back.

### 49. Canceling a message edit leaves removed attachments hidden in the UI but still in the DB (they get sent anyway)

**Scenario:** 49 (scenario code in e2e-suite.js)

**Status:** verified

**Repro:** in a chat with an attachment, click Edit on the message, click the
attachment's Ã— (it hides), then click Cancel instead of Save/Branch.

**Expected:** canceling an edit restores the attachment (or at least the removal
is consistently applied or not — never half-applied).

**Actual:** the attachment stays hidden in the UI while its DB row survives, so
the next request still sends it to the API. `editMessage` sets
`_editingMessageId` and starts `_removedAttachmentIds = []`; the attachment Ã—
handler defers deletion to the next Save (`_removedAttachmentIds.push(attId)` +
`wrapper.style.display = 'none'`), but the Cancel handler only removes the
`.editing` class — it neither applies the deferred deletion nor restores the
hidden wrapper, and it leaves `_editingMessageId` truthy, so subsequent Ã—
clicks on any attachment also defer (hide) instead of deleting.

**Evidence:** `webui/js/chat/chat-branching.js` `editMessage()` /
`commitEdit()` and the cancel wiring (`bubble.classList.remove('editing')`
only); `webui/js/chat/attachments/chat-attachments-setup.js`
`setupMessageAttachmentDeleteDelegation()` defers when `_editingMessageId` is
truthy.

**Verification:** headless scenario 49 seeds a user message with an attachment,
clicks Edit â†’ Ã— (wrapper hides, DB row still present) â†’ Cancel, and observes
the wrapper stays hidden, the DB row is still there, and `_editingMessageId`
remains set.

### 48. Forking a chat resets the token/cost stats (active_path_tokens and cumulative counters are not copied or recomputed)

**Scenario:** 48 (scenario code in e2e-suite.js)

**Status:** verified

**Repro:** open a chat with some token/cost history (token bar shows context
used and a running cost), click Fork on a message, and look at the forked
chat's token bar.

**Expected:** the fork reflects the copied conversation — at least the active
path's context tokens, and ideally the totals.

**Actual:** the fork's token bar resets to 0 / $0.00. `TreeRepo.ForkThread`
copies message rows but neither the thread's `cumulative_*` counters nor the
leaf's `active_path_tokens`, and it never calls `_RecomputeActivePath` on the
new thread — so `GetThreadStats` reads zeros.

**Evidence:** `chat/db/TreeRepo.ahk` `ForkThread()`/`_InsertForkMessage()` —
no `active_path_tokens` column in the INSERT and no `_RecomputeActivePath`
call; `ThreadRepo.Create()` starts cumulative counters at 0.

**Verification:** headless scenario 48 seeds a thread with token stats
(`active_path_tokens` + cumulative counters), confirms the source token bar
shows them, forks from the UI, and observes the fork's token bar shows $0.00
and the new thread's leaf `active_path_tokens` is 0.

### 52. Usage dashboard double-counts thinking tokens for command usage

**Scenario:** 52 (scenario code in e2e-suite.js)

**Status:** verified

**Repro:** run an inline command (pasteMode replace/append) or a title-gen call
with a reasoning model that reports thinking tokens, then open Usage Dashboard
and look at Total Tokens or the per-model Output chart.

**Expected:** each generated token is counted once, and identical usage counts
identically for chat vs commands.

**Actual:** command output tokens are counted twice when thinking is present.
The command-usage rows store `completion_tokens` as the FULL completion
(`ResponseParser` returns the raw `completion_tokens`, which include reasoning
tokens for OpenAI-style models, or the Gemini-inflated `total - prompt`) plus a
separate `thinking_tokens` column; `renderSummary` then computes
`cmdOutput = completion_tokens + thinking_tokens` and `renderModelSections`
does the same, so thinking tokens are added twice. Chat rows are stored as
`output_tokens` (already full, incl. thinking) and counted once — the same
100-token response with 40 thinking tokens is counted as 100 for chat and 140
for commands.

**Evidence:** `webui/js/usage-dashboard.js` `renderSummary()` (`cmdOutput =
(c.completion_tokens||0) + (c.thinking_tokens||0)`) and `renderModelSections()`
(same); `api/ResponseParser.ahk` `ParseChatResponse()` (completionTokens =
full); `app/InlineRequestRunner.ahk` `_PasteAndLogResponse()` /
`_ExtractUsage()`; `chat/ThreadTitleGen.ahk` `_TitleGen_TrackUsage()`.

**Verification:** headless scenario 52 seeds one chat row and one command row
with identical usage (prompt 10, completion 100, thinking 40) and opens the
dashboard: Total Tokens shows 260 (command counted as 140) instead of 220.

### 53. Dashboard "Last 24 Hours" spans two calendar days — the summary counts yesterday while the chart only plots today

**Scenario:** 53 (scenario code in e2e-suite.js)

**Status:** verified

**Repro:** open Usage Dashboard, select "Last 24 Hours", and compare the
summary with the chart when there was usage both yesterday and today.

**Expected:** the chart and summary cover the same window.

**Actual:** the SQL filter is `date >= date('now', '-1 day')` — yesterday's
00:00 UTC through now, i.e. up to ~48 hours — so the summary sums BOTH
yesterday's and today's rows, while `getDateRangeLabels('day')` produces a
single "today" label and the chart only plots today's rows. The summary
therefore always over-reports vs the chart for this range.

**Evidence:** `chat/db/UsageRepo.ahk` `_WhereDate()` (`"day"` returns
`date >= date('now', '-1 day')`); `webui/js/usage-dashboard.js`
`getDateRangeLabels()` (`day` â†’ 1 label) and `renderMainChart()` /
`renderSummary()`.

**Verification:** headless scenario 53 seeds usage rows for yesterday and
today and opens the dashboard with "Last 24 Hours": the summary shows $4.00
(both days) while the chart has exactly 1 label (today only).

### 55. Branch switch / search navigation land on the OLDEST continuation of a message while the tree modal lands on the newest (header shows the stale branch's context)

**Scenario:** 55 (scenario code in e2e-suite.js)

**Status:** verified

**Repro:** in a chat, branch from the same assistant message twice (two
different follow-ups created at different times), then use the branch-nav
arrows (or a search result) to switch to that branch; compare the header's
Context Used with what the tree modal shows for the same node.

**Expected:** switching to a branch lands on its newest continuation (the same
leaf the tree modal navigates to), so the header's Context Used reflects that
branch's latest state.

**Actual:** the branch switch (and search navigation) descend via
`TreeRepo._WalkToLeaf`, which picks the FIRST child by `ORDER BY created_at
LIMIT 1` — the OLDEST continuation — while the tree modal's `_findDefaultLeaf`
picks `children[children.length - 1]` (the newest). The header then shows the
stale branch's Context Used, disagreeing with the tree modal.

**Evidence:** `chat/db/TreeRepo.ahk` `_WalkToLeaf()` (`ORDER BY created_at
LIMIT 1`); `webui/js/chat/chat-tree-modal.js` `_findDefaultLeaf()`
(`children[children.length - 1]`).

**Verification:** headless scenario 55 seeds a message with an old and a new
continuation (context 70 vs 95) plus a sibling branch, switches branches with
the nav arrows, and observes Context Used shows 70 (oldest); clicking the same
node in the tree modal navigates to 95 (newest).

### 56. Stopping a stream before the first token shows an error banner instead of a clean cancel

**Scenario:** 56 (scenario code in e2e-suite.js)

**Status:** verified

**Repro:** send a message to a slow model and press Stop (or Esc) before any
content or reasoning token has arrived.

**Expected:** a user-initiated cancellation is reported as cancelled — no error
banner.

**Actual:** the UI shows the generic failure banner "Request failed. Check your
API key and try again." `_finalizeStreaming` checks "no content AND no
reasoning" FIRST and routes that case to `_handleStreamError`; the
`_streamCancelled` flag is only consulted after that check. A Stop that lands
before the first token therefore looks exactly like a connection failure.

**Evidence:** `chat/streaming/StreamHandler.ahk` `_finalizeStreaming()` — the
empty-content branch (`_handleStreamError()`) precedes the `wasCancelled`
check; `chat/streaming/StreamError.ahk` `_handleStreamError()` falls back to
the generic API-key message when stderr is empty.

**Verification:** headless scenario 56 (noApp) statically scans
`StreamHandler.ahk` and asserts the empty-content error branch runs before the
`_streamCancelled` branch and that the fallback error text blames the API key.

### 57. Chat message content is rendered as raw HTML with no sanitization (embedded HTML/scripts execute in the WebView)

**Scenario:** 57 (scenario code in e2e-suite.js)

**Status:** verified

**Repro:** have a model respond with (or paste into a message) HTML such as
`<img src="x" onerror="...">` and view the message.

**Expected:** message content is displayed as inert text; HTML from the model
or pasted input must not execute.

**Actual:** `markdown-it` is configured with `html: true` and every message /
streamed chunk is fed straight into `md.render()` without escaping or
sanitizing, so inline event handlers execute in the WebView. Because the page
has access to `window.chrome.webview.postMessage`, a malicious model response
or pasted message can drive app actions (send messages, change settings, etc.).

**Evidence:** `webui/js/main.js` `markdownit({ html: true, ... })`;
`webui/js/chat/chat-render.js` `createMessageBubble()` (`md.render(msg.content
|| '')`); `webui/js/chat/stream.js` `onStreamContent()` /
`_finalizeStreamContent()`; no CSP or sanitizer anywhere in `webui/`.

**Verification:** headless scenario 57 seeds an assistant message containing
`<img src="x" onerror="window.__xssPwned = 1">`, loads the thread, and observes
`window.__xssPwned === 1` — the handler executed.

### 58. Forking a chat drops the thread's folder (the copy lands in Unfiled)

**Scenario:** 58 (scenario code in e2e-suite.js)

**Status:** verified

**Repro:** put a chat in a folder, click Fork on a message, and look at the
sidebar.

**Expected:** the forked copy appears in the same folder as its source (like
the other copied thread-level settings).

**Actual:** the fork is created with `folder_id = NULL` and appears under
Unfiled. `TreeRepo._CopyThreadSettings` copies model/system/reasoning/
temperature/assistant but never `folder_id`.

**Evidence:** `chat/db/TreeRepo.ahk` `_CopyThreadSettings()` (no `folder_id`
UPDATE); `ThreadRepo.Create()` inserts a thread without a folder.

**Verification:** headless scenario 58 seeds a folder + a thread inside it,
forks from the UI, and queries the new thread's `folder_id` — it is NULL
(Unfiled) instead of the source folder.

---

## History (append-only)

Entries move here when a bug is closed (user committed) or refuted. Add one line per
closure; never rewrite past entries.

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
- 2026-08-02 — "Dashboard 'All Time' caps the chart at 365 days (summary shows all time)" — FIXED in 35770c0: `getDateRangeLabels()` now handles the `all` range explicitly, spanning oldest-recorded-date through today (365-day fallback when empty) so the chart matches the summary; scenario 19 flipped to a regression check (`regression: true`) + usage-dashboard unit tests.
- 2026-08-02 — "Custom icon picked outside the repo never applies to the chat window" — FIXED in 6a8a0db: new `chat/ChatIconResolver.ahk` resolves icon paths (absolute/UNC paths used as-is, repo-relative ones prefixed with `A_ScriptDir "\..\"`) so ChatWindow loads icons picked outside the repo; scenario 18 flipped to a regression check (`regression: true`) + ChatIconResolver unit tests.
- 2026-08-02 — "New models added in Settings lose reasoning/thinking metadata" — FIXED in aa9b263: `models.js` now parses `api`/`compat`/`thinkingLevelMap`/`thinkingOff` from fetched raw entries, stashes them on rows, and re-emits them on save (previously only default ids survived via the defaults merge); scenario 5 kept as a regression check (`regression: true`) + unit tests.
- 2026-08-02 — "Chat request failure with no output file shows no error and leaves the UI stuck" — FIXED in 53aa3e4: `_handleStreamError` now always posts `showError` + `setChatButtonsEnabled(true)` (using cURL stderr when the output file never exists) instead of gating the error/re-enable on the output file; scenario 6 flipped to a regression check (`regression: true`) + StreamError unit test.
- 2026-08-02 — "Trash retention never auto-purges" — FIXED in e9741f5: `Main.ahk` now calls `ChatDB.Thread_PurgeExpired()` at startup, on an hourly timer, and on settings updates (retention changes apply immediately); scenario 7 flipped to a regression check (`regression: true`) + ChatDB purge unit test.
- 2026-08-02 — "Close Windows hotkey setting is ignored by the chat window" — FIXED in 0660294: new `chat/ChatHotkeys.ahk` registers the configured `closeWindowsHotkey` in the chat process at startup and after settings saves (empty = disabled), replacing the hardcoded `~^w::`; the stale "restart required" Hotkeys banner was removed (hotkey changes are live on both processes); scenario 8 flipped to a regression check (`regression: true`) + ChatHotkeys unit tests.
- 2026-08-02 — "Suspend banner edits don't take effect until restart" — FIXED in 5957786: new `app/SuspendBanner.ahk` exposes `_rebuildSuspendBanner()`, which Main now calls at startup and on settings updates (destroying the old GUI, rebuilding from current settings, re-showing when already suspended); scenario 12 flipped to a regression check (`regression: true`) + SuspendBanner unit tests.
- 2026-08-02 — "Command Input Window settings are dead (colors never apply; size/font need restart)" — FIXED in a35233a: `InputWindow` constructor now applies background + font color, and new `_rebuildInputWindow()` (called at startup and on settings updates) rebuilds the GUI from current settings; scenario 13 flipped to a regression check (`regression: true`) + InputWindow unit tests.
- 2026-08-02 — "Title generation makes sidebar folder groups disappear until re-entry" — FIXED in a5bd97c: `ThreadTitleGen.ahk` now posts `threadList` as `{ threads, folders }` (reusing `_GetFolders()`) so folder sections stay rendered, and posts the thread's real folder name in `updateTopbarTitle` instead of hardcoded "Unfiled"; scenario 14 flipped to a regression check (`regression: true`) + extended unit test.
- 2026-08-02 — "Chat topbar 'Export' button does nothing" — FIXED in 71a1294: the button got `id="export-chat-btn"` and `exportChat()` (reusing `getMessageText`) downloads the conversation as a title-named `.txt`; scenario 15 flipped to a regression check (`regression: true`) + unit tests.
- 2026-08-02 — "API Logs viewer latency column always shows '–'" — FIXED in b1f0386: the viewer now renders `responseTimeMs` (the field every logger writes) instead of the never-written `latencyMs`; scenario 16 flipped to a regression check (`regression: true`) + inline-viewer unit tests.
- 2026-08-02 — "Input window text invisible: Edit field stays white against the dark background" — FIXED in c13d15c: the Edit control now gets its own `Background` option (it doesn't inherit `Gui.BackColor`), and the default design is light (white field + black text) to match the app theme; scenarios 24 + 25 flipped to regression checks (`regression: true`) + a rendered-pixel probe.
- 2026-08-02 — "System-prompt modal '0 chars' counter never updates" — FIXED in 6d81eaa: the chat right-rail system prompt modal now updates `#charCount` on input and when opened; scenario 17 flipped to a regression check (`regression: true`) + unit test.
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
- 2026-08-04 - "Commands lose their system prompt after a settings save: bare system-message filenames cannot be resolved by the command path" - FIXED in 6f7ae77: CommandMenu._resolveSystemMessage now searches default-settings/system-messages/ + AppData like the assistant path; scenario 50 flipped to a regression check (`regression: true`) + UserConfig AHK unit test.
- 2026-08-04 - "Opening Settings wipes the right-rail per-thread settings" - FIXED in f64a59d: main.js routes only the chat-sidebar partial `currentSettings` payload through `populateCurrentSettings`; the full merged settings object goes only to `SettingsPanel.onSettingsReceived` (discriminator: `Array.isArray(data.commands)`); scenario 26 flipped to a regression check (`regression: true`) + main.js routing unit test.
- 2026-08-04 - "System-message files referenced by their legacy `system-messages/` path are never resolved" - CLOSED as won't-fix (single-user, no migration): the path only exists in profiles saved before commit 0229368 moved the files into default-settings/; the user corrected their one profile manually. Scenario 59 removed (no regression check kept).
- 2026-08-04 - "Per-thread system prompt / temperature edits are discarded on reload when an assistant is active" - FIXED in a30ae19: `_restoreThreadSettings` now applies the assistant's system message / reasoning / temperature ONLY when the thread has no per-thread override for that field, so per-thread edits survive reloads and reach the API request; scenario 47 flipped to a regression check (`regression: true`) + ChatSettings AHK unit tests (overrides win; assistant defaults still apply when no override).
- 2026-08-04 - "Typing a system prompt directly into the right-rail field never reaches the API request (the field is display-only)" - FIXED in 50d4111: `#sysMsgMini` now has an input listener that updates `_currentSettings.systemMessage` and posts the debounced `updateModelSettings` (mirrors the modal Save path); scenario 60 flipped to a regression check (`regression: true`) + model-picker-config unit test.
- 2026-08-04 - "Commands Advanced card collapses when you click inside it to edit a field" - FIXED in b31a6b9: the Advanced toggle listener moved from the whole `.cmd-advanced-wrap` to the `.cmd-advanced-toggle` header, so clicks inside fields no longer collapse the card; scenario 27 flipped to a regression check (`regression: true`) + commands-advanced-toggle unit test.
