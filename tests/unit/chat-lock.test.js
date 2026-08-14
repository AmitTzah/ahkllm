// chat-lock.test.js — Unit tests for webui/js/chat/chat-lock.js
// (locked-chat overlay, PBKDF2 hashing, lock modal flows).
const { describe, it } = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const nodeCrypto = require('node:crypto');

function loadModules(rejectActions) {
  const src = fs.readFileSync(path.resolve(__dirname, '..', '..', 'webui', 'js', 'chat', 'chat-lock.js'), 'utf-8');
  const posted = [];
  const els = {};
  function makeEl(tag, id) {
    return {
      tagName: tag, id: id || '', className: '', innerHTML: '', textContent: '', title: '',
      value: '', disabled: false, style: {}, children: [], parentNode: null,
      _handlers: {},
      _attrs: {},
      get firstChild() { return this; },
      classList: { add() {}, remove() {}, contains() { return false; }, toggle() {} },
      addEventListener(evt, fn) { (this._handlers[evt] = this._handlers[evt] || []).push(fn); },
      dispatch(evt, arg) { (this._handlers[evt] || []).forEach(function(fn) { fn(arg); }); },
      appendChild(child) { child.parentNode = this; this.children.push(child); return child; },
      contains(child) { return child === this || this.children.indexOf(child) >= 0; },
      getBoundingClientRect() { return { left: 0, top: 0, bottom: 12, width: 30 }; },
      focus() {},
      remove() { if (this.id && els[this.id] === this) delete els[this.id]; },
      closest(sel) { return this.className.indexOf(sel.replace('.', '')) >= 0 ? this : null; },
      querySelector() { return makeEl('div'); },
      querySelectorAll() { return []; },
      getAttribute(k) { return this._attrs[k] || null; },
      setAttribute(k, v) { this._attrs[k] = String(v); }
    };
  }
  const doc = {
    _els: els,
    body: {
      appendChild(el) { els[el.id] = el; el.parentNode = doc.body; },
      removeChild(el) { delete els[el.id]; }
    },
    getElementById(id) {
      if (!els[id]) els[id] = makeEl('div', id);
      return els[id];
    },
    querySelector(sel) {
      if (sel === '.search-wrap.in-panel .search-input') {
        if (!els._scoped) els._scoped = makeEl('input', '_scoped');
        return els._scoped;
      }
      return null;
    },
    querySelectorAll() { return []; },
    createElement(tag) { return makeEl(tag); },
    addEventListener() {},
    removeEventListener() {}
  };
  const sandbox = {
    document: doc,
    console: console,
    crypto: nodeCrypto.webcrypto,
    TextEncoder: TextEncoder,
    setTimeout: setTimeout,
    clearTimeout: clearTimeout,
    chatMessages: [],
    activeThreadId: '',
    _threadMeta: {},
    updateTopbarTitle: function() {},
    _setActiveHighlight: function() {},
    updateScopedSearchState: function() {},
    Ipc: {
      request: async function(action, payload) {
        posted.push({ action: action, payload: payload });
        if (rejectActions && rejectActions[action]) throw rejectActions[action];
        return { ok: true };
      },
      postToHost: function(action, payload) { posted.push({ action: action, payload: payload }); return 'r1'; }
    }
  };
  sandbox.global = sandbox;
  sandbox.escHtml = function(s) {
    if (!s) return '';
    return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  };
  sandbox.loadThread = function(id) { sandbox.loadedThread = id; };
  vm.runInContext(src, vm.createContext(sandbox));
  return { sandbox, posted, doc, els };
}

async function flush() {
  for (let i = 0; i < 20; i++) await new Promise((r) => setTimeout(r, 0));
}

async function waitFor(predicate, timeoutMs) {
  const start = Date.now();
  const limit = timeoutMs || 15000;
  while (Date.now() - start < limit) {
    if (predicate()) return true;
    await new Promise((r) => setTimeout(r, 20));
  }
  return predicate();
}

