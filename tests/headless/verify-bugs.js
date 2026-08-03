// verify-bugs.js — Headless bug verification runner (WebView2 via CDP + AHK probes).
// Usage:
//   node verify-bugs.js --pilot            # bugs 1, 3, 6, 15, 22
//   node verify-bugs.js --all              # every scenario
//   node verify-bugs.js --scenarios=1,6,15 # specific bugs
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const { spawnSync } = require('node:child_process');

const { CDP } = require('./cdp');
const { startMockServer } = require('./mock-llm-server');
const seed = require('./seed');
const launcher = require('./launch');

const RESULTS_DIR = path.join(__dirname, 'results');
const RESULTS_FILE = path.join(RESULTS_DIR, 'headless-verification.txt');
let diagShown = false;

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// ---------- AHK probe helpers ----------

function runProbe(command, args = []) {
  const outFile = path.join(os.tmpdir(), 'llm-probe-' + command + '-' + process.pid + '.json');
  try { fs.unlinkSync(outFile); } catch {}
  const res = spawnSync(launcher.AHK, ['/ErrorStdOut', launcher.PROBE_AHK, command, outFile, ...args], {
    timeout: 25000,
    windowsHide: true,
    encoding: 'utf8'
  });
  if (res.error) throw new Error('probe ' + command + ' spawn failed/timed out: ' + res.error.message);
  if (res.stderr) process.stderr.write('[probe:' + command + ' stderr] ' + res.stderr);
  return parseProbeOutput(fs.readFileSync(outFile, 'utf-8'));
}

function parseProbeOutput(text) {
  const obj = {};
  // FileAppend "UTF-8" writes a BOM on the first line — strip it.
  for (const line of String(text || '').replace(/^\uFEFF/, '').split(/\r?\n/)) {
    if (!line) continue;
    const i = line.indexOf('|');
    if (i < 0) continue;
    const k = line.slice(0, i), v = line.slice(i + 1);
    obj[k] = /^-?\d+(\.\d+)?$/.test(v) ? Number(v) : v;
  }
  return obj;
}

// The app writes settings.json with a UTF-8 BOM — strip it before parsing.
function readJsonFile(file) {
  const raw = fs.readFileSync(file, 'utf8');
  return JSON.parse(raw.replace(/^\uFEFF/, ''));
}

function runThinkingProbe() {
  const outFile = path.join(os.tmpdir(), 'llm-thinking-probe-' + process.pid + '.json');
  try { fs.unlinkSync(outFile); } catch {}
  const probe = path.join(__dirname, 'probe-thinking.ahk');
  const res = spawnSync(launcher.AHK, ['/ErrorStdOut', probe, outFile], { timeout: 25000, windowsHide: true, encoding: 'utf8' });
  if (res.error) throw new Error('thinking probe spawn failed/timed out: ' + res.error.message);
  if (res.stderr) process.stderr.write('[probe-thinking stderr] ' + res.stderr);
  try { return fs.readFileSync(outFile, 'utf-8').split(/\r?\n/).filter(Boolean); } catch { return []; }
}

// ---------- CDP helpers ----------

async function showChat() {
  runProbe('show-chat');
}

async function openSettings(cdp) {
  await cdp.click('#settings-icon');
  await cdp.waitFor('document.getElementById("settingsNav").style.display !== "none" && document.querySelector("#providerGrid") !== null', 20000, 250, 'settings panel open');
  await sleep(500);
}

async function openSection(cdp, name) {
  await cdp.click('.settings-nav .nav-item[data-section="' + name + '"]');
  await sleep(400);
}

async function saveSettings(cdp, dataDir, timeoutMs = 20000) {
  const file = path.join(dataDir, 'settings.json');
  await cdp.click('.nav-footer .btn-primary');
  // Poll until the merged settings (with the models key) is on disk.
  const start = Date.now();
  for (;;) {
    try {
      const txt = fs.readFileSync(file, 'utf8');
      if (txt.includes('"models"')) return;
    } catch {}
    if (Date.now() - start > timeoutMs) throw new Error('saveSettings timeout');
    await sleep(300);
  }
}

async function hideSettingsToChat(cdp) {
  await cdp.click('#sidebar-toggle');
  await sleep(600);
}

async function sendChatMessage(cdp, text) {
  await cdp.type('#chat-input', text);
  await cdp.click('#chat-send-btn');
}

async function waitStreamingIdle(cdp, timeoutMs = 30000) {
  await cdp.waitFor(
    'typeof streamState !== "undefined" && !streamState.active && !isLoading',
    timeoutMs, 300, 'stream idle'
  );
}

// ---------- Scenario infrastructure ----------

