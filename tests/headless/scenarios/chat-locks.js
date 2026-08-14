// scenarios/chat-locks.js - Locked-chat (password-protected) feature checks.
//
// Part of the headless E2E suite (entry: ../e2e-suite.js). Every real-app
// scenario launches the app against an isolated profile and drives the real
// WebView2 over CDP; `noApp: true` scenarios are static source checks for
// wiring that cannot be exercised headlessly (mid-stream repaint gating).
//
// All scenarios are `regression: true`: they assert the FIXED behavior of the
// locked-chats feature, so they double as the growing regression suite.
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const nodeCrypto = require('node:crypto');
const launcher = require('../launch');
const seed = require('../seed');
const { sleep, runProbe, showChat } = require('./helpers');

const scenarios = [];

// PBKDF2 settings shared with the WebView derivePasswordHash (chat-lock.js).
const LOCK_SALT = '00112233445566778899aabbccddeeff';
const LOCK_ITERATIONS = 600000;
const LOCK_PASSWORD = 'correct horse';

function lockHash(password, saltHex, iterations) {
  return nodeCrypto.pbkdf2Sync(password, Buffer.from(saltHex, 'hex'), iterations, 32, 'sha256').toString('hex');
}

// Fixtures for a locked thread with one user + one assistant message.
function lockedFixtures(threadId, title, content) {
  return {
    threads: [{ id: threadId, title: title, active_leaf_id: threadId + '-a1', is_locked: 1 }],
    messages: [
      { id: threadId + '-u1', thread_id: threadId, role: 'user', content: content },
      { id: threadId + '-a1', thread_id: threadId, role: 'assistant', content: 'response to ' + content, parent_id: threadId + '-u1', model: 'deepseek/deepseek-v4-flash' }
    ],
    chatLocks: [{
      thread_id: threadId,
      salt: LOCK_SALT,
      hash: lockHash(LOCK_PASSWORD, LOCK_SALT, LOCK_ITERATIONS),
      iterations: LOCK_ITERATIONS
    }]
  };
}

const lockedItem = (id) => '#thread-list .chat-item[data-chat="' + id + '"]';

scenarios.push({
  id: 235,
  name: 'Locked chat renders in the sidebar with a lock icon and a redacted title',
  regression: true,
  mode: null,
  fixtures: lockedFixtures('t-lock-235', 'Secret Plan', 'hidden content'),
  async body({ cdp }) {
    await showChat();
    await cdp.waitFor('document.querySelector(' + JSON.stringify(lockedItem('t-lock-235')) + ') !== null', 15000, 300, 'locked chat in sidebar');
    const info = await cdp.eval(`(() => {
      const item = document.querySelector(${JSON.stringify(lockedItem('t-lock-235'))});
      const name = item.querySelector('.chat-name');
      return {
        title: name.textContent.trim(),
        hasLockIcon: !!item.querySelector('.chat-name svg'),
        metaTitle: window._threadMeta['t-lock-235'] && window._threadMeta['t-lock-235'].title
      };
    })()`);
    if (info.title !== 'Locked chat') throw new Error('locked title not redacted: ' + info.title);
    if (!info.hasLockIcon) throw new Error('locked chat must show a lock icon');
    if (info.metaTitle !== 'Locked chat') throw new Error('_threadMeta title leaked: ' + info.metaTitle);
    return 'sidebar shows "Locked chat" + lock icon for t-lock-235';
  }
});

