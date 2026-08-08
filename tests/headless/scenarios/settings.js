// scenarios/settings.js - Settings persistence and application (hotkeys, icons, tray, modals)
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
const { sleep, runIconCheck, readJsonFile, showChat, openSettings, openSection, saveSettings, hideSettingsToChat, sendChatMessage, waitStreamingIdle } = require('./helpers');

const scenarios = [];

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
    // Zero-injection: verify the registrar skips empty bindings statically
    // (sending the real backtick to prove the menu does not open would leak a
    // keystroke into the user's typing when the injection misses the hotkey).
    const hr = fs.readFileSync(path.join(launcher.REPO_ROOT, 'app', 'HotkeyRegistrar.ahk'), 'utf8');
    const skipsEmpty = /if !key\s*\n\s*return ""/.test(hr);
    const mainRoutedThroughHotkeyOn = /_activeHotkeys\.main := _HotkeyOn\(mainHotkey/.test(hr);
    if (!skipsEmpty || !mainRoutedThroughHotkeyOn)
      throw new Error('HotkeyRegistrar no longer skips empty keys: skipsEmpty=' + skipsEmpty + ' mainRouted=' + mainRoutedThroughHotkeyOn);
    return 'cleared main hotkey saves as "" and _HotkeyOn returns "" for empty keys (no live key injection)';
  }
});