async function runScenario(sc, iso, opts) {
  let server = null;
  let mainPid = 0;
  let cdp = null;
  let target = null;
  let noApp = !!sc.noApp;
  let mockLog = '';
  // For non-mock scenarios use a just-freed port so cURL fails with
  // "connection refused" BEFORE any output file exists (bug #6 path).
  const refusePort = await launcher.findFreePort();
  let endpoint = 'http://127.0.0.1:' + refusePort + '/v1/chat/completions';
  const detail = { step: 'setup' };
  try {
    if (sc.mode) {
      mockLog = path.join(iso.sandboxData, 'mock-requests.jsonl');
      server = await startMockServer(sc.mode, mockLog);
      endpoint = 'http://127.0.0.1:' + server.port + '/v1/chat/completions';
    }
    if (!noApp) launcher.resetDataDir(iso.sandboxData);
    const dataDir = noApp ? null : iso.sandboxData;
    if (!noApp) seed.writeSettings(dataDir, sc.settings || {}, endpoint);
    if (!noApp && sc.preLaunch) sc.preLaunch(dataDir);
    const dbPath = (!noApp && sc.fixtures) ? seed.createDb(dataDir, sc.fixtures) : (!noApp ? path.join(dataDir, 'chat_history.db') : null);
    detail.dbPath = dbPath;

    const port = await launcher.findFreePort();
    if (!noApp) {
      const launched = launcher.launch({ sandbox: iso.sandboxData, port });
      mainPid = launched.mainPid;
      detail.port = port;
      target = await launcher.waitForChatTarget(port);
      cdp = await CDP.connect(target.webSocketDebuggerUrl);
      await cdp.installPostMessageHook();
      await cdp.waitFor('document.readyState === "complete" && typeof chatMessages !== "undefined"', 60000, 400, 'chat page ready');
      // AHK wires the send button (onclick) after webViewReady — wait for it so
      // clicks/typing work on the very first interaction.
      await cdp.waitFor('document.getElementById("chat-send-btn") && document.getElementById("chat-send-btn").onclick !== null', 30000, 300, 'send button wired');
      await sleep(500);
      if (!diagShown) {
        diagShown = true;
        try {
          const info = runProbe('chat-info');
          console.log('window diag (live): ' + JSON.stringify(info));
        } catch {}
      }
    }

    const result = await sc.body({ cdp, dataDir, dbPath, port, endpoint, mockLog });
    if (cdp) await cdp.close();
    return { id: sc.id, name: sc.name, pass: true, detail: result, pid: mainPid };
  } catch (e) {
    if (cdp) try { await cdp.close(); } catch {}
    return { id: sc.id, name: sc.name, pass: false, detail: detail.step + ' -> ' + (e && e.message ? e.message : String(e)), dataDir: iso.sandboxData, pid: mainPid };
  } finally {
    if (mainPid) launcher.teardown(mainPid);
    if (server) try { server.server.close(); } catch {}
  }
}

// ---------- Scenarios ----------

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
  id: 3,
  name: 'Removing models/providers in Settings persists (removed entries stay removed)',
  regression: true, // FIXED bug kept as a regression check (removals must not be resurrected by merge)
  mode: null,
  settings: {},
  async body({ cdp, dataDir }) {
    const settingsFile = path.join(dataDir, 'settings.json');
    await openSettings(cdp);
    await openSection(cdp, 'models');
    await cdp.waitFor('document.querySelectorAll("#modelsTableBody tr").length > 0', 10000, 250, 'models table');
    await cdp.click('#modelsTableBody tr .btn-sm.danger');
    await openSection(cdp, 'providers');
    await cdp.waitFor('document.querySelectorAll("#providerGrid .provider-card").length > 1', 10000, 250, 'provider cards');
    await cdp.click('#providerGrid .provider-card .btn-sm.danger');
    await saveSettings(cdp, dataDir);
    const saved = readJsonFile(settingsFile);
    // The first table row is the alphabetically-first model of the merged
    // defaults (deepseek/deepseek-chat). The row input shows the STRIPPED id,
    // so assert on the full key.
    const modelBack = saved.models && saved.models['deepseek/deepseek-chat'];
    const providerBack = saved.providers && saved.providers.deepseek;
    if (modelBack) throw new Error('removed model deepseek/deepseek-chat is still present in settings.json after save');
    if (providerBack) throw new Error('removed provider deepseek is still present in settings.json after save');
    // Reload half: hide and reopen Settings so AHK re-merges the saved file
    // with defaults (the same Merge used at startup and after WM_SETTINGS_UPDATED).
    // Removed entries must not come back from the defaults.
    await cdp.waitFor('window.SettingsPanel && !window.SettingsPanel.isDirty()', 10000, 250, 'save acknowledged');
    await cdp.click('#sidebar-toggle');
    await sleep(500);
    await openSettings(cdp);
    await openSection(cdp, 'models');
    await cdp.waitFor('document.querySelectorAll("#modelsTableBody tr").length > 0', 10000, 250, 'models table re-rendered');
    await sleep(400);
    const modelRows = await cdp.eval(`[...document.querySelectorAll('#modelsTableBody tr')].map(tr => ({
      id: (tr.querySelector('[data-field="id"]') || {}).value || '',
      provider: (tr.querySelector('[data-field="provider"]') || {}).value || ''
    }))`);
    if (modelRows.some((r) => r.id === 'deepseek-chat' && r.provider === 'deepseek'))
      throw new Error('removed model deepseek/deepseek-chat came back from defaults after reopening settings: ' + JSON.stringify(modelRows));
    await openSection(cdp, 'providers');
    const providerKeys = await cdp.eval(`[...document.querySelectorAll('#providerGrid .provider-card')].map(c => c.dataset.providerKey || '')`);
    if (providerKeys.includes('deepseek'))
      throw new Error('removed provider deepseek came back from defaults after reopening settings: ' + JSON.stringify(providerKeys));
    return 'after removing deepseek/deepseek-chat and provider deepseek, both stay removed in settings.json and after reopening settings';
  }
});

