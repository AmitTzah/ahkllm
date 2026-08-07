// check-ahk-load.js - Guardrail against AHK v2 load-time hangs and #Warn
// popups caused by unresolved identifier references.
//
// Background (verified empirically 2026-08-05): in AHK v2.0.18+, a function
// body that references a name which is NOT defined anywhere in the final
// script (e.g. a class that was never #Included) makes AutoHotkey64.exe hang
// at parse time when #Warn is off - even if the function is never called -
// and shows a modal "#Warn: this local variable appears to never be assigned"
// dialog when #Warn is enabled. This is how standalone probes that loaded
// CostCalculator.ahk without ModelResolver.ahk froze for 20+ minutes.
//
// This script runs AutoHotkey64 over (a) the full production include chain
// and (b) every standalone-loadable module, each with `#Warn All, StdOut`,
// a watchdog timer, and a hard spawnSync timeout. Any warning, hang, or
// non-clean exit fails the check with the offending text - it can never hang
// the caller.
//
// Usage: node scripts/check-ahk-load.js
'use strict';
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const REPO_ROOT = path.join(__dirname, '..');
const AHK = process.env.AHK_EXE || 'C:\\Program Files\\AutoHotkey\\v2\\AutoHotkey64.exe';
const TIMEOUT_MS = 30000;

const shared = (name) => path.join(REPO_ROOT, 'shared', name);
const standaloneTargets = [
  { name: 'shared/AppInfo', file: shared('AppInfo.ahk') },
  { name: 'shared/ModelParser', file: shared('ModelParser.ahk') },
  { name: 'shared/ModelResolver', file: shared('ModelResolver.ahk') },
  { name: 'shared/SystemMessageResolver', file: shared('SystemMessageResolver.ahk') },
  { name: 'shared/ModelPricingParser', file: shared('ModelPricingParser.ahk') },
  { name: 'shared/DebugLog', file: shared('DebugLog.ahk') },
  { name: 'shared/ImageUtils', file: shared('ImageUtils.ahk') },
  { name: 'shared/AttachmentUtils', file: shared('AttachmentUtils.ahk') },
  {
    name: 'api/CostCalculator',
    file: path.join(REPO_ROOT, 'api', 'CostCalculator.ahk'),
    stubs: 'global models := Map()\n'
  },
  { name: 'chat/db/AssistantRepo', file: path.join(REPO_ROOT, 'chat', 'db', 'AssistantRepo.ahk') },
  {
    name: 'app/TrayIcon',
    file: path.join(REPO_ROOT, 'app', 'TrayIcon.ahk'),
    stubs: 'global iconOn := "icons\\IconOn.ico"\nglobal iconOff := "icons\\IconOff.ico"\n'
  }
];
const allTargets = [
  { name: 'lib/Config (full production chain)', file: path.join(REPO_ROOT, 'lib', 'Config.ahk') },
  ...standaloneTargets
];

function harnessFor(target) {
  return [
    '#Requires AutoHotkey v2.0.18+',
    '#Warn All, StdOut',
    '#SingleInstance Off',
    '#NoTrayIcon',
    'MsgBox(text, title := "", options := "") {',
    '    return "OK"',
    '}',
    'SetTimer(WD, -15000)',
    'WD(*) {',
    '    FileAppend("WATCHDOG`n", "*")',
    '    ExitApp(9)',
    '}',
    target.stubs || '',
    '#Include ' + target.file,
    'FileAppend("LOADED`n", "*")',
    'ExitApp(0)',
    ''
  ].join('\n');
}

let failures = 0;
const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'llm-loadcheck-'));
console.log('Checking ' + allTargets.length + ' AHK load target(s) with #Warn All, StdOut (bounded ' + TIMEOUT_MS + 'ms)...');

for (const target of allTargets) {
  const file = path.join(tmpDir, target.name.replace(/[/\\]/g, '_') + '.ahk');
  fs.writeFileSync(file, harnessFor(target));
  const res = spawnSync(AHK, ['/ErrorStdOut', file], { timeout: TIMEOUT_MS, windowsHide: true, encoding: 'utf8' });
  const out = String(res.stdout || '');
  const err = String(res.stderr || '');

  let ok = true;
  let reason = '';
  if (res.error && res.error.code === 'ETIMEDOUT') {
    ok = false;
    reason = 'TIMEOUT (process hung at load)';
  } else if (out.includes('WATCHDOG')) {
    ok = false;
    reason = 'WATCHDOG (process hung at load)';
  } else if (out.includes('Warning:')) {
    ok = false;
    const warning = out.split(/\r?\n/).filter((l) => /Warning:|Specifically:/.test(l)).join(' | ');
    reason = 'WARNING: ' + (warning || out.trim().slice(0, 200));
  } else if (!out.includes('LOADED')) {
    ok = false;
    reason = 'did not report LOADED (exit ' + res.status + ')';
  } else if (err.trim()) {
    ok = false;
    reason = 'stderr: ' + err.trim().slice(0, 200);
  }

  if (!ok) failures++;
  console.log((ok ? 'PASS' : 'FAIL') + ' | ' + target.name.padEnd(38) + ' | ' + (reason || 'clean load'));
}

fs.rmSync(tmpDir, { recursive: true, force: true });
console.log(failures === 0
  ? 'AHK load check OK: no unresolved identifiers, no warnings, no hangs.'
  : 'AHK load check FAILED: ' + failures + ' target(s) have unresolved identifiers/warnings.');
process.exit(failures === 0 ? 0 : 1);
