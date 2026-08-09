// Verification: the offscreen video pipeline must NEVER leak processes,
// listeners, temp dirs, or an isolated profile. Covers:
//   1. the self-healing sweep (orphaned offscreen node processes + temp dirs),
//   2. a HUNG offscreen scene: the per-scene watchdog must clean up, restore
//      the profile, and hard-exit; afterwards zero orphans/listeners/dirs,
//   3. teardown(0) still closes repo app processes when the PID is unknown.
// Run (interactive session, elevated): node tests/headless/verify-cleanup.js
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const { spawn, spawnSync } = require('node:child_process');
const launcher = require('./launch');
const { seedData } = require('./capture-screenshots');
const pipeline = require('../../scripts/videos/offscreen-pipeline');

const VIDEOS_DIR = path.join(launcher.REPO_ROOT, 'scripts', 'videos');
const REAL_DATA_DIR = path.join(process.env.APPDATA || '', 'AhkLLM');
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
let failures = 0;

function ok(msg) { console.log('PASS: ' + msg); }
function check(cond, msg) {
  if (cond) ok(msg);
  else { failures++; console.error('FAIL: ' + msg); }
}

function countRepoProcesses() {
  const ps = spawnSync('powershell.exe', ['-NoProfile', '-Command',
    // @(...) required: a bare (...).Count on a single result is empty.
    "@(Get-CimInstance Win32_Process | Where-Object { ($_.Name -eq 'AutoHotkey64.exe') -and ($_.CommandLine -match 'ahkllm') -and ($_.CommandLine -match 'Main\\.ahk|ChatWindow\\.ahk') }).Count"
  ], { encoding: 'utf8' });
  return Number((ps.stdout || '').trim()) || 0;
}

function countOffscreenNode() {
  return launcher.countOffscreenNodeProcesses();
}

// Count offscreen node processes that own a LISTENING localhost TCP endpoint
// (the "still listening on a localhost port" symptom from the leak).
function countOffscreenListeners() {
  const ps = spawnSync('powershell.exe', ['-NoProfile', '-Command',
    "$self = " + process.pid + "; " +
    "$pids = @(Get-CimInstance Win32_Process | Where-Object { ($_.Name -eq 'node.exe') -and ($_.ProcessId -ne $self) -and ($_.CommandLine -match 'scripts[\\\\/]videos[\\\\/]') } | ForEach-Object { $_.ProcessId }); " +
    "if ($pids.Count -eq 0) { 0 } else { @(Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue | Where-Object { $pids -contains $_.OwningProcess }).Count }"
  ], { encoding: 'utf8' });
  return Number((ps.stdout || '').trim()) || 0;
}

function countTempDirs(prefix) {
  try { return fs.readdirSync(os.tmpdir()).filter((n) => n.startsWith(prefix)).length; } catch { return 0; }
}

function realProfileIsolated() {
  try { return fs.lstatSync(REAL_DATA_DIR).isSymbolicLink(); } catch { return false; }
}

// ---------------------------------------------------------------- Phase 1 ---
// The start-of-run self-healing sweep must kill orphaned offscreen node
// processes (by command line, never blanket) and remove our temp dirs.
async function testSelfHealingSweep() {
  console.log('\n--- Phase 1: self-healing sweep ---');
  const stamp = Date.now();
  const fakeDirs = [
    path.join(os.tmpdir(), 'llm-escape-verify-' + stamp),
    path.join(os.tmpdir(), 'llm-webview2-verify-' + stamp),
    path.join(os.tmpdir(), 'ahkllm-frames-verify-' + stamp)
  ];
  for (const d of fakeDirs) fs.mkdirSync(d, { recursive: true });
  // A marker node process whose command line matches the repo's offscreen
  // scene pattern (scripts/videos/*offscreen*), standing in for an orphan.
  const markerFile = path.join(VIDEOS_DIR, '__cleanup_marker_offscreen_' + process.pid + '.js');
  fs.writeFileSync(markerFile, 'setInterval(() => {}, 1000);\n', 'utf-8');
  const marker = spawn(process.execPath, [markerFile], { stdio: 'ignore' });
  try {
    // CIM command-line visibility for a freshly spawned child can lag ~1s;
    // poll briefly instead of asserting on a single snapshot.
    let visible = 0;
    for (let i = 0; i < 10 && visible < 1; i++) {
      await sleep(500);
      visible = countOffscreenNode();
    }
    check(visible >= 1, 'marker offscreen node process is visible to the sweep');
    const before = fakeDirs.filter((d) => fs.existsSync(d)).length;
    check(before === 3, 'fake temp dirs created (' + before + '/3)');

    const swept = launcher.sweepOffscreenArtifacts();
    await sleep(1000);

    check(swept !== 'nothing to clean up', 'sweep reported work: ' + swept);
    check(fakeDirs.every((d) => !fs.existsSync(d)), 'fake llm-escape-/llm-webview2-/ahkllm-frames- dirs removed');
    check(countOffscreenNode() === 0, 'orphaned offscreen node process killed');
    check(countTempDirs('llm-escape-') === 0 && countTempDirs('llm-webview2-') === 0 && countTempDirs('ahkllm-frames-') === 0,
      'no leftover llm-escape-*/llm-webview2-*/ahkllm-frames- dirs');
  } finally {
    try { marker.kill(); } catch {}
    try { fs.unlinkSync(markerFile); } catch {}
    for (const d of fakeDirs) try { fs.rmSync(d, { recursive: true, force: true }); } catch {}
  }
}