scenarios.push({
  id: 4,
  name: 'Clearing a hotkey field disables the hotkey (empty = off)',
  regression: true, // FIXED bug kept as a regression check (cleared hotkeys must stay disabled)
  mode: null,
  settings: { hotkeys: { main: '`', reload: '~^!r', closeWindows: '~^w', suspend: 'CapsLock & `' } },
  async body({ cdp, dataDir }) {
    const settingsFile = path.join(dataDir, 'settings.json');
    await openSettings(cdp);
    await openSection(cdp, 'hotkeys');
    await cdp.waitFor('document.getElementById("hkMain") !== null', 10000, 250, 'hotkeys form');
    await cdp.type('#hkMain', '');
    await saveSettings(cdp, dataDir);
    const saved = readJsonFile(settingsFile);
    if (saved.hotkeys.main !== '') throw new Error('expected empty main hotkey saved, got ' + JSON.stringify(saved.hotkeys.main));
    await sleep(1500); // let Main re-register hotkeys after WM_SETTINGS_UPDATED
    let menu = runProbe('menu-open');
    if (menu.open) {
      await sleep(1500);
      menu = runProbe('menu-open');
    }
    if (menu.open) throw new Error('backtick still opens the command menu after disabling the main hotkey; probe=' + JSON.stringify(menu));
    return 'cleared main hotkey saves as "" and backtick no longer opens the command menu';
  }
});

