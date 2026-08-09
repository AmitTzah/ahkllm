// launch.js — Launch the real app (Main.ahk) in an isolated sandbox and
// expose its WebView2 pages over CDP. Zero dependencies.
'use strict';
const net = require('node:net');
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const { spawn, spawnSync } = require('node:child_process');

const AHK = process.env.AHK_EXE || 'C:\\Program Files\\AutoHotkey\\v2\\AutoHotkey64.exe';
const REPO_ROOT = path.resolve(__dirname, '..', '..');
const MAIN_AHK = path.join(REPO_ROOT, 'Main.ahk');
const PROBE_AHK = path.join(__dirname, 'probe.ahk');
// Unique WebView2 user-data folder for the current run. The app's WebView2
// defaults to the SHARED machine Edge folder (%LOCALAPPDATA%\Microsoft\Edge\
// User Data), so a leftover browser process from an aborted run holds it and
// the next launch fails with ERROR_BUSY (0x800700AA, "resource in use"). A
// per-run folder removes the collision entirely, and doubles as a safe marker
// for cleanup (only OUR msedgewebview2.exe processes carry it).
let activeWebView2Dir = '';
// The app resolves A_AppData via the Windows known-folder API, NOT the APPDATA
// env var, so env-based isolation cannot work. Instead we temporarily move the
// real profile aside and point it at a temp dir via a junction, restoring after.
const REAL_DATA_DIR = 'C:\\Users\\Amit\\AppData\\Roaming\\AhkLLM';

// Synchronous short sleep for teardown retries without spawning child processes.
function sleepSync(ms) {
  Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms);
}

// Remove every leftover llm-webview2-* folder (they are all ours, unique per
// run). The browser processes can hold files briefly after taskkill /F, so
// retry until nothing remains or the bounded attempt budget runs out.
function sweepWebView2Dirs(maxAttempts = 8) {
  let total = 0;
  for (let attempt = 0; attempt < maxAttempts; attempt++) {
    let removed = 0;
    try {
      for (const name of fs.readdirSync(os.tmpdir())) {
        if (!name.startsWith('llm-webview2-')) continue;
        try { fs.rmSync(path.join(os.tmpdir(), name), { recursive: true, force: true }); removed++; } catch {}
      }
    } catch {}
    if (removed === 0) break;
    total += removed;
    sleepSync(500);
  }
  return total;
}

function findFreePort() {
  return new Promise((resolve, reject) => {
    const srv = net.createServer();
    srv.listen(0, '127.0.0.1', () => {
      const port = srv.address().port;
      srv.close(() => resolve(port));
    });
    srv.on('error', reject);
  });
}

function makeSandbox() {
  return fs.mkdtempSync(path.join(os.tmpdir(), 'llm-headless-'));
}

function rmrf(dir) {
  try { fs.rmSync(dir, { recursive: true, force: true }); } catch {}
}

function isJunction(p) {
  try { return fs.lstatSync(p).isSymbolicLink(); } catch { return false; }
}

// Move the real profile aside and install a junction to a fresh temp dir.
// Recovers from a previously interrupted run (leftover junction + .bak).
function isolateProfile() {
  const tmp = os.tmpdir();
  // 1. Recover leftovers from an interrupted run.
  for (const name of fs.readdirSync(tmp)) {
    if (!name.startsWith('llm-profile-bak-')) continue;
    const bak = path.join(tmp, name);
    if (isJunction(REAL_DATA_DIR)) {
      try { fs.unlinkSync(REAL_DATA_DIR); } catch {}
    }
    if (!fs.existsSync(REAL_DATA_DIR) && fs.existsSync(bak)) {
      fs.mkdirSync(path.dirname(REAL_DATA_DIR), { recursive: true });
      fs.renameSync(bak, REAL_DATA_DIR);
    }
  }
  // 2. Move the real (non-junction) folder aside.
  let backupDir = '';
  if (fs.existsSync(REAL_DATA_DIR) && !isJunction(REAL_DATA_DIR)) {
    backupDir = path.join(tmp, 'llm-profile-bak-' + Date.now());
    fs.renameSync(REAL_DATA_DIR, backupDir);
  }
  // 3. Fresh data dir + junction.
  const sandboxData = path.join(tmp, 'llm-data-' + Date.now());
  fs.mkdirSync(sandboxData, { recursive: true });
  fs.mkdirSync(path.dirname(REAL_DATA_DIR), { recursive: true });
  const ps = spawnSync('powershell.exe', [
    '-NoProfile', '-Command',
    'New-Item -ItemType Junction -Path ' + JSON.stringify(REAL_DATA_DIR) +
    ' -Target ' + JSON.stringify(sandboxData) + ' | Out-Null'
  ], { timeout: 20000, windowsHide: true });
  if (!isJunction(REAL_DATA_DIR)) throw new Error('failed to create junction at ' + REAL_DATA_DIR);
  return { backupDir, sandboxData };
}

