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
  name: 'Chat window title follows the active thread after a rename + switch',
  regression: true, // FIXED bug kept as a regression check (switching threads must update the window title)
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
    // FIXED (bug #38): _LoadThreadAndRefreshUI now updates chatWindow.Title
    // from the active thread, so after renaming A and switching to B the title
    // bar follows the newly active thread.
    if (topbarTitle.indexOf('Beta') < 0)
      throw new Error('thread B did not load (setup): topbar=' + JSON.stringify(topbarTitle));
    if ((info.title || '').indexOf('Beta') < 0)
      throw new Error('window title did not follow the thread switch: ' + JSON.stringify(info.title) + ' topbar=' + JSON.stringify(topbarTitle));
    return 'window title follows the active thread: "' + info.title + '"';
  }
});

scenarios.push({
  id: 44,
  name: 'Forking a chat drops the per-thread font size and Advanced toggles',
  mode: null,
  regression: true, // FIXED: fork now inherits font_size and advanced_toggles (was dropped),
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
    // FIXED: TreeRepo._CopyThreadSettings now copies font_size and advanced_toggles
    if (Number(s.font_size) !== 20 || String(s.advanced_toggles || '').indexOf('codeExecution') < 0 || fontAfter !== '20px')
      throw new Error('fork did not keep source settings (fix broken): ' + JSON.stringify(s) + ' font=' + fontAfter);
    return 'source thread font_size=20 + advanced_toggles set; fork id=' + newId +
      ' correctly has font_size=' + s.font_size + ' advanced_toggles=' + JSON.stringify(s.advanced_toggles) +
      ' and the UI shows ' + fontAfter;
  }
});

scenarios.push({
  id: 48,
  name: 'Forking a chat keeps the token/cost stats (active_path_tokens and cumulative counters are copied)',
  regression: true, // FIXED bug kept as a regression check (forks must inherit context tokens and cumulative cost)
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
    // FIXED (bug #48): TreeRepo.ForkThread copies each message's
    // active_path_tokens and carries the source thread's cumulative counters,
    // so the fork's token bar keeps the context + cost stats.
    if (String(forkBar).indexOf('$0.50') < 0)
      throw new Error('fork lost the cost stats (bug #48 not fixed): ' + JSON.stringify(forkBar));
    if (forkRow.cumulative_cost !== 0.5)
      throw new Error('fork did not inherit cumulative_cost: ' + forkRow.cumulative_cost);
    if (leafStats.active_path_tokens !== 10)
      throw new Error('fork leaf active_path_tokens was not copied: ' + leafStats.active_path_tokens);
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
  name: 'Branch switch / search navigation land on the newest continuation (matching the tree modal)',
  regression: true, // FIXED bug kept as a regression check (branch-nav/search must land on the same leaf the tree modal picks)
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
    // FIXED (bug #55): _WalkToLeaf now picks the same leaf the tree modal's
    // _findDefaultLeaf picks (the newest continuation), so branch-nav/search
    // navigation lands on the newest continuation.
    if (leafAfterSwitch !== 'm-br-55-a2bx' || String(contextSwitch).indexOf('95') < 0)
      throw new Error('branch switch did not land on the newest continuation (bug #55 not fixed): leaf=' + leafAfterSwitch + ' context=' + contextSwitch);
    // Tree modal navigation to the SAME node must land on the newest leaf (95) -
    // proving the two navigation paths disagree.
    await cdp.click('#treeBtn');
    await cdp.waitFor('typeof window._treeData !== "undefined" && window._treeData.length > 0', 15000, 300, 'tree data');
    await cdp.waitFor('document.querySelector(\'.tree-node[data-target="m-br-55-a1b"]\') !== null', 15000, 300, 'tree node');
    await cdp.click('.tree-node[data-target="m-br-55-a1b"]');
    await cdp.waitFor('chatMessages[chatMessages.length - 1] && chatMessages[chatMessages.length - 1].id === "m-br-55-a2bx"', 15000, 300, 'tree navigated to newest');
    await sleep(700);
    const contextTree = await cdp.eval('document.querySelector("#tokenBar .tu-item:first-child .tu-val").textContent');
    if (String(contextTree).indexOf('95') < 0)
      throw new Error('tree modal did not land on the newest continuation: ' + JSON.stringify(contextTree));
    return 'branch-nav switch from a1 landed on leaf ' + leafAfterSwitch + ' (context ' + JSON.stringify(contextSwitch) +
      ') and the tree modal lands on m-br-55-a2bx (context ' + JSON.stringify(contextTree) + ') - both newest';
  }
});