scenarios.push({
  id: 5,
  name: 'New model keeps thinking metadata across a Settings save (reasoning dropdown shows its levels)',
  regression: true, // FIXED bug kept as a regression check (metadata must survive settings saves)
  mode: 'json',
  settings: {},
  preLaunch(dataDir) {
    // Seed a NEW model id (not present in DefaultModels.ahk) that carries full
    // metadata, exactly as the fetch pipeline produces it. It has no defaults
    // entry to refill from, so everything it has must survive the save
    // round-trip on its own.
    const settingsFile = path.join(dataDir, 'settings.json');
    const cfg = readJsonFile(settingsFile);
    cfg.models = {
      'openai/gpt-brand-new': {
        provider: 'openai',
        api: 'openai-completions',
        compat: {
          thinkingFormat: 'openai',
          supportsReasoningEffort: true,
          supportsUsageInStreaming: true,
          maxTokensField: 'max_completion_tokens'
        },
        thinkingLevelMap: { low: 'low', high: 'high' },
        thinkingOff: 'none',
        input: 0.4, cachedInput: 0.1, output: 1.6, context: 128000, reasoning: true, vision: false
      }
    };
    fs.writeFileSync(settingsFile, JSON.stringify(cfg, null, 2));
  },
  async body({ cdp, dataDir }) {
    await showChat();
    await openSettings(cdp);
    await openSection(cdp, 'models');
    await cdp.waitFor('document.querySelectorAll("#modelsTableBody tr").length > 0', 10000, 250, 'models table');
    // Make the panel dirty (Save is disabled otherwise) with a no-op edit on
    // the seeded row, then run the save round-trip.
    const rowSel = '#modelsTableBody tr:first-child [data-field="context"]';
    await cdp.waitFor('document.querySelector(' + JSON.stringify(rowSel) + ') !== null', 5000, 200, 'seeded model row');
    await cdp.type(rowSel, '128K');
    await cdp.click('.nav-footer .btn-primary');
    await cdp.waitFor('window.SettingsPanel && !window.SettingsPanel.isDirty()', 15000, 300, 'save acknowledged');
    // The saved file must still carry the metadata for the new id.
    const saved = readJsonFile(path.join(dataDir, 'settings.json'));
    const back = saved.models && saved.models['openai/gpt-brand-new'];
    if (!back || !back.thinkingLevelMap || !back.thinkingLevelMap.high)
      throw new Error('saved model lost thinking metadata: ' + JSON.stringify(back));
    await hideSettingsToChat(cdp);
    await cdp.waitFor('window.modelList && Object.keys(window.modelList).length > 0', 15000, 300, 'model list');
    await cdp.click('#modelCardTrigger');
    await cdp.waitFor('document.getElementById("modelPopover").classList.contains("open")', 5000, 200, 'popover open');
    await cdp.click('.popover-tab[data-target="tab-models"]');
    await cdp.waitFor('[...document.querySelectorAll("#tab-models .selector-item .si-name")].some(e => e.textContent === "gpt-brand-new")', 10000, 250, 'new model listed');
    await cdp.eval(`(() => {
      const items = [...document.querySelectorAll('#tab-models .selector-item')];
      const it = items.find(e => e.querySelector('.si-name').textContent === 'gpt-brand-new');
      it.click();
      return true;
    })()`);
    await cdp.waitFor('window._currentSettings.model.indexOf("gpt-brand-new") >= 0', 10000, 250, 'model selected');
    // FIXED behavior: the model's levels must be offered after the save
    // round-trip (before the fix, only "Model Default" remained).
    await cdp.waitFor('document.getElementById("reasoningDropdown").options.length > 1', 15000, 300, 'reasoning dropdown shows levels');
    const opts = await cdp.eval('[...document.getElementById("reasoningDropdown").options].map(o => o.textContent)');
    if (opts.length <= 1) throw new Error('expected the model\'s levels, got only ' + JSON.stringify(opts));
    if (opts.filter((o) => o === 'Low' || o === 'High').length < 2)
      throw new Error('seeded levels low/high missing from dropdown: ' + JSON.stringify(opts));
    return 'after Settings save, openai/gpt-brand-new keeps thinkingLevelMap and offers ' + JSON.stringify(opts);
  }
});

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
  id: 8,
  name: 'Close-Windows hotkey setting is honored by the chat window (dynamic registration)',
  regression: true, // FIXED bug kept as a regression check (chat window must keep honoring the setting)
  mode: null,
  settings: { hotkeys: { main: '`', reload: '~^!r', closeWindows: '~^q', suspend: 'CapsLock & `' } },
  async body({ cdp }) {
    // Live key injection is unreliable in this session (injected keys sometimes
    // don't reach AHK hotkeys). Verify the fix statically: the chat window must
    // register the CONFIGURED closeWindowsHotkey dynamically (no hardcoded
    // ~^w::), empty = disabled, and re-register after settings saves.
    const chatWin = fs.readFileSync(path.join(launcher.REPO_ROOT, 'chat', 'ChatWindow.ahk'), 'utf8');
    const chatHk = fs.readFileSync(path.join(launcher.REPO_ROOT, 'chat', 'ChatHotkeys.ahk'), 'utf8');
    const dispatch = fs.readFileSync(path.join(launcher.REPO_ROOT, 'chat', 'callbacks', 'Dispatch.ahk'), 'utf8');
    const hr = fs.readFileSync(path.join(launcher.REPO_ROOT, 'app', 'HotkeyRegistrar.ahk'), 'utf8');
    const noHardcode = !/::\s*ChatHotkeys\("closeWindows"\)/.test(chatWin) && !/~\^w::/.test(chatWin);
    const includesModule = chatWin.includes('#Include ChatHotkeys.ahk');
    const registersAtStartup = chatWin.includes('_registerChatHotkeys()');
    const dynamicRegister = /Hotkey\(\s*closeWindowsHotkey/.test(chatHk) && /_activeChatHotkey/.test(chatHk);
    const emptyMeansDisabled = /if\s+_activeChatHotkey[\s\S]*Hotkey\(_activeChatHotkey,\s*"Off"\)/.test(chatHk)
      && /if\s+closeWindowsHotkey[\s\S]*Hotkey\(closeWindowsHotkey/.test(chatHk);
    const reRegistersOnSave = (dispatch.match(/_registerChatHotkeys\(\)/g) || []).length >= 2;
    const mainOnlyClosesInput = /case "closeWindows":[\s\S]*?commandInputWindow\.guiObj\.hWnd/.test(hr);
    if (!noHardcode || !includesModule || !registersAtStartup) throw new Error('ChatWindow still hardcodes the close hotkey or does not register it');
    if (!dynamicRegister || !emptyMeansDisabled) throw new Error('ChatHotkeys.ahk does not register closeWindowsHotkey dynamically with empty=disabled');
    if (!reRegistersOnSave) throw new Error('Dispatch does not re-register chat hotkeys after settings saves');
    if (!mainOnlyClosesInput) throw new Error('Main closeWindows handler unexpectedly closes the chat window');
    // The Hotkeys tab must no longer claim a restart is required — hotkey
    // changes are live on both the main script and the chat window.
    await openSettings(cdp);
    await openSection(cdp, 'hotkeys');
    await cdp.waitFor('document.getElementById("hkMain") !== null', 10000, 250, 'hotkeys form');
    const restartWarning = await cdp.eval(`(() => {
      const btn = document.getElementById('restartNowBtn');
      const banner = [...document.querySelectorAll('.warning-banner')].find(b => b.textContent.indexOf('restart') >= 0);
      return { btn: !!btn, banner: !!banner };
    })()`);
    if (restartWarning.btn || restartWarning.banner)
      throw new Error('stale restart warning still shown in Hotkeys: ' + JSON.stringify(restartWarning));
    return 'ChatWindow registers the configured closeWindowsHotkey via ChatHotkeys.ahk (empty=disabled, re-registered on save); Main still handles only the input window; no restart warning shown';
  }
});

