// run-ahk-tests.js - Bounded runner for the AHK test suite.
//
// Runs tests/run_ahk_tests.ahk with a hard timeout, reads the results the
// suite writes to %TEMP%\test_results.txt, prints the summary, and exits
// non-zero on any failure or hang. Use this from npm scripts / CI so the AHK
// suite can never block a command forever.
//
// Usage: node scripts/run-ahk-tests.js
'use strict';
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const REPO_ROOT = path.join(__dirname, '..');
const AHK = process.env.AHK_EXE || 'C:\\Program Files\\AutoHotkey\\v2\\AutoHotkey64.exe';
const TIMEOUT_MS = 180000;
const RESULTS_FILE = path.join(os.tmpdir(), 'test_results.txt');

try { fs.unlinkSync(RESULTS_FILE); } catch {}

const res = spawnSync(AHK, [path.join(REPO_ROOT, 'tests', 'run_ahk_tests.ahk')], {
  timeout: TIMEOUT_MS,
  windowsHide: true,
  encoding: 'utf8'
});

if (res.error && res.error.code === 'ETIMEDOUT') {
  console.error('AHK suite TIMEOUT after ' + TIMEOUT_MS + 'ms (hang)');
  process.exit(1);
}
if (res.error) {
  console.error('AHK suite failed to spawn: ' + res.error.message);
  process.exit(1);
}

const text = fs.existsSync(RESULTS_FILE) ? fs.readFileSync(RESULTS_FILE, 'utf8') : '';
const summary = text.match(/(\d+) tests run \| (\d+) passed \| (\d+) failed/);
if (!summary) {
  console.error('AHK suite produced no result summary (exit ' + res.status + ')');
  if (text) console.error(text.slice(-600));
  process.exit(1);
}

console.log(summary[0]);
const pass = summary[3] === '0' && /RESULT: PASS/.test(text);
if (!pass) {
  const failures = text.split(/\r?\n/).filter((l) => l.startsWith('[FAIL]'));
  console.error(failures.slice(0, 20).join('\n'));
}
process.exit(pass ? 0 : 1);