scenarios.push({
  id: 58,
  name: 'Forking a chat keeps the thread\'s folder',
  regression: true, // FIXED bug kept as a regression check (forks must stay in the source folder)
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
    // FIXED (bug #58): _CopyThreadSettings now copies folder_id, so the fork
    // appears in the source thread's folder.
    if (folder !== 'f-fork-58')
      throw new Error('fork did not keep the source folder (bug #58 not fixed): folder=' + JSON.stringify(folder));
    return 'source thread is in folder f-fork-58; fork id=' + newId + ' has folder_id=' + JSON.stringify(folder) + ' (same folder)';
  }
});

scenarios.push({
  id: 113,
  name: 'Forking at a message drops the deeper branches below off-path siblings (tree copy is one level deep)',
  regression: true, // FIXED bug kept as a regression check (forks must copy full off-path subtrees)
  mode: null,
  settings: {},
  fixtures: {
    threads: [{ id: 't-fork-113', title: 'Fork Deep Tree', active_leaf_id: 'm-113-a1' }],
    messages: [
      // Active path: u1 -> a1 (fork point). a1b is an off-path sibling with a
      // whole subtree under it (u2b->a2b and a retry pair u2b2->a2b2).
      { id: 'm-113-u1', thread_id: 't-fork-113', role: 'user', content: 'root', token_count: 10, active_path_tokens: 10 },
      { id: 'm-113-a1', thread_id: 't-fork-113', role: 'assistant', content: 'reply A', model: 'deepseek/deepseek-v4-flash', parent_id: 'm-113-u1', sibling_group: 'sg-113', sibling_index: 0, token_count: 20, active_path_tokens: 30 },
      { id: 'm-113-a1b', thread_id: 't-fork-113', role: 'assistant', content: 'reply B', model: 'deepseek/deepseek-v4-flash', parent_id: 'm-113-u1', sibling_group: 'sg-113', sibling_index: 1, token_count: 20, active_path_tokens: 30 },
      // Continuations below the OFF-PATH sibling a1b (normal branch navigation walks into these).
      { id: 'm-113-u2b', thread_id: 't-fork-113', role: 'user', content: 'follow B', parent_id: 'm-113-a1b', sibling_group: 'sg-113b', sibling_index: 0, token_count: 5, active_path_tokens: 35 },
      { id: 'm-113-a2b', thread_id: 't-fork-113', role: 'assistant', content: 'ans B', model: 'deepseek/deepseek-v4-flash', parent_id: 'm-113-u2b', token_count: 30, active_path_tokens: 65 },
      // Retry of "follow B" - another sibling group that only exists below the off-path sibling.
      { id: 'm-113-u2b2', thread_id: 't-fork-113', role: 'user', content: 'follow B retry', parent_id: 'm-113-a1b', sibling_group: 'sg-113b', sibling_index: 1, token_count: 8, active_path_tokens: 38 },
      { id: 'm-113-a2b2', thread_id: 't-fork-113', role: 'assistant', content: 'ans B2', model: 'deepseek/deepseek-v4-flash', parent_id: 'm-113-u2b2', token_count: 25, active_path_tokens: 63 }
    ]
  },
  async body({ cdp, dbPath }) {
    await showChat();
    await cdp.waitFor('document.querySelectorAll("#thread-list .chat-item").length > 0', 15000, 300, 'thread list');
    await cdp.click('#thread-list .chat-item');
    await cdp.waitFor('document.querySelectorAll("#chat-messages .msg").length >= 2', 15000, 300, 'thread loaded');
    await sleep(600);
    // Fork at the assistant message (a1) - the last message on the active path.
    await cdp.click('#chat-messages .msg:nth-child(2) .msg-action-btn[title="Fork"]');
    await cdp.waitFor('window.activeThreadId !== "t-fork-113"', 15000, 300, 'fork created');
    const newId = await cdp.eval('window.activeThreadId');
    await sleep(700);
    const forkMsgs = seed.query(dbPath, "SELECT id, parent_id, sibling_group, content FROM messages WHERE thread_id = ? ORDER BY created_at", [newId]);
    const ids = forkMsgs.map((m) => m.id).sort();
    // FIXED (bug #113): _CopyOffPathSiblings now walks descendants of the
    // copied off-path siblings, so the fork is a faithful copy of the whole
    // conversation tree (u1, a1, a1b + the u2b/a2b and u2b2/a2b2 subtrees).
    if (ids.length !== 7)
      throw new Error('fork message count changed: ' + ids.length + ' -> ' + ids.join(','));
    const deepMissing = ['follow B', 'ans B', 'follow B retry', 'ans B2'].filter((c) => !forkMsgs.some((m) => m.content === c));
    if (deepMissing.length !== 0)
      throw new Error('fork still drops deep branches: missing=' + JSON.stringify(deepMissing) + ' ids=' + JSON.stringify(ids));
    // The visible symptom: switching branch in the fork walks INTO the a1b
    // subtree (path u1 -> a1b -> u2b2 -> a2b2, 4 messages) instead of landing
    // on a dead a1b leaf with no continuation.
    await cdp.click('#chat-messages .msg .msg-action-btn[title="Next branch"]');
    await cdp.waitFor('chatMessages.length === 4 && chatMessages[1] && chatMessages[1].siblingInfo && chatMessages[1].siblingInfo.total === 2', 15000, 300, 'fork switched into the a1b subtree');
    const forkThread = seed.query(dbPath, 'SELECT active_leaf_id FROM chat_threads WHERE id = ?', [newId])[0];
    const a1bFork = seed.query(dbPath, "SELECT id FROM messages WHERE thread_id = ? AND content = 'reply B'", [newId])[0];
    const a1bChildren = seed.query(dbPath, 'SELECT COUNT(*) AS c FROM messages WHERE parent_id = ?', [a1bFork.id])[0].c;
    if (a1bChildren !== 2)
      throw new Error('a1b copy lost its continuations: children=' + a1bChildren);
    if (forkThread.active_leaf_id === a1bFork.id)
      throw new Error('branch switch still lands on the dead a1b leaf');
    const forkCount = forkMsgs.length;
    return 'fork id=' + newId + ' has ' + forkCount + ' messages (' + ids.join(',') +
      ') - deep branches below the off-path sibling a1b are copied; branch switch walks into the subtree (a1b children=' + a1bChildren + ')';
  }
});

