// launch.js — Launch the real app (Main.ahk) in an isolated sandbox and
// expose its WebView2 pages over CDP. Zero dependencies.
'use strict';
const net = require('node:net');
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const { spawn, spawnSync } = require('node:child_process');

const AHK = 'C:\\Program Files\\AutoHotkey\\v2\\AutoHotkey64.exe';
const REPO_ROOT = path.resolve(__dirname, '..', '..');
const MAIN_AHK = path.join(REPO_ROOT, 'Main.ahk');
const PROBE_AHK = path.join(__dirname, 'probe.ahk');
// The app resolves A_AppData via the Windows known-folder API, NOT the APPDATA
// env var, so env-based isolation cannot work. Instead we temporarily move the
// real profile aside and point it at a temp dir via a junction, restoring after.
const REAL_DATA_DIR = 'C:\\Users\\Amit\\AppData\\Roaming\\LLM-AutoHotkey-Assistant';

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

// Remove the junction and restore the real profile. Verifies settings.json.
function restoreProfile(iso) {
  let ok = false;
  if (isJunction(REAL_DATA_DIR)) {
    try { fs.unlinkSync(REAL_DATA_DIR); } catch {}
  }
  if (iso.backupDir && fs.existsSync(iso.backupDir)) {
    if (!fs.existsSync(REAL_DATA_DIR)) {
      fs.mkdirSync(path.dirname(REAL_DATA_DIR), { recursive: true });
      fs.renameSync(iso.backupDir, REAL_DATA_DIR);
      ok = fs.existsSync(path.join(REAL_DATA_DIR, 'settings.json'));
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
  const env = Object.assign({}, process.env, {
    WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS: '--remote-debugging-port=' + port + ' --remote-allow-origins=*',
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
async function waitForChatTarget(port, timeoutMs = 120000) {
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

// Kill only the process tree we spawned (Main + its ChatWindow + WebView2 children).
function teardown(mainPid) {
  if (!mainPid) return;
  try {
    spawnSync('taskkill', ['/PID', String(mainPid), '/T', '/F'], { windowsHide: true, timeout: 15000 });
  } catch {}
  // A stray ChatWindow orphan (if taskkill missed it) is closed by title.
  try {
    spawnSync(AHK, [PROBE_AHK, 'kill-chat'], { windowsHide: true, timeout: 10000 });
  } catch {}
}

module.exports = { findFreePort, rmrf, preflight, launch, waitForChatTarget, findTarget, teardown, isolateProfile, resetDataDir, restoreProfile, AHK, PROBE_AHK, REPO_ROOT, listTargets };
