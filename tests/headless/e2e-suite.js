// e2e-suite.js - Growing headless E2E suite for AhkLLM.
//
// Usage:
//   node e2e-suite.js --all               # every scenario against the real app
//   node e2e-suite.js --scenarios=1,6,15  # specific scenarios
//   node e2e-suite.js --pilot             # quick smoke (1, 3, 6, 15, 22)
//   node e2e-suite.js --check-sync        # report <-> scenarios in sync?
//   node e2e-suite.js --cleanup           # close leftover app processes, restore
//                                        # an isolated profile, sweep temp folders
//
// Scenario definitions live in scenarios/*.js (grouped by area); shared helpers
// live in scenarios/helpers.js. Each scenario launches the real app
// (Main.ahk -> ChatWindow -> WebView2) against an isolated profile and drives
// it over CDP, so every scenario is a genuine end-to-end check. Scenarios
// marked `regression: true` guard fixed bugs and accumulate as the suite grows.
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const { CDP } = require('./cdp');
const { startMockServer } = require('./mock-llm-server');
const seed = require('./seed');
const launcher = require('./launch');
const { runProbe, sleep } = require('./scenarios/helpers');

const RESULTS_DIR = path.join(__dirname, 'results');
const RESULTS_FILE = path.join(RESULTS_DIR, 'headless-verification.txt');
let diagShown = false;

async function closeMockServer(handle) {
  const srv = handle && handle.server;
  if (!srv)
    return;
  try {
    if (typeof srv.closeAllConnections === 'function')
      srv.closeAllConnections();
  } catch {}
  if (!srv.listening)
    return;
  await new Promise((resolve) => {
    try { srv.close(() => resolve()); }
    catch { resolve(); }
  });
}

// ---------- Scenario infrastructure ----------

async function runScenario(sc, iso, opts) {
  let server = null;
  let mainPid = 0;
  let cdp = null;
  let target = null;
  let noApp = !!sc.noApp;
  let mockLog = '';
  // For non-mock scenarios use a just-freed port so cURL fails with
  // "connection refused" BEFORE any output file exists (bug #6 path).
  const refusePort = await launcher.findFreePort();
  let endpoint = 'http://127.0.0.1:' + refusePort + '/v1/chat/completions';
  const detail = { step: 'setup' };
  try {
    if (sc.mode) {
      mockLog = path.join(iso.sandboxData, 'mock-requests.jsonl');
      server = await startMockServer(sc.mode, mockLog, sc.mockOpts || {});
      endpoint = 'http://127.0.0.1:' + server.port + '/v1/chat/completions';
    }
    if (!noApp) launcher.resetDataDir(iso.sandboxData);
    const dataDir = noApp ? null : iso.sandboxData;
    if (!noApp) seed.writeSettings(dataDir, sc.settings || {}, endpoint);
    if (!noApp && sc.preLaunch) sc.preLaunch(dataDir, endpoint);
    const dbPath = (!noApp && sc.fixtures) ? seed.createDb(dataDir, sc.fixtures) : (!noApp ? path.join(dataDir, 'chat_history.db') : null);
    detail.dbPath = dbPath;

    const port = await launcher.findFreePort();
    if (!noApp) {
      const launched = launcher.launch({ sandbox: iso.sandboxData, port });
      mainPid = launched.mainPid;
      detail.port = port;
      target = await launcher.waitForChatTarget(port);
      cdp = await CDP.connect(target.webSocketDebuggerUrl);
      await cdp.installPostMessageHook();
      await cdp.waitFor('document.readyState === "complete" && typeof chatMessages !== "undefined"', 60000, 400, 'chat page ready');
      // AHK wires the send button (onclick) after webViewReady — wait for it so
      // clicks/typing work on the very first interaction.
      await cdp.waitFor('document.getElementById("chat-send-btn") && document.getElementById("chat-send-btn").onclick !== null', 30000, 300, 'send button wired');
      await sleep(500);
      if (!diagShown) {
        diagShown = true;
        try {
          const info = runProbe('chat-info');
          console.log('window diag (live): ' + JSON.stringify(info));
        } catch {}
      }
    }

    const result = await sc.body({ cdp, dataDir, dbPath, port, endpoint, mockLog });
    if (cdp) await cdp.close();
    return { id: sc.id, name: sc.name, pass: true, detail: result, pid: mainPid };
  } catch (e) {
    if (cdp) try { await cdp.close(); } catch {}
    return { id: sc.id, name: sc.name, pass: false, detail: detail.step + ' -> ' + (e && e.message ? e.message : String(e)), dataDir: iso.sandboxData, pid: mainPid };
  } finally {
    if (mainPid) launcher.teardown(mainPid);
    if (server) await closeMockServer(server);
  }
}

