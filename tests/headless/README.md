# Headless Bug-Verification Harness

Verifies GUI bugs in this app by **executing the real repro steps against the running
application** and asserting on live state — not by looking at pixels. It launches
`Main.ahk` (the real AutoHotkey app), drives its embedded WebView2 chat UI over Chrome
DevTools Protocol (CDP), and checks Win32-level behavior with small AHK probes. No
screenshots, no physical mouse/keyboard, no `npm install` (Node 24 built-ins only).

> **The bug workflow lives in `BUG_HUNT_REPORT.md` in this folder.** This file is the
> harness manual; that file is the live bug list + step-by-step agent workflow. Start
> there when you want to verify, fix, or add bugs.

## Quick start

Requirements: an interactive Windows session, AutoHotkey v2
(`C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe`), WebView2 runtime, Node 24+.

The app must **not already be running** (it is `#SingleInstance`; the harness aborts if so).

```powershell
node tests/headless/verify-bugs.js --all              # run every scenario
node tests/headless/verify-bugs.js --scenarios=1,6,15 # specific scenario ids
node tests/headless/verify-bugs.js --check-sync       # report <-> scenarios in sync?
```

Launching the app is a GUI operation, so the sandbox will ask for elevated permissions —
that is expected (`--check-sync` needs no app and no permission). Results go to
`tests/headless/results/headless-verification.txt` and stdout, one `PASS/FAIL` line per
scenario.

Scenario ids are stable keys defined in `verify-bugs.js`; each bug entry in
`BUG_HUNT_REPORT.md` lists the scenario that verifies it and a **Status** (reported →
verified → fix in progress → fix applied → awaiting user commit → removed). Keep the two
in sync — `--check-sync` enforces it.

**What is a scenario?** One automated reproduction of one bug. Each scenario is a
numbered block in `verify-bugs.js` that (1) seeds a fresh isolated app state, (2) launches
the real app, (3) connects to the real WebView2 UI, (4) performs the repro steps (clicks,
typing, saving, sending), and (5) asserts the expected outcome. **PASS = the buggy
behavior was reproduced** (the bug is real); **FAIL = it wasn't** (the error message says
which assertion failed). Run one with `--scenarios=<id>`.

Each bug entry in `BUG_HUNT_REPORT.md` carries a `**Scenario:** <id>` line — that id points
at the scenario *code* in `verify-bugs.js`; the report only references it (the Repro /
Evidence text in the entry is the human-readable description).

## How a developer uses this

Point an agent at this folder — `BUG_HUNT_REPORT.md` is the entry point:

- **"Fix bug #5"** (or any number) → the agent runs the fix cycle on that entry
  (it must be `verified`; an explicit choice overrides rank order).
- **"Add more bugs to the bug hunt"** → the agent runs intake for each suspected bug:
  write the entry (`reported`) → add a scenario → run it → `verified` + ranked → `--check-sync`.
- **"Verify this: \<repro steps\>"** → the agent writes the entry, adds a scenario, verifies.
- **"Continue"** → the agent resumes from "Where we left off" + the entries' Statuses.
- **"Re-verify everything"** → run `node tests/headless/verify-bugs.js --all` and update
  the entries' Statuses.
- **"What's open?"** → read "Current state" / the open-bug list.

The results file (`results/headless-verification.txt`) is regenerated on every run; the
report is the authoritative source for bug status.

## Verifying a fix with git stash (optional)

While a fix is uncommitted (entry status `fix applied`), you can temporarily put it aside
to confirm the bug was real before you commit:

```powershell
git stash                     # remove the fix from the working tree
# run the repro (or the scenario): the buggy behavior should come back
git stash pop                 # restore the fix
# run the repro again: the fixed behavior should be back
```

This works best when the fix is the only thing in the working tree. If you have unrelated
uncommitted changes you want to keep visible, stash just the fix files instead:

```powershell
git stash push -- chat/ app/ webui/   # adjust paths to the fix's files
git stash pop
```

**Gotcha:** a flipped scenario (asserting the *fixed* behavior) will FAIL while the fix is
stashed — that failure is the "bug reproduced" signal, not a broken harness. After `pop`,
the same scenario should PASS again. If `pop` reports a conflict, resolve it and re-run the
scenario; never commit from a stashed state.

## Safety: the real profile is never touched

AHK's `A_AppData` comes from the Windows known-folder API, **not** the `APPDATA` env var,
so env-based isolation does not work. Instead the harness:

1. Moves the real profile (`%APPDATA%\LLM-AutoHotkey-Assistant`) aside to
   `%TEMP%\llm-profile-bak-<ts>`.
2. Creates a **junction** at the real path pointing to a temp data dir
   (`%TEMP%\llm-data-<ts>`).