scenarios.push({
  id: 236,
  name: 'Clicking a locked chat shows the lock overlay with zero content leak',
  regression: true,
  mode: null,
  fixtures: lockedFixtures('t-lock-236', 'Secret Plan', 'hidden content'),
  async body({ cdp }) {
    await showChat();
    await cdp.waitFor('document.querySelector(' + JSON.stringify(lockedItem('t-lock-236')) + ') !== null', 15000, 300, 'locked chat in sidebar');
    await cdp.click(lockedItem('t-lock-236'));
    await cdp.waitFor('document.getElementById("threadLockOverlay") !== null', 15000, 300, 'lock overlay');
    const state = await cdp.eval(`(() => ({
      msgCount: chatMessages.length,
      domMsgs: document.querySelectorAll('#chat-messages .msg').length,
      inputDisabled: document.getElementById('chat-input') ? document.getElementById('chat-input').disabled : null,
      postedInit: (window.__posted || []).some(s => s.indexOf('"target":"initChatMode"') >= 0)
    }))()`);
    if (state.msgCount !== 0) throw new Error('chatMessages leaked content: ' + state.msgCount);
    if (state.domMsgs !== 0) throw new Error('DOM leaked messages: ' + state.domMsgs);
    if (!state.inputDisabled) throw new Error('composer must be disabled while locked');
    if (state.postedInit) throw new Error('initChatMode must not be posted for a locked chat');

    // Escape dismisses the prompt without opening the chat.
    await cdp.eval(`document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true })); true`);
    await cdp.waitFor('document.getElementById("threadLockOverlay") === null && window.activeThreadId === ""', 10000, 300, 'overlay dismissed with Escape');
    const afterEscape = await cdp.eval(`(() => ({
      msgs: document.querySelectorAll('#chat-messages .msg').length,
      inputDisabled: document.getElementById('chat-input') ? document.getElementById('chat-input').disabled : null
    }))()`);
    if (afterEscape.msgs !== 0) throw new Error('content leaked after dismissing the overlay');
    if (afterEscape.inputDisabled) throw new Error('composer must be restored after dismissing');

    // The Cancel button dismisses the same way.
    await cdp.click(lockedItem('t-lock-236'));
    await cdp.waitFor('document.getElementById("threadLockOverlay") !== null', 10000, 300, 'lock overlay (second)');
    await cdp.click('#lockOverlayCancel');
    await cdp.waitFor('document.getElementById("threadLockOverlay") === null && window.activeThreadId === ""', 10000, 300, 'overlay dismissed with Cancel');
    return 'lock overlay shown with zero content; Escape and Cancel both dismiss it';
  }
});

scenarios.push({
  id: 237,
  name: 'Wrong password is rejected and content stays hidden',
  regression: true,
  mode: null,
  fixtures: lockedFixtures('t-lock-237', 'Secret Plan', 'hidden content'),
  async body({ cdp }) {
    await showChat();
    await cdp.waitFor('document.querySelector(' + JSON.stringify(lockedItem('t-lock-237')) + ') !== null', 15000, 300, 'locked chat in sidebar');
    await cdp.click(lockedItem('t-lock-237'));
    await cdp.waitFor('document.getElementById("threadLockOverlay") !== null', 15000, 300, 'lock overlay');
    await cdp.type('#lockPasswordInput', 'wrong-password');
    await cdp.click('#lockUnlockBtn');
    await cdp.waitFor('document.getElementById("lockError") && document.getElementById("lockError").textContent.indexOf("Incorrect password.") >= 0', 30000, 300, 'wrong password error');
    const domMsgs = await cdp.eval('document.querySelectorAll("#chat-messages .msg").length');
    if (domMsgs !== 0) throw new Error('content rendered after wrong password: ' + domMsgs);
    return 'wrong password shows an error and no content is revealed';
  }
});

scenarios.push({
  id: 238,
  name: 'Correct password unlocks and renders the chat',
  regression: true,
  mode: null,
  fixtures: lockedFixtures('t-lock-238', 'Secret Plan', 'hidden content'),
  async body({ cdp }) {
    await showChat();
    await cdp.waitFor('document.querySelector(' + JSON.stringify(lockedItem('t-lock-238')) + ') !== null', 15000, 300, 'locked chat in sidebar');
    await cdp.click(lockedItem('t-lock-238'));
    await cdp.waitFor('document.getElementById("threadLockOverlay") !== null', 15000, 300, 'lock overlay');
    await cdp.type('#lockPasswordInput', LOCK_PASSWORD);
    await cdp.click('#lockUnlockBtn');
    await cdp.waitFor('document.querySelectorAll("#chat-messages .msg").length >= 1', 30000, 300, 'messages render after unlock');
    const state = await cdp.eval(`(() => ({
      active: window.activeThreadId,
      overlay: document.getElementById('threadLockOverlay') === null,
      msgCount: document.querySelectorAll('#chat-messages .msg').length
    }))()`);
    if (state.active !== 't-lock-238') throw new Error('active thread not set after unlock: ' + state.active);
    if (!state.overlay) throw new Error('lock overlay must close after unlock');
    if (state.msgCount < 1) throw new Error('no messages rendered after unlock');
    await cdp.waitFor(`window._threadMeta['t-lock-238'] && window._threadMeta['t-lock-238'].title === 'Secret Plan'`, 15000, 300, 'real title after unlock');
    const hasRename = await cdp.eval(`!!document.querySelector(${JSON.stringify(lockedItem('t-lock-238'))} + ' .chat-action-btn[title="Rename"]')`);
    if (!hasRename) throw new Error('rename must be available once the chat is unlocked');
    return 'correct password unlocks and renders ' + state.msgCount + ' message(s)';
  }
});