scenarios.push({
  id: 114,
  name: 'Hard-deleting a message in a branched tree miscalculates cumulative token counters (rowid order, not tree paths)',
  regression: true, // FIXED bug kept as a regression check (branched-delete recompute must be tree-accurate)
  mode: null,
  settings: {},
  fixtures: {
    threads: [{ id: 't-del-114', title: 'Branch Delete', active_leaf_id: 'm-114-a2',
      cumulative_input_tokens: 550, cumulative_output_tokens: 150, cumulative_cached_tokens: 0, cumulative_cost: 0 }],
    messages: [
      // Branch A (active): u1 -> a1 -> u2 -> a2 (leaf).
      { id: 'm-114-u1', thread_id: 't-del-114', role: 'user', content: 'first', token_count: 100, active_path_tokens: 100 },
      { id: 'm-114-a1', thread_id: 't-del-114', role: 'assistant', content: 'reply A', model: 'deepseek/deepseek-v4-flash', parent_id: 'm-114-u1', token_count: 50, active_path_tokens: 150 },
      { id: 'm-114-u2', thread_id: 't-del-114', role: 'user', content: 'follow A', parent_id: 'm-114-a1', token_count: 100, active_path_tokens: 250 },
      { id: 'm-114-a2', thread_id: 't-del-114', role: 'assistant', content: 'ans A', model: 'deepseek/deepseek-v4-flash', parent_id: 'm-114-u2', token_count: 50, active_path_tokens: 300 },
      // Branch B (off-path): u2b -> a2b (a retry sibling of u2).
      { id: 'm-114-u2b', thread_id: 't-del-114', role: 'user', content: 'follow B', parent_id: 'm-114-a1', token_count: 100, active_path_tokens: 250 },
      { id: 'm-114-a2b', thread_id: 't-del-114', role: 'assistant', content: 'ans B', model: 'deepseek/deepseek-v4-flash', parent_id: 'm-114-u2b', token_count: 50, active_path_tokens: 300 }
    ]
  },
  async body({ cdp, dbPath }) {
    await showChat();
    await cdp.waitFor('document.querySelectorAll("#thread-list .chat-item").length > 0', 15000, 300, 'thread list');
    await cdp.click('#thread-list .chat-item');
    await cdp.waitFor('document.querySelectorAll("#chat-messages .msg").length >= 4', 15000, 300, 'thread loaded');
    await sleep(700);
    // Delete the ACTIVE leaf assistant (a2). It is not on branch B's path.
    await cdp.click('#chat-messages .msg:nth-child(4) .msg-action-btn[title="Delete"]');
    await sleep(300);
    await cdp.waitFor('document.getElementById("customConfirmOverlay") !== null', 5000, 200, 'confirm');
    await cdp.click('#customConfirmOverlay .yes-confirm-btn');
    await sleep(900);

    const thread = seed.query(dbPath, 'SELECT cumulative_input_tokens, cumulative_output_tokens, active_leaf_id FROM chat_threads WHERE id = ?', ['t-del-114'])[0];
    // FIXED (bug #114): _RecomputeCumulativeCounters is tree-accurate - it uses
    // each assistant's prompt ground truth (or its parent's active_path_tokens)
    // instead of a rowid-order running sum. After deleting a2 the remaining API
    // calls are a1 (prompt = u1's 100) and a2b (prompt = u1 100 + a1 50 + u2b
    // 100 = 250) -> 350 input tokens, NOT the buggy 450 (u2's tokens charged to
    // branch B).
    if (Number(thread.cumulative_input_tokens) !== 350)
      throw new Error('cumulative input after branched delete = ' + thread.cumulative_input_tokens + ' (expected the tree-accurate 350)');
    const bar = await cdp.eval('document.getElementById("tokenBar").textContent');
    if (String(bar).indexOf('\u2191 350') < 0)
      throw new Error('header input tokens do not show the corrected 350: ' + JSON.stringify(bar));
    return 'deleted leaf a2 from a branched tree: cumulative_input_tokens=' + thread.cumulative_input_tokens +
      ' (tree-accurate 350; the buggy rowid-order recompute charged 450) and the header shows the corrected total';
  }
});