scenarios.push({
  id: 9,
  name: 'Quick Access > Usage Dashboard does nothing on prewarmed window',
  mode: null,
  settings: {},
  regression: true, // REFUTED bug kept as a regression check (dashboard must keep opening)
  async body({ cdp }) {
    const info = runProbe('chat-info');
    if (info.title !== 'LLM AutoHotkey Assistant') throw new Error('unexpected prewarm title: ' + JSON.stringify(info.title));
    const menu = runProbe('send-menu-usage');
    if (!menu.menuOpened) throw new Error('backtick menu did not open; probe=' + JSON.stringify(menu));
    await sleep(1200);
    const dash = await cdp.eval('document.getElementById("dashboard-panel") ? getComputedStyle(document.getElementById("dashboard-panel")).display : "missing"');
    if (dash === 'flex') {
      return 'REFUTED: Quick Access > usage: OPENED the dashboard despite prewarmed title "' + info.title + '"';
    }
    return 'prewarmed title="' + info.title + '", menuOpened=1, dashboard stayed ' + dash + ' after Quick Access > usage:';
  }
});

scenarios.push({
  id: 12,
  name: 'Suspend banner edits apply live (no restart required)',
  regression: true, // FIXED bug kept as a regression check (banner must keep rebuilding on save)
  mode: null,
  settings: { ui: { suspendBanner: { text: 'OLD BANNER TEXT', fontSize: 's10', fontFace: 'Arial', textColor: 'cBlack', background: '0xFFDF00' } } },
  async body({ cdp, dataDir }) {
    // Static: Main's settings-updated handler must rebuild the banner GUI.
    const mainAhk = fs.readFileSync(path.join(launcher.REPO_ROOT, 'Main.ahk'), 'utf8');
    const sbModule = fs.readFileSync(path.join(launcher.REPO_ROOT, 'app', 'SuspendBanner.ahk'), 'utf8');
    if (!mainAhk.includes('_rebuildSuspendBanner()'))
      throw new Error('Main.ahk does not rebuild the suspend banner on settings updates');
    if (!/suspendBanner\.Destroy\(\)[\s\S]*suspendBanner := Gui\(\)/.test(sbModule))
      throw new Error('SuspendBanner.ahk does not rebuild the GUI from scratch');
    await openSettings(cdp);
    await openSection(cdp, 'ui');
    await cdp.waitFor('document.getElementById("sbText") !== null', 10000, 250, 'ui form');
    await cdp.type('#sbText', 'NEW BANNER TEXT');
    await saveSettings(cdp, dataDir);
    await sleep(1500); // let Main receive WM_SETTINGS_UPDATED and rebuild
    const banner = runProbe('suspend-banner');
    if (!banner.found) throw new Error('suspend banner window not found; probe=' + JSON.stringify(banner));
    if (String(banner.bannerText).trim() !== 'NEW BANNER TEXT')
      throw new Error('banner still shows ' + JSON.stringify(String(banner.bannerText).trim()) + '; probe=' + JSON.stringify(banner));
    return 'after saving NEW BANNER TEXT, suspended banner shows it live without a restart';
  }
});

