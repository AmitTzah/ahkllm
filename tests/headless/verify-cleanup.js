// Verification: teardown must kill leftover repo app processes even when the
// PID is unknown (the path that used to leak orphaned AhkLLM processes).
// Run (interactive session): node tests/headless/verify-cleanup.js
'use strict';
const { spawnSync } = require('node:child_process');
const launcher = require('./launch');
const { seedData } = require('./capture-screenshots');

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

function countRepoProcesses() {
  const ps = spawnSync('powershell.exe', ['-NoProfile', '-Command',
    "(Get-CimInstance Win32_Process | Where-Object { ($_.Name -eq 'AutoHotkey64.exe') -and ($_.CommandLine -match 'ahkllm') -and ($_.CommandLine -match 'Main\\.ahk|ChatWindow\\.ahk') }).Count"
  ], { encoding: 'utf8' });
  return Number((ps.stdout || '').trim()) || 0;
}

async function main() {
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
    if (before < 1) throw new Error('expected the app to be running');

    launcher.teardown(0); // simulate a run that crashed before capturing the PID
    await sleep(1500);
    const after = countRepoProcesses();
    console.log('repo processes after teardown(0):', after);
    if (after !== 0) throw new Error('orphans remain: ' + after);
    console.log('PASS: teardown(0) cleaned up all repo app processes');
  } finally {
    const ok = launcher.restoreProfile(iso);
    console.log('Real profile restored:', ok ? 'yes' : 'FAILED');
  }
}

main().catch((e) => { console.error('verify failed:', e.message); process.exit(1); });