scenarios.push({
  id: 239,
  name: 'Global search never surfaces locked chats',
  regression: true,
  mode: null,
  fixtures: {
    threads: [
      { id: 't-lock-239', title: 'Locked needle title', active_leaf_id: 't-lock-239-a1', is_locked: 1 },
      { id: 't-open-239', title: 'Open needle title', active_leaf_id: 't-open-239-a1' }
    ],
    messages: [
      { id: 't-lock-239-u1', thread_id: 't-lock-239', role: 'user', content: 'hidden needle content' },
      { id: 't-lock-239-a1', thread_id: 't-lock-239', role: 'assistant', content: 'locked reply', parent_id: 't-lock-239-u1', model: 'deepseek/deepseek-v4-flash' },
      { id: 't-open-239-u1', thread_id: 't-open-239', role: 'user', content: 'public needle content' },
      { id: 't-open-239-a1', thread_id: 't-open-239', role: 'assistant', content: 'open reply', parent_id: 't-open-239-u1', model: 'deepseek/deepseek-v4-flash' }
    ],
    chatLocks: [{
      thread_id: 't-lock-239',
      salt: LOCK_SALT,
      hash: lockHash(LOCK_PASSWORD, LOCK_SALT, LOCK_ITERATIONS),
      iterations: LOCK_ITERATIONS
    }]
  },
  async body({ cdp }) {
    await showChat();
    await cdp.waitFor('document.querySelector(".search-wrap:not(.in-panel) .search-input") !== null', 15000, 300, 'global search input');
    await cdp.type('.search-wrap:not(.in-panel) .search-input', 'needle');
    await cdp.waitFor('document.querySelectorAll(".search-result-item").length > 0', 20000, 300, 'search results');
    await sleep(500);
    const info = await cdp.eval(`(() => {
      const items = [...document.querySelectorAll('.search-result-item')];
      return {
        threadIds: items.map(i => i.getAttribute('data-thread-id')),
        text: items.map(i => i.textContent).join('|')
      };
    })()`);
    if (info.threadIds.indexOf('t-lock-239') >= 0) throw new Error('search leaked the locked chat: ' + info.text);
    if (info.threadIds.indexOf('t-open-239') < 0) throw new Error('search must still find unlocked chats: ' + info.text);
    return 'global search finds t-open-239 only; locked t-lock-239 never appears';
  }
});

scenarios.push({
  id: 240,
  name: 'WM_LOAD_THREAD (Main->ChatWindow IPC) cannot bypass the lock',
  regression: true,
  mode: null,
  fixtures: lockedFixtures('t-lock-240', 'Secret Plan', 'hidden content'),
  async body({ cdp }) {
    await showChat();
    const probe = runProbe('load-thread', ['t-lock-240']);
    if (!probe.hwnd) throw new Error('load-thread probe could not find the chat window');
    await cdp.waitFor('document.getElementById("threadLockOverlay") !== null', 15000, 300, 'overlay after WM_LOAD_THREAD');
    const state = await cdp.eval(`(() => ({
      msgs: document.querySelectorAll('#chat-messages .msg').length,
      active: window.activeThreadId,
      postedInit: (window.__posted || []).some(s => s.indexOf('"target":"initChatMode"') >= 0)
    }))()`);
    if (state.msgs !== 0 || state.postedInit)
      throw new Error('WM_LOAD_THREAD bypassed the lock: msgs=' + state.msgs + ' postedInit=' + state.postedInit);
    if (state.active !== 't-lock-240')
      throw new Error('active thread mismatch: ' + state.active);
    return 'WM_LOAD_THREAD shows the lock overlay; no content is posted';
  }
});

