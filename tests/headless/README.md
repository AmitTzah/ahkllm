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
node tests/headless/e2e-suite.js --all              # run every scenario
node tests/headless/e2e-suite.js --scenarios=1,6,15 # specific scenario ids
node tests/headless/e2e-suite.js --check-sync       # report <-> scenarios in sync?
node tests/headless/e2e-suite.js --cleanup          # close leftover app processes only
```

The app launches with the chat window positioned OFF-SCREEN, so nothing flashes on your
screen and no focus is stolen. It still needs elevated permissions (profile isolation +
WebView2 startup), so the sandbox will ask - that is expected (`--check-sync` needs no app
and no permission). Each run gets its own WebView2 user-data folder, so leftover browser
processes from aborted runs cannot block the next launch. Results go to
`tests/headless/results/headless-verification.txt` and stdout, one `PASS/FAIL` line per
scenario.

## Cleanup after an aborted run

`--cleanup` closes ONLY this repo's app processes (`Main.ahk`, `chat/ChatWindow.ahk` -
matched by process command line, which works even when the user started the app on their
own desktop that the sandbox cannot see, plus script-window title; killed by PID) plus the
harness's own WebView2 browser processes (matched by their unique `--user-data-dir=...llm-webview2-*`
marker - never other apps' WebView2), and removes leftover `llm-webview2-*` temp folders,
so a stale instance never blocks a run. It prints the PIDs it closed. **Never** run
`Stop-Process -Name AutoHotkey64 -Force` or `taskkill /IM AutoHotkey64.exe` to "clean
up" - the user runs their own AHK scripts on this machine and a blanket kill closes all
of them. If `--cleanup` reports `Closed 0` but the app profile is still locked, another
process (possibly a hung, windowless AHK script) holds it - do not kill AHK processes by
guesswork; ask the user to close their scripts.

The offscreen video pipeline (`scripts/videos/offscreen-pipeline.js`) has the same
guarantees built in: every scene runs under a hard per-scene watchdog plus
`unhandledRejection`/`uncaughtException` handlers, and one unified cleanup closes the CDP
socket, kills spawned encoders, force-closes the mock server, tears down the app, and
restores the real profile before an explicit `process.exit` - so a hung scene can never
leave an orphaned node process holding its port. At the start of each scene it runs
`launcher.sweepOffscreenArtifacts()`: kill orphaned `node.exe` processes matching this
repo's offscreen scenes (command-line matched, never a blanket node kill), close leftover
repo app/WebView2 processes, and remove `llm-escape-*`, `llm-webview2-*`,
`ahkllm-frames-*`, and stale `llm-data-*` temp dirs (never the real AhkLLM profile or
`llm-profile-bak-*`). Generated one-off scene scripts should be run through
`pipeline.runSceneFile()` (bounded child + backstop sweep + file deletion); fixed scenes
like `offscreen-demo.js` stay in `scripts/videos/`. `tests/headless/verify-cleanup.js`
verifies all of this (sweep, hung-scene reaping, teardown-with-unknown-PID).

Scenario ids are stable keys defined by the scenario objects in `scenarios/*.js`
(assembled into the run list by `e2e-suite.js`); each bug entry in
`BUG_HUNT_REPORT.md` lists the scenario that verifies it and a **Status** (reported →
verified → fix in progress → fix applied → awaiting user commit → removed). Keep the two
in sync — `--check-sync` enforces it.

**What is a scenario?** One automated reproduction of one bug. Each scenario is a
numbered object in `scenarios/*.js` that (1) seeds a fresh isolated app state, (2) launches
the real app, (3) connects to the real WebView2 UI, (4) performs the repro steps (clicks,
typing, saving, sending), and (5) asserts the expected outcome. **PASS = the buggy
behavior was reproduced** (the bug is real); **FAIL = it wasn't** (the error message says
which assertion failed). Run one with `--scenarios=<id>`.

Each bug entry in `BUG_HUNT_REPORT.md` carries a `**Scenario:** <id>` line — that id points
at the scenario *code* in `scenarios/*.js`; the report only references it (the Repro /
Evidence text in the entry is the human-readable description).

Scenario files are grouped by area (`chat-tree`, `commands`, `settings`,
`usage-tokens`, `chat-ui`, `misc`); see `scenarios/README.md` for the object shape and
how to add a scenario.

## How a developer uses this

Point an agent at this folder — `BUG_HUNT_REPORT.md` is the entry point:

- **"Fix bug #5"** (or any number) → the agent runs the fix cycle on that entry
  (it must be `verified`; an explicit choice overrides rank order).
- **"Add more bugs to the bug hunt"** → the agent runs intake for each suspected bug:
  write the entry (`reported`) → add a scenario → run it → `verified` + ranked → `--check-sync`.
- **"Verify this: \<repro steps\>"** → the agent writes the entry, adds a scenario, verifies.
- **"Continue"** → the agent resumes from "Where we left off" + the entries' Statuses.
- **"Re-verify everything"** → run `node tests/headless/e2e-suite.js --all` and update
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

1. Moves the real profile (`%APPDATA%\AhkLLM`) aside to
   `%TEMP%\llm-profile-bak-<ts>`.
2. Creates a **junction** at the real path pointing to a temp data dir
   (`%TEMP%\llm-data-<ts>`).
3. Runs the app against the temp dir (each scenario resets and re-seeds it).
4. Removes the junction and renames the backup back, verifying `settings.json` exists
   (the run prints "Real profile restored: yes").

If a run is interrupted, the real profile is safe in the `.bak` folder. Ctrl+C /
SIGTERM triggers an in-process cleanup that restores it immediately; a hard kill
(taskkill /F, IDE stop) leaves it isolated until you run `--cleanup`, which now
detects the interrupted state and restores the profile (verifying `settings.json`
before moving anything) before sweeping leftover WebView2/profile-sandbox folders.
The next scenario run also auto-recovers as a fallback.

## Architecture

| File | Purpose |
|---|---|
| `cdp.js` | Minimal CDP client (fetch + built-in WebSocket): evaluate, click, type, waitFor, postMessage hook |
  | `mock-llm-server.js` | Local fake LLM (SSE / JSON / title / error / scripted / mid-fail / slow modes) so send/stream/title-gen paths are deterministic |
| `seed.js` | Writes `settings.json` and creates/seeds the SQLite DB (schema mirrors `chat/db/ChatDB.ahk`; message fixtures support `prompt_tokens` alongside the other token fields) |
| `launch.js` | Profile isolation (junction), app launch with WebView2 remote-debugging args, CDP discovery, teardown |
  | `probe.ahk` | Win32 checks the browser can't see: window titles, icons via `WM_GETICON` + pixel fingerprint, hotkey presses, suspend banner, input window |
  | `probe-thinking.ahk` | Standalone AHK check used by one scenario (see report) |
  | `probe-utf8.ahk` | Standalone AHK check for `_readFileChunk`'s UTF-8-RAW byte-seek semantics (multibyte poll-split corruption, scenario 160) |
  | `probe-bughunt-db.ahk` | Standalone AHK check that runs the REAL ChatDB/repo code against a temp SQLite DB and prints token-accounting / tree-copy results (used by the DB-audit scenarios; see report) |
| `e2e-suite.js` | Scenario runner: CLI, profile isolation, CDP wiring, cleanup/recovery |
| `scenarios/*.js` | Scenario definitions, grouped by area (the files to extend) |
| `scenarios/helpers.js` | Shared helpers used by scenario bodies (probes, UI navigation) |
| `verify-cleanup.js` | Offscreen-pipeline leak verification: self-healing sweep, hung-scene watchdog reaping, teardown with unknown PID |
| `capture-screenshots.js` | Generates README screenshots: runs the real app off-screen, captures WebView2 pages via CDP `Page.captureScreenshot` |
| `BUG_HUNT_REPORT.md` | Live bug list + agent workflow (start here) |

## Capturing screenshots

`capture-screenshots.js` reuses the launch/seed/CDP machinery to render the real app
with an isolated profile and save PNGs of the chat window, tree view, usage dashboard,
and Settings Providers tab to `docs/screenshots/`. It is useful both for the README and
for vision-capable agents that need a fresh look at the UI. The same preflight rule
applies as for scenarios: the app must not already be running. The real profile is
restored on exit.

```powershell
node tests/headless/capture-screenshots.js
```

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
7. Keyboard injection is inherently unreliable here AND can leak keystrokes into whatever
   the user is typing on the interactive desktop. For that reason NO scenario injects
   keys: the hotkey-dependent checks (#4, #9, #12, #13, #24, #25) were converted to
   static/unit checks. The key-sending probe commands (`menu-open`, `open-input`,
   `send-menu-usage`, `suspend-banner`, ...) remain for MANUAL debugging only.

## Limitations

- Purely visual bugs (tray icon/menu appearance) are not automated — a human verifies them.
- AHK `#Persistent` does not exist in v2 (scripts with hotkeys stay alive automatically).

## Interrupted runs

Results are written **per scenario** (plus a run header and a final summary), so a run
that is killed mid-flight still leaves a partial record showing exactly how far it got.
If a run dies with no summary, the most likely cause is another process or agent running
a **blanket** `AutoHotkey64.exe`/`node` cleanup (this harness only ever closes this
repo's own `Main.ahk`/`ChatWindow.ahk` by command line, never unrelated AHK scripts).
Recover with `node tests/headless/e2e-suite.js --cleanup`, which also restores an
isolated profile even when the backup has no `settings.json`.