scenarios.push({
  id: 124,
  name: 'Conversation tree modal says "Viewing active path" but counts every node in the tree (off-path branches included)',
  regression: true, // FIXED bug kept as a regression check (subtitle must count the active path, not the whole tree)
  mode: null,
  settings: {},
  fixtures: {
    threads: [{ id: 't-tree-124', title: 'Tree Count', active_leaf_id: 'm-124-a1' }],
    messages: [
      // Active path: u1 -> a1 (2 messages).
      { id: 'm-124-u1', thread_id: 't-tree-124', role: 'user', content: 'root', token_count: 10, active_path_tokens: 10 },
      { id: 'm-124-a1', thread_id: 't-tree-124', role: 'assistant', content: 'reply A', model: 'deepseek/deepseek-v4-flash', parent_id: 'm-124-u1', sibling_group: 'sg-124', sibling_index: 0, token_count: 20, active_path_tokens: 30 },
      // Off-path branch: a1b -> u2b -> a2b (3 more nodes, NOT on the active path).
      { id: 'm-124-a1b', thread_id: 't-tree-124', role: 'assistant', content: 'reply B', model: 'deepseek/deepseek-v4-flash', parent_id: 'm-124-u1', sibling_group: 'sg-124', sibling_index: 1, token_count: 20, active_path_tokens: 30 },
      { id: 'm-124-u2b', thread_id: 't-tree-124', role: 'user', content: 'follow B', parent_id: 'm-124-a1b', token_count: 5, active_path_tokens: 35 },
      { id: 'm-124-a2b', thread_id: 't-tree-124', role: 'assistant', content: 'ans B', model: 'deepseek/deepseek-v4-flash', parent_id: 'm-124-u2b', token_count: 30, active_path_tokens: 65 }
    ]
  },
  async body({ cdp }) {
    await showChat();
    await cdp.waitFor('document.querySelectorAll("#thread-list .chat-item").length > 0', 15000, 300, 'thread list');
    await cdp.click('#thread-list .chat-item');
    await cdp.waitFor('document.querySelectorAll("#chat-messages .msg").length >= 2', 15000, 300, 'thread loaded');
    await sleep(600);
    await cdp.click('#treeBtn');
    await cdp.waitFor('document.getElementById("treeOverlay").classList.contains("open") && document.querySelector(".tree-modal-sub") && document.querySelector(".tree-modal-sub").textContent.indexOf("Viewing active path") === 0', 15000, 300, 'tree modal open');
    const label = await cdp.text('.tree-modal-sub');
    // FIXED (bug #124): renderChatTree counts only the ACTIVE PATH nodes - the
    // active path here has 2 messages, so the label says 2 even though the
    // whole tree has 5 nodes (off-path branches no longer inflate it).
    if (!String(label).includes('2 node'))
      throw new Error('tree label does not show the active-path count: ' + JSON.stringify(label));
    if (String(label).includes('5 node'))
      throw new Error('tree label still counts the whole tree (bug #124 not fixed): ' + JSON.stringify(label));
    return 'tree modal label: ' + JSON.stringify(label) + ' - counts the 2 active-path nodes, not all 5 tree nodes';
  }
});

