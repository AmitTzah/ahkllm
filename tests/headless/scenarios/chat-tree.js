// scenarios/chat-tree.js - Threads, fork, branch, rename, delete, trash
//
// Part of the headless E2E suite (entry: ../e2e-suite.js). Scenarios launch
// the REAL app against an isolated profile and drive it via WebView2 CDP +
// AHK probes; `noApp: true` scenarios are static source checks. Add new
// scenarios here when a bug is verified/fixed - see ../README.md and
// BUG_HUNT_REPORT.md for the workflow. Scenario ids are stable (the report
// references them); never renumber.
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const launcher = require('../launch');
const seed = require('../seed');
const { sleep, runProbe, showChat, sendChatMessage } = require('./helpers');

const scenarios = [];

scenarios.push({
  id: 1,
  name: 'New chat after deleting active chat starts clean (no leaked per-thread settings)',
  regression: true, // FIXED bug kept as a regression check (new chats must stay clean after deletions)
  mode: null, // refused endpoint: request fails fast, thread + settings still created
  settings: {
    assistants: [{
      id: 'asst-1', name: 'My Assistant', baseModel: 'deepseek/deepseek-v4-flash',
      systemMessage: 'You are a pirate.', systemMessageFile: '', description: '',
      reasoning: 'high', temperature: '0.3', isDefault: false
    }]
  },
  fixtures: {
    threads: [{
      id: 't-leak-1', title: 'Leak Source', active_leaf_id: 'm-leak-1',
      assistant_id: 'asst-1', model_override: 'deepseek/deepseek-v4-pro',
      system_override: 'You are a pirate.', reasoning_override: 'high',
      temperature_override: 0.3, font_size: 21
    }],
    messages: [{ id: 'm-leak-1', thread_id: 't-leak-1', role: 'user', content: 'hello', token_count: 5 }]
  },
  async body({ cdp, dbPath }) {
    await showChat();
    await cdp.waitFor('document.querySelectorAll("#thread-list .chat-item").length > 0', 15000, 300, 'thread list');
    await cdp.click('#thread-list .chat-item');
    await cdp.waitFor('window.activeThreadId === "t-leak-1" && document.querySelectorAll(".msg").length === 1', 15000, 300, 'thread loaded');
    await cdp.eval(`(() => {
      const item = [...document.querySelectorAll('#thread-list .chat-item')].find(i => i.getAttribute('data-chat') === 't-leak-1');
      if (!item) return 'no-item';
      const btn = item.querySelector('.chat-action-btn.danger');
      if (!btn) return 'no-btn';
      btn.click();
      return 'clicked';
    })()`);
    // NOTE: post deleteThread directly (instead of driving the delete-confirm
    // dialog) so this scenario stays focused on the per-thread settings leak and is
    // independent of the delete-confirm flow covered by scenario 23.
    await cdp.eval(`window.chrome.webview.postMessage(JSON.stringify({ action: 'sidebarAction', subAction: 'deleteThread', threadId: 't-leak-1' })); true`);
    await cdp.waitFor('window.activeThreadId === "" && chatMessages.length === 0', 10000, 250, 'chat emptied');
    await sendChatMessage(cdp, 'fresh message');
    await cdp.waitFor('window.activeThreadId !== ""', 10000, 250, 'new thread created');
    const newId = await cdp.eval('window.activeThreadId');
    const rows = seed.query(dbPath,
      'SELECT assistant_id, model_override, system_override, reasoning_override, temperature_override, font_size FROM chat_threads WHERE id = ?',
      [newId]);
    const s = rows[0] || {};
    const leaked = s.assistant_id === 'asst-1' && s.system_override === 'You are a pirate.' &&
      s.reasoning_override === 'high' && Number(s.temperature_override) === 0.3 && Number(s.font_size) === 21;
    if (leaked) throw new Error('new thread leaked deleted chat settings: ' + JSON.stringify(s));
    return 'new thread ' + newId + ' starts clean (no assistant/system/reasoning/temp/font from deleted chat)';
  }
});

scenarios.push({
  id: 2,
  name: 'New chat honors the "New Chats Start With" default (assistant)',
  regression: true, // FIXED bug kept as a regression check (new-chat default must keep applying)
  mode: 'json',
  settings: {
    assistants: [
      { id: 'asst-d', name: 'Default Assistant', baseModel: 'deepseek/deepseek-v4-flash', systemMessage: 'default sys', systemMessageFile: '', description: '', reasoning: 'high', temperature: '0.5' },
      { id: 'asst-x', name: 'Other Assistant', baseModel: 'openai/gpt-5-mini', systemMessage: '', systemMessageFile: '', description: '', reasoning: '', temperature: '' }
    ],
    newChatStartsWith: 'asst:asst-d'
  },
  async body({ cdp, mockLog }) {
    await showChat();
    await cdp.waitFor('typeof window._currentSettings !== "undefined" && typeof window._assistantList !== "undefined"', 15000, 300, 'settings state');
    await cdp.click('#new-chat-btn');
    await cdp.waitFor('window.activeThreadId !== ""', 10000, 250, 'new chat created');
    await sleep(600);
    const assistantName = await cdp.eval('window._currentSettings.assistantName || ""');
    const model = await cdp.eval('window._currentSettings.model || ""');
    if (assistantName !== 'Default Assistant') throw new Error('new chat did not start with the default assistant: ' + assistantName);
    if (model !== 'deepseek/deepseek-v4-flash') throw new Error('unexpected model: ' + model);
    return 'new chat starts with assistant "' + assistantName + '" (' + model + ')';
  }
});

