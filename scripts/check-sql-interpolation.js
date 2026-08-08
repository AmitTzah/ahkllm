// check-sql-interpolation.js - Static guard for hardening item 1.
//
// Raw SQL value interpolation in AHK (`"WHERE id='" var "'"` string
// concatenation) is banned: every DB value must go through SQLite.Query bound
// parameters (`?` placeholders), so caller data can never alter the SQL text.
//
// The signature of an interpolation is a single quote adjacent to an AHK
// double-quote inside the SQL argument of an Exec/Query call ("'"). Lines that
// intentionally build a string that is BOUND as a value (e.g.
// SearchRepo._FTS5QuoteTerm) carry a "sql-lint: ok" marker.
//
// Usage: node scripts/check-sql-interpolation.js  (wired into npm test:fast)
'use strict';
const fs = require('node:fs');
const path = require('node:path');

const REPO_ROOT = path.join(__dirname, '..');
const SCAN_DIRS = ['chat', 'app', 'shared', 'api', 'lib'];
const EXTRA_FILES = ['Main.ahk'];

function collectAhkFiles() {
  const files = [];
  const walk = (dir) => {
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
      const p = path.join(dir, entry.name);
      if (entry.isDirectory()) walk(p);
      else if (entry.name.endsWith('.ahk')) files.push(p);
    }
  };
  for (const dir of SCAN_DIRS) walk(path.join(REPO_ROOT, dir));
  for (const extra of EXTRA_FILES) {
    const p = path.join(REPO_ROOT, extra);
    if (fs.existsSync(p)) files.push(p);
  }
  return files;
}

// Double-quote immediately followed by single-quote: an AHK string literal
// ending in a single quote, i.e. the `"WHERE id='" var "'"` concatenation
// pattern. Plain SQL literals (`DEFAULT 'New Chat'`) never have that adjacency.
const INTERPOLATION = /"'/;

let failures = 0;
for (const file of collectAhkFiles()) {
  const lines = fs.readFileSync(file, 'utf8').split(/\r?\n/);
  lines.forEach((line, idx) => {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith(';')) return; // comments / documentation
    if (trimmed.includes('sql-lint: ok')) return;     // deliberate bound-value builders
    // Only flag interpolation inside an actual SQL execution site - error
    // strings, debug logs, JSON/curl builders legitimately use quote
    // concatenation and are not SQL.
    const isSqlCall = /(\.Exec\(|\.Query\()/.test(line);
    if (isSqlCall && INTERPOLATION.test(line)) {
      console.log(path.relative(REPO_ROOT, file) + ':' + (idx + 1) + ': raw SQL quote-interpolation: ' + trimmed.slice(0, 140));
      failures++;
    }
  });
}

if (failures > 0) {
  console.error('FAIL: ' + failures + ' raw SQL interpolation site(s) - bind values with SQLite.Query instead.');
  process.exit(1);
}
console.log('SQL interpolation check: OK (no raw value interpolation into SQL)');