scenarios.push({
  id: 125,
  name: 'Branch position labels (x/y) go stale after deleting a sibling - they use the raw sibling_index, not the position among remaining branches',
  mode: null,
  settings: {},
  fixtures: {
    threads: [{ id: 't-label-125', title: 'Branch Labels', active_leaf_id: 'm-125-a1c' }],
    messages: [
      { id: 'm-125-u1', thread_id: 't-label-125', role: 'user', content: 'root', token_count: 10, active_path_tokens: 10 },
      // Three retry branches of the same question (sibling group with indexes 0,1,2).
      { id: 'm-125-a1', thread_id: 't-label-125', role: 'assistant', content: 'answer A', model: 'deepseek/deepseek-v4-flash', parent_id: 'm-125-u1', sibling_group: 'sg-125', sibling_index: 0, token_count: 20, active_path_tokens: 30 },
      { id: 'm-125-a1b', thread_id: 't-label-125', role: 'assistant', content: 'answer B', model: 'deepseek/deepseek-v4-flash', parent_id: 'm-125-u1', sibling_group: 'sg-125', sibling_index: 1, token_count: 20, active_path_tokens: 30 },
      { id: 'm-125-a1c', thread_id: 't-label-125', role: 'assistant', content: 'answer C', model: 'deepseek/deepseek-v4-flash', parent_id: 'm-125-u1', sibling_group: 'sg-125', sibling_index: 2, token_count: 20, active_path_tokens: 30 }
    ]
  },
  async body({ cdp, dbPath }) {
    await showChat();
    await cdp.waitFor('document.querySelectorAll("#thread-list .chat-item").length > 0', 15000, 300, 'thread list');
    await cdp.click('#thread-list .chat-item');
    await cdp.waitFor('document.querySelectorAll("#chat-messages .msg").length >= 2', 15000, 300, 'thread loaded');
    await sleep(700);
    // Sanity: the third branch (leaf) correctly shows 3/3 before any delete.
    const labelBefore = await cdp.text('#chat-messages .msg:nth-child(2) .branch-label-inline');
    if (labelBefore !== '3/3')
      throw new Error('expected 3/3 before delete, got ' + JSON.stringify(labelBefore));
    // Switch back to the FIRST branch (a1, index 0).
    await cdp.click('#chat-messages .msg:nth-child(2) .msg-action-btn[title="Previous branch"]');
    await cdp.waitFor('chatMessages.length === 2 && chatMessages[1] && chatMessages[1].content === "answer B"', 15000, 300, 'switched to branch B');
    await cdp.click('#chat-messages .msg:nth-child(2) .msg-action-btn[title="Previous branch"]');
    await cdp.waitFor('chatMessages.length === 2 && chatMessages[1] && chatMessages[1].content === "answer A"', 15000, 300, 'switched to branch A');
    await sleep(400);
    const labelA = await cdp.text('#chat-messages .msg:nth-child(2) .branch-label-inline');
    if (labelA !== '1/3')
      throw new Error('expected 1/3 on branch A, got ' + JSON.stringify(labelA));
    // Delete the FIRST branch (index 0). The remaining siblings still carry
    // their original sibling_index 1 and 2.
    await cdp.click('#chat-messages .msg:nth-child(2) .msg-action-btn[title="Delete"]');
    await sleep(300);
    await cdp.waitFor('document.getElementById("customConfirmOverlay") !== null', 5000, 200, 'confirm');
    await cdp.click('#customConfirmOverlay .yes-confirm-btn');
    await cdp.waitFor('chatMessages.length === 1', 15000, 300, 'thread emptied to user message');
    await sleep(400);
    // Navigate to branch B through the tree modal.
    await cdp.click('#treeBtn');
    await cdp.waitFor('document.getElementById("treeOverlay").classList.contains("open")', 15000, 300, 'tree open');
    await cdp.waitFor('document.querySelectorAll(".tree-node").length >= 3', 20000, 300, 'tree nodes rendered');
    const targets = await cdp.eval('[].map.call(document.querySelectorAll(".tree-node"), function(n){ return n.getAttribute("data-target"); }).join(",")');
    if (String(targets).indexOf('m-125-a1b') < 0)
      throw new Error('branch B node missing from tree; targets=' + targets);
    await cdp.click('.tree-node[data-target="m-125-a1b"]');
    await cdp.waitFor('chatMessages.length === 2 && chatMessages[1] && chatMessages[1].content === "answer B"', 15000, 300, 'navigated to branch B');
    await sleep(500);
    const labelB = await cdp.text('#chat-messages .msg:nth-child(2) .branch-label-inline');
    // BUG: buildStructuredMessagesFromPath labels the message with the RAW
    // sibling_index + 1 (2) even though it is now the FIRST of 2 remaining
    // branches. Expected 1/2.
    if (labelB !== '2/2')
      throw new Error('branch B label after deleting branch A = ' + JSON.stringify(labelB) + ' (expected the buggy 2/2)');
    // And branch C now shows 3/2 (expected 2/2).
    await cdp.click('#treeBtn');
    await cdp.waitFor('document.getElementById("treeOverlay").classList.contains("open")', 15000, 300, 'tree open again');
    await cdp.click('.tree-node[data-target="m-125-a1c"]');
    await cdp.waitFor('chatMessages.length === 2 && chatMessages[1] && chatMessages[1].content === "answer C"', 15000, 300, 'navigated to branch C');
    await sleep(500);
    const labelC = await cdp.text('#chat-messages .msg:nth-child(2) .branch-label-inline');
    if (labelC !== '3/2')
      throw new Error('branch C label after deleting branch A = ' + JSON.stringify(labelC) + ' (expected the buggy 3/2)');
    return 'labels before delete: A=' + labelA + ', C=' + labelBefore + '; after deleting A: B=' + labelB + ' (should be 1/2), C=' + labelC + ' (should be 2/2)';
  }
});