scenarios.push({
  id: 241,
  name: 'chatSend is rejected while locked and the DB stays untouched',
  regression: true,
  mode: null,
  fixtures: lockedFixtures('t-lock-241', 'Secret Plan', 'hidden content'),
  async body({ cdp, dbPath }) {
    await showChat();
    await cdp.waitFor('document.querySelector(' + JSON.stringify(lockedItem('t-lock-241')) + ') !== null', 15000, 300, 'locked chat in sidebar');
    await cdp.click(lockedItem('t-lock-241'));
    await cdp.waitFor('document.getElementById("threadLockOverlay") !== null', 15000, 300, 'lock overlay');
    await cdp.eval(`window.chrome.webview.postMessage(JSON.stringify({ action: 'chatSend', message: 'leak attempt' })); true`);
    await cdp.waitFor('document.querySelector("#chat-messages .error-banner") !== null && document.querySelector("#chat-messages .error-banner").textContent.indexOf("locked") >= 0', 15000, 300, 'lock rejection banner');
    const rows = seed.query(dbPath, 'SELECT COUNT(*) AS c FROM messages WHERE thread_id = ?', ['t-lock-241']);
    if (rows[0].c !== 2) throw new Error('message count changed while locked: ' + rows[0].c);
    return 'chatSend rejected with a "locked" error; DB still has exactly 2 messages';
  }
});

scenarios.push({
  id: 242,
  name: 'Streams never paint into locked chats and API logs redact locked bodies',
  regression: true,
  mode: null,
  noApp: true,
  async body() {
    const streamHandler = fs.readFileSync(path.join(launcher.REPO_ROOT, 'chat', 'streaming', 'StreamHandler.ahk'), 'utf8');
    if (!/ThreadLockService\.IsLocked\(requestParams\["_streamThreadId"\]\)/.test(streamHandler))
      throw new Error('_shouldPostStreamToUI lock gate missing');
    for (const f of ['chat/streaming/StreamCompletion.ahk', 'chat/streaming/StreamError.ahk']) {
      const src = fs.readFileSync(path.join(launcher.REPO_ROOT, f), 'utf8');
      if (!src.includes('"<hidden: locked chat>"')) throw new Error(f + ' API-log redaction missing');
      if (!src.includes('ThreadLockService.ShouldRedactContent')) throw new Error(f + ' redaction not gated on lock state');
    }
    return 'in-flight streams stop painting into locked chats; API logs store "<hidden: locked chat>" bodies';
  }
});

scenarios.push({
  id: 243,
  name: 'Deleting a locked chat is blocked until it is unlocked',
  regression: true,
  mode: null,
  fixtures: lockedFixtures('t-lock-243', 'Secret Plan', 'hidden content'),
  async body({ cdp, dbPath }) {
    await showChat();
    await cdp.waitFor('document.querySelector(' + JSON.stringify(lockedItem('t-lock-243')) + ') !== null', 15000, 300, 'locked chat in sidebar');
    await cdp.click(lockedItem('t-lock-243'));
    await cdp.waitFor('document.getElementById("threadLockOverlay") !== null', 15000, 300, 'lock overlay');
    await cdp.eval(`window.chrome.webview.postMessage(JSON.stringify({ action: 'sidebarAction', subAction: 'deleteThread', threadId: 't-lock-243' })); true`);
    await cdp.waitFor('document.querySelector("#chat-messages .error-banner") !== null && document.querySelector("#chat-messages .error-banner").textContent.indexOf("locked") >= 0', 15000, 300, 'delete rejection banner');
    const rows = seed.query(dbPath, 'SELECT is_deleted FROM chat_threads WHERE id = ?', ['t-lock-243']);
    if (!rows.length || rows[0].is_deleted !== 0) throw new Error('locked chat was deleted without the password');
    return 'deleteThread on a locked chat is rejected; the thread is untouched';
  }
});

