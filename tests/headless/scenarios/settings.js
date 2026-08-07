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
  name: 'Tray icon changes do not apply until restart (static check of the settings-update path)',
  mode: null,
  noApp: true,
  async body() {
    const mainSrc = fs.readFileSync(path.join(launcher.REPO_ROOT, 'Main.ahk'), 'utf8');
    // Startup applies the tray icon; the WM_SETTINGS_UPDATED handler must too
    // for icon edits to take effect live.
    const hasStartupApply = /TraySetIcon\(iconOn\)/.test(mainSrc);
    const updStart = mainSrc.indexOf('WM_SETTINGS_UPDATED');
    const reloadStart = mainSrc.indexOf('WM_RELOAD_MAIN');
    const handler = mainSrc.slice(updStart, reloadStart > updStart ? reloadStart : updStart + 1200);
    const hasLiveApply = /TraySetIcon/.test(handler);
    // BUG: the settings-update handler reloads globals and re-registers
    // hotkeys but never re-applies the tray icon, so icon edits need a restart.
    if (!hasStartupApply || hasLiveApply)
      throw new Error('bug not reproduced: startupApply=' + hasStartupApply + ' liveApplyInHandler=' + hasLiveApply);
    return 'TraySetIcon is called at startup but NOT in the WM_SETTINGS_UPDATED handler; tray icon edits require a restart';
  }
});

scenarios.push({
  id: 35,
  name: 'Temperature override of 0 is dropped when the thread reloads (right rail shows Default)',
  mode: null,
  settings: {},
  fixtures: {
    threads: [{ id: 't-temp0-35', title: 'Temp Zero Thread', active_leaf_id: 'm-temp0-35', temperature_override: 0 }],
    messages: [{ id: 'm-temp0-35', thread_id: 't-temp0-35', role: 'user', content: 'hello' }]
  },
  async body({ cdp }) {
    await showChat();
    await cdp.waitFor('document.querySelectorAll("#thread-list .chat-item").length > 0', 15000, 300, 'thread list');
    await cdp.click('#thread-list .chat-item');
    // Wait until the thread actually loads (messages render), then read the
    // right-rail temperature state.
    await cdp.waitFor('document.querySelectorAll("#chat-messages .msg").length >= 1', 15000, 300, 'thread loaded');
    await sleep(500); // currentSettings round trip for the right rail
    const tempVal = await cdp.eval('document.getElementById("tempVal") ? document.getElementById("tempVal").textContent : "(missing)"');
    const slider = await cdp.eval('document.getElementById("tempSlider") ? document.getElementById("tempSlider").value : "(missing)"');
    // BUG: ChatSettings._restoreThreadSettings uses a truthiness check
    // (`if settings.temperatureOverride`), and AHK treats 0 as falsy, so a
    // saved 0 override is never restored - the rail falls back to Default/1.0.
    if (tempVal === '0.0' || slider === '0')
      throw new Error('temperature 0 override was restored (bug not reproduced): tempVal=' + JSON.stringify(tempVal) + ' slider=' + JSON.stringify(slider));
    return 'thread with temperature_override=0 shows tempVal=' + JSON.stringify(tempVal) + ' slider=' + JSON.stringify(slider) + ' instead of 0.0';
  }
});

scenarios.push({
  id: 37,
  name: 'Tray menu item changes do not apply until restart (static check of the settings-update path)',
  mode: null,
  noApp: true,
  async body() {
    const mainSrc = fs.readFileSync(path.join(launcher.REPO_ROOT, 'Main.ahk'), 'utf8');
    // The tray menu is populated once at startup from trayMenuItems...
    const hasStartupBuild = /A_TrayMenu\.Add/.test(mainSrc);
    // ...but the WM_SETTINGS_UPDATED handler never rebuilds it.
    const updStart = mainSrc.indexOf('WM_SETTINGS_UPDATED');
    const reloadStart = mainSrc.indexOf('WM_RELOAD_MAIN');
    const handler = mainSrc.slice(updStart, reloadStart > updStart ? reloadStart : updStart + 1200);
    const hasRebuild = /A_TrayMenu/.test(handler);
    // BUG: Menu Items -> tray edits are written to settings.json but the tray
    // menu keeps the startup entries until the app is restarted.
    if (!hasStartupBuild || hasRebuild)
      throw new Error('bug not reproduced: startupBuild=' + hasStartupBuild + ' rebuildInHandler=' + hasRebuild);
    return 'A_TrayMenu is populated at startup but never rebuilt in WM_SETTINGS_UPDATED; tray menu edits require a restart';
  }
});

