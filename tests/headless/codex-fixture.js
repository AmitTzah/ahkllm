'use strict';
const fs = require('node:fs');
const path = require('node:path');

function installFakeCodex(dataDir) {
  fs.writeFileSync(path.join(dataDir, 'fake-codex.cmd'), [
    '@echo off', '"%FAKE_NODE_EXE%" "%FAKE_CODEX_SCRIPT%" %*', 'exit /b %ERRORLEVEL%', ''
  ].join('\r\n'), 'utf8');
  fs.writeFileSync(path.join(dataDir, 'fake-codex-log.jsonl'), '', 'utf8');
}

function fakeCodexEnvironment({dataDir}) {
  return {CODEX_CLI_PATH: path.join(dataDir, 'fake-codex.cmd'), FAKE_NODE_EXE: process.execPath,
    FAKE_CODEX_SCRIPT: path.join(__dirname, 'fake-codex-cli.js'), FAKE_CODEX_LOG: path.join(dataDir, 'fake-codex-log.jsonl')};
}

function codexRequests(dataDir) {
  const file = path.join(dataDir, 'fake-codex-log.jsonl');
  return fs.existsSync(file) ? fs.readFileSync(file, 'utf8').split(/\r?\n/).filter(Boolean).map(JSON.parse).filter(entry => entry.kind === 'exec') : [];
}

module.exports = {installFakeCodex, fakeCodexEnvironment, codexRequests};