scenarios.push({
  id: 244,
  name: 'Unlock persists for the session across thread switches (and stays locked in the DB)',
  regression: true,
  mode: null,
  fixtures: {
    threads: [
      { id: 't-lock-244', title: 'Secret Plan', active_leaf_id: 't-lock-244-a1', is_locked: 1 },
      { id: 't-open-244', title: 'Open Chat', active_leaf_id: 't-open-244-a1' }
    ],
    messages: [
      { id: 't-lock-244-u1', thread_id: 't-lock-244', role: 'user', content: 'hidden content' },
      { id: 't-lock-244-a1', thread_id: 't-lock-244', role: 'assistant', content: 'locked reply', parent_id: 't-lock-244-u1', model: 'deepseek/deepseek-v4-flash' },
      { id: 't-open-244-u1', thread_id: 't-open-244', role: 'user', content: 'open content' },
      { id: 't-open-244-a1', thread_id: 't-open-244', role: 'assistant', content: 'open reply', parent_id: 't-open-244-u1', model: 'deepseek/deepseek-v4-flash' }
    ],
    chatLocks: [{
      thread_id: 't-lock-244',
      salt: LOCK_SALT,
      hash: lockHash(LOCK_PASSWORD, LOCK_SALT, LOCK_ITERATIONS),
      iterations: LOCK_ITERATIONS
    }]
  },
  async body({ cdp, dbPath }) {
    await showChat();
    await cdp.waitFor('document.querySelector(' + JSON.stringify(lockedItem('t-lock-244')) + ') !== null', 15000, 300, 'locked chat in sidebar');
    await cdp.click(lockedItem('t-lock-244'));
    await cdp.waitFor('document.getElementById("threadLockOverlay") !== null', 15000, 300, 'lock overlay');
    await cdp.type('#lockPasswordInput', LOCK_PASSWORD);
    await cdp.click('#lockUnlockBtn');
    await cdp.waitFor('document.querySelectorAll("#chat-messages .msg").length >= 1', 30000, 300, 'locked chat renders');
    // Switch away and back: no password prompt should appear again.
    await cdp.click(lockedItem('t-open-244'));
    await cdp.waitFor('window.activeThreadId === "t-open-244" && document.querySelectorAll("#chat-messages .msg").length >= 1', 15000, 300, 'open chat renders');
    await cdp.click(lockedItem('t-lock-244'));
    await cdp.waitFor('window.activeThreadId === "t-lock-244" && document.getElementById("threadLockOverlay") === null && document.querySelectorAll("#chat-messages .msg").length >= 1', 15000, 300, 'locked chat re-renders without prompt');
    await cdp.waitFor(`window._threadMeta['t-lock-244'] && window._threadMeta['t-lock-244'].title === 'Secret Plan'`, 15000, 300, 'real title stays after re-render');
    const rows = seed.query(dbPath, 'SELECT is_locked FROM chat_threads WHERE id = ?', ['t-lock-244']);
    if (!rows.length || rows[0].is_locked !== 1) throw new Error('unlock must NOT clear the DB lock flag');
    return 'session unlock survives thread switches; is_locked stays 1 in the DB';
  }
});

