// check-release-readiness.js - fast public-tree guardrail.
//
// This check intentionally does not replace a full secret scanner or a
// provenance review. It catches common accidental files, missing release
// documents, hard-coded developer paths, and broken local CSS asset links.
'use strict';

const fs = require('node:fs');
const path = require('node:path');

const REPO_ROOT = path.resolve(__dirname, '..');
const requiredFiles = [
  'LICENSE',
  'README.md',
  'SECURITY.md',
  'CONTRIBUTING.md',
  'THIRD_PARTY_NOTICES.md',
  'lib/WebView2Loader_LICENSE.md',
  'lib/UIA_LICENSE.txt',
  'lib/SQLite/License.txt',
  'lib/ToolTipEx_LICENSE.txt',
  'webui/fonts/OFL-1.1.txt',
  'webui/fonts/NOTICES.md'
];
const requiredRuntimeFiles = [
  'Main.ahk',
  'lib/32bit/WebView2Loader.dll',
  'lib/64bit/WebView2Loader.dll',
  'lib/SQLite/lib/bin/sqlite332.dll',
  'lib/SQLite/lib/bin/sqlite364.dll',
  'webui/index.html'
];
const forbiddenTrackedPath = /(^|\/)(\.env(?:\.|$)|node_modules|\.chatgpt|agent-workspace)(\/|$)|\.(?:db|sqlite|sqlite3|log|dmp|dump|bak|tmp|temp)$/i;
const secretPatterns = [
  { name: 'OpenAI-style key', pattern: /sk-[A-Za-z0-9][A-Za-z0-9_-]{19,}/ },
  { name: 'Google-style key', pattern: /AIza[A-Za-z0-9_-]{20,}/ },
  { name: 'AWS access key', pattern: /AKIA[0-9A-Z]{16}/ },
  { name: 'GitHub token', pattern: /gh[pousr]_[A-Za-z0-9_]{20,}/ },
  { name: 'Slack token', pattern: /xox[baprs]-[A-Za-z0-9-]{10,}/ },
  { name: 'private key header', pattern: /-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----/ }
];
const localAhkLlmPathPattern = /[A-Za-z]:[\\/]Users[\\/][^\\/]+[\\/]AppData[\\/](?:Roaming|Local)[\\/]AhkLLM(?:[\\/]|$)/i;

function publicFiles() {
  const ignoredDirectories = new Set(['.git', '.chatgpt', '.tools', 'node_modules', 'agent-workspace']);
  const files = [];
  function visit(directory) {
    for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
      if (entry.isDirectory() && ignoredDirectories.has(entry.name)) continue;
      const absolute = path.join(directory, entry.name);
      if (entry.isDirectory()) visit(absolute);
      else files.push(path.relative(REPO_ROOT, absolute).split(path.sep).join('/'));
    }
  }
  visit(REPO_ROOT);
  return files;
}

function readText(file) {
  const absolute = path.join(REPO_ROOT, file);
  if (!fs.existsSync(absolute)) return null;
  const data = fs.readFileSync(absolute);
  if (data.includes(0)) return null;
  return data.toString('utf8');
}

function checkLocalCssReferences(files, failures) {
  for (const file of files.filter((item) => item.toLowerCase().endsWith('.css'))) {
    const source = readText(file);
    if (source === null) continue;
    const cssDir = path.dirname(file);
    for (const match of source.matchAll(/url\((?:['"]?)([^)'"\s]+)(?:['"]?)\)/gi)) {
      const reference = match[1];
      if (/^(?:data:|https?:|\/\/|#)/i.test(reference)) continue;
      const target = path.normalize(path.join(REPO_ROOT, cssDir, reference));
      if (!target.toLowerCase().startsWith(REPO_ROOT.toLowerCase() + path.sep)) {
        failures.push(`${file}: CSS reference escapes repository: ${reference}`);
      } else if (!fs.existsSync(target)) {
        failures.push(`${file}: missing local CSS asset: ${reference}`);
      }
    }
  }
}

function main() {
  const files = publicFiles();
  const failures = [];
  for (const file of requiredFiles.concat(requiredRuntimeFiles)) {
    if (!fs.existsSync(path.join(REPO_ROOT, file))) failures.push(`missing required file: ${file}`);
  }

  const notices = readText('THIRD_PARTY_NOTICES.md');
  if (notices && /\|\s*BLOCKER\s*\|/i.test(notices)) {
    failures.push('THIRD_PARTY_NOTICES.md still contains a BLOCKER status');
  }

  for (const file of files) {
    if (forbiddenTrackedPath.test(file)) failures.push(`forbidden tracked path: ${file}`);
    const source = readText(file);
    if (source === null) continue;
    if (localAhkLlmPathPattern.test(source)) {
      failures.push(`developer-specific path in tracked text: ${file}`);
    }
    for (const item of secretPatterns) {
      if (item.pattern.test(source)) failures.push(`${item.name} pattern in tracked text: ${file}`);
    }
  }

  checkLocalCssReferences(files, failures);
  const uniqueFailures = [...new Set(failures)];
  console.log(`Release readiness tree check: ${files.length} public-tree files scanned (including untracked files).`);
  if (uniqueFailures.length) {
    for (const failure of uniqueFailures) console.error(`FAIL: ${failure}`);
    console.error(`Release readiness check failed with ${uniqueFailures.length} finding(s).`);
    process.exitCode = 1;
  } else {
    console.log('Release readiness tree check passed: required docs/runtime files present; no forbidden paths, known secret patterns, developer paths, or broken local CSS links found.');
  }
}

main();