// ---------- Scenarios ----------
// Definitions live in scenarios/*.js, grouped by area. Each file exports an
// array of scenario objects; they are flattened here and run in id order so
// results and the report stay stable.
const scenarios = [].concat(
  require('./scenarios/chat-tree'),
  require('./scenarios/commands'),
  require('./scenarios/settings'),
  require('./scenarios/usage-tokens'),
  require('./scenarios/chat-ui'),
  require('./scenarios/search-tools'),
  require('./scenarios/misc'),
  require('./scenarios/chat-locks'),
  require('./scenarios/db-verify')
).sort((a, b) => a.id - b.id);
// ---------- Runner ----------

function parseArgs() {
  const argv = process.argv.slice(2);
  if (argv.includes('--pilot')) return [1, 3, 6, 15, 22];
  if (argv.includes('--all')) return scenarios.map((s) => s.id);
  const sc = argv.find((a) => a.startsWith('--scenarios='));
  if (sc) return sc.split('=')[1].split(',').map((n) => parseInt(n, 10));
  return [1, 3, 6, 15, 22]; // default pilot
}

// Cross-check BUG_HUNT_REPORT.md against the scenario list so neither goes stale.
function checkReportSync() {
  const reportFile = path.join(__dirname, 'BUG_HUNT_REPORT.md');
  if (!fs.existsSync(reportFile)) {
    console.error('Sync FAIL: BUG_HUNT_REPORT.md not found next to e2e-suite.js');
    return false;
  }
  const text = fs.readFileSync(reportFile, 'utf8');
  const start = text.indexOf('## Open bugs');
  const end = Math.min(
    ...['## History', '## Refuted', '## Fixed']
      .map((h) => text.indexOf(h))
      .filter((i) => i > start)
  );
  const section = (start >= 0 && end > start) ? text.slice(start, end) : text;
  const reportIds = new Set();
  for (const m of section.matchAll(/\*\*Scenario:\*\*\s*(\d+)/g)) reportIds.add(parseInt(m[1], 10));
  const known = new Set(scenarios.map((s) => s.id));
  const missing = [...reportIds].filter((id) => !known.has(id));
  const unlisted = scenarios.filter((s) => !reportIds.has(s.id) && !s.regression).map((s) => s.id);
  const dupes = [...new Set(scenarios.map((s) => s.id).filter((id, i, arr) => arr.indexOf(id) !== i))];
  let ok = true;
  if (missing.length) {
    console.error('Sync FAIL: report references scenarios that do not exist in scenarios/*.js: ' + missing.join(', '));
    ok = false;
  }
  if (unlisted.length) {
    console.error('Sync FAIL: scenarios with no report entry (add an entry or mark regression: true): ' + unlisted.join(', '));
    ok = false;
  }
  if (dupes.length) {
    console.error('Sync FAIL: duplicate scenario ids in scenarios/*.js: ' + dupes.join(', '));
    ok = false;
  }
  if (ok) {
    const reg = scenarios.filter((s) => s.regression).length;
    console.log('Sync OK: ' + reportIds.size + ' open-bug entries, ' + scenarios.length + ' scenarios (' + reg + ' regression/refuted checks)');
  }
  return ok;
}