describe('chat-lock KDF helpers', () => {
  it('hex conversions round-trip', () => {
    const { sandbox } = loadModules();
    const bytes = new Uint8Array([0, 1, 15, 16, 255, 171]);
    const hex = sandbox._bytesToHex(bytes);
    assert.strictEqual(hex, '00010f10ffab');
    assert.deepStrictEqual(Array.from(sandbox._hexToBytes(hex)), [0, 1, 15, 16, 255, 171]);
  });

  it('constant-time compare handles equality and mismatch', () => {
    const { sandbox } = loadModules();
    assert.ok(sandbox._constantTimeEquals('aabb', 'aabb'));
    assert.ok(!sandbox._constantTimeEquals('aabb', 'aabc'));
    assert.ok(!sandbox._constantTimeEquals('aabb', 'aab'));
    assert.ok(sandbox._constantTimeEquals('', ''));
  });

  it('derives the same PBKDF2-SHA-256 hash as Node crypto', async () => {
    const { sandbox } = loadModules();
    const salt = '00112233445566778899aabbccddeeff';
    const expected = nodeCrypto.pbkdf2Sync('hunter2', Buffer.from(salt, 'hex'), 1000, 32, 'sha256').toString('hex');
    const got = await sandbox.derivePasswordHash('hunter2', salt, 1000);
    assert.strictEqual(got, expected);
  });
});

describe('locked-thread overlay', () => {
  it('renders the overlay, wipes content, redacts the title, disables the composer', () => {
    const { sandbox, doc, els } = loadModules();
    sandbox.chatMessages = [{ id: 'm1' }];
    const pane = doc.getElementById('chat-messages');
    pane.innerHTML = '<div class="msg">secret</div>';
    els.chatInput = doc.getElementById('chat-input');
    els.chatInput.disabled = false;
    els.chatSendBtn = doc.getElementById('chat-send-btn');
    els.chatSendBtn.disabled = false;

    sandbox.handleThreadLocked({ threadId: 't1', salt: 'ab', iterations: 1000 });

    assert.ok(doc.getElementById('threadLockOverlay') !== null);
    assert.strictEqual(sandbox.chatMessages.length, 0);
    assert.strictEqual(doc.getElementById('chat-messages').innerHTML, '');
    assert.strictEqual(sandbox._threadMeta.t1.title, 'Locked chat');
    assert.strictEqual(els.chatInput.disabled, true);
    assert.strictEqual(els.chatSendBtn.disabled, true);
    assert.ok(els._scoped.disabled);
  });

  it('clearThreadLockOverlay removes the overlay and restores the composer', () => {
    const { sandbox, doc, els } = loadModules();
    els.chatInput = doc.getElementById('chat-input');
    els.chatInput.disabled = false;
    sandbox.handleThreadLocked({ threadId: 't1', salt: 'ab', iterations: 1000 });
    assert.strictEqual(els.chatInput.disabled, true);
    sandbox.clearThreadLockOverlay();
    assert.strictEqual(doc.getElementById('threadLockOverlay').parentNode, null);
    assert.strictEqual(els.chatInput.disabled, false);
  });
});

describe('unlock flow', () => {
  it('posts the derived hash on success', async () => {
    const { sandbox, posted, doc } = loadModules();
    sandbox.handleThreadLocked({ threadId: 't1', salt: '00112233445566778899aabbccddeeff', iterations: 1000 });
    doc.getElementById('lockPasswordInput').value = 'secret';
    doc.getElementById('lockUnlockBtn').dispatch('click');
    assert.ok(await waitFor(() => posted.some((p) => p.action === 'unlockThread')), 'unlockThread must be posted');
    const msg = posted.find((p) => p.action === 'unlockThread');
    assert.ok(msg, 'unlockThread must be posted');
    assert.strictEqual(msg.payload.threadId, 't1');
    assert.strictEqual(
      msg.payload.passwordHash,
      nodeCrypto.pbkdf2Sync('secret', Buffer.from('00112233445566778899aabbccddeeff', 'hex'), 1000, 32, 'sha256').toString('hex')
    );
  });

  it('shows the rejection message on a wrong password', async () => {
    const { sandbox, posted, doc } = loadModules({ unlockThread: new Error('Incorrect password.') });
    sandbox.handleThreadLocked({ threadId: 't1', salt: '00112233445566778899aabbccddeeff', iterations: 1000 });
    doc.getElementById('lockPasswordInput').value = 'wrong';
    doc.getElementById('lockUnlockBtn').dispatch('click');
    assert.ok(await waitFor(() => posted.some((p) => p.action === 'unlockThread')), 'unlockThread must be posted');
    assert.ok(await waitFor(() => doc.getElementById('lockError').textContent === 'Incorrect password.'), 'error must surface');
  });
});