3. Runs the app against the temp dir (each scenario resets and re-seeds it).
4. Removes the junction and renames the backup back, verifying `settings.json` exists
   (the run prints "Real profile restored: yes").

If a run is interrupted, the real profile is safe in the `.bak` folder; the next run
auto-recovers. Manual recovery: delete the junction at the real path and rename the
`.bak` folder back.

## Architecture

| File | Purpose |
|---|---|
| `cdp.js` | Minimal CDP client (fetch + built-in WebSocket): evaluate, click, type, waitFor, postMessage hook |
| `mock-llm-server.js` | Local fake LLM (SSE / JSON / title / error modes) so send/stream/title-gen paths are deterministic |
| `seed.js` | Writes `settings.json` and creates/seeds the SQLite DB (schema mirrors `chat/db/ChatDB.ahk`) |
| `launch.js` | Profile isolation (junction), app launch with WebView2 remote-debugging args, CDP discovery, teardown |
| `probe.ahk` | Win32 checks the browser can't see: window titles, icons via `WM_GETICON` + pixel fingerprint, hotkey presses, suspend banner, input window |
| `probe-thinking.ahk` | Standalone AHK check used by one scenario (see report) |
| `verify-bugs.js` | Scenario runner + all scenarios (the file to extend) |
| `BUG_HUNT_REPORT.md` | Live bug list + agent workflow (start here) |

## Adding a scenario (template)

```js
scenarios.push({
  id: 99,                                   // unique id
  name: 'Short description of the bug',
  mode: 'sse-success',                      // mock LLM mode, or null for refused-port/refused API
  settings: { /* settings.json overrides (merged over defaults) */ },
  fixtures: {                               // SQLite seeds (threads, messages, folders, chatUsage)
    threads: [], messages: []
  },
  preLaunch(dataDir) { },                   // optional: patch settings.json before launch
  noApp: false,                             // true if the scenario needs no app launch
  async body({ cdp, dataDir, dbPath, port, endpoint, mockLog }) {
    // Act through the real UI: cdp.click/type/waitFor/eval, runProbe('...')
    // Throw Error(...) on failure; return a short evidence string on success.
  }
});
```

Helpers available in scenarios: `openSettings`, `openSection`, `saveSettings(cdp, dataDir)`,
`hideSettingsToChat`, `sendChatMessage`, `waitStreamingIdle`, `runProbe(command, args)`,
`readJsonFile`, `seed.query(dbPath, sql, params)`. A postMessage hook (`window.__posted`)
captures every JS→AHK message for assertions.

A scenario asserts the **buggy** behavior, so it PASSES while the bug exists and FAILS once
the bug is fixed. When fixing a bug, flip the assertion to expect the fixed behavior.

## Writing AHK probes — environment quirks (read before writing any `.ahk`)

These cost the original author many hours — do not repeat them:

1. **Referencing the built-in `ErrorLevel` anywhere in a standalone AHK script makes
   AutoHotkey64.exe hang silently at load** (no output, even with `/ErrorStdOut`, before
   the first line runs). Use the *return value* of `SendMessage(...)` instead of
   `ErrorLevel`.
2. **Any unresolved identifier (undefined function or global) inside a function body has
   the same effect** — it hangs the script at load. When including an app module
   standalone, define stub globals/functions for every identifier its function bodies
   reference (see `probe-thinking.ahk` for the pattern).
3. The app writes `settings.json` with a UTF-8 **BOM** — strip it before `JSON.parse`
   (the runner's `readJsonFile` does this). Probe output files also carry a BOM —
   `parseProbeOutput` strips it.
4. AHK v2 GUI windows have class **`AutoHotkeyGUI`**, not `AutoHotkey` (which is the
   hidden script window). Any window lookup must use the right class.
5. Every probe script must have `#ErrorStdOut`, a watchdog `SetTimer`, an `OnError`
   handler, and `ExitApp` at the end. Invoke probes with `spawnSync(..., { timeout })`
   so nothing can hang the run.
6. **Direct-spawned `cURL.exe` cannot receive responses from a local Node mock in this
   session** (upload completes, 0 bytes back — even for SSE). Streaming works because the
   app's cURL command contains a `2>` redirection, which makes AHK `Run` go through cmd.
   Non-stream requests (title-gen, inline commands) are therefore not end-to-end
   automatable here — verify those statically or with unit tests.
7. Injected keyboard input sometimes does not reach AHK hotkeys in this session.
   Hotkey-dependent live checks use the app context where proven reliable; otherwise fall
   back to static/unit evidence and note the limitation in the report entry.

## Limitations

- Purely visual bugs (tray icon/menu appearance) are not automated — a human verifies them.
- AHK `#Persistent` does not exist in v2 (scripts with hotkeys stay alive automatically).