scenarios.push({
  id: 126,
  name: 'Forking mid-conversation copies the source thread\'s FULL cumulative token/cost counters even though the fork only contains the prefix',
  mode: null,
  settings: {},
  fixtures: {
    threads: [{
      id: 't-fork-126', title: 'Fork Counters', active_leaf_id: 'm-126-a2',
      cumulative_input_tokens: 25, cumulative_output_tokens: 50,
      cumulative_cached_tokens: 0, cumulative_cost: 0
    }],
    messages: [
      // Call 1: u1 -> a1 (input 10, output 20). Call 2: u2 -> a2 (input 15, output 30).
      { id: 'm-126-u1', thread_id: 't-fork-126', role: 'user', content: 'root', token_count: 10, active_path_tokens: 10 },
      { id: 'm-126-a1', thread_id: 't-fork-126', role: 'assistant', content: 'answer one', model: 'deepseek/deepseek-v4-flash', parent_id: 'm-126-u1', token_count: 20, active_path_tokens: 30 },
      { id: 'm-126-u2', thread_id: 't-fork-126', role: 'user', content: 'follow up', parent_id: 'm-126-a1', token_count: 5, active_path_tokens: 35 },
      { id: 'm-126-a2', thread_id: 't-fork-126', role: 'assistant', content: 'answer two', model: 'deepseek/deepseek-v4-flash', parent_id: 'm-126-u2', token_count: 30, active_path_tokens: 65 }
    ]
  },
  async body({ cdp, dbPath }) {
    await showChat();
    await cdp.waitFor('document.querySelectorAll("#thread-list .chat-item").length > 0', 15000, 300, 'thread list');
    await cdp.click('#thread-list .chat-item');
    await cdp.waitFor('document.querySelectorAll("#chat-messages .msg").length >= 4', 15000, 300, 'thread loaded');
    await sleep(700);
    // Fork at a1 (the second message): the fork contains ONLY u1 + a1, whose
    // single API call consumed 10 input / 20 output tokens.
    await cdp.click('#chat-messages .msg:nth-child(2) .msg-action-btn[title="Fork"]');
    await cdp.waitFor('window.activeThreadId !== "t-fork-126"', 15000, 300, 'fork created');
    const newId = await cdp.eval('window.activeThreadId');
    await sleep(900);
    const forkMsgs = seed.query(dbPath, 'SELECT COUNT(*) AS c FROM messages WHERE thread_id = ?', [newId])[0].c;
    if (forkMsgs !== 2)
      throw new Error('fork should contain exactly 2 messages, has ' + forkMsgs);
    const forkThread = seed.query(dbPath, 'SELECT cumulative_input_tokens, cumulative_output_tokens FROM chat_threads WHERE id = ?', [newId])[0];
    // BUG: ForkThread copies the source thread's cumulative counters verbatim
    // (25/50), but the fork's own messages only account for the first API call
    // (10/20). The fork's header over-reports the conversation's totals until
    // the next structural change (a delete then recalibrates them).
    if (Number(forkThread.cumulative_input_tokens) !== 25 || Number(forkThread.cumulative_output_tokens) !== 50)
      throw new Error('fork counters = ' + JSON.stringify(forkThread) + ' (expected the buggy copied 25/50)');
    const bar = await cdp.text('#tokenBar .tu-item:nth-child(2) .tu-val');
    if (String(bar).indexOf('\u2191 25') < 0 || String(bar).indexOf('\u2193 50') < 0)
      throw new Error('fork header does not show the copied totals: ' + JSON.stringify(bar));
    return 'fork id=' + newId + ' has ' + forkMsgs + ' messages but copied counters ' +
      JSON.stringify(forkThread) + ' (its own calls are only 10 input / 20 output); header shows ' + JSON.stringify(bar);
  }
});