scenarios.push({
  id: 245,
  name: 'Password change and removal require the current password',
  regression: true,
  mode: null,
  fixtures: lockedFixtures('t-lock-245', 'Secret Plan', 'hidden content'),
  async body({ cdp, dbPath }) {
    await showChat();
    await cdp.waitFor('document.querySelector(' + JSON.stringify(lockedItem('t-lock-245')) + ') !== null', 15000, 300, 'locked chat in sidebar');
    await cdp.click(lockedItem('t-lock-245'));
    await cdp.waitFor('document.getElementById("threadLockOverlay") !== null', 15000, 300, 'lock overlay');
    await cdp.type('#lockPasswordInput', LOCK_PASSWORD);
    await cdp.click('#lockUnlockBtn');
    await cdp.waitFor('document.querySelectorAll("#chat-messages .msg").length >= 1', 30000, 300, 'locked chat renders');

    const openLockMenuEval = `(() => {
      const item = document.querySelector(${JSON.stringify(lockedItem('t-lock-245'))});
      const btn = item && item.querySelector('.chat-action-btn[title="Lock options"]');
      if (!btn) return false;
      btn.click();
      return true;
    })()`;

    // Change: current + new password via the lock menu.
    if (!(await cdp.eval(openLockMenuEval))) throw new Error('Lock options button not found in the sidebar');
    await cdp.waitFor('document.getElementById("lockMenuDropdown") !== null', 5000, 300, 'lock menu');
    await cdp.click('#lockMenuDropdown .lock-menu-item[data-action="change"]');
    await cdp.waitFor('document.getElementById("threadLockModal") !== null', 10000, 300, 'change-lock modal');
    await cdp.waitFor('document.getElementById("lockModalSave") && !document.getElementById("lockModalSave").disabled', 10000, 300, 'save enabled after lock info loads');
    await cdp.type('#lockModalCurrent', LOCK_PASSWORD);
    await cdp.type('#lockModalNew', 'new secret');
    await cdp.type('#lockModalConfirm', 'new secret');
    await cdp.click('#lockModalSave');
    await cdp.waitFor('document.getElementById("threadLockModal") === null', 45000, 400, 'modal closes after password change');
    const afterChange = seed.query(dbPath, 'SELECT hash FROM chat_locks WHERE thread_id = ?', ['t-lock-245']);
    if (!afterChange.length) throw new Error('lock row missing after change');
    if (afterChange[0].hash === lockHash(LOCK_PASSWORD, LOCK_SALT, LOCK_ITERATIONS))
      throw new Error('password hash did not change');

    // Remove: current password only, again via the lock menu.
    if (!(await cdp.eval(openLockMenuEval))) throw new Error('Lock options button not found after password change');
    await cdp.waitFor('document.getElementById("lockMenuDropdown") !== null', 5000, 300, 'lock menu (remove)');
    await cdp.click('#lockMenuDropdown .lock-menu-item[data-action="change"]');
    await cdp.waitFor('document.getElementById("threadLockModal") !== null', 10000, 300, 'change-lock modal (remove)');
    await cdp.waitFor('document.getElementById("lockModalSave") && !document.getElementById("lockModalSave").disabled', 10000, 300, 'save enabled after lock info loads (remove)');
    await cdp.type('#lockModalCurrent', 'new secret');
    await cdp.click('#lockModalRemove');
    await cdp.waitFor('document.getElementById("threadLockModal") === null', 45000, 400, 'modal closes after removal');

    const afterRemove = seed.query(dbPath, 'SELECT COUNT(*) AS c FROM chat_locks WHERE thread_id = ?', ['t-lock-245']);
    if (afterRemove[0].c !== 0) throw new Error('lock row still exists after removal');
    const flags = seed.query(dbPath, 'SELECT is_locked FROM chat_threads WHERE id = ?', ['t-lock-245']);
    if (flags[0].is_locked !== 0) throw new Error('is_locked still 1 after removal');
    await cdp.waitFor(`window._threadMeta['t-lock-245'] && window._threadMeta['t-lock-245'].title === 'Secret Plan'`, 15000, 300, 'real title restored after removal');
    return 'password changed (new hash stored) and removed (lock row gone, title restored)';
  }
});