// Recover from a run that was killed mid-execution (Ctrl+C, taskkill /F, IDE
// stop, crash): close leftover repo app processes, restore the real profile
// if it is still isolated behind a junction, and sweep leftover temp folders.
// Safe by construction: only this repo's app processes (matched by command
// line) are closed, only llm-* temp folders we created are removed, and the
// profile is only moved back when the backup contains settings.json.
function recoverInterruptedRun() {
  const realProfile = path.join(process.env.APPDATA || '', 'AhkLLM');
  const parts = [];
  // 1. Close leftover repo app processes (command-line matched only; never a
  //    blanket AutoHotkey64.exe kill — the user runs their own scripts).
  let out;
  try { out = runProbe('kill-app'); } catch { out = { closed: 0, pids: '' }; }
  if (out.closed) parts.push('closed ' + out.closed + ' app process(es)' + (out.pids ? ' (' + out.pids + ')' : ''));
  // 2. Restore a real profile that is still isolated (junction -> temp sandbox)
  //    with its backup still in temp. fs.unlinkSync on a junction removes only
  //    the link, never the target. The backup does not need a settings.json:
  //    a wiped/fresh profile legitimately has none until the first Settings
  //    save, and requiring it left real profiles "restored: NO" forever.
  let backups = [];
  try { backups = fs.readdirSync(os.tmpdir()).filter((n) => n.startsWith('llm-profile-bak-')).sort(); } catch {}
  const bak = backups.length ? path.join(os.tmpdir(), backups[backups.length - 1]) : '';
  let profileIsJunction = false;
  try { profileIsJunction = fs.lstatSync(realProfile).isSymbolicLink(); } catch {}
  if (profileIsJunction && bak && fs.existsSync(bak)) {
    try {
      fs.unlinkSync(realProfile);
      fs.renameSync(bak, realProfile);
      profileIsJunction = false;
      parts.push('restored isolated real profile');
    } catch (e) {
      parts.push('profile restore FAILED: ' + e.message + ' (run --cleanup again or check manually)');
    }
  } else if (!profileIsJunction && bak && !fs.existsSync(realProfile) && fs.existsSync(bak)) {
    try {
      fs.renameSync(bak, realProfile);
      parts.push('restored real profile from backup');
    } catch (e) {
      parts.push('profile restore FAILED: ' + e.message);
    }
  }
  // 3. Sweep leftover per-run WebView2 user-data folders (ours by name),
  //    retrying until they are gone (browser processes release files late).
  const webView2Before = fs.readdirSync(os.tmpdir()).filter((n) => n.startsWith('llm-webview2-')).length;
  launcher.sweepWebView2Dirs(10);
  const removedWebView2Dirs = webView2Before - fs.readdirSync(os.tmpdir()).filter((n) => n.startsWith('llm-webview2-')).length;
  if (removedWebView2Dirs > 0) parts.push('removed ' + removedWebView2Dirs + ' WebView2 data folder(s)');
  // 4. Sweep stale profile sandboxes once the real profile is no longer
  //    isolated (deleting an active sandbox would orphan the junction).
  let removedDataDirs = 0;
  try { profileIsJunction = fs.lstatSync(realProfile).isSymbolicLink(); } catch { profileIsJunction = false; }
  if (!profileIsJunction) {
    try {
      for (const name of fs.readdirSync(os.tmpdir())) {
        if (!name.startsWith('llm-data-')) continue;
        try { fs.rmSync(path.join(os.tmpdir(), name), { recursive: true, force: true }); removedDataDirs++; } catch {}
      }
    } catch {}
  }
  if (removedDataDirs) parts.push('removed ' + removedDataDirs + ' stale profile sandbox(es)');
  if (profileIsJunction) parts.push('real profile still isolated (left for next-run recovery)');
  return parts.join('; ') || 'nothing to clean up';
}