scenarios.push({
  id: 128,
  name: 'Hard-deleting a message inflates the thread\'s cumulative OUTPUT tokens (user messages\' backfilled input token_count is counted as output)',
  mode: null,
  settings: {},
  fixtures: {
    threads: [{ id: 't-out-128', title: 'Output Inflation', active_leaf_id: 'm-128-a2',
      cumulative_input_tokens: 800, cumulative_output_tokens: 150, cumulative_cached_tokens: 0, cumulative_cost: 0 }],
    messages: [
      // Branch A (active): u1 -> a1 -> u2 -> a2 (leaf). Off-path branch B: u2b -> a2b.
      // token_count on users = backfilled input contribution; on assistants = visible output.
      { id: 'm-128-u1', thread_id: 't-out-128', role: 'user', content: 'first', token_count: 100, active_path_tokens: 100 },
      { id: 'm-128-a1', thread_id: 't-out-128', role: 'assistant', content: 'reply A', model: 'deepseek/deepseek-v4-flash', parent_id: 'm-128-u1', token_count: 50, active_path_tokens: 150 },
      { id: 'm-128-u2', thread_id: 't-out-128', role: 'user', content: 'follow A', parent_id: 'm-128-a1', token_count: 100, active_path_tokens: 250 },
      { id: 'm-128-a2', thread_id: 't-out-128', role: 'assistant', content: 'ans A', model: 'deepseek/deepseek-v4-flash', parent_id: 'm-128-u2', token_count: 50, active_path_tokens: 300 },
      { id: 'm-128-u2b', thread_id: 't-out-128', role: 'user', content: 'follow B', parent_id: 'm-128-a1', token_count: 100, active_path_tokens: 250 },
      { id: 'm-128-a2b', thread_id: 't-out-128', role: 'assistant', content: 'ans B', model: 'deepseek/deepseek-v4-flash', parent_id: 'm-128-u2b', token_count: 50, active_path_tokens: 300 }
    ]
  },
  async body({ cdp, dbPath }) {
    await showChat();
    await cdp.waitFor('document.querySelectorAll("#thread-list .chat-item").length > 0', 15000, 300, 'thread list');
    await cdp.click('#thread-list .chat-item');
    await cdp.waitFor('document.querySelectorAll("#chat-messages .msg").length >= 4', 15000, 300, 'thread loaded');
    await sleep(700);
    // Delete the ACTIVE leaf assistant (a2).
    await cdp.click('#chat-messages .msg:nth-child(4) .msg-action-btn[title="Delete"]');
    await sleep(300);
    await cdp.waitFor('document.getElementById("customConfirmOverlay") !== null', 5000, 200, 'confirm');
    await cdp.click('#customConfirmOverlay .yes-confirm-btn');
    await sleep(900);

    const thread = seed.query(dbPath, 'SELECT cumulative_input_tokens, cumulative_output_tokens FROM chat_threads WHERE id = ?', ['t-out-128'])[0];
    // Ground truth after deleting a2: the remaining API calls produced only
    // a1 (50 output) and a2b (50 output) = 100 output tokens. The recompute
    // instead walks every remaining row and adds token_count to `output` for
    // USER rows too - user token_counts are backfilled INPUT contributions
    // (u1 100 + u2 100 + u2b 100), so output inflates to 400.
    if (Number(thread.cumulative_output_tokens) !== 400)
      throw new Error('cumulative output after delete = ' + thread.cumulative_output_tokens + ' (expected the buggy 400; correct is 100)');
    const bar = await cdp.eval('document.getElementById("tokenBar").textContent');
    if (String(bar).indexOf('\u2193 400') < 0)
      throw new Error('header output tokens do not show the corrupted 400: ' + JSON.stringify(bar));
    return 'deleted leaf a2: cumulative_output_tokens=' + thread.cumulative_output_tokens +
      ' (correct 100; buggy recompute counts user input token_counts as output = 400) and the header shows the inflated total';
  }
});