// ---------------------------------------------------------------- Phase 2 ---
// A scene that hangs (body never resolves, CDP socket keeps the loop alive)
// must be reaped by the per-scene watchdog: mock server closed, app torn
// down, profile restored, hard exit - and afterwards zero orphans/listeners.
async function testHungScene() {
  console.log('\n--- Phase 2: hung offscreen scene cleanup ---');
  const sceneFile = path.join(VIDEOS_DIR, '__hung_cleanup_offscreen_' + process.pid + '.js');
  const seedPath = path.join(launcher.REPO_ROOT, 'tests', 'headless', 'seed');
  const pipelinePath = path.join(launcher.REPO_ROOT, 'scripts', 'videos', 'offscreen-pipeline');
  const src = `'use strict';
const { writeSettings, createDb } = require(${JSON.stringify(seedPath)});
const { runOffscreenScene } = require(${JSON.stringify(pipelinePath)});
runOffscreenScene({
  outName: 'hung-cleanup-test.mp4',
  seedFn: (dataDir, endpoint) => {
    writeSettings(dataDir, { threadTitles: { enabled: false } }, endpoint);
    createDb(dataDir, { threads: [
      { id: 't1', title: 'A' }, { id: 't2', title: 'B' }, { id: 't3', title: 'C' }
    ] });
  },
  mock: { mode: 'sse-success' },
  timeoutMs: 25000,
  async body() {
    console.log('HUNG-BODY-ENTERED');
    // Hang forever; the open CDP socket keeps the event loop alive, so the
    // per-scene watchdog must fire, clean up, and hard-exit this process.
    await new Promise(() => {});
  }
}).then(() => { console.log('UNEXPECTED-COMPLETION'); process.exit(0); })
  .catch((e) => { console.error('SCENE-ERROR: ' + e.message); process.exit(1); });
`;
  fs.writeFileSync(sceneFile, src, 'utf-8');

  const before = countOffscreenNode();
  const { outcome } = await pipeline.runSceneFile(sceneFile, { timeoutMs: 120000 });
  console.log('hung scene outcome:', outcome);
  check(String(outcome).startsWith('exit-'), 'hung scene exited (watchdog hard-exit), not killed externally');
  await sleep(1500);

  check(countOffscreenNode() === before, 'zero orphaned offscreen node processes after the hang');
  check(countOffscreenListeners() === 0, 'no lingering localhost listeners from offscreen node processes');
  check(countRepoProcesses() === 0, 'zero leftover repo app (AHK/WebView2) processes');
  check(!fs.existsSync(sceneFile), 'generated scene script deleted after the run');
  check(countTempDirs('llm-escape-') === 0 && countTempDirs('llm-webview2-') === 0 && countTempDirs('ahkllm-frames-') === 0,
    'no leftover llm-escape-*/llm-webview2-*/ahkllm-frames- dirs');
  check(!realProfileIsolated(), 'real profile is not left isolated behind a junction');
  check(!launcher.preflight(), 'app is not running after the hang');
}

// ---------------------------------------------------------------- Phase 3 ---
// The original guarantee: teardown(0) closes every repo app process even when
// the PID is unknown (the path that used to leak orphaned AhkLLM processes).
async function testTeardownZero() {
  console.log('\n--- Phase 3: teardown(0) with unknown PID ---');
  const iso = launcher.isolateProfile();
  try {
    launcher.resetDataDir(iso.sandboxData);
    seedData(iso.sandboxData);
    const port = await launcher.findFreePort();
    const launched = launcher.launch({ sandbox: iso.sandboxData, port });
    await launcher.waitForChatTarget(port, 60000);
    await sleep(2500);
    const before = countRepoProcesses();
    console.log('repo processes while running:', before);
    check(before >= 1, 'expected the app to be running');

    launcher.teardown(0); // simulate a run that crashed before capturing the PID
    await sleep(1500);
    check(countRepoProcesses() === 0, 'teardown(0) cleaned up all repo app processes');
  } finally {
    const ok = launcher.restoreProfile(iso);
    console.log('Real profile restored:', ok ? 'yes' : 'FAILED');
    check(ok, 'real profile restored after teardown test');
  }
}

async function main() {
  if (launcher.preflight()) {
    console.error('ABORT: AhkLLM is already running - close it first (the cleanup tests close repo app processes and must not touch your live session).');
    process.exit(3);
  }
  // Baseline sweep so counts start from zero (also proves the sweep on a clean
  // system is a safe no-op).
  console.log('Baseline sweep:', launcher.sweepOffscreenArtifacts());
  await testSelfHealingSweep();
  await testHungScene();
  await testTeardownZero();
  console.log('\nSummary: ' + (failures === 0 ? 'ALL CLEANUP CHECKS PASSED' : failures + ' check(s) FAILED'));
  process.exit(failures === 0 ? 0 : 1);
}

main().catch((e) => { console.error('verify failed:', e.message); process.exit(1); });