describe('lock overlay dismissal', () => {
  it('Cancel posts dismissLockedThread, removes the overlay and resets the active thread', () => {
    const { sandbox, posted, doc } = loadModules();
    sandbox.handleThreadLocked({ threadId: 't1', salt: 'ab', iterations: 1000 });
    assert.ok(doc.getElementById('threadLockOverlay') !== null);
    doc.getElementById('lockOverlayCancel').dispatch('click');
    assert.ok(posted.some((p) => p.action === 'dismissLockedThread'), 'dismissLockedThread must be posted');
    assert.strictEqual(doc.getElementById('threadLockOverlay').parentNode, null);
    assert.strictEqual(sandbox.activeThreadId, '');
  });
});

describe('lock modal flows', () => {
  it('set flow posts a fresh salt + derived hash and closes the modal', async () => {
    const { sandbox, posted, doc } = loadModules();
    sandbox.openThreadLockModal('t1', 'set');
    doc.getElementById('lockModalNew').value = 'newpass';
    doc.getElementById('lockModalConfirm').value = 'newpass';
    doc.getElementById('lockModalSave').dispatch('click');
    assert.ok(await waitFor(() => posted.some((p) => p.action === 'setThreadLock')), 'setThreadLock must be posted');
    const msg = posted.find((p) => p.action === 'setThreadLock');
    assert.strictEqual(msg.payload.mode, 'set');
    assert.strictEqual(msg.payload.threadId, 't1');
    assert.strictEqual(msg.payload.salt.length, 32);
    assert.strictEqual(msg.payload.passwordHash.length, 64);
    assert.strictEqual(msg.payload.iterations, 600000);
    assert.strictEqual(msg.payload.currentPasswordHash, '');
    assert.strictEqual(doc.getElementById('threadLockModal').parentNode, null);
  });

  it('rejects mismatched passwords without posting', async () => {
    const { sandbox, posted, doc } = loadModules();
    sandbox.openThreadLockModal('t1', 'set');
    doc.getElementById('lockModalNew').value = 'aaaa';
    doc.getElementById('lockModalConfirm').value = 'bbbb';
    doc.getElementById('lockModalSave').dispatch('click');
    await waitFor(() => posted.length > 0, 500);
    assert.ok(!posted.some((p) => p.action === 'setThreadLock'));
    assert.strictEqual(doc.getElementById('lockModalError').textContent, 'Passwords do not match.');
  });

  it('change flow includes the current-password hash derived from the stored salt', async () => {
    const { sandbox, posted, doc } = loadModules();
    const salt = '00112233445566778899aabbccddeeff';
    sandbox.handleThreadLockInfo({ threadId: 't1', salt: salt, iterations: 1000 });
    sandbox.openThreadLockModal('t1', 'change');
    doc.getElementById('lockModalCurrent').value = 'oldpass';
    doc.getElementById('lockModalNew').value = 'newpass';
    doc.getElementById('lockModalConfirm').value = 'newpass';
    doc.getElementById('lockModalSave').dispatch('click');
    assert.ok(await waitFor(() => posted.some((p) => p.action === 'setThreadLock')), 'setThreadLock must be posted');
    const msg = posted.find((p) => p.action === 'setThreadLock');
    assert.strictEqual(msg.payload.mode, 'change');
    assert.strictEqual(
      msg.payload.currentPasswordHash,
      nodeCrypto.pbkdf2Sync('oldpass', Buffer.from(salt, 'hex'), 1000, 32, 'sha256').toString('hex')
    );
    assert.strictEqual(msg.payload.passwordHash.length, 64);
    // The page must keep the CURRENT salt after a change so a follow-up
    // remove/change derives the current hash correctly.
    assert.strictEqual(sandbox._lockInfo.t1.salt, msg.payload.salt);
    assert.strictEqual(sandbox._lockInfo.t1.iterations, msg.payload.iterations);
  });

  it('remove flow posts mode remove with the current-password hash', async () => {
    const { sandbox, posted, doc } = loadModules();
    const salt = '00112233445566778899aabbccddeeff';
    sandbox.handleThreadLockInfo({ threadId: 't1', salt: salt, iterations: 1000 });
    sandbox.openThreadLockModal('t1', 'change');
    doc.getElementById('lockModalCurrent').value = 'oldpass';
    doc.getElementById('lockModalRemove').dispatch('click');
    assert.ok(await waitFor(() => posted.some((p) => p.action === 'setThreadLock')), 'setThreadLock must be posted');
    const msg = posted.find((p) => p.action === 'setThreadLock');
    assert.strictEqual(msg.payload.mode, 'remove');
    assert.strictEqual(
      msg.payload.currentPasswordHash,
      nodeCrypto.pbkdf2Sync('oldpass', Buffer.from(salt, 'hex'), 1000, 32, 'sha256').toString('hex')
    );
    assert.strictEqual(msg.payload.passwordHash, '');
  });
});