scenarios.push({
  id: 7,
  name: 'Trash retention auto-purges expired trashed threads (wired at startup + timer)',
  regression: true, // FIXED bug kept as a regression check (expired trash must keep purging)
  mode: null,
  settings: { trash: { retentionDays: 1 } },
  fixtures: {
    threads: [{ id: 't-trash-1', title: 'Old Trashed', is_deleted: 1, deleted_at: '2026-07-01 00:00:00' }]
  },
  async body({ cdp, dbPath }) {
    // Static: the purge must now be reachable from production code. The ONLY
    // direct call to the repo implementation stays the ChatDB facade, and
    // Main.ahk must call the facade at startup + on the timer (settings-update
    // re-purge is a bonus, so >= 2 is enough).
    let repoCalls = 0;
    let facadeCalls = 0;
    const scanDirs = ['app', 'api', 'chat', 'shared', 'ipc'];
    const files = [path.join(launcher.REPO_ROOT, 'Main.ahk')];
    const walk = (dir) => {
      for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
        const p = path.join(dir, e.name);
        if (e.isDirectory()) walk(p);
        else if (e.name.endsWith('.ahk')) files.push(p);
      }
    };
    for (const d of scanDirs) walk(path.join(launcher.REPO_ROOT, d));
    for (const f of files) {
      const txt = fs.readFileSync(f, 'utf8');
      repoCalls += (txt.match(/ThreadRepo\.PurgeExpired\(/g) || []).length;
      facadeCalls += (txt.match(/ChatDB\.Thread_PurgeExpired\(/g) || []).length;
    }
    if (repoCalls !== 1) throw new Error('expected exactly 1 direct ThreadRepo.PurgeExpired() call (the ChatDB facade), found ' + repoCalls);
    if (facadeCalls < 2) throw new Error('expected Main.ahk to call ChatDB.Thread_PurgeExpired() at startup + timer, found ' + facadeCalls);
    // Live: an expired trashed thread must be purged during the app run
    // (the startup purge runs before the chat page is ready).
    await sleep(2500);
    const rows = seed.query(dbPath, "SELECT id FROM chat_threads WHERE id='t-trash-1' AND is_deleted=1");
    if (rows.length !== 0) throw new Error('expired trashed thread was not purged');
    return 'PurgeExpired wired via ChatDB facade in Main.ahk; expired trashed thread purged during app run';
  }
});

scenarios.push({
  id: 23,
  name: 'Chat delete confirmation works (chat overlay opens; Delete posts and deletes)',
  regression: true, // FIXED bug kept as a regression check (delete confirm must keep working)
  mode: null,
  settings: {},
  fixtures: {
    threads: [{ id: 't-del-1', title: 'To Delete', active_leaf_id: 'm-del-1' }],
    messages: [{ id: 'm-del-1', thread_id: 't-del-1', role: 'user', content: 'hello' }]
  },
  async body({ cdp, dbPath }) {
    await showChat();
    await cdp.waitFor('document.querySelectorAll("#thread-list .chat-item").length > 0', 15000, 300, 'thread list');
    await cdp.click('#thread-list .chat-item');
    await cdp.waitFor('window.activeThreadId === "t-del-1"', 15000, 300, 'thread loaded');
    await cdp.clearPosted();
    await cdp.eval(`(() => {
      const item = [...document.querySelectorAll('#thread-list .chat-item')].find(i => i.getAttribute('data-chat') === 't-del-1');
      if (!item) return 'no-item';
      const btn = item.querySelector('.chat-action-btn.danger');
      if (!btn) return 'no-btn';
      btn.click();
      return 'clicked';
    })()`);
    await sleep(400);
    const settingsModalOpen = await cdp.eval('(document.getElementById("confirmModal") || {}).classList ? document.getElementById("confirmModal").classList.contains("open") : false');
    const chatOverlay = await cdp.eval('!!document.getElementById("customConfirmOverlay")');
    const overlayMsg = await cdp.text('#customConfirmOverlay') || '';
    if (settingsModalOpen) throw new Error('settings confirmModal opened instead of the chat overlay');
    if (!chatOverlay) throw new Error('customConfirmOverlay did not open');
    if (!overlayMsg.includes('Delete this chat?')) throw new Error('unexpected overlay message: ' + JSON.stringify(overlayMsg));
    await cdp.click('#customConfirmOverlay .yes-confirm-btn');
    await sleep(600);
    const posted = await cdp.postedMessages();
    if (!posted.some((m) => m.includes('deleteThread'))) throw new Error('deleteThread was not posted');
    const alive = seed.query(dbPath, "SELECT id FROM chat_threads WHERE id='t-del-1' AND is_deleted=0").length === 1;
    if (alive) throw new Error('thread survived the delete confirm');
    return 'delete confirm opens the chat overlay with the right message; clicking Delete posts deleteThread and deletes the chat';
  }
});

scenarios.push({
  id: 28,
  name: 'Sidebar inline rename saves on Escape instead of canceling',
  regression: true, // REFUTED: Escape cancels correctly (blur does not fire on DOM removal); kept as a regression check
  mode: null,
  settings: {},
  fixtures: {
    threads: [{ id: 't-ren-1', title: 'Original Title', active_leaf_id: 'm-ren-1' }],
    messages: [{ id: 'm-ren-1', thread_id: 't-ren-1', role: 'user', content: 'hello' }]
  },
  async body({ cdp }) {
    await showChat();
    await cdp.waitFor('document.querySelectorAll("#thread-list .chat-item").length > 0', 15000, 300, 'thread list');
    await cdp.click('#thread-list .chat-item .chat-action-btn[title="Rename"]');
    await cdp.waitFor('document.querySelector("#thread-list .chat-item .chat-name input") !== null', 5000, 200, 'inline rename input');
    // Type a new name without committing.
    await cdp.eval(`(() => {
      const inp = document.querySelector("#thread-list .chat-item .chat-name input");
      if (!inp) return false;
      const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set;
      setter.call(inp, 'Renamed By Escape');
      inp.dispatchEvent(new Event('input', { bubbles: true }));
      return true;
    })()`);
    await cdp.clearPosted();
    // Press Escape: this must CANCEL the rename, not save it.
    await cdp.eval(`(() => {
      const inp = document.querySelector("#thread-list .chat-item .chat-name input");
      if (!inp) return false;
      inp.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true, cancelable: true }));
      return true;
    })()`);
    await sleep(300);
    const posted = await cdp.postedMessages();
    const renamePosted = posted.some((m) => m.includes('renameThread'));
    const shown = await cdp.eval('document.querySelector("#thread-list .chat-item .chat-name").textContent');
    // FIXED/expected: Escape cancels the rename - no renameThread is posted and
    // the original title is restored (the earlier suspicion that blur fires on
    // DOM removal was refuted in WebView2).
    if (renamePosted) throw new Error('Escape still posts renameThread: ' + JSON.stringify(posted.filter((m) => m.includes('renameThread'))));
    if (shown !== 'Original Title') throw new Error('Escape did not restore the original title: ' + JSON.stringify(shown));
    return 'Escape canceled the rename (no renameThread posted); title stays ' + JSON.stringify(shown);
  }
});

scenarios.push({
  id: 30,
  name: 'Deleting a message confirms "data is preserved" but hard-deletes it',
  mode: null,
  regression: true, // FIXED: confirmation now honestly says permanent delete (was "data is preserved" lie),
  settings: {},
  fixtures: {
    threads: [{ id: 't-del-30', title: 'Delete Copy Thread', active_leaf_id: 'm-del-30b' }],
    messages: [
      { id: 'm-del-30a', thread_id: 't-del-30', role: 'user', content: 'first message' },
      { id: 'm-del-30b', thread_id: 't-del-30', role: 'assistant', content: 'reply', model: 'deepseek/deepseek-v4-flash', parent_id: 'm-del-30a' }
    ]
  },
  async body({ cdp, dbPath }) {
    await showChat();
    // Load the seeded thread first - bubbles only render after loadThread.
    await cdp.waitFor('document.querySelectorAll("#thread-list .chat-item").length > 0', 15000, 300, 'thread list');
    await cdp.click('#thread-list .chat-item');
    await cdp.waitFor('document.querySelectorAll("#chat-messages .msg").length >= 2', 15000, 300, 'messages rendered');
    // Delete the user message: the confirm dialog must now honestly warn permanent deletion.
    await cdp.click('#chat-messages .msg:nth-child(1) .msg-action-btn[title="Delete"]');
    await cdp.waitFor('document.getElementById("customConfirmOverlay") !== null', 5000, 200, 'confirm overlay');
    const confirmText = await cdp.eval('document.getElementById("customConfirmOverlay").textContent');
    const saysPreserved = confirmText.indexOf('data is preserved') >= 0;
    await cdp.click('#customConfirmOverlay .yes-confirm-btn');
    await sleep(900); // IPC round trip + DB delete + re-render
    const rows = seed.query(dbPath, "SELECT COUNT(*) AS c FROM messages WHERE id='m-del-30a'");
    const deletedForever = rows[0].c === 0;
    // FIXED: dialog now honestly warns permanent deletion, not data preserved.
    const saysPermanent = confirmText.indexOf('permanently') >= 0 || confirmText.indexOf('cannot be undone') >= 0;
    if (saysPreserved)
      throw new Error('confirmation still claims data is preserved (lie not fixed): ' + JSON.stringify(confirmText.trim()));
    if (!saysPermanent)
      throw new Error('confirmation should warn permanent deletion: ' + JSON.stringify(confirmText.trim()));
    if (!deletedForever)
      throw new Error('message should still be hard-deleted (row gone) but survived: deletedForever=' + deletedForever + ' text=' + JSON.stringify(confirmText.trim()));
    return 'confirm dialog honestly says "' + confirmText.trim() + '" and the message row is permanently gone';
  }
});

scenarios.push({
  id: 38,
  name: 'Chat window title stays stale after renaming a thread and switching to another',
  mode: null,
  settings: {},
  fixtures: {
    threads: [
      { id: 't-title-38a', title: 'Alpha Thread', active_leaf_id: 'm-title-38a' },
      { id: 't-title-38b', title: 'Beta Thread', active_leaf_id: 'm-title-38b' }
    ],
    messages: [
      { id: 'm-title-38a', thread_id: 't-title-38a', role: 'user', content: 'hello alpha' },
      { id: 'm-title-38b', thread_id: 't-title-38b', role: 'user', content: 'hello beta' }
    ]
  },
  async body({ cdp, dbPath }) {
    await showChat();
    const clickItem = (idx) => cdp.eval(`(() => {
      const items = document.querySelectorAll('#thread-list .chat-item');
      if (!items[${idx}]) return false;
      items[${idx}].click();
      return true;
    })()`);
    const clickRename = (idx) => cdp.eval(`(() => {
      const items = document.querySelectorAll('#thread-list .chat-item');
      const btn = items[${idx}] && items[${idx}].querySelector('.chat-action-btn[title="Rename"]');
      if (!btn) return false;
      btn.click();
      return true;
    })()`);
    await cdp.waitFor('document.querySelectorAll("#thread-list .chat-item").length >= 2', 15000, 300, 'thread list');
    // Load thread A, then rename it via the sidebar (this sets the window title).
    await clickItem(0);
    await cdp.waitFor('document.querySelectorAll("#chat-messages .msg").length >= 1', 15000, 300, 'thread A loaded');
    await clickRename(0);
    await cdp.waitFor('document.querySelector("#thread-list .chat-item .chat-name input") !== null', 5000, 200, 'rename input');
    await cdp.type('#thread-list .chat-item .chat-name input', 'Alpha Renamed');
    const inputVal = await cdp.eval('document.querySelector("#thread-list .chat-item .chat-name input") ? document.querySelector("#thread-list .chat-item .chat-name input").value : "(missing)"');
    await cdp.clearPosted();
    await cdp.eval(`(() => {
      const inp = document.querySelector('#thread-list .chat-item .chat-name input');
      if (!inp) return false;
      inp.dispatchEvent(new Event('blur', { bubbles: true }));
      return true;
    })()`);
    await sleep(900); // rename IPC + title update + list refresh
    const postedAfterRename = await cdp.postedMessages();
    if (!postedAfterRename.some((m) => m.includes('renameThread')))
      throw new Error('renameThread was not posted after blur; inputVal=' + JSON.stringify(inputVal) + ' posted=' + JSON.stringify(postedAfterRename));
    const renamedRows = seed.query(dbPath, "SELECT title FROM chat_threads WHERE id='t-title-38a'");
    if (!renamedRows.length || renamedRows[0].title !== 'Alpha Renamed')
      throw new Error('rename did not commit before switching (setup): ' + JSON.stringify(renamedRows));
    // Switch to thread B.
    await clickItem(1);
    await cdp.waitFor('document.querySelectorAll("#chat-messages .msg").length >= 1', 15000, 300, 'thread B loaded');
    await sleep(800);
    const topbarTitle = await cdp.eval('document.querySelector(".title-text") ? document.querySelector(".title-text").textContent : ""');
    const info = runProbe('chat-info');
    // BUG: _LoadThreadAndRefreshUI never updates chatWindow.Title; only
    // renameThread does. After renaming A and switching to B the title bar still
    // shows the renamed A title.
    if (topbarTitle.indexOf('Beta') < 0)
      throw new Error('thread B did not load (setup): topbar=' + JSON.stringify(topbarTitle));
    if ((info.title || '').indexOf('Beta') >= 0)
      throw new Error('window title followed the thread (bug not reproduced): ' + JSON.stringify(info.title));
    return 'topbar shows "' + topbarTitle + '" but the window title is "' + info.title + '" (stale renamed-A title)';
  }
});

scenarios.push({
  id: 44,
  name: 'Forking a chat drops the per-thread font size and Advanced toggles',
  mode: null,
  settings: {},
  fixtures: {
    threads: [{ id: 't-fork-44', title: 'Fork Source', active_leaf_id: 'm-fork-44', font_size: 20 }],
    messages: [{ id: 'm-fork-44', thread_id: 't-fork-44', role: 'user', content: 'fork me' }]
  },
  async body({ cdp, dbPath }) {
    // Seed advanced_toggles on the source thread (the fixtures builder has no
    // column for it) BEFORE loading the thread so the fork must copy both
    // per-thread settings to preserve them.
    const { DatabaseSync } = require('node:sqlite');
    const db = new DatabaseSync(dbPath);
    db.exec("UPDATE chat_threads SET advanced_toggles = '{\"codeExecution\":true,\"webSearch\":true}' WHERE id='t-fork-44'");
    db.close();

    await showChat();
    await cdp.waitFor('document.querySelectorAll("#thread-list .chat-item").length > 0', 15000, 300, 'thread list');
    await cdp.click('#thread-list .chat-item');
    await cdp.waitFor('document.querySelectorAll("#chat-messages .msg").length >= 1', 15000, 300, 'thread loaded');
    await sleep(700);
    const fontBefore = await cdp.eval('document.getElementById("font-size-display").textContent');
    if (fontBefore !== '20px')
      throw new Error('source thread font size not applied (setup): ' + JSON.stringify(fontBefore));
    // Fork the chat from the user message.
    await cdp.click('#chat-messages .msg .msg-action-btn[title="Fork"]');
    await cdp.waitFor('window.activeThreadId !== "t-fork-44"', 15000, 300, 'fork created');
    const newId = await cdp.eval('window.activeThreadId');
    await sleep(700);
    const rows = seed.query(dbPath, 'SELECT font_size, advanced_toggles FROM chat_threads WHERE id = ?', [newId]);
    const s = rows[0] || {};
    const fontAfter = await cdp.eval('document.getElementById("font-size-display").textContent');
    // BUG: TreeRepo._CopyThreadSettings copies model/system/reasoning/temperature/
    // assistant but NOT font_size or advanced_toggles, so the fork starts at the
    // defaults (17px, toggles off) instead of inheriting the source thread.
    if (Number(s.font_size) === 20 && String(s.advanced_toggles || '').indexOf('codeExecution') >= 0 && fontAfter === '20px')
      throw new Error('fork kept the source settings (bug not reproduced): ' + JSON.stringify(s) + ' font=' + fontAfter);
    return 'source thread font_size=20 + advanced_toggles set; fork id=' + newId +
      ' has font_size=' + s.font_size + ' advanced_toggles=' + JSON.stringify(s.advanced_toggles) +
      ' and the UI shows ' + fontAfter + ' instead of 20px';
  }
});

scenarios.push({
  id: 48,
  name: 'Forking a chat resets the token/cost stats (active_path_tokens and cumulative counters are not copied or recomputed)',
  mode: null,
  settings: {},
  fixtures: {
    threads: [{ id: 't-stats-48', title: 'Stats Source', active_leaf_id: 'm-stats-48b' }],
    messages: [
      { id: 'm-stats-48a', thread_id: 't-stats-48', role: 'user', content: 'hello', token_count: 10, active_path_tokens: 10 },
      { id: 'm-stats-48b', thread_id: 't-stats-48', role: 'assistant', content: 'hi', model: 'deepseek/deepseek-v4-flash', parent_id: 'm-stats-48a', token_count: 20, active_path_tokens: 40 }
    ]
  },
  async body({ cdp, dbPath }) {
    // Give the source thread real cumulative usage stats (the fixtures builder
    // defaults them to 0), matching what MessageRepo.Insert accumulates.
    const { DatabaseSync } = require('node:sqlite');
    const db = new DatabaseSync(dbPath);
    db.exec("UPDATE chat_threads SET cumulative_input_tokens=10, cumulative_output_tokens=20, cumulative_cached_tokens=2, cumulative_cost=0.5, cumulative_input_cost=0.3, cumulative_cached_input_cost=0.01, cumulative_output_cost=0.2 WHERE id='t-stats-48'");
    db.close();

    await showChat();
    await cdp.waitFor('document.querySelectorAll("#thread-list .chat-item").length > 0', 15000, 300, 'thread list');
    await cdp.click('#thread-list .chat-item');
    await cdp.waitFor('document.querySelectorAll("#chat-messages .msg").length >= 2', 15000, 300, 'thread loaded');
    await sleep(700);
    const sourceBar = await cdp.eval('document.getElementById("tokenBar").textContent');
    if (String(sourceBar).indexOf('$0.50') < 0)
      throw new Error('source token bar missing $0.50 (setup): ' + JSON.stringify(sourceBar));
    // Fork the chat from the user message.
    await cdp.click('#chat-messages .msg:nth-child(1) .msg-action-btn[title="Fork"]');
    await cdp.waitFor('window.activeThreadId !== "t-stats-48"', 15000, 300, 'fork created');
    const newId = await cdp.eval('window.activeThreadId');
    await sleep(800);
    const forkBar = await cdp.eval('document.getElementById("tokenBar").textContent');
    const forkRow = seed.query(dbPath, 'SELECT cumulative_input_tokens, cumulative_output_tokens, cumulative_cost, active_leaf_id FROM chat_threads WHERE id = ?', [newId])[0] || {};
    const leafStats = forkRow.active_leaf_id
      ? seed.query(dbPath, 'SELECT active_path_tokens FROM messages WHERE id = ?', [forkRow.active_leaf_id])[0] || {}
      : {};
    // BUG: TreeRepo.ForkThread copies messages but neither the thread's
    // cumulative_* counters nor the leaf's active_path_tokens (and never calls
    // _RecomputeActivePath), so the fork's token bar and cost reset to zero.
    if (String(forkBar).indexOf('$0.50') >= 0)
      throw new Error('fork kept the cost stats (bug not reproduced): ' + JSON.stringify(forkBar));
    return 'source token bar: ' + JSON.stringify(sourceBar) + '; fork token bar: ' + JSON.stringify(forkBar) +
      ' (cumulative_cost=' + forkRow.cumulative_cost + ', leaf active_path_tokens=' + leafStats.active_path_tokens + ')';
  }
});

scenarios.push({
  id: 54,
  name: 'Chat-header token bar contract on branch switch: context follows the active path, cumulative cost/tokens stay',
  regression: true, // REFUTED: the contract HOLDS (context 65->80, cost/totals unchanged); kept as a regression check
  mode: null,
  settings: {},
  fixtures: {
    threads: [{ id: 't-br-54', title: 'Branch Tokens', active_leaf_id: 'm-br-a2' }],
    messages: [
      { id: 'm-br-u1', thread_id: 't-br-54', role: 'user', content: 'first', token_count: 10, active_path_tokens: 10 },
      { id: 'm-br-a1', thread_id: 't-br-54', role: 'assistant', content: 'reply A', model: 'deepseek/deepseek-v4-flash', parent_id: 'm-br-u1', sibling_group: 'sg-br', sibling_index: 0, token_count: 20, active_path_tokens: 30 },
      { id: 'm-br-u2', thread_id: 't-br-54', role: 'user', content: 'follow A', parent_id: 'm-br-a1', token_count: 5, active_path_tokens: 35 },
      { id: 'm-br-a2', thread_id: 't-br-54', role: 'assistant', content: 'answer A', model: 'deepseek/deepseek-v4-flash', parent_id: 'm-br-u2', token_count: 30, active_path_tokens: 65 },
      { id: 'm-br-a1b', thread_id: 't-br-54', role: 'assistant', content: 'reply B', model: 'deepseek/deepseek-v4-flash', parent_id: 'm-br-u1', sibling_group: 'sg-br', sibling_index: 1, token_count: 20, active_path_tokens: 30 },
      { id: 'm-br-u2b', thread_id: 't-br-54', role: 'user', content: 'follow B', parent_id: 'm-br-a1b', token_count: 10, active_path_tokens: 40 },
      { id: 'm-br-a2b', thread_id: 't-br-54', role: 'assistant', content: 'answer B', model: 'deepseek/deepseek-v4-flash', parent_id: 'm-br-u2b', token_count: 40, active_path_tokens: 80 }
    ]
  },
  async body({ cdp, dbPath }) {
    // Shared per-thread cumulative ledger (tooltip: "across all conversation
    // branches") - must NOT change on branch switch.
    const { DatabaseSync } = require('node:sqlite');
    const db = new DatabaseSync(dbPath);
    db.exec("UPDATE chat_threads SET cumulative_input_tokens=25, cumulative_output_tokens=110, cumulative_cached_tokens=4, cumulative_cost=1.5, cumulative_input_cost=0.5, cumulative_cached_input_cost=0.1, cumulative_output_cost=1.0 WHERE id='t-br-54'");
    db.close();

    await showChat();
    await cdp.waitFor('document.querySelectorAll("#thread-list .chat-item").length > 0', 15000, 300, 'thread list');
    await cdp.click('#thread-list .chat-item');
    await cdp.waitFor('document.querySelectorAll("#chat-messages .msg").length >= 4', 15000, 300, 'branch A loaded');
    await sleep(700);
    const barA = await cdp.eval('document.getElementById("tokenBar").textContent');
    if (String(barA).indexOf('65') < 0 || String(barA).indexOf('$1.50') < 0)
      throw new Error('branch A header values missing (setup): ' + JSON.stringify(barA));
    // Switch to branch B via the nav arrow on the shared assistant message.
    await cdp.click('#chat-messages .msg .msg-action-btn[title="Next branch"]');
    await cdp.waitFor('chatMessages.length >= 4 && chatMessages[3] && chatMessages[3].id === "m-br-a2b"', 15000, 300, 'branch B loaded');
    await sleep(700);
    const barB = await cdp.eval('document.getElementById("tokenBar").textContent');
    const costB = await cdp.eval('document.querySelector("#tokenBar .tu-item:last-child .tu-val").textContent');
    const contextB = await cdp.eval('document.querySelector("#tokenBar .tu-item:first-child .tu-val").textContent');
    // CONTRACT: context follows the active path (65 -> 80) while the cumulative
    // cost and totals stay per-thread. Throw with observed values if violated.
    if (String(contextB).indexOf('80') < 0 || costB !== '$1.50')
      throw new Error('token bar contract violated on branch switch: branch A bar=' + JSON.stringify(barA) +
        ' branch B bar=' + JSON.stringify(barB) + ' contextB=' + JSON.stringify(contextB) + ' costB=' + JSON.stringify(costB));
    return 'branch A bar=' + JSON.stringify(barA) + ' -> branch B bar=' + JSON.stringify(barB) +
      ' (context ' + JSON.stringify(contextB) + ', cost ' + costB + ' - contract holds)';
  }
});

scenarios.push({
  id: 55,
  name: 'Branch switch / search navigation land on the OLDEST continuation while the tree modal lands on the newest (header context disagrees)',
  mode: null,
  settings: {},
  fixtures: {
    threads: [{ id: 't-br-55', title: 'Multi-Child Branch', active_leaf_id: 'm-br-55-a2x' }],
    messages: [
      { id: 'm-br-55-u1', thread_id: 't-br-55', role: 'user', content: 'first', token_count: 10, active_path_tokens: 10, created_at: '2026-08-01 09:00:00' },
      { id: 'm-br-55-a1', thread_id: 't-br-55', role: 'assistant', content: 'reply A', model: 'deepseek/deepseek-v4-flash', parent_id: 'm-br-55-u1', sibling_group: 'sg-55', sibling_index: 0, token_count: 20, active_path_tokens: 30, created_at: '2026-08-01 09:01:00' },
      { id: 'm-br-55-u2', thread_id: 't-br-55', role: 'user', content: 'follow A1', parent_id: 'm-br-55-a1', token_count: 5, active_path_tokens: 35, created_at: '2026-08-01 09:02:00' },
      { id: 'm-br-55-a2', thread_id: 't-br-55', role: 'assistant', content: 'ans A1', model: 'deepseek/deepseek-v4-flash', parent_id: 'm-br-55-u2', token_count: 30, active_path_tokens: 65, created_at: '2026-08-01 09:03:00' },
      { id: 'm-br-55-u2x', thread_id: 't-br-55', role: 'user', content: 'follow A2', parent_id: 'm-br-55-a1', token_count: 10, active_path_tokens: 40, created_at: '2026-08-01 10:00:00' },
      { id: 'm-br-55-a2x', thread_id: 't-br-55', role: 'assistant', content: 'ans A2', model: 'deepseek/deepseek-v4-flash', parent_id: 'm-br-55-u2x', token_count: 40, active_path_tokens: 90, created_at: '2026-08-01 10:01:00' },
      { id: 'm-br-55-a1b', thread_id: 't-br-55', role: 'assistant', content: 'reply B', model: 'deepseek/deepseek-v4-flash', parent_id: 'm-br-55-u1', sibling_group: 'sg-55', sibling_index: 1, token_count: 20, active_path_tokens: 30, created_at: '2026-08-01 09:05:00' },
      { id: 'm-br-55-u2b', thread_id: 't-br-55', role: 'user', content: 'follow B1', parent_id: 'm-br-55-a1b', token_count: 10, active_path_tokens: 40, created_at: '2026-08-01 09:06:00' },
      { id: 'm-br-55-a2b', thread_id: 't-br-55', role: 'assistant', content: 'ans B1', model: 'deepseek/deepseek-v4-flash', parent_id: 'm-br-55-u2b', token_count: 30, active_path_tokens: 70, created_at: '2026-08-01 09:07:00' },
      { id: 'm-br-55-u2bx', thread_id: 't-br-55', role: 'user', content: 'follow B2', parent_id: 'm-br-55-a1b', token_count: 15, active_path_tokens: 45, created_at: '2026-08-01 11:00:00' },
      { id: 'm-br-55-a2bx', thread_id: 't-br-55', role: 'assistant', content: 'ans B2', model: 'deepseek/deepseek-v4-flash', parent_id: 'm-br-55-u2bx', token_count: 50, active_path_tokens: 95, created_at: '2026-08-01 11:01:00' }
    ]
  },
  async body({ cdp }) {
    await showChat();
    await cdp.waitFor('document.querySelectorAll("#thread-list .chat-item").length > 0', 15000, 300, 'thread list');
    await cdp.click('#thread-list .chat-item');
    await cdp.waitFor('chatMessages.length >= 4 && chatMessages[chatMessages.length - 1].id === "m-br-55-a2x"', 15000, 300, 'newest continuation loaded');
    await sleep(700);
    const contextStart = await cdp.eval('document.querySelector("#tokenBar .tu-item:first-child .tu-val").textContent');
    if (String(contextStart).indexOf('90') < 0)
      throw new Error('active continuation context missing (setup): ' + JSON.stringify(contextStart));
    // Branch-nav switch to the sibling (a1 -> a1b). a1b has TWO continuations:
    // u2b (oldest, leaf context 70) and u2bx (newest, leaf context 95).
    await cdp.click('#chat-messages .msg .msg-action-btn[title="Next branch"]');
    await cdp.waitFor('chatMessages.length >= 4 && chatMessages[chatMessages.length - 1].id !== "m-br-55-a2x"', 15000, 300, 'branch switched');
    await sleep(700);
    const contextSwitch = await cdp.eval('document.querySelector("#tokenBar .tu-item:first-child .tu-val").textContent');
    const leafAfterSwitch = await cdp.eval('chatMessages[chatMessages.length - 1] ? chatMessages[chatMessages.length - 1].id : ""');
    // BUG: _WalkToLeaf picks ORDER BY created_at LIMIT 1 -> the OLDEST child
    // (a2b, context 70) instead of the newest continuation (a2bx, context 95)
    // that the tree modal's _findDefaultLeaf would pick.
    if (leafAfterSwitch === 'm-br-55-a2bx' && String(contextSwitch).indexOf('95') >= 0)
      throw new Error('branch switch landed on the newest continuation (bug not reproduced): leaf=' + leafAfterSwitch + ' context=' + contextSwitch);
    // Tree modal navigation to the SAME node must land on the newest leaf (95) -
    // proving the two navigation paths disagree.
    await cdp.click('#treeBtn');
    await cdp.waitFor('typeof window._treeData !== "undefined" && window._treeData.length > 0', 15000, 300, 'tree data');
    await cdp.waitFor('document.querySelector(\'.tree-node[data-target="m-br-55-a1b"]\') !== null', 15000, 300, 'tree node');
    await cdp.click('.tree-node[data-target="m-br-55-a1b"]');
    await cdp.waitFor('chatMessages[chatMessages.length - 1] && chatMessages[chatMessages.length - 1].id === "m-br-55-a2bx"', 15000, 300, 'tree navigated to newest');
    await sleep(700);
    const contextTree = await cdp.eval('document.querySelector("#tokenBar .tu-item:first-child .tu-val").textContent');
    return 'branch-nav switch from a1 landed on leaf ' + leafAfterSwitch + ' (context ' + JSON.stringify(contextSwitch) +
      ', oldest) while the tree modal lands on m-br-55-a2bx (context ' + JSON.stringify(contextTree) + ', newest)';
  }
});

scenarios.push({
  id: 58,
  name: 'Forking a chat drops the thread\'s folder (the copy lands in Unfiled)',
  mode: null,
  settings: {},
  fixtures: {
    folders: [{ id: 'f-fork-58', name: 'My Folder' }],
    threads: [{ id: 't-fork-58', title: 'Forked Source', active_leaf_id: 'm-fork-58', folder_id: 'f-fork-58' }],
    messages: [{ id: 'm-fork-58', thread_id: 't-fork-58', role: 'user', content: 'fork me' }]
  },
  async body({ cdp, dbPath }) {
    await showChat();
    await cdp.waitFor('document.querySelectorAll("#thread-list .chat-item").length > 0', 15000, 300, 'thread list');
    await cdp.click('#thread-list .chat-item');
    await cdp.waitFor('document.querySelectorAll("#chat-messages .msg").length >= 1', 15000, 300, 'thread loaded');
    await sleep(500);
    await cdp.click('#chat-messages .msg .msg-action-btn[title="Fork"]');
    await cdp.waitFor('window.activeThreadId !== "t-fork-58"', 15000, 300, 'fork created');
    const newId = await cdp.eval('window.activeThreadId');
    await sleep(500);
    const rows = seed.query(dbPath, 'SELECT folder_id FROM chat_threads WHERE id = ?', [newId]);
    const folder = rows[0] && rows[0].folder_id;
    // BUG: TreeRepo._CopyThreadSettings copies settings but never folder_id, so
    // the forked thread appears in Unfiled instead of the source's folder.
    if (folder === 'f-fork-58')
      throw new Error('fork kept the folder (bug not reproduced): folder=' + folder);
    return 'source thread is in folder f-fork-58; fork id=' + newId + ' has folder_id=' + JSON.stringify(folder) + ' (Unfiled)';
  }
});

module.exports = scenarios;