scenarios.push({
  id: 13,
  name: 'Command Input Window settings apply live (width/height/font/colors)',
  regression: true, // FIXED bug kept as a regression check (input window must keep rebuilding on save)
  mode: null,
  settings: {
    ui: { inputWindow: { background: '0x212529', fontSize: 's14', fontColor: 'cWhite', fontFace: 'Arial', width: 500, height: 250 } },
    commands: [{
      commandName: 'Test Input', menuText: '&9 - Test Input', APIModels: 'deepseek/deepseek-v4-flash',
      pasteMode: 'chat', showInputBox: true, userMessage: '{{input}}', thinking: '', stream: false
    }]
  },
  async body({ cdp, dataDir }) {
    await openSettings(cdp);
    await openSection(cdp, 'ui');
    await cdp.waitFor('document.getElementById("iwWidth") !== null', 10000, 250, 'ui form');
    await cdp.type('#iwWidth', '800');
    await saveSettings(cdp, dataDir);
    await sleep(1500); // let Main receive WM_SETTINGS_UPDATED and rebuild
    const opened = runProbe('open-input', ['9']);
    if (!opened.menuOpened) throw new Error('backtick menu did not open for input window; probe=' + JSON.stringify(opened));
    await sleep(600);
    const pos = runProbe('input-window-pos', ['Test Input']);
    if (!pos.hwnd) throw new Error('input window did not open');
    runProbe('close-input');
    if (Number(pos.w) < 700) throw new Error('input window opened at width ' + pos.w + ' (setting not applied live)');
    return 'after saving width 800, input window opened at width ' + pos.w + ' (applied live, no restart)';
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
  id: 16,
  name: 'API Logs viewer latency column shows the request duration',
  regression: true, // FIXED bug kept as a regression check (latency must keep rendering)
  mode: 'sse-success',
  settings: {},
  async body({ cdp, port }) {
    await showChat();
    await sendChatMessage(cdp, 'hello from bug 16');
    await waitStreamingIdle(cdp);
    const t = await launcher.findTarget(port, 'api-logs.html', 30000);
    if (!t) throw new Error('api-logs viewer target not found');
    const logs = await CDP.connect(t.webSocketDebuggerUrl);
    await logs.eval('reloadLogs()');
    await logs.waitFor('document.querySelectorAll("#logBody tr.clickable").length > 0', 15000, 300, 'log rows');
    const latency = await logs.eval('document.querySelector("#logBody tr.clickable td:nth-child(4)").textContent');
    await logs.close();
    // FIXED: the viewer must read responseTimeMs (the field every logger
    // writes) so the column shows the real duration instead of "-".
    if (latency === '-' || latency === '') throw new Error('latency cell still empty: ' + JSON.stringify(latency));
    return 'log row latency cell = ' + JSON.stringify(latency) + ' (viewer reads responseTimeMs)';
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
  id: 18,
  name: 'Custom icon picked outside the repo never applies to the chat window',
  regression: true, // FIXED bug kept as a regression check (absolute icon paths must keep loading)
  mode: null,
  settings: { icons: { iconOn: '', iconOff: 'icons/IconOff.ico' } },
  preLaunch(dataDir) {
    // Copy the repo icon to %TEMP% (OUTSIDE the repo) and point iconOn at it.
    const absIco = path.join(os.tmpdir(), 'llm-headless-custom-' + process.pid + '.ico');
    fs.copyFileSync(path.join(launcher.REPO_ROOT, 'icons', 'IconOn.ico'), absIco);
    const settingsFile = path.join(dataDir, 'settings.json');
    const cfg = readJsonFile(settingsFile);
    cfg.icons.iconOn = absIco;
    fs.writeFileSync(settingsFile, JSON.stringify(cfg, null, 2));
  },
  async body({ cdp }) {
    const absIco = path.join(os.tmpdir(), 'llm-headless-custom-' + process.pid + '.ico');
    const mangled = runProbe('icon-check', [absIco]);
    if (mangled.hCustom === 0) throw new Error('direct LoadPicture of the chosen icon failed; probe=' + JSON.stringify(mangled));
    if (mangled.hMangled !== 0) throw new Error('mangled path unexpectedly loaded; probe=' + JSON.stringify(mangled));
    if (mangled.customApplied !== 1) throw new Error('custom icon NOT applied to chat window; probe=' + JSON.stringify(mangled));
    return 'absolute icon path: direct LoadPicture ok (h=' + mangled.hCustom + '), mangled path h=' + mangled.hMangled + ', custom icon applied to chat window (customApplied=1)';
  }
});

scenarios.push({
  id: 19,
  name: 'Dashboard "All Time" chart caps at 365 days while summary sums all rows',
  regression: true, // FIXED bug kept as a regression check (All Time must keep spanning the full history)
  mode: null,
  settings: {},
  fixtures: {
    chatUsage: [
      { date: seed.daysAgo(400), model: 'deepseek/deepseek-v4-flash', provider: 'deepseek', call_count: 1, prompt_tokens: 10, completion_tokens: 5, cached_tokens: 2, input_cost: 2, cached_input_cost: 0.2, output_cost: 3, total_cost: 5 },
      { date: seed.daysAgo(1), model: 'deepseek/deepseek-v4-flash', provider: 'deepseek', call_count: 1, prompt_tokens: 10, completion_tokens: 5, cached_tokens: 0, input_cost: 0.4, cached_input_cost: 0, output_cost: 0.6, total_cost: 1 }
    ]
  },
  async body({ cdp }) {
    await showChat();
    await cdp.click('#dashboard-icon');
    await cdp.waitFor('typeof allData !== "undefined" && allData.chat && allData.chat.length >= 1', 15000, 300, 'dashboard data');
    await cdp.eval('document.getElementById("timeRange").value = "all"; loadData(); true');
    await cdp.waitFor('typeof allData !== "undefined" && allData.chat.length === 2', 15000, 300, 'all-time data');
    const totalCost = await cdp.text('#totalCost');
    const labels = await cdp.eval('mainChart ? mainChart.data.labels.length : -1');
    if (totalCost !== '$6.00') throw new Error('summary total = ' + totalCost + ' (expected $6.00 = all-time)');
    if (labels !== 401) throw new Error('chart labels = ' + labels + ' (expected 401 = full history incl. the 400-day-old row)');
    const firstLabel = await cdp.eval('mainChart.data.labels[0]');
    return 'All Time: summary shows $6.00 (includes 400-day-old row) and chart spans the full history — ' + labels + ' labels, first = ' + firstLabel;
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
  id: 22,
  name: 'Command thinking setting survives settings round-trip (Map/object forms)',
  regression: true, // FIXED bug kept as a regression check (thinking must keep surviving round-trips)
  mode: null,
  settings: {},
  noApp: true,
  async body() {
    const lines = runThinkingProbe();
    const text = lines.join('\n');
    if (!text.includes('BUG22 FIXED')) throw new Error('probe output: ' + text);
    return text.split('\n').filter((l) => l.includes('thinking')).join(' | ');
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
  id: 24,
  name: 'Input window Edit field renders the configured background (text stays visible)',
  regression: true, // FIXED bug kept as a regression check (Edit must keep honoring the configured background)
  mode: null,
  settings: {
    ui: { inputWindow: { background: '0x212529', fontSize: 's14', fontColor: 'cWhite', fontFace: 'Arial', width: 500, height: 250 } },
    commands: [{
      commandName: 'Test Input', menuText: '&9 - Test Input', APIModels: 'deepseek/deepseek-v4-flash',
      pasteMode: 'chat', showInputBox: true, userMessage: '{{input}}', thinking: '', stream: false
    }]
  },
  async body() {
    // REGRESSION: the input window fix applied a dark background + light font,
    // but the Edit control does not inherit Gui.BackColor — it stayed white, so
    // white text was invisible. The Edit must be created with its own
    // Background option so the field matches the configured background.
    const opened = runProbe('open-input', ['9']);
    if (!opened.menuOpened) throw new Error('backtick menu did not open for input window; probe=' + JSON.stringify(opened));
    await sleep(600);
    const sample = runProbe('input-window-edit-color', ['Test Input']);
    if (!sample.hwnd) throw new Error('input window did not open');
    runProbe('close-input');
    if (sample.color === '0xFFFFFF')
      throw new Error('Edit field still renders the default white background (invisible light text): ' + JSON.stringify(sample));
    return 'input window Edit field renders ' + sample.color + ' (dark background, light text visible)';
  }
});

scenarios.push({
  id: 25,
  name: 'Input window default design is light (readable text on the default field)',
  regression: true, // FIXED bug kept as a regression check (default must stay light)
  mode: null,
  settings: {
    commands: [{
      commandName: 'Test Input', menuText: '&9 - Test Input', APIModels: 'deepseek/deepseek-v4-flash',
      pasteMode: 'chat', showInputBox: true, userMessage: '{{input}}', thinking: '', stream: false
    }]
  },
  async body() {
    // REGRESSION guard: the app is light-themed, so the DEFAULT input window
    // must be light (white field + dark text). The previous default was dark
    // (0x212529 + cWhite), which looked broken against the light UI.
    const opened = runProbe('open-input', ['9']);
    if (!opened.menuOpened) throw new Error('backtick menu did not open for input window; probe=' + JSON.stringify(opened));
    await sleep(600);
    const sample = runProbe('input-window-edit-color', ['Test Input']);
    if (!sample.hwnd) throw new Error('input window did not open');
    runProbe('close-input');
    const isDark = /^0x[0-7]/.test(sample.color); // high byte 0x00-0x7F = dark
    if (isDark)
      throw new Error('default input window field is dark (' + sample.color + '); expected light');
    return 'default input window Edit field renders ' + sample.color + ' (light design)';
  }
});

// ---------- Runner ----------

function parseArgs() {
  const argv = process.argv.slice(2);
  if (argv.includes('--pilot')) return [1, 3, 6, 15, 22];
  if (argv.includes('--all')) return scenarios.map((s) => s.id);
  const sc = argv.find((a) => a.startsWith('--scenarios='));
  if (sc) return sc.split('=')[1].split(',').map((n) => parseInt(n, 10));
  return [1, 3, 6, 15, 22]; // default pilot
}

// Cross-check BUG_HUNT_REPORT.md against the scenario list so neither goes stale.
function checkReportSync() {
  const reportFile = path.join(__dirname, 'BUG_HUNT_REPORT.md');
  if (!fs.existsSync(reportFile)) {
    console.error('Sync FAIL: BUG_HUNT_REPORT.md not found next to verify-bugs.js');
    return false;
  }
  const text = fs.readFileSync(reportFile, 'utf8');
  const start = text.indexOf('## Open bugs');
  const end = Math.min(
    ...['## History', '## Refuted', '## Fixed']
      .map((h) => text.indexOf(h))
      .filter((i) => i > start)
  );
  const section = (start >= 0 && end > start) ? text.slice(start, end) : text;
  const reportIds = new Set();
  for (const m of section.matchAll(/\*\*Scenario:\*\*\s*(\d+)/g)) reportIds.add(parseInt(m[1], 10));
  const known = new Set(scenarios.map((s) => s.id));
  const missing = [...reportIds].filter((id) => !known.has(id));
  const unlisted = scenarios.filter((s) => !reportIds.has(s.id) && !s.regression).map((s) => s.id);
  const dupes = [...new Set(scenarios.map((s) => s.id).filter((id, i, arr) => arr.indexOf(id) !== i))];
  let ok = true;
  if (missing.length) {
    console.error('Sync FAIL: report references scenarios that do not exist in verify-bugs.js: ' + missing.join(', '));
    ok = false;
  }
  if (unlisted.length) {
    console.error('Sync FAIL: scenarios with no report entry (add an entry or mark regression: true): ' + unlisted.join(', '));
    ok = false;
  }
  if (dupes.length) {
    console.error('Sync FAIL: duplicate scenario ids in verify-bugs.js: ' + dupes.join(', '));
    ok = false;
  }
  if (ok) {
    const reg = scenarios.filter((s) => s.regression).length;
    console.log('Sync OK: ' + reportIds.size + ' open-bug entries, ' + scenarios.length + ' scenarios (' + reg + ' regression/refuted checks)');
  }
  return ok;
}

async function main() {
  fs.mkdirSync(RESULTS_DIR, { recursive: true });
  const ids = parseArgs();
  if (process.argv.includes('--check-sync')) {
    process.exit(checkReportSync() ? 0 : 1);
  }
  if (process.argv.includes('--cleanup')) {
    // Close ONLY this repo's app scripts (Main.ahk, chat/ChatWindow.ahk), by PID.
    // Never kill AutoHotkey64.exe processes wholesale -- the user runs their own
    // AHK scripts and a blanket kill (Stop-Process -Name AutoHotkey64 -Force,
    // taskkill /IM AutoHotkey64.exe) closes those too. The probe matches by
    // process command line, so it also finds an app the user started on their
    // own (interactive) desktop, which this sandbox desktop cannot see.
    let out;
    try {
      out = runProbe('kill-app');
    } catch (e) {
      console.error('cleanup probe failed: ' + e.message);
      process.exit(4);
    }
    console.log('Closed ' + out.closed + ' app process(es)' + (out.pids ? ' (pids: ' + out.pids + ')' : '') + '. Other AutoHotkey scripts were not touched.');
    process.exit(0);
  }
  const selected = scenarios.filter((s) => ids.includes(s.id));
  if (selected.length !== ids.length) {
    console.error('Unknown scenario ids: ' + ids.filter((i) => !scenarios.some((s) => s.id === i)).join(','));
    process.exit(2);
  }
  if (launcher.preflight()) {
    console.error('ABORT: the app (Main.ahk/ChatWindow.ahk) appears to be running already (#SingleInstance). Close it and re-run, or if it is a leftover from an aborted run: node tests/headless/verify-bugs.js --cleanup');
    process.exit(3);
  }
  console.log('Isolating the real profile (junction redirect)...');
  const spawnedPids = [];
  const lines = [];
  let passCount = 0;
  let iso = null;
  let restored = 'not attempted';
  try {
    iso = launcher.isolateProfile();
    console.log('Launching headless verification for ' + selected.length + ' scenarios...');
    for (const sc of selected) {
      const started = Date.now();
      const r = await runScenario(sc, iso, {});
      if (r.pid) spawnedPids.push(r.pid);
      if (r.dataDir) lines.push('  (data dir for inspection: ' + r.dataDir + ')');
      const secs = ((Date.now() - started) / 1000).toFixed(1);
      const tag = r.pass ? 'PASS' : 'FAIL';
      if (r.pass) passCount++;
      const line = tag + ' | #' + String(r.id).padStart(2, '0') + ' | ' + r.name + ' | ' + r.detail + (r.pass ? '' : '');
      console.log(line);
      lines.push(line + ' | ' + secs + 's');
    }
  } catch (e) {
    console.error('Runner error:', e);
    if (/EPERM|isolat/i.test(String(e && e.message))) {
      console.error('Hint: the profile could not be moved. Two common causes: (1) the app is running or left over and holds the profile -- run `node tests/headless/verify-bugs.js --cleanup` (closes ONLY this repo\'s Main.ahk / chat/ChatWindow.ahk by command line + window title, never other AHK scripts); (2) the runner lacks permission to move the real profile (sandbox) -- re-run with elevated permissions, since launching the app and isolating the profile need the user\'s rights. If cleanup reports "Closed 0" and the profile is still blocked, ask the user before killing any AutoHotkey64.exe.');
    }
    lines.push('RUNNER ERROR: ' + (e && e.message ? e.message : String(e)));
  } finally {
    for (const pid of spawnedPids) launcher.teardown(pid);
    if (iso) restored = launcher.restoreProfile(iso) ? 'yes' : 'NO — CHECK MANUALLY';
  }
  lines.push('');
  lines.push('Summary: ' + passCount + '/' + selected.length + ' scenarios PASS');
  lines.push('Real profile restored: ' + restored);
  lines.push('Report sync: ' + (checkReportSync() ? 'OK' : 'MISMATCH — update BUG_HUNT_REPORT.md or verify-bugs.js'));
  fs.writeFileSync(RESULTS_FILE, lines.join('\n') + '\n', 'utf-8');
  console.log('\nResults written to ' + RESULTS_FILE);
  console.log('Real profile restored: ' + restored);
  console.log('Report sync: ' + (checkReportSync() ? 'OK' : 'MISMATCH — update BUG_HUNT_REPORT.md or verify-bugs.js'));
  process.exit(passCount === selected.length ? 0 : 1);
}

main().catch((e) => {
  console.error('Runner error:', e);
  process.exit(2);
});