scenarios.push({
  id: 39,
  name: 'System-message modal silently clears a custom (unlisted) system-message file on Save',
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
    // BUG: sysmsg-modal.js saves fileSelect.value (""), so the command's
    // systemMessageFile is silently cleared even though the user changed nothing.
    if (after && after.systemMessageFile === 'default-settings/system-messages/my-custom-prompt.txt')
      throw new Error('custom file survived the modal save (bug not reproduced): ' + JSON.stringify(after));
    return 'modal select selectedIndex=' + selState.selectedIndex + ' value=' + JSON.stringify(selState.value) +
      '; after Save systemMessageFile=' + JSON.stringify(after && after.systemMessageFile) + ' label="' + label + '"';
  }
});

scenarios.push({
  id: 40,
  name: 'Refresh-models modal discards edits to a model id (stale data-full-id wins on Save)',
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
    // BUG: saveRefresh reads data-full-id (the ORIGINAL id) instead of the
    // edited input value, so the rename is silently discarded.
    if (after === 'renamed-model-id')
      throw new Error('model id edit was kept (bug not reproduced): before=' + JSON.stringify(before) + ' after=' + after);
    return 'edited the first model id to "renamed-model-id" in the refresh modal; after Save the table still shows "' + after +
      '" (stale data-full-id=' + JSON.stringify(before && before.fullId) + ')';
  }
});

scenarios.push({
  id: 41,
  name: 'Tray "New Chat" ignores the "New Chats Start With" default (static check of the tray path)',
  mode: null,
  noApp: true,
  async body() {
    const mainSrc = fs.readFileSync(path.join(launcher.REPO_ROOT, 'Main.ahk'), 'utf8');
    const sidebarSrc = fs.readFileSync(path.join(launcher.REPO_ROOT, 'chat', 'callbacks', 'Sidebar.ahk'), 'utf8');
    const utilsSrc = fs.readFileSync(path.join(launcher.REPO_ROOT, 'chat', 'ChatUtils.ahk'), 'utf8');
    const ipcSrc = fs.readFileSync(path.join(launcher.REPO_ROOT, 'chat', 'ChatIPC.ahk'), 'utf8');
    // Tray "New Chat" creates the thread directly and opens it...
    const trayNewChat = /openChatWindow\(ChatDB\.Thread_Create\(\)\)/.test(mainSrc);
    // ...while the sidebar newChat action DOES apply the start-with default.
    const sidebarApplies = sidebarSrc.includes('_applyNewChatDefault()');
    // The unified loader path (tray -> notifyLoadThread -> LoadThreadIntoUI ->
    // _LoadThreadAndRefreshUI) never applies the default.
    const loaderApplies = ipcSrc.includes('_applyNewChatDefault') || utilsSrc.includes('_applyNewChatDefault');
    // BUG: tray-started chats skip _applyNewChatDefault (and the default font
    // size that the sidebar newChat path writes), so they always start with the
    // raw app default model instead of the configured "New Chats Start With".
    if (!trayNewChat || !sidebarApplies || loaderApplies)
      throw new Error('bug not reproduced: trayNewChat=' + trayNewChat + ' sidebarApplies=' + sidebarApplies + ' loaderApplies=' + loaderApplies);
    return 'tray New Chat calls openChatWindow(ChatDB.Thread_Create()) directly; LoadThreadIntoUI/_LoadThreadAndRefreshUI never call _applyNewChatDefault, so tray-started chats ignore newChatStartsWith and the default font size';
  }
});

scenarios.push({
  id: 45,
  name: '"Response Font" setting is not applied to chat messages until Settings is opened',
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
    // BUG: ui-theme.js only sets --chat-font-family inside load(), which runs
    // when the Settings panel receives the full settings payload. At startup the
    // CSS var keeps the default, so the configured Response Font is not applied.
    if (String(familyBefore).indexOf('Georgia') >= 0)
      throw new Error('response font was applied before opening settings (bug not reproduced): ' + familyBefore);
    await openSettings(cdp);
    await sleep(400);
    const familyAfter = await cdp.eval(`getComputedStyle(document.querySelector('.msg-content')).fontFamily`);
    return 'configured ui.responseFont=Georgia; before opening Settings msg font=' + JSON.stringify(familyBefore) +
      ' (var=' + JSON.stringify(varBefore) + '); after opening Settings it becomes ' + JSON.stringify(familyAfter);
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

module.exports = scenarios;