scenarios.push({
  id: 5,
  name: 'New model keeps thinking metadata across a Settings save (reasoning dropdown shows its levels)',
  regression: true, // FIXED bug kept as a regression check (metadata must survive settings saves)
  mode: 'json',
  settings: {},
  preLaunch(dataDir) {
    // Seed a NEW model id (not present in default-settings/DefaultModels.ahk) that carries full
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
    // Step 3 of the IPC refactor: the chat window registers the hotkey hook
    // with SettingsService, which runs it at startup and on every settings
    // apply (replacing the old explicit _registerChatHotkeys() call sites).
    const registersAtStartup = chatWin.includes('SettingsService.RegisterHook("chatHotkeys", _registerChatHotkeys)');
    const dynamicRegister = /Hotkey\(\s*closeWindowsHotkey/.test(chatHk) && /_activeChatHotkey/.test(chatHk);
    const emptyMeansDisabled = /if\s+_activeChatHotkey[\s\S]*Hotkey\(_activeChatHotkey,\s*"Off"\)/.test(chatHk)
      && /if\s+closeWindowsHotkey[\s\S]*Hotkey\(closeWindowsHotkey/.test(chatHk);
    const reRegistersOnSave = (dispatch.match(/SettingsService\.(Apply|SaveFromWebView|ReloadFromDisk)\(/g) || []).length >= 2;
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
    return 'ChatWindow registers closeWindowsHotkey via a SettingsService hook (empty=disabled, re-registered on every settings apply); Main still handles only the input window; no restart warning shown';
  }
});

scenarios.push({
  id: 24,
  name: 'Input window Edit field applies the configured background (static check of the Edit Background option)',
  regression: true, // FIXED bug kept as a regression check (Edit must keep honoring the configured background)
  mode: null,
  noApp: true,
  async body() {
    // REGRESSION: the input window fix applied a dark background + light font,
    // but the Edit control does not inherit Gui.BackColor — it stayed white, so
    // white text was invisible. The Edit must be created with its own
    // Background option so the field matches the configured background. The
    // rendered-pixel live check was removed (it required key injection to open
    // the input window); InputWindow.test.ahk covers the applied colors.
    const iw = fs.readFileSync(path.join(launcher.REPO_ROOT, 'app', 'InputWindow.ahk'), 'utf8');
    const editOwnsBackground = /Background" inputWindowBackground/.test(iw);
    if (!editOwnsBackground)
      throw new Error('InputWindow Edit no longer carries its own Background option');
    return 'InputWindow Edit control carries its own Background option (never inherits the default white field)';
  }
});

scenarios.push({
  id: 25,
  name: 'Input window default design is light (static check of the default background)',
  regression: true, // FIXED bug kept as a regression check (default must stay light)
  mode: null,
  noApp: true,
  async body() {
    // REGRESSION guard: the app is light-themed, so the DEFAULT input window
    // must be light (white field + dark text). The previous default was dark
    // (0x212529 + cWhite), which looked broken against the light UI. Checked
    // statically to avoid key injection.
    const ds = fs.readFileSync(path.join(launcher.REPO_ROOT, 'default-settings', 'DefaultSettings.ahk'), 'utf8');
    const lightDefault = /inputWindowBackground\s*:=\s*"0xFFFFFF"/.test(ds);
    if (!lightDefault)
      throw new Error('default inputWindowBackground is no longer light (0xFFFFFF)');
    return 'default inputWindowBackground = 0xFFFFFF (light design preserved)';
  }
});

scenarios.push({
  id: 26,
  name: 'Opening Settings wipes the right-rail per-thread settings',
  regression: true, // FIXED bug kept as a regression check (right rail must survive opening Settings)
  mode: null,
  settings: {},
  async body({ cdp }) {
    // Set a per-thread system message through the right rail first, so there
    // is something to lose when Settings is opened.
    await showChat();
    await cdp.waitFor('document.getElementById("sysMsgMini") !== null && document.getElementById("expandSysMsg") !== null', 10000, 250, 'right rail');
    await cdp.click('#expandSysMsg');
    await cdp.waitFor('document.getElementById("sysMsgOverlay").classList.contains("open")', 5000, 200, 'sysmsg overlay');
    await cdp.type('#sysMsgFull', 'must survive settings open');
    await cdp.click('#sysMsgSave');
    await sleep(900); // 300ms debounce + IPC round trip
    const before = await cdp.eval('document.getElementById("sysMsgMini").value');
    if (before !== 'must survive settings open')
      throw new Error('system message not applied before opening settings: ' + JSON.stringify(before));
    // Open Settings: AHK answers requestAllSettings with the FULL merged
    // settings object, which main.js routes through populateCurrentSettings.
    await openSettings(cdp);
    const after = await cdp.eval('document.getElementById("sysMsgMini").value');
    // FIXED (bug #26): the full merged settings payload (requestAllSettings)
    // is no longer routed through populateCurrentSettings, so the right rail
    // keeps its per-thread system message when Settings opens.
    if (after !== before)
      throw new Error('opening Settings wiped the right-rail system message: "' + before + '" -> "' + after + '"');
    return 'right-rail system message survived opening Settings ("' + after + '")';
  }
});

scenarios.push({
  id: 33,
  name: 'Clearing the chat-window icon setting still loads the default custom icon',
  mode: null,
  regression: true, // FIXED: clearing icon now correctly clears global (was skipped and kept default)
  settings: { icons: { iconOn: '', iconOff: '' } },
  async body() {
    const defaultIco = path.join(launcher.REPO_ROOT, 'icons', 'IconOn.ico');
    const info = runIconCheck(defaultIco);
    if (info.hwnd === 0) throw new Error('chat window not found; probe=' + JSON.stringify(info));
    if (info.renderFailed === 1) throw new Error('icon render failed 3x; probe=' + JSON.stringify(info));
    // FIXED: with icons.iconOn="" the window now correctly shows no custom icon
    // because SettingsApply._ApplyIcons now applies empty values (was skipped).
    if (info.customApplied !== 0)
      throw new Error('cleared icon was NOT honored (fix broken): ' + JSON.stringify(info));
    return 'window correctly shows no custom IconOn.ico fingerprint when icons.iconOn is cleared (' + JSON.stringify(info) + ')';
  }
});

scenarios.push({
  id: 34,
  name: 'Tray icon changes apply live on settings updates (static check of the settings-update path)',
  regression: true, // FIXED bug kept as a regression check (tray icon must re-apply on settings updates)
  mode: null,
  noApp: true,
  async body() {
    const mainSrc = fs.readFileSync(path.join(launcher.REPO_ROOT, 'Main.ahk'), 'utf8');
    const traySrc = fs.readFileSync(path.join(launcher.REPO_ROOT, 'app', 'TrayIcon.ahk'), 'utf8');
    // FIXED: startup applies the icon through the shared rebuild, the rebuild
    // is registered as the trayIcon settings hook, and it honors suspend state.
    const hasStartupRebuild = /_rebuildTrayIcon\(\)/.test(mainSrc);
    const hasHook = mainSrc.includes('SettingsService.RegisterHook("trayIcon", _rebuildTrayIcon)');
    const hasApply = /TraySetIcon\(_trayIconForCurrentState\(\)/.test(traySrc);
    const hasOnBranch = /iconOn/.test(traySrc);
    const hasOffBranch = /iconOff/.test(traySrc);
    const hasSuspendBranch = /A_IsSuspended/.test(traySrc);
    const updStart = mainSrc.indexOf('WM_SETTINGS_UPDATED');
    const reloadStart = mainSrc.indexOf('WM_RELOAD_MAIN');
    const handler = mainSrc.slice(updStart, reloadStart > updStart ? reloadStart : updStart + 1200);
    // The handler reloads through SettingsService, which runs the registered
    // trayIcon hook, so icon edits apply without a restart.
    const handlerReloads = handler.includes('SettingsService.ReloadFromDisk()');
    if (!hasStartupRebuild || !hasHook || !hasApply || !hasOnBranch || !hasOffBranch || !hasSuspendBranch || !handlerReloads)
      throw new Error('tray icon fix not wired: startupRebuild=' + hasStartupRebuild + ' hook=' + hasHook +
        ' apply=' + hasApply + ' onBranch=' + hasOnBranch + ' offBranch=' + hasOffBranch + ' suspendBranch=' + hasSuspendBranch +
        ' handlerReloads=' + handlerReloads);
    return 'Tray icon rebuild runs at startup, is registered as the trayIcon settings hook, honors suspend state, and the settings-update handler reloads via SettingsService';
  }
});

scenarios.push({
  id: 35,
  name: 'Temperature override of 0 is restored when the thread reloads (request uses 0)',
  regression: true, // FIXED bug kept as a regression check (temperature 0 override must survive thread reload)
  mode: 'sse-success',
  settings: {},
  fixtures: {
    threads: [{ id: 't-temp0-35', title: 'Temp Zero Thread', active_leaf_id: 'm-temp0-35', temperature_override: 0 }],
    messages: [{ id: 'm-temp0-35', thread_id: 't-temp0-35', role: 'user', content: 'hello' }]
  },
  async body({ cdp, mockLog }) {
    await showChat();
    await cdp.waitFor('document.querySelectorAll("#thread-list .chat-item").length > 0', 15000, 300, 'thread list');
    await cdp.click('#thread-list .chat-item');
    // Wait until the thread actually loads (messages render), then let the
    // currentSettings round trip finish.
    await cdp.waitFor('document.querySelectorAll("#chat-messages .msg").length >= 1', 15000, 300, 'thread loaded');
    await sleep(500); // currentSettings round trip for the right rail
    // FIXED (bug #35): the 0 override is restored into requestParams, so the
    // next request must carry temperature 0. (The right-rail DISPLAY of 0 is
    // a separate bug, #78, tracked in its own cycle.)
    await sendChatMessage(cdp, 'second message');
    await waitStreamingIdle(cdp, 30000);
    await sleep(500);
    const lines = fs.readFileSync(mockLog, 'utf8').split(/\r?\n/).filter(Boolean);
    const chatReq = lines.map((l) => JSON.parse(l)).find((e) => e.body && e.body.stream === true);
    if (!chatReq) throw new Error('no streaming chat request was logged; lines=' + lines.length);
    const temp = chatReq.body.temperature;
    if (temp !== 0)
      throw new Error('temperature 0 override was dropped from the request: ' + JSON.stringify(temp));
    return 'thread with temperature_override=0 sent a request with temperature=0 (' + temp + ')';
  }
});

scenarios.push({
  id: 37,
  name: 'Tray menu item changes apply live via the settings hook (static check of the settings-update path)',
  regression: true, // FIXED bug kept as a regression check (tray menu must rebuild from trayMenuItems on settings update)
  mode: null,
  noApp: true,
  async body() {
    const mainSrc = fs.readFileSync(path.join(launcher.REPO_ROOT, 'Main.ahk'), 'utf8');
    const trayMenuSrc = fs.readFileSync(path.join(launcher.REPO_ROOT, 'app', 'TrayMenu.ahk'), 'utf8');
    // FIXED (bug #37): the tray menu rebuild lives in app/TrayMenu.ahk and is
    // registered as a SettingsService hook, so Menu Items edits apply live
    // (the WM_SETTINGS_UPDATED handler reloads via SettingsService, which runs
    // the hooks).
    const hasInclude = /#Include app\\TrayMenu\.ahk/.test(mainSrc);
    const hasHook = /SettingsService\.RegisterHook\("trayMenu", _rebuildTrayMenu\)/.test(mainSrc);
    const hasStartupCall = /_rebuildTrayMenu\(\)/.test(mainSrc);
    const menuDeletes = /A_TrayMenu\.Delete\(\)/.test(trayMenuSrc);
    const menuAdds = /A_TrayMenu\.Add/.test(trayMenuSrc);
    const iteratesItems = /for _, item in trayMenuItems/.test(trayMenuSrc);
    if (!hasInclude || !hasHook || !hasStartupCall || !menuDeletes || !menuAdds || !iteratesItems)
      throw new Error('tray menu rebuild not wired through the settings hook: include=' + hasInclude +
        ' hook=' + hasHook + ' startupCall=' + hasStartupCall + ' deletes=' + menuDeletes +
        ' adds=' + menuAdds + ' iterates=' + iteratesItems);
    return 'A_TrayMenu is rebuilt from trayMenuItems by _rebuildTrayMenu (app/TrayMenu.ahk), registered as the trayMenu settings hook in Main.ahk - menu edits apply without restart';
  }
});

scenarios.push({
  id: 39,
  name: 'System-message modal preserves a custom (unlisted) system-message file on Save',
  regression: true, // FIXED bug kept as a regression check (opening + saving the modal must not clear a custom system-message file)
  mode: null,
  settings: {
    commands: [{
      commandName: 'Custom File Command', menuText: 'Custom File Command',
      APIModels: 'deepseek/deepseek-v4-flash', pasteMode: 'chat', stream: false,
      systemMessageFile: 'default-settings/system-messages/my-custom-prompt.txt'
    }]
  },
  async body({ cdp }) {
    await openSettings(cdp);
    await openSection(cdp, 'commands');
    await cdp.waitFor('document.querySelectorAll("#commandsListBody .cmd-item").length > 0', 15000, 250, 'command list');
    await cdp.click('#commandsListBody .cmd-item');
    await sleep(400);
    // Open the system-message edit modal for the selected command.
    await cdp.click('#cmdEditSysMsg');
    await cdp.waitFor('document.getElementById("sysMsgEditModal").classList.contains("open")', 5000, 200, 'sysmsg modal');
    const selState = await cdp.eval(`(() => {
      const sel = document.getElementById('smFileSelect');
      return sel ? { selectedIndex: sel.selectedIndex, value: sel.value } : null;
    })()`);
    // The seeded file (system-messages/my-custom-prompt.txt) is NOT one of the
    // hardcoded options, so the select falls back to value "" (no selection).
    // Click Save without changing anything.
    await cdp.click('#sysMsgEditSave');
    await sleep(300);
    const after = await cdp.eval(`(() => {
      const c = window.Cmds && window.Cmds.commands();
      return c && c[0] ? { systemMessageFile: c[0].systemMessageFile, systemMessage: c[0].systemMessage } : null;
    })()`);
    const label = await cdp.eval('document.getElementById("cmdSysMsgLabel") ? document.getElementById("cmdSysMsgLabel").textContent : ""');
    // FIXED (bug #39): the modal remembers the stored file and falls back to it
    // when the select has no matching option, so the custom file survives.
    if (!after || after.systemMessageFile !== 'default-settings/system-messages/my-custom-prompt.txt')
      throw new Error('custom system-message file was not preserved through the modal save: ' +
        JSON.stringify(after) + ' label="' + label + '"');
    return 'custom file survived the modal save: systemMessageFile=' +
      JSON.stringify(after.systemMessageFile) + ' label="' + label + '"';
  }
});

scenarios.push({
  id: 40,
  name: 'Refresh-models modal keeps edits to a model id on Save',
  regression: true, // FIXED bug kept as a regression check (edited model ids must survive the refresh-modal save)
  mode: null,
  settings: {},
  async body({ cdp }) {
    await openSettings(cdp);
    await openSection(cdp, 'models');
    await cdp.waitFor('document.querySelectorAll("#modelsTableBody tr").length > 0', 15000, 250, 'models table');
    await cdp.click('#refreshPricingBtn');
    await cdp.waitFor('document.getElementById("refreshModal").classList.contains("open")', 5000, 200, 'refresh modal');
    await cdp.waitFor('document.querySelectorAll("#refreshRightTbody tr [data-field=id]").length > 0', 15000, 250, 'right panel models');
    const before = await cdp.eval(`(() => {
      const inp = document.querySelector('#refreshRightTbody tr [data-field=id]');
      return inp ? { value: inp.value, fullId: inp.getAttribute('data-full-id') } : null;
    })()`);
    // Rename the model id in the "Your Models" panel.
    await cdp.type('#refreshRightTbody tr [data-field=id]', 'renamed-model-id');
    await sleep(200);
    await cdp.click('#refreshSaveBtn');
    await sleep(400);
    const after = await cdp.eval(`(() => {
      const inp = document.querySelector('#modelsTableBody tr [data-field=id]');
      return inp ? inp.value : null;
    })()`);
    // FIXED (bug #40): saveRefresh and _rightPanelIds now prefer the live
    // input value over the stale data-full-id attribute.
    if (after !== 'renamed-model-id')
      throw new Error('model id edit was discarded on Save: before=' + JSON.stringify(before) + ' after=' + JSON.stringify(after));
    return 'edited the first model id to "renamed-model-id" in the refresh modal; after Save the table shows "' + after + '"';
  }
});

scenarios.push({
  id: 41,
  name: 'Tray "New Chat" applies the "New Chats Start With" default (static check of the tray path)',
  regression: true, // FIXED bug kept as a regression check (tray-started chats must start with the configured default)
  mode: null,
  noApp: true,
  async body() {
    const mainSrc = fs.readFileSync(path.join(launcher.REPO_ROOT, 'Main.ahk'), 'utf8');
    const trayMenuSrc = fs.readFileSync(path.join(launcher.REPO_ROOT, 'app', 'TrayMenu.ahk'), 'utf8');
    const sidebarSrc = fs.readFileSync(path.join(launcher.REPO_ROOT, 'chat', 'callbacks', 'Sidebar.ahk'), 'utf8');
    const utilsSrc = fs.readFileSync(path.join(launcher.REPO_ROOT, 'chat', 'ChatUtils.ahk'), 'utf8');
    const ipcSrc = fs.readFileSync(path.join(launcher.REPO_ROOT, 'chat', 'ChatIPC.ahk'), 'utf8');
    const settingsSrc = fs.readFileSync(path.join(launcher.REPO_ROOT, 'chat', 'ChatSettings.ahk'), 'utf8');
    // Tray "New Chat" creates the thread directly and opens it (the tray menu
    // build lives in app/TrayMenu.ahk since bug #37).
    const trayNewChat = /openChatWindow\(ChatDB\.Thread_Create\(\)\)/.test(trayMenuSrc);
    // FIXED (bug #41): the unified loader path now applies the new-chat
    // default to fresh (message-less, settings-less) threads.
    const loaderApplies = ipcSrc.includes('_applyNewChatDefaultToFreshThread(threadId)');
    const helperExists = settingsSrc.includes('_applyNewChatDefaultToFreshThread(threadId)');
    // The sidebar newChat action still applies the default at creation.
    const sidebarApplies = sidebarSrc.includes('_applyNewChatDefault()');
    if (!trayNewChat || !loaderApplies || !helperExists || !sidebarApplies)
      throw new Error('tray new-chat default wiring missing: trayNewChat=' + trayNewChat +
        ' loaderApplies=' + loaderApplies + ' helperExists=' + helperExists + ' sidebarApplies=' + sidebarApplies);
    return 'LoadThreadIntoUI applies _applyNewChatDefaultToFreshThread to fresh threads, so tray "New Chat" starts with the configured default';
  }
});

scenarios.push({
  id: 45,
  name: '"Response Font" is applied to chat messages at startup and after saves',
  regression: true, // FIXED bug kept as a regression check (response font must apply without opening Settings)
  mode: null,
  settings: { ui: { responseFont: 'Georgia' } },
  fixtures: {
    threads: [{ id: 't-font-45', title: 'Font Face Thread', active_leaf_id: 'm-font-45' }],
    messages: [{ id: 'm-font-45', thread_id: 't-font-45', role: 'assistant', content: 'hello world', model: 'deepseek/deepseek-v4-flash' }]
  },
  async body({ cdp }) {
    await showChat();
    await cdp.waitFor('document.querySelectorAll("#thread-list .chat-item").length > 0', 15000, 300, 'thread list');
    await cdp.click('#thread-list .chat-item');
    await cdp.waitFor('document.querySelectorAll("#chat-messages .msg").length >= 1', 15000, 300, 'thread loaded');
    await sleep(500);
    const familyBefore = await cdp.eval(`getComputedStyle(document.querySelector('.msg-content')).fontFamily`);
    const varBefore = await cdp.eval(`getComputedStyle(document.documentElement).getPropertyValue('--chat-font-family').trim()`);
    // FIXED (bug #45): appSettings is re-pushed on webViewReady and after
    // saves, so ui-theme.js applies --chat-font-family at startup.
    if (String(familyBefore).indexOf('Georgia') < 0)
      throw new Error('response font was not applied at startup: ' + JSON.stringify(familyBefore) + ' var=' + JSON.stringify(varBefore));
    if (String(varBefore).indexOf('Georgia') < 0)
      throw new Error('--chat-font-family not set at startup: ' + JSON.stringify(varBefore));
    return 'configured ui.responseFont=Georgia applied at startup: msg font=' + JSON.stringify(familyBefore) + ' (var=' + JSON.stringify(varBefore) + ')';
  }
});

scenarios.push({
  id: 47,
  name: 'Per-thread system prompt / temperature edits are discarded on reload when an assistant is active',
  regression: true, // FIXED bug kept as a regression check (overrides must survive reloads)
  mode: null,
  settings: {
    assistants: [{
      id: 'asst-47', name: 'Test Assistant', baseModel: 'deepseek/deepseek-v4-flash',
      systemMessage: 'assistant system', systemMessageFile: '', description: '',
      reasoning: 'high', temperature: '0.3'
    }]
  },
  fixtures: {
    threads: [{ id: 't-asst-47', title: 'Assistant Thread', active_leaf_id: 'm-asst-47', assistant_id: 'asst-47' }],
    messages: [{ id: 'm-asst-47', thread_id: 't-asst-47', role: 'user', content: 'hello' }]
  },
  async body({ cdp, dbPath }) {
    await showChat();
    await cdp.waitFor('document.querySelectorAll("#thread-list .chat-item").length > 0', 15000, 300, 'thread list');
    await cdp.click('#thread-list .chat-item');
    await cdp.waitFor('document.querySelectorAll("#chat-messages .msg").length >= 1', 15000, 300, 'thread loaded');
    await sleep(700);
    // Edit the system prompt while the assistant is active (right-rail modal).
    await cdp.click('#expandSysMsg');
    await cdp.waitFor('document.getElementById("sysMsgOverlay").classList.contains("open")', 5000, 200, 'sysmsg overlay');
    await cdp.type('#sysMsgFull', 'user override');
    await cdp.click('#sysMsgSave');
    await sleep(900); // 300ms debounce + IPC round trip
    const miniAfter = await cdp.eval('document.getElementById("sysMsgMini").value');
    if (miniAfter !== 'user override')
      throw new Error('system prompt edit did not apply (setup): ' + JSON.stringify(miniAfter));
    // Reload the thread (click the same sidebar item -> _restoreThreadSettings).
    await cdp.eval(`(() => {
      const items = document.querySelectorAll('#thread-list .chat-item');
      if (!items[0]) return false;
      items[0].click();
      return true;
    })()`);
    await cdp.waitFor('document.querySelectorAll("#chat-messages .msg").length >= 1', 15000, 300, 'thread reloaded');
    await sleep(700);
    const miniReloaded = await cdp.eval('document.getElementById("sysMsgMini").value');
    const rows = seed.query(dbPath, "SELECT system_override, temperature_override FROM chat_threads WHERE id='t-asst-47'");
    // FIXED (bug #47): the per-thread override is persisted AND wins over the
    // assistant's defaults when the thread reloads.
    if (miniReloaded !== 'user override')
      throw new Error('per-thread override did not survive the reload: "' + miniReloaded + '" (DB system_override=' +
        JSON.stringify(rows[0] && rows[0].system_override) + ')');
    return 'edited system prompt to "user override" with assistant active; after reload the rail still shows "' +
      miniReloaded + '" (DB system_override=' + JSON.stringify(rows[0] && rows[0].system_override) + ')';
  }
});

scenarios.push({
  id: 60,
  name: 'Typing a system prompt directly into the right-rail field never reaches the API request',
  regression: true, // FIXED bug kept as a regression check (direct typing must reach the API request)
  mode: 'sse-success',
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
    // FIXED (bug #60): typing into #sysMsgMini now updates requestParams, so
    // the sent request must carry the typed system message.
    if (!containsTyped)
      throw new Error('typed message did not reach the request: ' + JSON.stringify(sysMsg));
    return 'typed directly into the rail field; the sent request carries "DIRECT TYPED MESSAGE" (head=' +
      JSON.stringify(sysMsg[0] ? sysMsg[0].slice(0, 50) : '(none)') + ')';
  }
});

scenarios.push({
  id: 120,
  name: 'Lowering Trash Retention in Settings does NOT purge expired trash - the settings-update purge hook fails at runtime',
  regression: true, // FIXED bug kept as a regression check (retention changes must purge expired trash immediately)
  mode: null,
  settings: { trash: { retentionDays: 30 } },
  fixtures: {
    threads: [
      // Deleted 19 days ago: survives the startup purge (retention 30) but
      // must be purged the moment retention is lowered to 1 and saved.
      { id: 't-trash-120', title: 'To Purge', is_deleted: 1, deleted_at: '2026-07-20 00:00:00' },
      { id: 't-live-120', title: 'Live Thread', active_leaf_id: 'm-120-u1' }
    ],
    messages: [{ id: 'm-120-u1', thread_id: 't-live-120', role: 'user', content: 'hello' }]
  },
  async body({ cdp, dbPath, dataDir }) {
    await showChat();
    await cdp.waitFor('document.querySelectorAll("#thread-list .chat-item").length > 0', 15000, 300, 'thread list');
    // Sanity: with retention 30 the 19-day-old trashed thread must still exist
    // (startup purge must NOT have removed it).
    await sleep(1500);
    if (seed.query(dbPath, "SELECT id FROM chat_threads WHERE id='t-trash-120'").length !== 1)
      throw new Error('setup: trashed thread was purged before the retention change');

    // 1) General tab: lower trash retention to 1 and save.
    await openSettings(cdp);
    await openSection(cdp, 'general');
    await cdp.eval('(() => { const el = document.getElementById("trashRetentionDays"); el.value = "1"; el.dispatchEvent(new Event("input", { bubbles: true })); el.dispatchEvent(new Event("change", { bubbles: true })); return el.value; })()');
    await saveSettings(cdp, dataDir);
    const afterSave = readJsonFile(path.join(dataDir, 'settings.json'));
    if (!afterSave.trash || afterSave.trash.retentionDays !== 1)
      throw new Error('trash retention not persisted: ' + JSON.stringify(afterSave.trash));
    // The Main process reloads on WM_SETTINGS_UPDATED and re-runs the purge
    // hook. FIXED (bug #120): the hook is now a plain zero-arg wrapper
    // (TrashRetentionPurge) instead of the bare static-method reference
    // ChatDB.Thread_PurgeExpired, which AHK cannot invoke via fn.Call()
    // ("hook 'purgeExpired' failed: Missing a required parameter."), so the
    // expired trashed thread must be purged right after the save.
    const start = Date.now();
    let purged = false;
    while (Date.now() - start < 6000) {
      if (seed.query(dbPath, "SELECT id FROM chat_threads WHERE id='t-trash-120'").length === 0) { purged = true; break; }
      await sleep(300);
    }
    if (!purged)
      throw new Error('trashed thread was NOT purged after saving retention 1 (bug #120 still reproduces)');

    // 2) UI & Theme tab: change the default response font size to 20 and save.
    await openSection(cdp, 'ui');
    await cdp.eval('(() => { const el = document.getElementById("responseFontSize"); el.value = "20"; el.dispatchEvent(new Event("change", { bubbles: true })); return el.value; })()');
    await cdp.click('.nav-footer .btn-primary');
    // The saveSettings helper's "has models" poll returns instantly on a second
    // save (the key is already on disk), so poll for the actual value here.
    const start2 = Date.now();
    let afterSave2 = null;
    while (Date.now() - start2 < 15000) {
      try {
        const j = readJsonFile(path.join(dataDir, 'settings.json'));
        if (j.ui && j.ui.responseFontSize === '20') { afterSave2 = j; break; }
      } catch {}
      await sleep(300);
    }
    if (!afterSave2)
      throw new Error('responseFontSize not persisted: ' + JSON.stringify(afterSave2));
    // The settings DID persist and the app accepted them - only the purge hook
    // is broken. Continue verifying that OTHER settings still round-trip, so
    // the failure is isolated to the purge path.

    // 3) New Chat must start with the new default font size (20px) applied.
    await cdp.click('#sidebar-toggle'); // back to chat view
    await sleep(500);
    const oldThread = await cdp.eval('window.activeThreadId');
    await cdp.click('#new-chat-btn');
    await cdp.waitFor('window.activeThreadId !== ' + JSON.stringify(oldThread), 15000, 300, 'new chat created');
    await cdp.waitFor('document.getElementById("font-size-display") && document.getElementById("font-size-display").textContent === "20px"', 15000, 300, 'font size applied');
    const cssFont = await cdp.eval('document.documentElement.style.getPropertyValue("--chat-font-size").trim()');
    const newThread = await cdp.eval('window.activeThreadId');
    const row = seed.query(dbPath, 'SELECT font_size FROM chat_threads WHERE id = ?', [newThread])[0];
    if (cssFont !== '20px' || !row || Number(row.font_size) !== 20)
      throw new Error('new chat font size not reflected: css=' + JSON.stringify(cssFont) + ' db=' + JSON.stringify(row));
    return 'retention 30->1 persisted and t-trash-120 (deleted 19 days ago) WAS purged after saving ' +
      '(hook "purgeExpired" now runs via the TrashRetentionPurge wrapper); responseFontSize 17->20 persisted and new chat ' +
      newThread + ' has font_size=' + row.font_size + ' and --chat-font-size=' + cssFont;
  }
});

scenarios.push({
  id: 122,
  name: 'Saving Settings silently drops assistant temperature and isDefault (the Assistants tab save() only emits the card fields)',
  regression: true, // FIXED bug kept as a regression check (assistant temperature/isDefault survive a save)
  mode: null,
  settings: {
    assistants: [{
      id: 'asst-temp-122', name: 'Temp Assistant', baseModel: 'deepseek/deepseek-v4-flash',
      systemMessage: '', systemMessageFile: '', description: '', reasoning: 'high',
      temperature: '0.7', isDefault: true
    }]
  },
  async body({ cdp, dataDir, dbPath }) {
    await showChat();
    await cdp.waitFor('typeof window.assistantList !== "undefined" && window.assistantList.length === 1', 15000, 300, 'assistant list');
    // Sanity: the assistant arrives WITH its configured temperature.
    const before = await cdp.eval('window.assistantList[0].temperature');
    if (before !== '0.7')
      throw new Error('assistant did not arrive with temperature 0.7: ' + JSON.stringify(before));
    // Open Settings and make one harmless change so Save is enabled.
    await openSettings(cdp);
    // Wait until the settings panel has actually received the merged payload
    // (loadSettings -> clearDirty disables the Save button; until then
    // _currentSettings is unset and clicking Save silently does nothing).
    await cdp.waitFor('document.querySelector(".nav-footer .btn-primary") && document.querySelector(".nav-footer .btn-primary").disabled === true', 15000, 250, 'settings payload loaded');
    // Use a shortcut that cannot collide with any default command accelerator
    // ('9' is unused) - a conflicting value would abort the save in the
    // commands validator before it reaches AHK.
    await cdp.type('#chatShortcut', '9');
    await cdp.waitFor('typeof window.SettingsPanel !== "undefined" && window.SettingsPanel.isDirty && window.SettingsPanel.isDirty() === true', 5000, 200, 'settings marked dirty');
    await saveSettings(cdp, dataDir);
    await sleep(800);
    // FIXED (bug #122): assistants.js save() reads temperature/isDefault back
    // from the card dataset, and SettingsApply._ApplyAssistants carries them
    // into the runtime globals, so the save round-trip preserves both.
    const saved = readJsonFile(path.join(dataDir, 'settings.json'));
    const asst = (saved.assistants || []).find((a) => a.id === 'asst-temp-122');
    if (!asst) throw new Error('assistant missing from settings.json after save');
    if (asst.temperature !== '0.7')
      throw new Error('assistant temperature was dropped by the save (bug #122 not fixed): ' + JSON.stringify(asst));
    // AHK has no boolean type - jsongo persists true as 1, so accept any
    // truthy value (the bug was the key being dropped entirely).
    if (!asst.isDefault)
      throw new Error('assistant isDefault was dropped by the save (bug #122 not fixed): ' + JSON.stringify(asst));
    // AHK re-pushes assistantList after the save; the re-pushed copy must keep
    // the configured temperature.
    const start2 = Date.now();
    let afterList = null;
    while (Date.now() - start2 < 8000) {
      afterList = await cdp.eval('window.assistantList && window.assistantList[0] ? window.assistantList[0] : null');
      if (afterList && afterList.temperature === '0.7') break;
      await sleep(300);
    }
    if (!afterList || afterList.temperature !== '0.7')
      throw new Error('runtime assistantList lost temperature after save (bug #122 not fixed): ' + JSON.stringify(afterList));
    return 'assistant temperature 0.7 / isDefault true survived the Settings save round-trip in settings.json and the re-pushed assistantList';
  }
});

scenarios.push({
  id: 130,
  name: 'Saving Settings wipes a custom (unlisted) "Response Font" - the select has no matching option so save() emits an empty value',
  mode: null,
  settings: { ui: { responseFont: 'Courier New', responseFontSize: '17' } },
  fixtures: {
    threads: [{ id: 't-font-130', title: 'Custom Font', active_leaf_id: 'm-130-a1' }],
    messages: [{ id: 'm-130-a1', thread_id: 't-font-130', role: 'assistant', content: 'hello', model: 'deepseek/deepseek-v4-flash' }]
  },
  async body({ cdp, dataDir }) {
    const settingsFile = require('node:path').join(dataDir, 'settings.json');
    const before = readJsonFile(settingsFile);
    if (before.ui.responseFont !== 'Courier New')
      throw new Error('seed did not carry the custom font (setup): ' + JSON.stringify(before.ui));
    await openSettings(cdp);
    await openSection(cdp, 'ui');
    await cdp.waitFor('document.getElementById("responseFont") !== null', 10000, 250, 'ui section');
    // The select has NO "Courier New" option - load() assigns the raw value,
    // leaving the select with an empty selection.
    const selValue = await cdp.eval('document.getElementById("responseFont").value');
    if (selValue !== '')
      throw new Error('select unexpectedly matched the custom font: ' + JSON.stringify(selValue));
    // Make the panel dirty with a no-op edit on another UI field, then save.
    await cdp.type('#iwWidth', '500');
    await saveSettings(cdp, dataDir);
    const after = readJsonFile(settingsFile);
    // BUG: save() returns S.getVal('responseFont') - the empty selection - so
    // the custom font is permanently wiped from settings.json on the first
    // Settings save (same class as #39's custom system-message file).
    if (after.ui.responseFont === 'Courier New')
      throw new Error('custom font survived the save (bug may have been fixed): ' + JSON.stringify(after.ui.responseFont));
    if (after.ui.responseFont !== '')
      throw new Error('unexpected saved responseFont: ' + JSON.stringify(after.ui.responseFont));
    return 'seeded ui.responseFont="Courier New" (not one of the 5 select options); after opening Settings and saving, settings.json has responseFont="' +
      after.ui.responseFont + '" - the custom font is lost';
  }
});

module.exports = scenarios;