// Wipe the temp data dir so each scenario starts from a clean profile.
function resetDataDir(sandboxData) {
  fs.rmSync(sandboxData, { recursive: true, force: true });
  fs.mkdirSync(sandboxData, { recursive: true });
}

// Remove the junction and restore the real profile. A restore is only
// successful when the backup was actually moved back into place; the profile
// is NOT required to contain settings.json (a fresh or wiped profile has
// none until the first Settings save, and that is legitimate).
function restoreProfile(iso) {
  let ok = false;
  if (isJunction(REAL_DATA_DIR)) {
    try { fs.unlinkSync(REAL_DATA_DIR); } catch {}
  }
  if (iso.backupDir && fs.existsSync(iso.backupDir)) {
    if (!fs.existsSync(REAL_DATA_DIR)) {
      fs.mkdirSync(path.dirname(REAL_DATA_DIR), { recursive: true });
      fs.renameSync(iso.backupDir, REAL_DATA_DIR);
      ok = fs.existsSync(REAL_DATA_DIR);
    }
  }
  if (iso.sandboxData) rmrf(iso.sandboxData);
  return ok;
}

// Pre-flight: bail out if the real app is already running (#SingleInstance).
function preflight() {
  const res = spawnSync(AHK, [PROBE_AHK, 'preflight', path.join(os.tmpdir(), 'llm-preflight.json')], {
    timeout: 15000,
    windowsHide: true
  });
  if (res.error) throw new Error('preflight probe failed: ' + res.error.message);
  let out = {};
  try { out = JSON.parse(fs.readFileSync(path.join(os.tmpdir(), 'llm-preflight.json'), 'utf-8')); } catch {}
  return out.running || false;
}

// Launch the app with an isolated environment. Returns { mainPid, port, cdpBase }.
function launch({ sandbox, port }) {
  activeWebView2Dir = path.join(os.tmpdir(), 'llm-webview2-' + Date.now() + '-' + Math.random().toString(36).slice(2, 8));
  const env = Object.assign({}, process.env, {
    WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS: '--remote-debugging-port=' + port + ' --remote-allow-origins=*',
    WEBVIEW2_USER_DATA_FOLDER: activeWebView2Dir,
    DEEPSEEK_API_KEY: 'sk-headless-test',
    OPENAI_API_KEY: 'sk-headless-test',
    GEMINI_API_KEY: 'sk-headless-test'
  });
  const child = spawn(AHK, [MAIN_AHK], {
    env,
    cwd: REPO_ROOT,
    windowsHide: false, // the chat window must be visible to render
    detached: false
  });
  return { mainPid: child.pid, port };
}

async function listTargets(port) {
  const res = await fetch('http://127.0.0.1:' + port + '/json/list');
  if (!res.ok) throw new Error('CDP /json/list HTTP ' + res.status);
  return await res.json();
}

