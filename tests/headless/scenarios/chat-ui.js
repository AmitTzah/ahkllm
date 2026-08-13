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
const vm = require('node:vm');
const launcher = require('../launch');
const seed = require('../seed');
const { sleep, showChat, sendChatMessage, waitStreamingIdle } = require('./helpers');

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
    // The completed bubble stays in the DOM, but onStreamDone nulls the
    // streamState.bubble handle, so wait on the stream being idle instead of
    // requiring the (now-nulled) handle to survive completion.
    await cdp.waitFor('typeof streamState !== "undefined" && !streamState.active && !isLoading', 30000, 300, 'stream done');
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
    // Slice to the end of _finalizeStreaming (the next function definition).
    // Later bug-#98 comments made the fixed 1200-char slice too short, which
    // hid _handleStreamError and falsely failed this regression check.
    const cleanupPos = sh.indexOf('_cleanupStreamState() {', finalizePos);
    const block = sh.slice(finalizePos, cleanupPos > finalizePos ? cleanupPos : finalizePos + 3000);
    const cancelPos = block.indexOf('_handleStreamCancelled()');
    const errorPos = block.indexOf('_handleStreamError()');
    // FIXED (bug #56): the cancelled branch runs BEFORE the empty-content
    // error branch, so a Stop before the first token is a clean cancel.
    if (cancelPos < 0 || errorPos < 0 || cancelPos > errorPos)
      throw new Error('cancel branch not before the empty-content error branch (bug #56 not fixed): cancelPos=' + cancelPos + ' errorPos=' + errorPos);
    // _handleStreamCancelled posts a clean cancellation for empty content.
    // Bug #171 scoped the payload to the sending thread ({ threadId }),
    // replacing the earlier bare `true` - assert the object-form post (a
    // clean streamCancelled, never a showError banner).
    const cleanCancel = /postWebMessage\("streamCancelled",\s*\{/.test(se);
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

scenarios.push({
  id: 212,
  name: 'The first message in a fresh session discards right-rail selections - handleChatSend auto-creates the thread, then calls _applyNewChatDefault() UNCONDITIONALLY, so a pre-send assistant pick / typed system prompt / temperature is overwritten by the "New Chats Start With" default (since bug #196, "App Default" resolves to the marked default assistant) and the request carries the default assistant\'s system message',
  mode: 'sse-success',
  regression: true, // FIXED bug #212 kept as a regression check (the default only applies to pristine requestParams)
  settings: {},
  async body({ cdp, mockLog }) {
    await showChat();
    await cdp.waitFor('document.getElementById("modelCardTrigger") !== null && typeof window._assistantList !== "undefined"', 15000, 300, 'model card + list');
    await cdp.click('#modelCardTrigger');
    await cdp.waitFor('document.getElementById("modelPopover").classList.contains("open")', 5000, 200, 'popover open');
    await cdp.waitFor('[...document.querySelectorAll("#tab-assistants .selector-item .si-name")].some(e => e.textContent === "Violet")', 10000, 250, 'violet listed');
    await cdp.eval(`(() => {
      const items = [...document.querySelectorAll('#tab-assistants .selector-item')];
      const it = items.find((el) => el.querySelector('.si-name') && el.querySelector('.si-name').textContent === 'Violet');
      if (!it) return false;
      it.click();
      return true;
    })()`);
    await sleep(1500); // switchAssistant round trip
    // Type DIRECTLY into the mini field (no Expand modal), then send.
    await cdp.eval('document.getElementById("sysMsgMini").value = ""');
    await cdp.type('#sysMsgMini', 'DIRECT TYPED MESSAGE');
    await sleep(800);
    const railAfter = await cdp.eval('document.getElementById("sysMsgMini").value');
    if (railAfter !== 'DIRECT TYPED MESSAGE')
      throw new Error('typed message not visible in the rail (setup): ' + JSON.stringify(railAfter));
    await sendChatMessage(cdp, 'hello from direct typing');
    await waitStreamingIdle(cdp, 30000);
    await sleep(500);
    const lines = fs.readFileSync(mockLog, 'utf8').split(/\r?\n/).filter(Boolean).map((l) => JSON.parse(l));
    const chatReq = lines.find((e) => e.body && e.body.stream === true);
    if (!chatReq) throw new Error('no streaming chat request was logged; lines=' + lines.length);
    const b = chatReq.body;
    const sysMsg = (b.messages || []).filter((m) => m.role === 'system').map((m) => String(m.content || ''));
    const containsTyped = sysMsg.some((c) => c.indexOf('DIRECT TYPED MESSAGE') >= 0);
    // FIXED (bug #212): handleChatSend only applies the New Chats Start With
    // default when requestParams are pristine, so the typed system prompt (and
    // the Violet selection) survive thread creation and reach the request.
    if (!containsTyped)
      throw new Error('typed system prompt did not reach the request (fix incomplete): ' + JSON.stringify(sysMsg));
    return 'selected Violet + typed "DIRECT TYPED MESSAGE" before the first send; the request system message is the typed text (' +
      JSON.stringify(sysMsg[0] ? sysMsg[0].slice(0, 60) : '(none)') + ') - pre-send right-rail selections survive thread creation';
  }
});

scenarios.push({
  id: 178,
  name: 'SSE `data:` LINE split across poll boundaries silently loses the payload (the remainder arrives without the `data: ` prefix, so SSEParser ignores it)',
  mode: 'sse-split-line',
  regression: true, // FIXED: split data lines are re-formed by the pending-line buffer and all choices accumulate
  settings: {},
  async body({ cdp, dbPath, mockLog }) {
    await showChat();
    await sendChatMessage(cdp, 'split my stream line');
    // The bug leaves the stream active (the partial JSON crashes the poll
    // timer), so wait with a bounded cap instead of failing on the timeout.
    let idle = false;
    try { await waitStreamingIdle(cdp, 25000); idle = true; } catch {}
    await sleep(1200);
    let msgs = [];
    try { msgs = seed.query(dbPath, 'SELECT role, content FROM messages ORDER BY created_at'); } catch {}
    const asst = msgs.find((m) => m.role === 'assistant');
    const content = asst ? asst.content : '';
    const hasNormal = content.indexOf('Hello from the mock LLM.') >= 0;
    const hasSplit = content.indexOf('SPLIT-LEFT') >= 0;
    const diag = await cdp.eval('({ streamState: typeof streamState !== "undefined" ? streamState : null, isLoading: typeof isLoading !== "undefined" ? isLoading : null })').catch(() => ({}));
    const userSent = msgs.some((m) => m.role === 'user');
    if (!userSent)
      throw new Error('send failed (harness issue): ' + JSON.stringify(msgs));
    // FIXED (bug #178): the SPLIT-LEFT-RIGHT event (ONE `data:` line written
    // in two writes with a >poll gap) is re-formed by the stream's
    // pending-line buffer - the incomplete fragment is held across polls and
    // joined with the remainder, so the full payload (including the bare
    // continuation) is persisted and the stream finalizes normally.
    if (!asst)
      throw new Error('assistant message missing (fix incomplete): ' + JSON.stringify(msgs));
    if (!hasSplit || content.indexOf('SPLIT-LEFT-RIGHT') < 0)
      throw new Error('split payload did not survive in full (fix incomplete): ' + JSON.stringify(content));
    if (diag.streamState && diag.streamState.active)
      throw new Error('stream still active after finalize (fix incomplete): ' + JSON.stringify(diag.streamState));
    return 'split-line stream: idle=' + idle + ' streamState.active=' + (diag.streamState ? diag.streamState.active : '?') +
      ', assistant persisted=' + JSON.stringify(content) +
      ' - the split data line was re-formed by the pending-line buffer and its payload survives in full';
  }
});

scenarios.push({
  id: 193,
  name: 'Right-rail temperature 0 is silently dropped when ANY other right-rail setting is re-sent - _sendAllSettings posts temperature: s.temperature || "" (0 is falsy in JS), so typing a system prompt or changing reasoning with a 0 override resets it to default (bug #35/#78 family on the SEND path)',
  mode: null,
  regression: true, // FIXED: numeric temperature 0 survives the re-send (falsy-0 guard)
  noApp: true,
  settings: {},
  async body() {
    const src = fs.readFileSync(path.join(launcher.REPO_ROOT, 'webui', 'js', 'chat', 'model-picker', 'model-picker.js'), 'utf8');
    const posted = [];
    const sandbox = {
      console,
      window: {
        _currentSettings: { temperature: 0, systemMessage: '', reasoning: '', model: '', assistantName: '', codeExecution: false, webSearch: false }
      },
      document: {
        addEventListener() {},
        getElementById: () => null,
        querySelectorAll: () => [],
        querySelector: () => null,
        createElement: () => ({ style: {}, appendChild() {}, addEventListener() {}, querySelectorAll: () => [], querySelector: () => null, getContext() { return {}; } })
      },
      Ipc: { postToHost: (action, payload) => posted.push({ action, payload }) },
      setTimeout,
      clearTimeout,
      navigator: {},
      lucide: { createIcons() {} }
    };
    sandbox.global = sandbox;
    vm.createContext(sandbox);
    vm.runInContext(src, sandbox);
    // Simulate the right-rail re-send after ANY change (e.g. typing into the
    // system prompt field) while the thread's temperature override is 0.
    sandbox._sendAllSettings();
    await new Promise((r) => setTimeout(r, 400));
    const p = posted.find((x) => x.action === 'updateModelSettings');
    if (!p) throw new Error('updateModelSettings was not posted (sandbox issue)');
    // FIXED (bug #193): temperature 0 (a valid override per bug #35/#78) must
    // survive the re-send - only truly empty/absent values become "".
    if (p.payload.temperature !== 0)
      throw new Error('temperature 0 still dropped on re-send (fix incomplete): ' + JSON.stringify(p.payload));
    return '_sendAllSettings with a stored temperature of 0 posted updateModelSettings with temperature=0 - the 0 override survives every other right-rail change (e.g. typing a system prompt), so the next reload keeps 0.0';
  }
});

scenarios.push({
  id: 198,
  name: 'PDF/office attachments with a generic MIME type are misclassified as text_file - getAttachmentTypeFromMime only falls back to the extension for odt/odp/ods/rtf/epub, so a .pdf/.docx/.pptx/.xlsx with application/octet-stream is treated as plain text (no PDF/office extraction, sent as garbled text context)',
  mode: null,
  regression: true, // FIXED bug #198 kept as a regression check
  settings: {},
  async body({ cdp }) {
    await showChat();
    const type = await cdp.eval(`(() => {
      const file = new File([new Uint8Array([0x25, 0x50, 0x44, 0x46, 0x2D, 0x31, 0x2E, 0x34])], 'report.pdf', { type: 'application/octet-stream' });
      addAttachment(file);
      const att = attachmentState.length ? attachmentState[0] : null;
      return att ? JSON.stringify({ type: att.type, filename: att.filename, mimeType: att.mimeType }) : 'none';
    })()`);
    const att = JSON.parse(type);
    // FIXED (bug #198): the extension fallback classifies the generic-MIME
    // PDF as pdf so the app extracts text and sends it as a PDF context.
    if (att.type !== 'pdf')
      throw new Error('generic-MIME PDF was not classified by extension (fix incomplete): ' + type);
    if (att.filename !== 'report.pdf')
      throw new Error('setup: filename lost: ' + type);
    return 'File "report.pdf" with MIME application/octet-stream was classified as "' + att.type +
      '" - getAttachmentTypeFromMime now falls back to the extension for pdf/docx/pptx/xlsx, so the PDF is attached as a PDF and extracted';
  }
});

scenarios.push({
  id: 204,
  name: 'A stalled stream never times out - CurlBuilder.BuildStream has --connect-timeout 30 but NO --max-time, so an API that accepts the connection and then sends nothing leaves streamState.active/isLoading true and the Stop/input UI stuck forever',
  mode: null,
  noApp: true,
  regression: true, // FIXED bug #204 kept as a regression check
  settings: {},
  async body() {
    const src = fs.readFileSync(path.join(launcher.REPO_ROOT, 'api', 'CurlBuilder.ahk'), 'utf8');
    const streamIdx = src.indexOf('static BuildStream(');
    const block = streamIdx >= 0 ? src.slice(streamIdx, streamIdx + 900) : '';
    const hasMaxTime = /--max-time 120/.test(block);
    // FIXED (bug #204): the streaming command now carries --max-time 120, so
    // a stalled upstream eventually exits and the stream error path re-enables
    // the UI (the sse-hang mock stays in mock-llm-server.js as a harness mode).
    if (!hasMaxTime)
      throw new Error('BuildStream still lacks --max-time (fix incomplete): ' + block);
    return 'CurlBuilder.BuildStream now includes --max-time 120 alongside --connect-timeout 30 - a stalled upstream cannot hang the chat UI forever';
  }
});

scenarios.push({
  id: 208,
  name: 'Streaming bubble author label injects assistant/model names as raw HTML (XSS) - createStreamingBubble concatenates displayName into innerHTML without escaping, so an assistant named <img onerror=...> executes in the WebView',
  mode: 'sse-success',
  regression: true, // FIXED bug #208 kept as a regression check (the author label is now escHtml'd)
  settings: {
    // The assistant name carries the payload. It flows settings.json -> the
    // AHK streamModelName post (displayName = asst.name) -> streamState.modelName
    // -> createStreamingBubble's innerHTML.
    assistants: [{
      id: 'asst-xss-208',
      name: '<img src="x" onerror="window.__xssPwned=1">',
      baseModel: 'deepseek/deepseek-v4-flash',
      systemMessage: '',
      systemMessageFile: '',
      description: '',
      reasoning: '',
      temperature: '',
      isDefault: false
    }]
  },
  fixtures: {
    threads: [{ id: 't-xss-208', title: 'XSS Thread', active_leaf_id: 'm-xss-208', assistant_id: 'asst-xss-208' }],
    messages: [{ id: 'm-xss-208', thread_id: 't-xss-208', role: 'user', content: 'hello' }]
  },
  async body({ cdp }) {
    await showChat();
    await cdp.waitFor('document.querySelectorAll("#thread-list .chat-item").length > 0', 15000, 300, 'thread list');
    await cdp.click('#thread-list .chat-item');
    await cdp.waitFor('document.querySelectorAll("#chat-messages .msg").length >= 1', 15000, 300, 'thread loaded');
    await sleep(500); // let the assistant/thread settings round-trip finish
    await sendChatMessage(cdp, 'stream for me');
    await waitStreamingIdle(cdp, 30000);
    await sleep(500);
    const pwned = await cdp.eval('window.__xssPwned || 0');
    const authorHtml = await cdp.eval(`(() => {
      const bubbles = [...document.querySelectorAll('.msg.bot')];
      const last = bubbles[bubbles.length - 1];
      if (!last) return '';
      const a = last.querySelector('.msg-author');
      return a ? a.innerHTML : '';
    })()`);
    const authorText = await cdp.eval(`(() => {
      const bubbles = [...document.querySelectorAll('.msg.bot')];
      const last = bubbles[bubbles.length - 1];
      if (!last) return '';
      const a = last.querySelector('.msg-author');
      return a ? a.textContent : '';
    })()`);
    // FIXED (bug #208): the assistant name is escaped before innerHTML, so
    // the <img> tag is inert text - the onerror handler must NOT run, no raw
    // <img> may appear in the author label, and the name is still visible as
    // text (textContent carries the literal markup).
    if (pwned !== 0)
      throw new Error('inline handler still executed (bug #208 not fixed): pwned=' + pwned);
    if (String(authorHtml).indexOf('<img') >= 0)
      throw new Error('raw <img> tag still present in the author label (bug #208 not fixed): ' + JSON.stringify(authorHtml));
    if (String(authorText).indexOf('<img') < 0)
      throw new Error('author label lost the name text (should render as inert text): ' + JSON.stringify(authorText));
    return 'assistant name <img src="x" onerror=...> rendered inert in the streaming bubble (window.__xssPwned=0); author innerHTML=' + JSON.stringify(authorHtml) +
      ' textContent=' + JSON.stringify(authorText) + ' - the author label is escaped like every other bubble';
  }
});

scenarios.push({
  id: 213,
  name: 'Font-size adjustments made before the first message are silently dropped - handleUpdateFontSize only persists when activeThreadId exists, so a font change on a fresh (no-thread) chat never reaches requestParams and the auto-created thread saves the default 17px',
  mode: null,
  regression: true, // FIXED bug #213 kept as a regression check (pre-send font size survives thread creation)
  settings: {},
  fixtures: {}, // no threads -> fresh empty app state
  async body({ cdp, dbPath }) {
    await showChat();
    await cdp.waitFor('document.getElementById("font-size-display") !== null && window.activeThreadId === ""', 15000, 300, 'fresh empty chat');
    // Bump the font size while NO thread exists (topbar controls are always
    // visible). The + click posts updateFontSize, which handleUpdateFontSize
    // drops because activeThreadId is empty.
    await cdp.click('#btn-font-inc');
    await sleep(500);
    const displayAfter = await cdp.eval('document.getElementById("font-size-display").textContent');
    if (displayAfter !== '18px')
      throw new Error('setup: the + button did not bump the display to 18px: ' + JSON.stringify(displayAfter));
    // Send the first message -> handleChatSend auto-creates the thread and
    // calls _saveCurrentSettingsToThread, which reads requestParams["fontSize"].
    await sendChatMessage(cdp, 'first message');
    await cdp.waitFor('window.activeThreadId !== ""', 15000, 300, 'thread auto-created');
    await sleep(900);
    const threadId = await cdp.eval('window.activeThreadId');
    const rows = seed.query(dbPath, 'SELECT font_size FROM chat_threads WHERE id=?', [threadId]);
    if (!rows.length) throw new Error('setup: thread row missing: ' + threadId);
    const savedFont = Number(rows[0].font_size);
    // FIXED (bug #213): handleUpdateFontSize stores the size in requestParams
    // even with no active thread, so the auto-created thread keeps the
    // user's pre-send 18px adjustment instead of falling back to 17px.
    if (savedFont !== 18)
      throw new Error('font size was dropped on the auto-created thread (bug #213 not fixed): font_size=' + savedFont + ' expected 18');
    return 'bumped the font to 18px with NO active thread, then sent the first message: the auto-created thread ' + threadId +
      ' saved font_size=' + savedFont + ' - the pre-send 18px adjustment survives thread creation';
  }
});

scenarios.push({
  id: 214,
  name: 'Switching branches mid-stream re-enables the composer (setChatButtonsEnabled(true) inside updateChatMessages) - the user can send a SECOND request while the first stream is still in flight, and the second send clobbers the shared requestParams stream state so the first (billed) response is never persisted or logged',
  mode: 'sse-slow',
  regression: true, // FIXED bug #214 kept as a regression check (composer stays disabled mid-stream)
  settings: {},
  fixtures: {
    threads: [{ id: 't-mid-214', title: 'Mid-Stream Branch', active_leaf_id: 'm-214-a1' }],
    messages: [
      { id: 'm-214-u1', thread_id: 't-mid-214', role: 'user', content: 'root question', token_count: 5, active_path_tokens: 5 },
      { id: 'm-214-a1', thread_id: 't-mid-214', role: 'assistant', content: 'branch A answer', model: 'deepseek/deepseek-v4-flash', parent_id: 'm-214-u1', sibling_group: 'sg-214', sibling_index: 0, token_count: 5, prompt_tokens: 10, active_path_tokens: 15 },
      { id: 'm-214-a2', thread_id: 't-mid-214', role: 'assistant', content: 'branch B answer', model: 'deepseek/deepseek-v4-flash', parent_id: 'm-214-u1', sibling_group: 'sg-214', sibling_index: 1, token_count: 5, prompt_tokens: 10, active_path_tokens: 15 }
    ]
  },
  async body({ cdp, dbPath, mockLog }) {
    await showChat();
    await cdp.waitFor('document.querySelectorAll("#thread-list .chat-item").length > 0', 15000, 300, 'thread list');
    await cdp.click('#thread-list .chat-item');
    await cdp.waitFor('chatMessages.length >= 2 && chatMessages[1] && chatMessages[1].id === "m-214-a1"', 15000, 300, 'branch A loaded');
    await sleep(600);
    await sendChatMessage(cdp, 'follow-up on A');
    await cdp.waitFor('typeof streamState !== "undefined" && streamState.active === true', 20000, 50, 'streaming active');
    await sleep(150);
    // Switch to the sibling branch while A's stream is in flight (same flow
    // as the branch-nav arrows on the assistant bubble).
    await cdp.click('#chat-messages .msg:nth-child(2) .msg-action-btn[title="Next branch"]');
    await cdp.waitFor('chatMessages.length >= 2 && chatMessages[1] && chatMessages[1].id === "m-214-a2"', 15000, 300, 'branch B loaded');
    await sleep(300);
    // The first stream must STILL be in flight at this point.
    const state = await cdp.eval(`(() => ({
      streamActive: (typeof streamState !== 'undefined' && streamState.active) || false,
      inputDisabled: document.getElementById('chat-input').disabled,
      isLoading: (typeof isLoading !== 'undefined' && isLoading) || false,
      btnOnclick: (function(){ var b = document.getElementById('chat-send-btn'); return b && b.onclick ? String(b.onclick).indexOf('onStopStreaming') >= 0 ? 'stop' : 'send' : 'none'; })()
    }))()`);
    if (!state.streamActive)
      throw new Error('setup: first stream already finished before the state check (timing)');
    // FIXED (bug #214): updateChatMessages must NOT re-enable the composer
    // mid-stream - the input stays disabled, isLoading stays true, and the
    // button stays wired to Stop, so a second send is impossible.
    if (!state.inputDisabled || !state.isLoading || state.btnOnclick !== 'stop')
      throw new Error('composer was re-enabled after the branch switch mid-stream (bug #214 not fixed): ' + JSON.stringify(state));
    // The first stream must now complete untouched (no second request ever
    // fired), and its billed response must be persisted.
    await waitStreamingIdle(cdp, 40000);
    await sleep(800);
    const reEnabled = await cdp.eval('document.getElementById("chat-input").disabled === false && (typeof isLoading !== "undefined" && !isLoading)');
    if (!reEnabled)
      throw new Error('composer was not re-enabled after the stream completed: ' + reEnabled);
    // Regression: the first request's response IS persisted - an assistant
    // row is parented to the "follow-up on A" user message, and no "second
    // message on B" was ever created.
    const followUpId = seed.query(dbPath, "SELECT id FROM messages WHERE thread_id='t-mid-214' AND content='follow-up on A'")[0];
    const firstResp = seed.query(dbPath, "SELECT COUNT(*) AS c FROM messages WHERE thread_id='t-mid-214' AND role='assistant' AND parent_id=?", [followUpId ? followUpId.id : 'nope'])[0].c;
    const secondResp = seed.query(dbPath, "SELECT COUNT(*) AS c FROM messages WHERE thread_id='t-mid-214' AND role='assistant' AND parent_id IN (SELECT id FROM messages WHERE thread_id='t-mid-214' AND content='second message on B')")[0].c;
    if (firstResp !== 1)
      throw new Error('the first streamed response was not persisted (bug #214 not fixed): firstResp=' + firstResp);
    if (secondResp !== 0)
      throw new Error('a second message was sent while the first stream was in flight (bug #214 not fixed): secondResp=' + secondResp);
    return 'branch switch mid-stream kept the composer disabled (inputDisabled=' + state.inputDisabled +
      ' isLoading=' + state.isLoading + ' btn=' + state.btnOnclick + '); the first stream completed and its ' +
      'response was persisted (firstResp=' + firstResp + '), no second message was created (secondResp=' + secondResp + ')';
  }
});

scenarios.push({
  id: 215,
  name: 'Switching to an unanswered thread mid-stream leaves the loading indicator stuck after the stream completes - initChatMode shows the dots for the visible thread\'s trailing user message (isLoading is still true), and onStreamDone (scoped away by bug #195 for a non-current thread) never calls hideLoadingIndicator',
  mode: 'sse-slow',
  regression: true, // FIXED bug #215 kept as a regression check (completion clears the stuck dots)
  settings: {},
  fixtures: {
    threads: [
      { id: 't-ui-a-215', title: 'Thread A', active_leaf_id: 'm-215-u1a' },
      { id: 't-ui-b-215', title: 'Thread B (unanswered)', active_leaf_id: 'm-215-u1b' }
    ],
    messages: [
      { id: 'm-215-u1a', thread_id: 't-ui-a-215', role: 'user', content: 'question for A', token_count: 5, active_path_tokens: 5 },
      { id: 'm-215-u1b', thread_id: 't-ui-b-215', role: 'user', content: 'question for B (no answer yet)', token_count: 5, active_path_tokens: 5 }
    ]
  },
  async body({ cdp, dbPath }) {
    await showChat();
    await cdp.waitFor('document.querySelectorAll("#thread-list .chat-item").length >= 2', 15000, 300, 'thread list');
    await cdp.eval('window.loadThread("t-ui-a-215"); true');
    await cdp.waitFor('window.activeThreadId === "t-ui-a-215"', 15000, 300, 'thread A loaded');
    await sleep(600);
    await sendChatMessage(cdp, 'question for A');
    await cdp.waitFor('typeof streamState !== "undefined" && streamState.active === true', 20000, 50, 'streaming active');
    await sleep(150);
    // Switch to thread B (which ends with an unanswered USER message) while
    // A's stream is still in flight.
    await cdp.eval('window.loadThread("t-ui-b-215"); true');
    await cdp.waitFor('window.activeThreadId === "t-ui-b-215"', 15000, 300, 'thread B loaded');
    await sleep(400);
    // BUG: initChatMode sees isLoading=true and B's last message is a user
    // message, so it shows the loading dots in B's message list.
    const dotsDuring = await cdp.eval('document.getElementById("chat-loading") !== null');
    if (!dotsDuring)
      throw new Error('setup: loading dots not shown in B mid-stream (timing/flow changed): ' + dotsDuring);
    // Wait for A's stream to finish. B is not the sending thread, so
    // onStreamDone is scoped away (bug #195) and never hides the indicator.
    await waitStreamingIdle(cdp, 40000);
    await sleep(700);
    const dotsAfter = await cdp.eval('document.getElementById("chat-loading") !== null');
    const streamIdle = await cdp.eval('typeof streamState !== "undefined" && !streamState.active');
    if (!streamIdle) throw new Error('setup: stream never went idle');
    // FIXED (bug #215): once the stream completes, no request is in flight -
    // the composer is re-enabled and the visible loading dots must clear,
    // even though onStreamDone was scoped away for the non-current thread.
    if (dotsAfter)
      throw new Error('loading indicator is still visible after the stream completed (bug #215 not fixed)');
    return 'switched to unanswered thread B mid-stream: loading dots shown while streaming=' + dotsDuring +
      ', after A\'s stream completed (streamState.active=false) the dots are hidden in B=' + !dotsAfter +
      ' - completion of the non-current stream clears the stuck indicator';
  }
});

scenarios.push({
  id: 216,
  name: 'A failed retry restores the removed messages into WHATEVER thread is currently visible - restoreRetryMessagesOnError pushes _retryRemovedMessages (thread A\'s messages) into the global chatMessages array, so switching to thread B before the retry fails repaints A\'s assistant message into B\'s UI (the DB rows stay correct in A, the same class as bug #195 on the error path)',
  mode: 'sse-lateerror',
  regression: true, // FIXED bug #216 kept as a regression check (restore is scoped to the retry thread/path)
  settings: {},
  fixtures: {
    threads: [
      { id: 't-retry-a-216', title: 'Thread A', active_leaf_id: 'm-216-a1' },
      { id: 't-retry-b-216', title: 'Thread B', active_leaf_id: 'm-216-u1b' }
    ],
    messages: [
      { id: 'm-216-u1', thread_id: 't-retry-a-216', role: 'user', content: 'root question', token_count: 5, active_path_tokens: 5 },
      { id: 'm-216-a1', thread_id: 't-retry-a-216', role: 'assistant', content: 'first answer', model: 'deepseek/deepseek-v4-flash', parent_id: 'm-216-u1', token_count: 9, prompt_tokens: 12, active_path_tokens: 21 },
      { id: 'm-216-u1b', thread_id: 't-retry-b-216', role: 'user', content: 'question for B', token_count: 5, active_path_tokens: 5 }
    ]
  },
  async body({ cdp, dbPath }) {
    await showChat();
    await cdp.waitFor('document.querySelectorAll("#thread-list .chat-item").length >= 2', 15000, 300, 'thread list');
    await cdp.eval('window.loadThread("t-retry-a-216"); true');
    await cdp.waitFor('window.activeThreadId === "t-retry-a-216" && chatMessages.length >= 2', 15000, 300, 'thread A loaded');
    await sleep(600);
    // Retry the assistant message: the UI removes a1 from A's array and
    // stashes it in _retryRemovedMessages; the retry request starts streaming
    // against the mock (sse-lateerror) and will fail ~1.5s later.
    await cdp.click('#chat-messages .msg:nth-child(2) .msg-action-btn[title="Retry"]');
    await cdp.waitFor('chatMessages.length === 1 && chatMessages[0].id === "m-216-u1"', 15000, 300, 'retry removed a1');
    // The retry request is dispatched (buttons disabled / isLoading). The mock
    // mode sse-lateerror never emits content, so streamState.active stays
    // false - the failure arrives ~1.5s later with no content/reasoning.
    await cdp.waitFor('typeof isLoading !== "undefined" && isLoading === true', 20000, 50, 'retry in flight');
    // Switch to thread B BEFORE the retry fails.
    await cdp.eval('window.loadThread("t-retry-b-216"); true');
    await cdp.waitFor('window.activeThreadId === "t-retry-b-216"', 15000, 300, 'thread B loaded');
    await sleep(300);
    // Wait for the retry to fail (showError arrives; the retry's stream had no
    // content, so _handleStreamError posts the error banner).
    await cdp.waitFor('document.querySelector(".error-banner") !== null', 20000, 200, 'retry error banner');
    await sleep(600);
    const uiMsgs = await cdp.eval('chatMessages.map(function(m){ return m.id + ":" + m.content; })');
    const stillOnB = await cdp.eval('window.activeThreadId === "t-retry-b-216"');
    const a1inB = String(uiMsgs.join('|')).indexOf('first answer') >= 0;
    // FIXED (bug #216): the restore is scoped to the retry's thread/path, so
    // thread A's messages must NOT appear in thread B's visible UI.
    if (!stillOnB)
      throw new Error('setup: not on thread B anymore: ' + stillOnB);
    if (a1inB)
      throw new Error('restored thread-A messages still pollute thread B (bug #216 not fixed): ui=' + JSON.stringify(uiMsgs));
    // Sanity: the DB row for a1 still belongs to thread A only.
    const a1Rows = seed.query(dbPath, "SELECT thread_id FROM messages WHERE content='first answer'");
    const dbThreads = a1Rows.map((r) => r.thread_id);
    const a1OnlyInA = dbThreads.length === 1 && dbThreads[0] === 't-retry-a-216';
    if (!a1OnlyInA)
      throw new Error('DB sanity failed: "first answer" must live in thread A only: ' + JSON.stringify(dbThreads));
    return 'retried a1 in A, switched to B, then the retry failed: B\'s UI array is ' + JSON.stringify(uiMsgs) +
      ' (thread A\'s "first answer" is NOT in the visible thread B) while the DB row stays in ' +
      JSON.stringify(dbThreads) + ' - restoreRetryMessagesOnError is scoped to the retry thread';
  }
});

scenarios.push({
  id: 217,
  name: 'Deleting ANOTHER message\'s attachment while editing a message defers the wrong attachment to the edit commit - setupMessageAttachmentDeleteDelegation pushes any clicked attachment id into the GLOBAL _removedAttachmentIds (never checking it belongs to _editingMessageId), so overwrite-committing message 1\'s edit hard-deletes message 2\'s attachment row from the DB',
  mode: null,
  regression: true, // FIXED bug #217 kept as a regression check (only the edited message's attachments defer)
  settings: {},
  fixtures: {
    threads: [{ id: 't-att-217', title: 'Attachment Edit', active_leaf_id: 'm-217-u2' }],
    messages: [
      { id: 'm-217-u1', thread_id: 't-att-217', role: 'user', content: 'message one' },
      { id: 'm-217-u2', thread_id: 't-att-217', role: 'user', content: 'message two', parent_id: 'm-217-u1' }
    ]
  },
  async body({ cdp, dbPath }) {
    // Seed one attachment on EACH user message.
    const { DatabaseSync } = require('node:sqlite');
    const db = new DatabaseSync(dbPath);
    db.exec("INSERT INTO message_attachments (id, message_id, attachment_type, file_path, mime_type, original_filename, file_size, extracted_text) VALUES ('att-217-a', 'm-217-u1', 'text_file', 'attachments/a.txt', 'text/plain', 'a.txt', 12, ''), ('att-217-b', 'm-217-u2', 'text_file', 'attachments/b.txt', 'text/plain', 'b.txt', 12, '')");
    db.close();

    await showChat();
    await cdp.waitFor('document.querySelectorAll("#thread-list .chat-item").length > 0', 15000, 300, 'thread list');
    await cdp.click('#thread-list .chat-item');
    await cdp.waitFor('document.querySelectorAll("#chat-messages .msg").length >= 2', 15000, 300, 'thread loaded');
    await sleep(700);
    // Edit message 1.
    await cdp.click('#chat-messages .msg:nth-child(1) .msg-action-btn[title="Edit"]');
    await sleep(250);
    // While editing message 1, click the attachment X on message 2. The
    // delegated handler must scope the deferral to the edited message: an X
    // on a different bubble is neither deferred nor deleted (bug #217).
    await cdp.click('#chat-messages .msg:nth-child(2) .msg-attachment-delete');
    await sleep(250);
    const removedList = await cdp.eval('JSON.stringify(window._removedAttachmentIds || [])');
    if (String(removedList).indexOf('att-217-b') >= 0)
      throw new Error('setup: another message\'s attachment was still deferred: ' + removedList);
    // Commit message 1's edit (overwrite).
    await cdp.click('#chat-messages .msg:nth-child(1) .save-overwrite');
    await sleep(900);
    const rows = seed.query(dbPath, "SELECT id, message_id FROM message_attachments ORDER BY id");
    const ids = rows.map((r) => r.id);
    // FIXED (bug #217): the X on message 2's attachment is scoped out of the
    // edit - it is neither deferred into _removedAttachmentIds nor deleted,
    // so overwrite-committing message 1's edit leaves message 2's attachment
    // row untouched.
    if (String(removedList).indexOf('att-217-b') >= 0)
      throw new Error('another message\'s attachment was still deferred into the edit (bug #217 not fixed): ' + removedList);
    if (ids.indexOf('att-217-b') < 0)
      throw new Error('message 2 attachment was deleted by message 1\'s edit commit (bug #217 not fixed): ' + JSON.stringify(ids));
    if (ids.indexOf('att-217-a') < 0)
      throw new Error('message 1 attachment unexpectedly deleted: ' + JSON.stringify(ids));
    return 'edited message 1, clicked the X on message 2\'s attachment (deferred list stays ' + removedList +
      '), then overwrite-committed: the DB still holds ' + JSON.stringify(ids) +
      ' - only the edited message\'s attachments are affected by the edit';
  }
});

scenarios.push({
  id: 218,
  name: 'Switching THREADS mid-stream leaves a mismatched composer state - initChatMode unconditionally re-enables the input and send button (disabled=false) but never re-wires the button, so while the old stream is still active the input is editable, isLoading=false, and the button still shows Stop; pressing Enter sends a SECOND request that clobbers the first stream (same family as #214, but on the loadThread/initChatMode path)',
  mode: 'sse-slow',
  regression: true, // FIXED bug #218 kept as a regression check (composer stays in Stop mode mid-stream)
  settings: {},
  fixtures: {
    threads: [
      { id: 't-ui-a-218', title: 'Thread A', active_leaf_id: 'm-218-u1a' },
      { id: 't-ui-b-218', title: 'Thread B (answered)', active_leaf_id: 'm-218-a1b' }
    ],
    messages: [
      { id: 'm-218-u1a', thread_id: 't-ui-a-218', role: 'user', content: 'question for A', token_count: 5, active_path_tokens: 5 },
      { id: 'm-218-u1b', thread_id: 't-ui-b-218', role: 'user', content: 'question for B', token_count: 5, active_path_tokens: 5 },
      { id: 'm-218-a1b', thread_id: 't-ui-b-218', role: 'assistant', content: 'B answer', model: 'deepseek/deepseek-v4-flash', parent_id: 'm-218-u1b', token_count: 5, prompt_tokens: 10, active_path_tokens: 15 }
    ]
  },
  async body({ cdp }) {
    await showChat();
    await cdp.waitFor('document.querySelectorAll("#thread-list .chat-item").length >= 2', 15000, 300, 'thread list');
    await cdp.eval('window.loadThread("t-ui-a-218"); true');
    await cdp.waitFor('window.activeThreadId === "t-ui-a-218"', 15000, 300, 'thread A loaded');
    await sleep(600);
    await sendChatMessage(cdp, 'question for A');
    await cdp.waitFor('typeof streamState !== "undefined" && streamState.active === true', 20000, 50, 'streaming active');
    await sleep(150);
    // Switch to thread B (which ENDS WITH AN ASSISTANT) while A's stream is
    // still in flight.
    await cdp.eval('window.loadThread("t-ui-b-218"); true');
    await cdp.waitFor('window.activeThreadId === "t-ui-b-218" && chatMessages.length >= 2', 15000, 300, 'thread B loaded');
    await sleep(400);
    const state = await cdp.eval(`(() => ({
      streamActive: (typeof streamState !== 'undefined' && streamState.active) || false,
      inputDisabled: document.getElementById('chat-input').disabled,
      isLoading: (typeof isLoading !== 'undefined' && isLoading) || false,
      btnOnclick: (function(){ var b = document.getElementById('chat-send-btn'); return b && b.onclick ? String(b.onclick).indexOf('onStopStreaming') >= 0 ? 'stop' : 'send' : 'none'; })()
    }))()`);
    // FIXED (bug #218): initChatMode must keep the composer in Stop mode
    // while the first request is in flight - input disabled, isLoading stays
    // true, button wired to Stop.
    if (!state.streamActive)
      throw new Error('setup: first stream already finished before the state check');
    if (!state.inputDisabled || !state.isLoading || state.btnOnclick !== 'stop')
      throw new Error('composer mismatch after thread switch (bug #218 not fixed): ' + JSON.stringify(state));
    // Prove Enter cannot send a second request: even if a keydown reaches the
    // handler, the stream-active guard cancels instead of sending.
    await cdp.eval('if (window.__posted) window.__posted.length = 0;');
    await cdp.eval(`(() => {
      const input = document.getElementById('chat-input');
      input.value = 'second message';
      input.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true, cancelable: true }));
      return true;
    })()`);
    await sleep(500);
    const posted = await cdp.eval('(window.__posted || []).slice()');
    const secondSendPosted = posted.some((m) => String(m).indexOf('"chatSend"') >= 0 || String(m).indexOf('chatSend') >= 0);
    if (secondSendPosted)
      throw new Error('Enter sent a second request while the first stream was in flight (bug #218 not fixed): ' + JSON.stringify(posted));
    await waitStreamingIdle(cdp, 40000);
    return 'switched to assistant-ended thread B mid-stream: composer stayed disabled (inputDisabled=' + state.inputDisabled +
      ' isLoading=' + state.isLoading + ' btn=' + state.btnOnclick + '); a forced Enter keydown posted ' +
      JSON.stringify(posted) + ' (cancel, never chatSend) - the mismatch cannot fire a second send';
  }
});

scenarios.push({
  id: 222,
  name: 'Assistant responses whose paragraphs are separated by SINGLE newlines render as ONE block - chat-render.js md.render() never normalizes assistant content (unlike _prepUserContent for users), and markdown-it emits one <p> with soft breaks that CSS collapses to spaces, so a summarize-style response split into paragraphs by single newlines displays as a block of text',
  mode: 'sse-paragraphs',
  settings: {},
  async body({ cdp }) {
    await sendChatMessage(cdp, 'Please summarize this article.');
    // The mock streams three chunks whose paragraph breaks are SINGLE
    // newlines (a common summarize-style LLM output shape).
    await cdp.waitFor('document.querySelector(".msg.bot .msg-content") !== null', 30000, 300, 'assistant bubble rendered');
    await waitStreamingIdle(cdp, 30000);
    await sleep(500);
    const pCount = await cdp.eval('document.querySelectorAll(".msg.bot .msg-content p").length');
    const innerText = await cdp.eval('document.querySelector(".msg.bot .msg-content").innerText');
    const html = await cdp.eval('document.querySelector(".msg.bot .msg-content").innerHTML');
    // Buggy behavior (PASS = reproduced): the three paragraphs collapsed into
    // ONE <p> (soft breaks rendered as spaces), so the summary displays as a
    // block of text instead of three paragraphs.
    if (pCount !== 1)
      throw new Error('paragraphs were NOT collapsed into one block (bug not reproduced): pCount=' + pCount + ' html=' + JSON.stringify(html));
    const hasBreak = /<br\s*\/?>/i.test(String(html));
    return 'mock returned 3 paragraphs separated by single newlines; rendered pCount=' + pCount +
      (hasBreak ? ' (with <br>)' : ' (no <br>)') + ' innerText=' + JSON.stringify(String(innerText).replace(/\s+/g, ' ')) +
      ' - the summary displays as ONE block instead of maintaining the paragraphs';
  }
});

scenarios.push({
  id: 219,
  name: 'Mid-stream SSE error event (`data: {"error": ...}`) crashes SSEParser.ParseLine - parsed["choices"] throws on a Map without a "choices" key, so the partial streamed response is never persisted, the user sees an internal Key "choices" error, and streamState.active stays true: every subsequent Send is swallowed as cancelStream (the composer is wedged until reload)',
  mode: 'sse-error-event',
  settings: {},
  async body({ cdp, dbPath }) {
    await sendChatMessage(cdp, 'trigger an upstream stream error');
    // The mock streams one content chunk, then a REAL OpenAI-style
    // `data: {"error": {...}}` SSE event, then ends the response.
    await cdp.waitFor('document.querySelector(".error-banner") !== null', 25000, 200, 'error banner');
    await sleep(800);
    const banner = await cdp.text('.error-banner');
    const stillActive = await cdp.eval('typeof streamState !== "undefined" && streamState.active');
    const isLoadingNow = await cdp.eval('typeof isLoading !== "undefined" && isLoading');
    const uiMsgCount = await cdp.eval('chatMessages.length');
    const asstRows = seed.query(dbPath, "SELECT COUNT(*) AS cnt FROM messages WHERE role='assistant'");
    const partialInDb = seed.query(dbPath, "SELECT COUNT(*) AS cnt FROM messages WHERE content LIKE '%Partial answer%'");
    // Buggy behavior (PASS = reproduced): the internal parser crash leaves
    // streamState.active true - the composer stays in Stop mode and every
    // subsequent send is swallowed as cancelStream. The partial stream is also
    // lost (never persisted, never in chatMessages).
    if (!stillActive)
      throw new Error('streamState.active is false after the error event - composer not wedged (bug not reproduced): banner=' + JSON.stringify(banner));
    const showsInternal = String(banner).indexOf('choices') >= 0;
    return 'banner=' + JSON.stringify(banner) +
      ' streamState.active=' + stillActive + ' isLoading=' + isLoadingNow +
      ' chatMessages=' + uiMsgCount + ' assistantRowsInDb=' + asstRows[0].cnt +
      ' partialRowsInDb=' + partialInDb[0].cnt +
      (showsInternal ? ' (internal "choices" parser error surfaced)' : '') +
      ' - the partial stream is lost and the composer stays in Stop mode (every Send becomes cancelStream)';
  }
});

module.exports = scenarios;
