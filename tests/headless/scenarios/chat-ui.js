// scenarios/chat-ui.js - Chat window UI behavior (streaming, buttons, rendering, editing)
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
const { sleep, showChat, sendChatMessage } = require('./helpers');

const scenarios = [];

scenarios.push({
  id: 6,
  name: 'Stream failure with no output file shows an error and re-enables the UI',
  regression: true, // FIXED bug kept as a regression check (stream errors must always surface + re-enable)
  mode: null, // refused port -> curl exits before any output file
  settings: {},
  async body({ cdp }) {
    await showChat();
    await sendChatMessage(cdp, 'hello from bug 6');
    await cdp.waitFor('isLoading === true', 8000, 250, 'loading started');
    // FIXED behavior: the connection failure must surface an error banner and
    // re-enable the UI on its own — no Stop press, no stuck loading state.
    await cdp.waitFor('document.querySelectorAll(".error-banner").length > 0', 20000, 300, 'error banner');
    await cdp.waitFor('isLoading === false', 15000, 300, 'UI re-enabled');
    const inputDisabled = await cdp.eval('document.getElementById("chat-input").disabled');
    if (inputDisabled) throw new Error('input still disabled after the error');
    const bannerText = await cdp.text('.error-banner') || '';
    return 'connection failure shows error banner (' + bannerText.trim().slice(0, 60) + ') and re-enables the UI without Stop';
  }
});

scenarios.push({
  id: 12,
  name: 'Suspend banner is rebuilt from current settings on save (static check of the settings-update path)',
  regression: true, // FIXED bug kept as a regression check (banner must keep rebuilding on save)
  mode: null,
  noApp: true,
  async body() {
    // Zero-injection: Main's settings-updated handler must rebuild the banner
    // GUI (the live check sent the CapsLock+backtick suspend hotkey, which can
    // leak into the user's typing). Step 3 of the IPC refactor moved the
    // rebuild into the SettingsService hook registry.
    const mainAhk = fs.readFileSync(path.join(launcher.REPO_ROOT, 'Main.ahk'), 'utf8');
    const sbModule = fs.readFileSync(path.join(launcher.REPO_ROOT, 'app', 'SuspendBanner.ahk'), 'utf8');
    const updStart = mainAhk.indexOf('WM_SETTINGS_UPDATED');
    const reloadStart = mainAhk.indexOf('WM_RELOAD_MAIN');
    const handler = mainAhk.slice(updStart, reloadStart > updStart ? reloadStart : updStart + 1200);
    if (!/SettingsService\.ReloadFromDisk\(\)/.test(handler))
      throw new Error('Main.ahk settings-updated handler does not reload through SettingsService');
    if (!/SettingsService\.RegisterHook\("suspendBanner", _rebuildSuspendBanner\)/.test(mainAhk))
      throw new Error('Main.ahk does not register the suspend banner rebuild hook');
    if (!/suspendBanner\.Destroy\(\)[\s\S]*suspendBanner := Gui\(\)/.test(sbModule))
      throw new Error('SuspendBanner.ahk does not rebuild the GUI from scratch');
    return 'Main.ahk reloads via SettingsService with a registered suspendBanner hook; SuspendBanner.ahk rebuilds from current globals (no key injection)';
  }
});