// Wait until the CDP endpoint reports the chat page (webui/index.html).
async function waitForChatTarget(port, timeoutMs = 30000) {
  const start = Date.now();
  for (;;) {
    try {
      const targets = await listTargets(port);
      const chat = targets.find((t) => t.type === 'page' && (t.url || '').includes('webui/index.html'));
      if (chat && chat.webSocketDebuggerUrl) return chat;
    } catch {}
    if (Date.now() - start > timeoutMs) throw new Error('waitForChatTarget timeout (port ' + port + ')');
    await new Promise((r) => setTimeout(r, 500));
  }
}

async function findTarget(port, urlPart, timeoutMs = 30000) {
  const start = Date.now();
  for (;;) {
    try {
      const targets = await listTargets(port);
      const t = targets.find((x) => x.type === 'page' && (x.url || '').includes(urlPart));
      if (t && t.webSocketDebuggerUrl) return t;
    } catch {}
    if (Date.now() - start > timeoutMs) return null;
    await new Promise((r) => setTimeout(r, 300));
  }
}

// Kill every leftover AhkLLM app process for THIS repo, matched by command line
// (never by name, so the user's own AHK scripts are untouched). Covers runs
// that crashed before a PID was captured, and WebView2 children whose process
// tree escaped the main kill.
function killRepoAppProcesses() {
  const ps = [
    '-NoProfile', '-Command',
    "$procs = Get-CimInstance Win32_Process | Where-Object { ($_.Name -eq 'AutoHotkey64.exe') -and ($_.CommandLine -match 'ahkllm') -and ($_.CommandLine -match 'Main\\.ahk|ChatWindow\\.ahk') }; foreach ($p in $procs) { taskkill.exe /PID $p.ProcessId /T /F 2>$null | Out-Null };",
    "$wv = Get-CimInstance Win32_Process | Where-Object { ($_.Name -eq 'msedgewebview2.exe') -and ($_.CommandLine -match 'llm-webview2') }; foreach ($p in $wv) { taskkill.exe /PID $p.ProcessId /T /F 2>$null | Out-Null }"
  ];
  spawnSync('powershell.exe', ps, { timeout: 25000, windowsHide: true });
}

// Kill every leftover node.exe running an offscreen video scene for THIS repo,
// matched by command line: any script under scripts/videos/ (both the absolute
// "...ahkllm\scripts\videos\foo.js" form and the relative "scripts/videos/foo.js"
// form the orphaned runs left behind - hero-offscreen, commands-chat-offscreen,
// branch-navigation-offscreen, diag-retry, ...). Never a blanket node kill, so
// the user's own node processes elsewhere are untouched. excludePid defaults to
// the caller, so a scene (or the runner) never kills itself. Covers the orphaned
// node processes from runs that hung: they kept their mock server / CDP socket
// alive and never exited (the offscreen-pipeline leak).
function killOffscreenNodeProcesses(excludePid = process.pid) {
  const ps = [
    '-NoProfile', '-Command',
    "$self = " + Number(excludePid) + "; $procs = Get-CimInstance Win32_Process | Where-Object { ($_.Name -eq 'node.exe') -and ($_.ProcessId -ne $self) -and ($_.CommandLine -match 'scripts[\\\\/]videos[\\\\/]') }; foreach ($p in $procs) { taskkill.exe /PID $p.ProcessId /T /F 2>$null | Out-Null }"
  ];
  spawnSync('powershell.exe', ps, { timeout: 25000, windowsHide: true });
}

// Count leftover offscreen node processes (diagnostics/verification).
function countOffscreenNodeProcesses(excludePid = process.pid) {
  const ps = spawnSync('powershell.exe', ['-NoProfile', '-Command',
    // @(...) is required: a bare (...).Count on a SINGLE result performs
    // member enumeration on the CIM object and returns empty.
    "$self = " + Number(excludePid) + "; @(Get-CimInstance Win32_Process | Where-Object { ($_.Name -eq 'node.exe') -and ($_.ProcessId -ne $self) -and ($_.CommandLine -match 'scripts[\\\\/]videos[\\\\/]') }).Count"
  ], { timeout: 25000, windowsHide: true, encoding: 'utf8' });
  return Number((ps.stdout || '').trim()) || 0;
}