async function main() {
  fs.mkdirSync(RESULTS_DIR, { recursive: true });
  const ids = parseArgs();
  if (process.argv.includes('--check-sync')) {
    process.exit(checkReportSync() ? 0 : 1);
  }
  if (process.argv.includes('--cleanup')) {
    console.log(recoverInterruptedRun() + '. Other AutoHotkey scripts were not touched.');
    process.exit(0);
  }
  const selected = scenarios.filter((s) => ids.includes(s.id));
  if (selected.length !== ids.length) {
    console.error('Unknown scenario ids: ' + ids.filter((i) => !scenarios.some((s) => s.id === i)).join(','));
    process.exit(2);
  }
  if (launcher.preflight()) {
    console.error('ABORT: the app (Main.ahk/ChatWindow.ahk) appears to be running already (#SingleInstance). Close it and re-run, or if it is a leftover from an aborted run: node tests/headless/e2e-suite.js --cleanup');
    process.exit(3);
  }
  console.log('Isolating the real profile (junction redirect)...');
  // If the harness is stopped mid-run (Ctrl+C / SIGTERM), restore the profile
  // and close spawned processes instead of leaving the app isolated.
  let interrupted = false;
  const onInterrupt = (signal) => {
    if (interrupted) process.exit(130); // second interrupt forces exit
    interrupted = true;
    try { fs.appendFileSync(RESULTS_FILE, 'RUN INTERRUPTED (' + signal + ') - partial record above.\n', 'utf-8'); } catch {}
    console.error('\n[' + signal + '] stopping headless run — cleaning up...');
    try { console.error(recoverInterruptedRun()); } catch (e) { console.error('cleanup error: ' + e.message); }
    process.exit(130);
  };
  process.on('SIGINT', onInterrupt);
  process.on('SIGTERM', onInterrupt);
  const lines = [];
  let passCount = 0;
  let iso = null;
  let restored = 'not attempted';
  try {
    iso = launcher.isolateProfile();
    console.log('Launching headless verification for ' + selected.length + ' scenarios...');
    // Fresh record per run; each scenario appends immediately so an externally
    // killed run (e.g. another process blanket-killing AHK/node) still leaves a
    // diagnosable partial record instead of silently discarding progress.
    fs.writeFileSync(RESULTS_FILE, '# ' + new Date().toISOString() + ' | run of ' + selected.length + ' scenario(s)\n', 'utf-8');
    for (const sc of selected) {
      const started = Date.now();
      const r = await runScenario(sc, iso, {});
      if (r.dataDir) {
        const dataDirLine = '  (data dir for inspection: ' + r.dataDir + ')';
        lines.push(dataDirLine);
        fs.appendFileSync(RESULTS_FILE, dataDirLine + '\n', 'utf-8');
      }
      const secs = ((Date.now() - started) / 1000).toFixed(1);
      const tag = r.pass ? 'PASS' : 'FAIL';
      if (r.pass) passCount++;
      const line = tag + ' | #' + String(r.id).padStart(2, '0') + ' | ' + r.name + ' | ' + r.detail + (r.pass ? '' : '');
      console.log(line);
      lines.push(line + ' | ' + secs + 's');
      fs.appendFileSync(RESULTS_FILE, line + ' | ' + secs + 's\n', 'utf-8');
    }
  } catch (e) {
    console.error('Runner error:', e);
    if (/EPERM|isolat/i.test(String(e && e.message))) {
    console.error('Hint: the profile could not be moved. Two common causes: (1) the app is running or left over and holds the profile -- run `node tests/headless/e2e-suite.js --cleanup` (closes ONLY this repo\'s Main.ahk / chat/ChatWindow.ahk by command line + window title, never other AHK scripts); (2) the runner lacks permission to move the real profile (sandbox) -- re-run with elevated permissions, since launching the app and isolating the profile need the user\'s rights. If cleanup reports "Closed 0" and the profile is still blocked, ask the user before killing any AutoHotkey64.exe.');
    }
    lines.push('RUNNER ERROR: ' + (e && e.message ? e.message : String(e)));
  } finally {
    // runScenario already tears down each scenario's app. Do one repo-scoped
    // backstop sweep here; repeating teardown once per historical PID made a
    // full run spend minutes re-running PowerShell/taskkill for dead apps.
    launcher.teardown(0);
    if (iso) restored = launcher.restoreProfile(iso) ? 'yes' : 'NO — CHECK MANUALLY';
    // Final bounded sweep: a completed run must not leave WebView2 folders
    // behind, even if the last scenario's browser processes released their
    // files only after its teardown retry window.
    launcher.sweepWebView2Dirs(20);
  }
  // Final summary goes to BOTH the results file and the console; on failure
  // it names the failed scenarios so a long run is scannable at a glance.
  const failedScenarios = lines.filter((l) => l.startsWith('FAIL | ')).map((l) => l.split('|')[1].trim());
  const summary = 'Summary: ' + passCount + '/' + selected.length + ' scenarios PASS' +
    (failedScenarios.length ? ' — FAILED: ' + failedScenarios.join(', ') : '');
  const syncOk = checkReportSync();
  const syncLine = syncOk ? 'OK' : 'MISMATCH — update BUG_HUNT_REPORT.md or scenarios/*.js';
  fs.appendFileSync(RESULTS_FILE, '\n' + summary + '\nReal profile restored: ' + restored + '\nReport sync: ' + syncLine + '\n', 'utf-8');
  console.log('\n' + summary);
  console.log('Results written to ' + RESULTS_FILE);
  console.log('Real profile restored: ' + restored);
  console.log('Report sync: ' + syncLine);
  process.exit(passCount === selected.length ? 0 : 1);
}

main().catch((e) => {
  console.error('Runner error:', e);
  process.exit(2);
});