scenarios.push({
  id: 13,
  name: 'Command Input Window is rebuilt from current settings on save (static check of the settings-update path)',
  regression: true, // FIXED bug kept as a regression check (input window must keep rebuilding on save)
  mode: null,
  noApp: true,
  async body() {
    // Zero-injection: Main's settings-updated handler must rebuild the input
    // window from the current globals (the live check opened it via the
    // backtick menu, which injected keystrokes into the user's desktop).
    const mainAhk = fs.readFileSync(path.join(launcher.REPO_ROOT, 'Main.ahk'), 'utf8');
    const iw = fs.readFileSync(path.join(launcher.REPO_ROOT, 'app', 'InputWindow.ahk'), 'utf8');
    const updStart = mainAhk.indexOf('WM_SETTINGS_UPDATED');
    const reloadStart = mainAhk.indexOf('WM_RELOAD_MAIN');
    const handler = mainAhk.slice(updStart, reloadStart > updStart ? reloadStart : updStart + 1200);
    if (!/SettingsService\.ReloadFromDisk\(\)/.test(handler))
      throw new Error('Main.ahk settings-updated handler does not reload through SettingsService');
    if (!/SettingsService\.RegisterHook\("inputWindow", _rebuildInputWindow\.Bind\(onCommandInputSend\)\)/.test(mainAhk))
      throw new Error('Main.ahk does not register the input window rebuild hook');
    if (!/w" inputWindowWidth " h" inputWindowHeight/.test(iw))
      throw new Error('InputWindow does not apply the configured width/height');
    return 'Main.ahk reloads via SettingsService with a registered inputWindow hook; InputWindow applies width/height from globals (no key injection)';
  }
});

scenarios.push({
  id: 14,
  name: 'Title generation keeps the thread\'s folder label (no hardcoded Unfiled)',
  regression: true, // FIXED bug kept as a regression check (sidebar folder groups must survive title-gen)
  mode: null,
  settings: {},
  async body() {
    // End-to-end title-gen can't run headlessly here: the title-gen request is a
    // NON-stream cURL call, and direct-spawned cURL cannot receive responses from
    // a local mock in this session (streaming works only because AHK Run with the
    // 2> redirection goes through cmd). The bug is statically provable instead.
    const tgen = fs.readFileSync(path.join(launcher.REPO_ROOT, 'chat', 'ThreadTitleGen.ahk'), 'utf8');
    // FIXED: the post must resolve the thread's real folder instead of
    // hardcoding "Unfiled", and no literal "Unfiled" may remain in the post.
    const hardcoded = /folder:\s*"Unfiled"/.test(tgen);
    const resolvesFolder = /folderName[\s\S]*folder:\s*folderName/.test(tgen);
    if (hardcoded) throw new Error('updateTopbarTitle still hardcodes folder "Unfiled"');
    if (!resolvesFolder) throw new Error('updateTopbarTitle does not resolve the thread\'s real folder');
    // FIXED: the threadList refresh must include the folders array so sidebar
    // folder groups don't disappear after title generation.
    const postsFoldersWithList = /postWebMessage\("threadList",\s*\{\s*threads:\s*threads,\s*folders:\s*folders\s*\}/.test(tgen);
    if (!postsFoldersWithList) throw new Error('threadList post after title-gen does not carry the folders array');
    const sidebar = fs.readFileSync(path.join(launcher.REPO_ROOT, 'webui', 'js', 'chat', 'chat-sidebar.js'), 'utf8');
    if (!/data\.folder !== undefined[\s\S]*?_threadMeta\[activeThreadId\]\.folder = data\.folder/.test(sidebar))
      throw new Error('JS does not honor the incoming folder value');
    return 'ThreadTitleGen.ahk posts the real folder and refreshes threadList with folders; chat-sidebar.js stores both correctly';
  }
});

scenarios.push({
  id: 15,
  name: 'Chat topbar Export button downloads the conversation',
  regression: true, // FIXED bug kept as a regression check (Export must keep downloading)
  mode: null,
  settings: {},
  async body({ cdp }) {
    await cdp.waitFor('document.querySelector(\'button[title="Export"]\') !== null', 10000, 250, 'export button');
    // FIXED: the button must have an id + wired handler (previously it had
    // neither), and clicking it must create a download blob.
    const wiring = await cdp.eval(`(() => {
      const btn = document.querySelector('button[title="Export"]');
      return { id: btn.id, exportFn: typeof window.exportChat === 'function' };
    })()`);
    if (wiring.id !== 'export-chat-btn') throw new Error('export button has no id: ' + JSON.stringify(wiring));
    if (!wiring.exportFn) throw new Error('exportChat not defined: ' + JSON.stringify(wiring));
    await cdp.eval(`(() => {
      window.__exportBlobCalls = 0;
      const orig = URL.createObjectURL;
      URL.createObjectURL = function() { window.__exportBlobCalls++; return orig.apply(this, arguments); };
      return true;
    })()`);
    await cdp.click('#export-chat-btn');
    await sleep(400);
    const blobCalls = await cdp.eval('window.__exportBlobCalls');
    if (blobCalls < 1) throw new Error('Export did not create a download blob');
    return 'export button is wired (id=export-chat-btn, handler attached) and clicking it created a download blob';
  }
});

scenarios.push({
  id: 17,
  name: 'System-prompt modal char counter updates while typing',
  regression: true, // FIXED bug kept as a regression check (counter must keep updating)
  mode: null,
  settings: {},
  async body({ cdp }) {
    // FIXED: the counter lives in the chat right-rail system prompt modal
    // (#sysMsgOverlay/#sysMsgFull), opened via #expandSysMsg. Typing must
    // update #charCount (previously nothing wrote to it).
    await showChat();
    await cdp.waitFor('document.getElementById("expandSysMsg") !== null', 10000, 250, 'expand button');
    await cdp.click('#expandSysMsg');
    await cdp.waitFor('document.getElementById("sysMsgOverlay").classList.contains("open")', 5000, 200, 'sysmsg overlay');
    await cdp.type('#sysMsgFull', 'hello world typed by harness');
    const count = await cdp.text('#charCount');
    if (count !== '28 chars') throw new Error('charCount = ' + JSON.stringify(count) + ' (expected 28 chars)');
    return 'after typing 28 chars, #charCount shows "28 chars"';
  }
});

scenarios.push({
  id: 20,
  name: 'Right-rail Advanced toggles (Code Execution / Web Search) do nothing',
  regression: true, // FIXED bug kept as a regression check (toggles must keep persisting as stubs)
  mode: null,
  settings: {},
  async body({ cdp }) {
    await showChat();
    await cdp.click('#advancedToggle');
    await cdp.waitFor('document.getElementById("advancedWrap").classList.contains("open")', 5000, 200, 'advanced open');
    await cdp.clearPosted();
    await cdp.click('#advancedWrap .toggle-row .switch'); // first row = Code Execution
    await sleep(900); // debounce 300ms + IPC round trip
    const after = await cdp.postedMessages();
    const nonSettings = after.filter((m) => !m.includes('"updateModelSettings"'));
    if (nonSettings.length > 0) throw new Error('toggle triggered unexpected actions: ' + JSON.stringify(nonSettings));
    const lastAfter = after.filter((m) => m.includes('"updateModelSettings"')).pop();
    if (!lastAfter) throw new Error('no updateModelSettings posted after toggling a switch');
    const payload = JSON.parse(lastAfter);
    if (payload.codeExecution !== true) throw new Error('codeExecution not true in updateModelSettings payload: ' + lastAfter);
    const toggled = await cdp.eval('document.querySelector("#advancedWrap .toggle-row .switch").classList.contains("on")');
    if (!toggled) throw new Error('Code Execution switch did not stay visually on');
    return 'toggle posts updateModelSettings with codeExecution=true and the switch stays on (on=' + toggled + ')';
  }
});

scenarios.push({
  id: 21,
  name: 'Reasoning-only responses (thinking, no visible text) get no action buttons',
  regression: true, // FIXED bug kept as a regression check (thinking-only completions must keep getting actions)
  mode: 'sse-reasoning-only',
  settings: {},
  async body({ cdp }) {
    await showChat();
    await sendChatMessage(cdp, 'think only please');
    await cdp.waitFor('typeof streamState !== "undefined" && !streamState.active && streamState.bubble !== null', 30000, 300, 'stream done');
    const thinking = await cdp.eval('document.querySelectorAll(".thinking-block").length');
    const lastMsgRole = await cdp.eval('chatMessages[chatMessages.length - 1].role');
    const lastBubbleActions = await cdp.eval(`(() => {
      const bubbles = [...document.querySelectorAll('.msg')];
      const last = bubbles[bubbles.length - 1];
      if (!last || !last.classList.contains('bot')) return -1;
      return last.querySelectorAll('.msg-action-btn').length;
    })()`);
    if (thinking === 0) throw new Error('no thinking block rendered');
    if (lastMsgRole !== 'assistant') throw new Error('assistant message not added to chatMessages: ' + lastMsgRole);
    if (lastBubbleActions === 0) throw new Error('assistant bubble has no action buttons');
    return 'thinking block shown, assistant message added to chatMessages, bubble has ' + lastBubbleActions + ' action buttons';
  }
});

scenarios.push({
  id: 31,
  name: 'Font-size +/- buttons use a stale 17px base after a thread with a custom size loads',
  mode: null,
  regression: true, // FIXED: font-size +/- now syncs cached base after thread load (was 18px)
  settings: {},
  fixtures: {
    threads: [{ id: 't-font-31', title: 'Font Thread', active_leaf_id: 'm-font-31', font_size: 20 }],
    messages: [{ id: 'm-font-31', thread_id: 't-font-31', role: 'user', content: 'hello' }]
  },
  async body({ cdp }) {
    await showChat();
    await cdp.waitFor('document.querySelectorAll("#thread-list .chat-item").length > 0', 15000, 300, 'thread list');
    await cdp.click('#thread-list .chat-item');
    // The thread's per-thread font size (20) arrives via currentSettings and is
    // applied to the CSS var + display, and UiControls.syncFontSize updates the cached base.

    await cdp.waitFor('document.getElementById("font-size-display") && document.getElementById("font-size-display").textContent === "20px"', 15000, 300, 'thread font size applied');
    const before = await cdp.eval('document.getElementById("font-size-display").textContent');
    await cdp.click('#btn-font-inc');
    await sleep(300);
    const after = await cdp.eval('document.getElementById("font-size-display").textContent');
    // FIXED: the + button now correctly bumps 20px -> 21px (was 17px -> 18px stale)
    if (after !== '21px')
      throw new Error('font-size increment did not use thread size: ' + before + ' -> ' + after + ' (expected 21px)');
    return 'after loading a 20px thread, clicking + correctly changed the display from ' + before + ' to ' + after;
  }
});

scenarios.push({
  id: 49,
  name: 'Canceling a message edit rolls back deferred attachment removals',
  regression: true, // FIXED bug kept as a regression check (cancel must not leave attachments half-removed)
  mode: null,
  settings: {},
  fixtures: {
    threads: [{ id: 't-att-49', title: 'Attachment Thread', active_leaf_id: 'm-att-49' }],
    messages: [{ id: 'm-att-49', thread_id: 't-att-49', role: 'user', content: 'with file' }]
  },
  async body({ cdp, dbPath }) {
    // Seed an attachment row (the fixtures builder has no attachments support).
    const { DatabaseSync } = require('node:sqlite');
    const db = new DatabaseSync(dbPath);
    db.exec("INSERT INTO message_attachments (id, message_id, attachment_type, file_path, mime_type, original_filename, file_size, extracted_text) VALUES ('att-49', 'm-att-49', 'text_file', 'attachments/att-49.txt', 'text/plain', 'notes.txt', 12, 'SGVsbG8gd29ybGQ=')");
    db.close();

    await showChat();
    await cdp.waitFor('document.querySelectorAll("#thread-list .chat-item").length > 0', 15000, 300, 'thread list');
    await cdp.click('#thread-list .chat-item');
    await cdp.waitFor('document.querySelectorAll("#chat-messages .msg").length >= 1', 15000, 300, 'thread loaded');
    await sleep(700);
    await cdp.waitFor('document.querySelector(".msg-attachment-file .msg-attachment-delete") !== null', 10000, 300, 'attachment delete btn');
    // Open the editor and remove the attachment (deferred deletion).
    await cdp.click('#chat-messages .msg .msg-action-btn[title="Edit"]');
    await sleep(200);
    await cdp.click('#chat-messages .msg .msg-attachment-delete');
    await sleep(200);
    const hiddenDuringEdit = await cdp.eval(`(() => {
      const w = document.querySelector('.msg-attachment-file');
      return w ? w.style.display : 'no-wrapper';
    })()`);
    const rowDuring = seed.query(dbPath, "SELECT COUNT(*) AS c FROM message_attachments WHERE id='att-49'")[0].c;
    // Cancel the edit.
    await cdp.click('#chat-messages .msg .cancel-edit');
    await sleep(200);
    const hiddenAfterCancel = await cdp.eval(`(() => {
      const w = document.querySelector('.msg-attachment-file');
      return w ? w.style.display : 'no-wrapper';
    })()`);
    const editingId = await cdp.eval('typeof _editingMessageId !== "undefined" ? _editingMessageId : "undef"');
    const rowAfter = seed.query(dbPath, "SELECT COUNT(*) AS c FROM message_attachments WHERE id='att-49'")[0].c;
    // FIXED (bug #49): canceling rolls back the deferred removal (wrapper is
    // restored), clears the edit state, and leaves the DB row untouched.
    if (hiddenAfterCancel === 'none')
      throw new Error('cancel left the attachment hidden (bug #49 not fixed): hidden=' + hiddenAfterCancel);
    if (rowAfter === 0)
      throw new Error('cancel deleted the attachment instead of rolling back: rows=' + rowAfter);
    if (editingId !== null && editingId !== 'undef' && editingId !== '')
      throw new Error('cancel left a stale _editingMessageId=' + JSON.stringify(editingId));
    return 'Edit -> remove attachment -> Cancel: wrapper display=' + hiddenDuringEdit + ' -> ' + hiddenAfterCancel +
      ', DB rows during=' + rowDuring + ' after=' + rowAfter + ', _editingMessageId=' + JSON.stringify(editingId) +
      ' (cancel rolls back the deferred removal)';
  }
});

scenarios.push({
  id: 56,
  name: 'Stopping a stream before the first token is a clean cancel (static check)',
  regression: true, // FIXED bug kept as a regression check (cancel must be checked before the empty-content error branch)
  mode: null,
  noApp: true,
  async body() {
    const sh = fs.readFileSync(path.join(launcher.REPO_ROOT, 'chat', 'streaming', 'StreamHandler.ahk'), 'utf8');
    const se = fs.readFileSync(path.join(launcher.REPO_ROOT, 'chat', 'streaming', 'StreamError.ahk'), 'utf8');
    const finalizePos = sh.indexOf('_finalizeStreaming() {');
    const block = sh.slice(finalizePos, finalizePos + 1200);
    const cancelPos = block.indexOf('_handleStreamCancelled()');
    const errorPos = block.indexOf('_handleStreamError()');
    // FIXED (bug #56): the cancelled branch runs BEFORE the empty-content
    // error branch, so a Stop before the first token is a clean cancel.
    if (cancelPos < 0 || errorPos < 0 || cancelPos > errorPos)
      throw new Error('cancel branch not before the empty-content error branch (bug #56 not fixed): cancelPos=' + cancelPos + ' errorPos=' + errorPos);
    // _handleStreamCancelled posts a clean cancellation for empty content.
    const cleanCancel = /postWebMessage\("streamCancelled", true\)/.test(se);
    if (!cleanCancel)
      throw new Error('_handleStreamCancelled must post a clean streamCancelled for empty content');
    return '_finalizeStreaming checks _streamCancelled before the empty-content branch, so pressing Stop before the first token is a clean cancellation (no API-key banner)';
  }
});

scenarios.push({
  id: 57,
  name: 'Chat message HTML is rendered as inert text (XSS fixed)',
  regression: true, // FIXED bug kept as a regression check (raw HTML in messages must not execute)
  mode: null,
  settings: {},
  fixtures: {
    threads: [{ id: 't-xss-57', title: 'XSS Thread', active_leaf_id: 'm-xss-57' }],
    messages: [{ id: 'm-xss-57', thread_id: 't-xss-57', role: 'assistant', content: '<img src="x" onerror="window.__xssPwned = 1">', model: 'deepseek/deepseek-v4-flash' }]
  },
  async body({ cdp }) {
    await showChat();
    await cdp.waitFor('document.querySelectorAll("#thread-list .chat-item").length > 0', 15000, 300, 'thread list');
    await cdp.click('#thread-list .chat-item');
    await cdp.waitFor('document.querySelectorAll("#chat-messages .msg").length >= 1', 15000, 300, 'thread loaded');
    await sleep(700);
    const pwned = await cdp.eval('window.__xssPwned || 0');
    // FIXED (bug #57): markdown-it is configured with html:false, so raw HTML
    // in messages is escaped and rendered as inert text - the onerror handler
    // must not run.
    if (pwned !== 0)
      throw new Error('inline handler still executed (bug #57 not fixed): pwned=' + pwned);
    const renderedHtml = await cdp.eval('document.querySelector(".msg-content") ? document.querySelector(".msg-content").innerHTML : ""');
    if (String(renderedHtml).indexOf('<img') >= 0)
      throw new Error('raw <img> tag still present in rendered HTML (bug #57 not fixed): ' + JSON.stringify(renderedHtml));
    return 'assistant message <img src="x" onerror=...> rendered inert (window.__xssPwned=0); msg HTML=' + JSON.stringify(renderedHtml);
  }
});

module.exports = scenarios;