scenarios.push({
  id: 246,
  name: 'Lock options menu: Lock/Unlock/Change states and the relock flow',
  regression: true,
  mode: null,
  fixtures: {
    threads: [
      { id: 't-lock-246', title: 'Secret Plan', active_leaf_id: 't-lock-246-a1', is_locked: 1 },
      { id: 't-open-246', title: 'Open Chat', active_leaf_id: 't-open-246-a1' }
    ],
    messages: [
      { id: 't-lock-246-u1', thread_id: 't-lock-246', role: 'user', content: 'hidden content' },
      { id: 't-lock-246-a1', thread_id: 't-lock-246', role: 'assistant', content: 'locked reply', parent_id: 't-lock-246-u1', model: 'deepseek/deepseek-v4-flash' },
      { id: 't-open-246-u1', thread_id: 't-open-246', role: 'user', content: 'open content' },
      { id: 't-open-246-a1', thread_id: 't-open-246', role: 'assistant', content: 'open reply', parent_id: 't-open-246-u1', model: 'deepseek/deepseek-v4-flash' }
    ],
    chatLocks: [{
      thread_id: 't-lock-246',
      salt: LOCK_SALT,
      hash: lockHash(LOCK_PASSWORD, LOCK_SALT, LOCK_ITERATIONS),
      iterations: LOCK_ITERATIONS
    }]
  },
  async body({ cdp }) {
    const openMenu = (id) => `(() => {
      const item = document.querySelector(${JSON.stringify(lockedItem(id))});
      const btn = item && item.querySelector('.chat-action-btn[title="Lock options"]');
      if (!btn) return false;
      btn.click();
      return true;
    })()`;
    const menuStates = `(() => {
      const dd = document.getElementById('lockMenuDropdown');
      const items = {};
      dd.querySelectorAll('.lock-menu-item').forEach(function(b) {
        items[b.getAttribute('data-action')] = b.disabled;
      });
      return items;
    })()`;

    await showChat();
    await cdp.waitFor('document.querySelector(' + JSON.stringify(lockedItem('t-lock-246')) + ') !== null', 15000, 300, 'locked chat in sidebar');

    // Locked + hidden: only Unlock Chat and Change are active.
    if (!(await cdp.eval(openMenu('t-lock-246')))) throw new Error('Lock options button not found (locked)');
    await cdp.waitFor('document.getElementById("lockMenuDropdown") !== null', 5000, 300, 'lock menu (locked)');
    let states = await cdp.eval(menuStates);
    if (!states.lock || states.unlock !== false || states.change !== false)
      throw new Error('wrong menu states for a hidden locked chat: ' + JSON.stringify(states));

    // Unlock Chat from the menu -> password prompt -> chat renders with real title.
    await cdp.click('#lockMenuDropdown .lock-menu-item[data-action="unlock"]');
    await cdp.waitFor('document.getElementById("threadLockOverlay") !== null', 15000, 300, 'lock overlay from menu');
    await cdp.type('#lockPasswordInput', LOCK_PASSWORD);
    await cdp.click('#lockUnlockBtn');
    await cdp.waitFor('document.querySelectorAll("#chat-messages .msg").length >= 1', 30000, 300, 'messages render after menu unlock');
    await cdp.waitFor(`window._threadMeta['t-lock-246'] && window._threadMeta['t-lock-246'].title === 'Secret Plan'`, 15000, 300, 'real title after menu unlock');

    // Now Lock Chat is active: relock immediately.
    if (!(await cdp.eval(openMenu('t-lock-246')))) throw new Error('Lock options button not found (unlocked session)');
    await cdp.waitFor('document.getElementById("lockMenuDropdown") !== null', 5000, 300, 'lock menu (session-unlocked)');
    states = await cdp.eval(menuStates);
    if (states.lock !== false || !states.unlock || states.change !== false)
      throw new Error('wrong menu states for a session-unlocked chat: ' + JSON.stringify(states));
    await cdp.click('#lockMenuDropdown .lock-menu-item[data-action="lock"]');
    await cdp.waitFor('document.getElementById("threadLockOverlay") !== null', 15000, 300, 'overlay returns after relock');
    await cdp.waitFor(`window._threadMeta['t-lock-246'] && window._threadMeta['t-lock-246'].title === 'Locked chat'`, 15000, 300, 'title redacted again after relock');

    // Never-locked chat: only Lock Chat is active and it opens the protect modal.
    if (!(await cdp.eval(openMenu('t-open-246')))) throw new Error('Lock options button not found (open chat)');
    await cdp.waitFor('document.getElementById("lockMenuDropdown") !== null', 5000, 300, 'lock menu (open chat)');
    states = await cdp.eval(menuStates);
    if (states.lock !== false || !states.unlock || !states.change)
      throw new Error('wrong menu states for an unlocked chat: ' + JSON.stringify(states));
    await cdp.click('#lockMenuDropdown .lock-menu-item[data-action="lock"]');
    await cdp.waitFor('document.getElementById("threadLockModal") !== null', 10000, 300, 'protect modal opens');
    await cdp.waitFor('document.getElementById("lockModalSave") && !document.getElementById("lockModalSave").disabled', 10000, 300, 'save enabled in protect modal');
    return 'lock menu shows the right three states everywhere; relock and protect flows work';
  }
});

module.exports = scenarios;