// Remove every leftover temp dir the harness/scenes create: llm-webview2-*
// (per-run WebView2 user-data folders), llm-escape-* (E2E SQL-injection proof
// dirs), ahkllm-frames-* (offscreen capture frames). Stale llm-data-* profile
// sandboxes are removed too, but ONLY when the real profile is not currently
// isolated behind a junction (deleting an active sandbox would orphan the
// junction). Never touches the real AhkLLM profile or llm-profile-bak-*.
function sweepTempDirs() {
  let removed = 0;
  removed += sweepWebView2Dirs(8);
  const profileIsolated = isJunction(REAL_DATA_DIR);
  try {
    for (const name of fs.readdirSync(os.tmpdir())) {
      if (name.startsWith('llm-escape-') || name.startsWith('ahkllm-frames-')) {
        try { fs.rmSync(path.join(os.tmpdir(), name), { recursive: true, force: true }); removed++; } catch {}
      } else if (!profileIsolated && name.startsWith('llm-data-')) {
        try { fs.rmSync(path.join(os.tmpdir(), name), { recursive: true, force: true }); removed++; } catch {}
      }
    }
  } catch {}
  return removed;
}

// Self-healing sweep for the offscreen video pipeline: close leftover repo app
// processes (AHK + WebView2, command-line matched only), kill orphaned
// offscreen node processes, and clean our temp dirs. Safe by construction and
// idempotent; run at the start of every offscreen run.
function sweepOffscreenArtifacts() {
  const parts = [];
  const orphansBefore = countOffscreenNodeProcesses();
  killRepoAppProcesses();
  killOffscreenNodeProcesses();
  const removed = sweepTempDirs();
  const orphansAfter = countOffscreenNodeProcesses();
  if (orphansBefore > 0 && orphansAfter === 0)
    parts.push('killed ' + orphansBefore + ' orphaned offscreen node process(es)');
  if (removed > 0) parts.push('removed ' + removed + ' temp dir(s)');
  return parts.join('; ') || 'nothing to clean up';
}

// Kill the tree we spawned (Main + its ChatWindow + WebView2 children), then
// run the repo-scoped backstop so no orphan survives even when mainPid is
// unknown (e.g. a run that crashed before launch returned).
function teardown(mainPid) {
  if (mainPid) {
    // Graceful close FIRST: WinClose on the ChatWindow lets its OnExit handler
    // run and lets in-flight WebView2 operations settle. Force-killing first
    // raced those operations and popped modal AHK error dialogs
    // (0x800700AA "the requested resource is in use").
    try {
      spawnSync(AHK, [PROBE_AHK, 'kill-chat'], { windowsHide: true, timeout: 10000 });
    } catch {}
    try {
      spawnSync('powershell.exe', ['-NoProfile', '-Command', 'Start-Sleep -Milliseconds 800'], { windowsHide: true, timeout: 5000 });
    } catch {}
    try {
      spawnSync('taskkill', ['/PID', String(mainPid), '/T', '/F'], { windowsHide: true, timeout: 15000 });
    } catch {}
  }
  killRepoAppProcesses();
  // Remove our unique WebView2 user-data folder once the browser processes are
  // dead. taskkill /F returns before the browser processes have fully released
  // their file handles, so a single immediate rmSync routinely fails and leaves
  // the folder behind. Sweep every leftover llm-webview2-* folder (they are
  // all ours, unique per run) so a missed folder self-heals instead of
  // accumulating in temp. Bounded: ~4s worst case.
  sweepWebView2Dirs(8);
  activeWebView2Dir = '';
}

module.exports = { findFreePort, rmrf, preflight, launch, waitForChatTarget, findTarget, teardown, killRepoAppProcesses, killOffscreenNodeProcesses, countOffscreenNodeProcesses, sweepTempDirs, sweepOffscreenArtifacts, isolateProfile, resetDataDir, restoreProfile, sweepWebView2Dirs, AHK, PROBE_AHK, REPO_ROOT, listTargets };
