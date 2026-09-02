// ipc.test.js - Unit tests for the typed sender + correlation/ack layer
// (webui/js/shared/ipc.js): postToHost payloads, request() promise matching,
// error acks, and timeout.
const { describe, it } = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

function loadIpc(onPost) {
  const contractSrc = fs.readFileSync(path.resolve(__dirname, '..', '..', 'webui', 'js', 'shared', 'ipc-contract.js'), 'utf-8');
  const ipcSrc = fs.readFileSync(path.resolve(__dirname, '..', '..', 'webui', 'js', 'shared', 'ipc.js'), 'utf-8');
  let posted = [];
  const sandbox = {
    window: { chrome: { webview: { postMessage: (msg) => { posted.push(msg); if (onPost) onPost(msg, sandbox); } } } },
    console: console,
    setTimeout: setTimeout,
    clearTimeout: clearTimeout
  };
  sandbox.global = sandbox;
  const ctx = vm.createContext(sandbox);
  vm.runInContext(contractSrc, ctx);
  vm.runInContext(ipcSrc, ctx);
  return { Ipc: sandbox.Ipc, posted };
}

describe('Ipc.postToHost', () => {
  it('adds a unique reqId to every posted message', () => {
    const { Ipc, posted } = loadIpc();
    Ipc.postToHost('chatSend', { message: 'a' });
    Ipc.postToHost('retry');
    const m1 = JSON.parse(posted[0]);
    const m2 = JSON.parse(posted[1]);
    assert.strictEqual(m1.action, 'chatSend');
    assert.strictEqual(m1.message, 'a');
    assert.ok(m1.reqId && m2.reqId && m1.reqId !== m2.reqId, 'each message needs a unique reqId');
  });
});

describe('Ipc.request', () => {
  it('registers before posting so a synchronous ack is not lost', async () => {
    let Ipc;
    const loaded = loadIpc((msg) => {
      const request = JSON.parse(msg);
      Ipc.handleAck({ target: 'ack', data: { reqId: request.reqId, action: request.action, ok: true } });
    });
    Ipc = loaded.Ipc;
    const ack = await Ipc.request('saveSettings', { data: {} });
    assert.strictEqual(ack.action, 'saveSettings');
    assert.strictEqual(Object.keys(Ipc.pending).length, 0);
  });

  it('resolves when the matching ok ack arrives', async () => {
    const { Ipc } = loadIpc();
    const p = Ipc.request('saveSettings', { data: {} });
    const reqId = Object.keys(Ipc.pending)[0];
    Ipc.handleAck({ target: 'ack', data: { reqId: reqId, action: 'saveSettings', ok: true } });
    const ack = await p;
    assert.strictEqual(ack.action, 'saveSettings');
    assert.strictEqual(ack.ok, true);
  });

  it('rejects when the ack reports an error', async () => {
    const { Ipc } = loadIpc();
    const p = Ipc.request('saveSettings', { data: {} });
    const reqId = Object.keys(Ipc.pending)[0];
    Ipc.handleAck({ target: 'ack', data: { reqId: reqId, action: 'saveSettings', ok: false, error: 'boom' } });
    await assert.rejects(p, /boom/);
  });

  it('rejects on timeout when no ack arrives', async () => {
    const { Ipc } = loadIpc();
    const p = Ipc.request('saveSettings', { data: {} }, 30);
    await assert.rejects(p, /IPC timeout/);
  });
});