scenarios.push({
  id: 129,
  name: 'Empty Trash / deleteThreadForever leaves stale messages_fts rows (thread-level delete skips FTS cleanup, unlike HardDelete)',
  mode: null,
  settings: {},
  fixtures: {
    threads: [{ id: 't-fts-129', title: 'FTS Delete', active_leaf_id: 'm-129-a1' }],
    messages: [
      { id: 'm-129-u1', thread_id: 't-fts-129', role: 'user', content: 'first', token_count: 10, active_path_tokens: 10 },
      { id: 'm-129-a1', thread_id: 't-fts-129', role: 'assistant', content: 'reply', model: 'deepseek/deepseek-v4-flash', parent_id: 'm-129-u1', token_count: 5, active_path_tokens: 15 }
    ]
  },
  async body({ cdp, dbPath }) {
    await showChat();
    await cdp.waitFor('document.querySelectorAll("#thread-list .chat-item").length > 0', 15000, 300, 'thread list');
    await cdp.click('#thread-list .chat-item');
    await cdp.waitFor('document.querySelectorAll("#chat-messages .msg").length >= 2', 15000, 300, 'thread loaded');
    await sleep(600);
    // Soft-delete the thread from the sidebar, then permanently delete it
    // from the trash ("Delete forever" = ThreadRepo.Delete path).
    await cdp.click('#thread-list .chat-item .chat-action-btn.danger');
    await sleep(300);
    await cdp.waitFor('document.getElementById("customConfirmOverlay") !== null', 5000, 200, 'trash confirm');
    await cdp.click('#customConfirmOverlay .yes-confirm-btn');
    await sleep(900);
    await cdp.waitFor('document.querySelectorAll(".trash-item").length >= 1', 10000, 250, 'trash item appears');
    await cdp.click('.trash-item button.danger');
    await sleep(300);
    await cdp.waitFor('document.getElementById("customConfirmOverlay") !== null', 5000, 200, 'delete forever confirm');
    await cdp.click('#customConfirmOverlay .yes-confirm-btn');
    await sleep(900);

    const msgs = seed.query(dbPath, 'SELECT COUNT(*) AS c FROM messages WHERE thread_id = ?', ['t-fts-129'])[0].c;
    const threads = seed.query(dbPath, 'SELECT COUNT(*) AS c FROM chat_threads WHERE id = ?', ['t-fts-129'])[0].c;
    const ftsRows = seed.query(dbPath, "SELECT COUNT(*) AS c FROM messages_fts WHERE msg_id IN ('m-129-u1','m-129-a1')")[0].c;
    // Message-level HardDelete calls FTS_Remove (bug #65 guarantee: FTS stays
    // in sync). Thread-level ThreadRepo.Delete deletes messages via raw SQL and
    // never touches messages_fts, so the FTS index keeps orphaned entries.
    if (msgs !== 0 || threads !== 0)
      throw new Error('thread not fully deleted: msgs=' + msgs + ' threads=' + threads);
    if (ftsRows === 0)
      throw new Error('FTS rows were cleaned (bug may have been fixed): ftsRows=' + ftsRows);
    return 'thread deleted (messages=' + msgs + ' threads=' + threads + ') but messages_fts still holds ' +
      ftsRows + ' row(s) for the deleted messages - FTS index drifted from messages until the next startup rebuild';
  }
});

module.exports = scenarios;
