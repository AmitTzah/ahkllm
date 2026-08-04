// ======================================================
// check-ipc-contract.js - Drift check for the AHK <-> WebView
// message contract (webui/js/shared/ipc-contract.js).
//
// Scans the AHK sources for postWebMessage("...") targets and
// the WebView sources for action: '...' names, then fails when
// any posted message is not declared in the shared contract
// (or is declared with the wrong direction). Run with:
//   node scripts/check-ipc-contract.js
// ======================================================
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const contract = require('../webui/js/shared/ipc-contract.js');

const ROOT = path.resolve(__dirname, '..');
const VENDOR_RE = /(^|[\\/])(vendor|libs|dist)([\\/]|\.)/;

function walk(dir, visitFile) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, entry.name);
    if (entry.isDirectory()) walk(p, visitFile);
    else visitFile(p);
  }
}

function scanAhkTargets() {
  const found = new Set();
  for (const dir of ['chat', 'app']) {
    walk(path.join(ROOT, dir), (p) => {
      if (!p.endsWith('.ahk')) return;
      const src = fs.readFileSync(p, 'utf8');
      for (const m of src.matchAll(/postWebMessage\("([A-Za-z]+)"/g)) found.add(m[1]);
    });
  }
  return found;
}

function scanJsActions() {
  const found = new Set();
  walk(path.join(ROOT, 'webui', 'js'), (p) => {
    const rel = p.slice(ROOT.length + 1);
    if (!p.endsWith('.js') || VENDOR_RE.test(rel)) return;
    const src = fs.readFileSync(p, 'utf8');
    for (const m of src.matchAll(/action\s*:\s*'([A-Za-z]+)'/g)) found.add(m[1]);
    // All outgoing messages go through Ipc.postToHost / Ipc.request.
    for (const m of src.matchAll(/Ipc\.postToHost\('([A-Za-z]+)'/g)) found.add(m[1]);
    for (const m of src.matchAll(/Ipc\.request\('([A-Za-z]+)'/g)) found.add(m[1]);
  });
  return found;
}

let ok = true;

const ahkNames = [...scanAhkTargets()].sort();
const jsNames = [...scanJsActions()].sort();

const ahkMissing = ahkNames.filter((n) => !contract.messages[n] || contract.messages[n].dir !== 'ahk->web');
const jsMissing = jsNames.filter((n) => !contract.messages[n] || contract.messages[n].dir !== 'web->ahk');

if (ahkMissing.length) {
  ok = false;
  console.error('FAIL: AHK posts undeclared/wrong-direction messages: ' + ahkMissing.join(', '));
}
if (jsMissing.length) {
  ok = false;
  console.error('FAIL: WebView posts undeclared/wrong-direction actions: ' + jsMissing.join(', '));
}

if (ok) {
  console.log(
    'IPC contract OK: ' + ahkNames.length + ' ahk->web targets, ' +
    jsNames.length + ' web->ahk actions, ' +
    Object.keys(contract.subActions).length + ' sidebarAction sub-actions declared'
  );
  process.exit(0);
}
process.exit(1);
