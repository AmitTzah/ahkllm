// ipc-test-utils.js - Loads the shared IPC contract + typed sender into a
// vm sandbox so unit tests can keep asserting on the mocked webview after
// call sites migrated from inline window.chrome.webview.postMessage(...) to
// Ipc.postToHost(...).
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const CONTRACT_SRC = fs.readFileSync(
  path.resolve(__dirname, '..', '..', '..', 'webui', 'js', 'shared', 'ipc-contract.js'),
  'utf-8'
);
const IPC_SRC = fs.readFileSync(
  path.resolve(__dirname, '..', '..', '..', 'webui', 'js', 'shared', 'ipc.js'),
  'utf-8'
);

// Evaluate both files into the given vm context. Must run after the context
// is created and before the module under test posts any message.
function installIpc(ctx) {
  vm.runInContext(CONTRACT_SRC, ctx);
  vm.runInContext(IPC_SRC, ctx);
}

module.exports = { installIpc };