describe('sidebar lock menu', () => {
  it('shows three options with state-appropriate disabling (locked, not unlocked)', () => {
    const { sandbox, doc } = loadModules();
    sandbox.handleThreadLockInfo({ threadId: 't1', salt: 'ab', iterations: 1000 });
    sandbox.openLockMenu('t1', doc.getElementById('anchor'), { id: 't1', title: 'Locked chat', is_locked: 1 });
    const dd = doc.getElementById('lockMenuDropdown');
    assert.ok(dd, 'menu must be open');
    const byAction = {};
    dd.children.forEach(function(c) {
      if (c.className.indexOf('lock-menu-item') >= 0) byAction[c.getAttribute('data-action')] = c;
    });
    assert.strictEqual(Object.keys(byAction).length, 3);
    assert.ok(byAction.lock.disabled, 'Lock Chat must be disabled while already locked');
    assert.ok(!byAction.unlock.disabled, 'Unlock Chat must be enabled while locked');
    assert.ok(!byAction.change.disabled, 'Change password must be enabled while locked');
    dd.dispatch('click', { target: byAction.unlock });
    assert.strictEqual(sandbox.loadedThread, 't1', 'Unlock Chat must load the chat (which shows the overlay)');
  });

  it('Lock Chat relocks a session-unlocked chat via lockChatNow', () => {
    const { sandbox, posted, doc } = loadModules();
    sandbox.openLockMenu('t1', doc.getElementById('anchor'), { id: 't1', title: 'Secret Plan', is_locked: 1 });
    const dd = doc.getElementById('lockMenuDropdown');
    const lockBtn = dd.children.find((c) => c.className.indexOf('lock-menu-item') >= 0 && c.getAttribute('data-action') === 'lock');
    assert.ok(!lockBtn.disabled, 'Lock Chat must be enabled once the chat is unlocked in the session');
    dd.dispatch('click', { target: lockBtn });
    assert.ok(posted.some((p) => p.action === 'lockChatNow' && p.payload.threadId === 't1'), 'lockChatNow must be posted');
  });

  it('on an unlocked chat only Lock Chat is active and it opens the protect modal', () => {
    const { sandbox, doc } = loadModules();
    sandbox.openLockMenu('t2', doc.getElementById('anchor'), { id: 't2', title: 'Open chat', is_locked: 0 });
    const dd = doc.getElementById('lockMenuDropdown');
    const byAction = {};
    dd.children.forEach(function(c) {
      if (c.className.indexOf('lock-menu-item') >= 0) byAction[c.getAttribute('data-action')] = c;
    });
    assert.ok(!byAction.lock.disabled);
    assert.ok(byAction.unlock.disabled);
    assert.ok(byAction.change.disabled);
    sandbox.openThreadLockModal = function(id, mode) { sandbox.openedModal = { id: id, mode: mode }; };
    dd.dispatch('click', { target: byAction.lock });
    assert.deepStrictEqual(sandbox.openedModal, { id: 't2', mode: 'set' }, 'Lock Chat must open the protect modal');
  });
});
