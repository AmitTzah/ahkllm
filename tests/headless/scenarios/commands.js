// scenarios/commands.js - Command configuration and execution
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
const os = require('node:os');
const { spawnSync } = require('node:child_process');
const launcher = require('../launch');
const seed = require('../seed');
const { sleep, runProbe, runThinkingProbe, showChat, openSettings, openSection, saveSettings, readJsonFile } = require('./helpers');

const scenarios = [];

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
  id: 228,
  name: 'A command whose API Model is set to "Default" (empty APIModels), or whose Command Title / Menu Label is cleared, must keep those keys on the runtime command - SettingsApply._ApplyCommands assigns whenever the saved key exists (empty included), so cmd.APIModels / cmd.commandName / cmd.menuText read "" without throwing and processInitialRequest\'s #162 default-model substitution is reachable (bug #228 FIXED)',
  regression: true, // FIXED bug kept as a regression check (empty command fields must not drop the properties or crash the menu handler)
  mode: null,
  settings: {
    commands: [
      {
        commandName: 'Crash Test', menuText: 'Crash Test', APIModels: 'deepseek/deepseek-v4-flash',
        pasteMode: 'chat', userMessage: '{{input}}', stream: false
      },
      {
        commandName: '', menuText: 'Empty Title', APIModels: 'deepseek/deepseek-v4-flash',
        pasteMode: 'chat', stream: false
      },
      {
        commandName: 'Name Only', menuText: '', APIModels: 'deepseek/deepseek-v4-flash',
        pasteMode: 'chat', stream: false
      }
    ]
  },
  async body({ cdp, dataDir }) {
    // 1) Drive the REAL Settings UI: Commands -> select the command -> set API
    //    Model to "Default" -> Save. This is exactly how the buggy state is
    //    reached by a user (the dropdown's first option is "Default").
    await showChat();
    await openSettings(cdp);
    await openSection(cdp, 'commands');
    await cdp.waitFor('document.querySelectorAll("#commandsListBody .cmd-item").length > 0', 10000, 250, 'command list');
    await cdp.click('#commandsListBody .cmd-item');
    await sleep(400);
    await cdp.eval('(() => { const el = document.getElementById("cmdApiModel"); if (!el) return false; el.value = ""; el.dispatchEvent(new Event("change", { bubbles: true })); return el.value; })()');
    await sleep(300);
    await saveSettings(cdp, dataDir);
    const saved = readJsonFile(path.join(dataDir, 'settings.json'));
    const cmd = (saved.commands || []).find((c) => c.commandName === 'Crash Test');
    if (!cmd)
      throw new Error('seeded command missing from saved settings: ' + JSON.stringify(saved.commands));
    if (cmd.APIModels !== '')
      throw new Error('API Model was not saved as Default (empty): ' + JSON.stringify(cmd.APIModels));

    // 2) Run the REAL SettingsHandler.Load + SettingsApply.ApplyToGlobals chain
    //    against the saved file (fresh AHK process) and verify the FIXED
    //    behavior: the applied commands KEEP the empty-valued APIModels /
    //    commandName / menuText properties, and reading them (exactly what
    //    onCommandSelected does) does NOT throw - the #162 default-model
    //    substitution is then reachable. PASS means the fix holds.
    const outFile = path.join(os.tmpdir(), 'llm-bughunt-db-' + process.pid + '.txt');
    try { fs.unlinkSync(outFile); } catch {}
    const probe = path.join(__dirname, '..', 'probe-bughunt-db.ahk');
    const res = spawnSync(launcher.AHK, ['/ErrorStdOut', probe, outFile, 'command-empty-models-crash', path.join(dataDir, 'settings.json')], { timeout: 25000, windowsHide: true, encoding: 'utf8' });
    if (res.error) throw new Error('probe spawn failed/timed out: ' + res.error.message);
    if (res.stderr) process.stderr.write('[probe stderr] ' + res.stderr);
    const text = fs.readFileSync(outFile, 'utf-8');
    const m = text.replace(/^\uFEFF/, '').match(/hasProp=(\d+) accessThrew=(\d+)/);
    if (!m) throw new Error('probe output missing EMPTYMODELCRASH line: ' + text);
    const hasProp = Number(m[1]), accessThrew = Number(m[2]);
    const m2 = text.replace(/^\uFEFF/, '').match(/hasNameProp=(\d+) nameAccessThrew=(\d+)/);
    if (!m2) throw new Error('probe output missing empty-name line: ' + text);
    const hasNameProp = Number(m2[1]), nameAccessThrew = Number(m2[2]);
    const m3 = text.replace(/^\uFEFF/, '').match(/hasMenuProp=(\d+) menuAccessThrew=(\d+)/);
    if (!m3) throw new Error('probe output missing empty-menu line: ' + text);
    const hasMenuProp = Number(m3[1]), menuAccessThrew = Number(m3[2]);
    // FIXED: the applied commands keep the APIModels / commandName / menuText
    // properties (empty) AND direct access does not throw.
    if (hasProp !== 1 || accessThrew !== 0 || hasNameProp !== 1 || nameAccessThrew !== 0 || hasMenuProp !== 1 || menuAccessThrew !== 0)
      throw new Error('empty-field commands still drop properties or throw (fix incomplete): hasProp=' + hasProp + ' accessThrew=' + accessThrew +
        ' hasNameProp=' + hasNameProp + ' nameAccessThrew=' + nameAccessThrew + ' hasMenuProp=' + hasMenuProp + ' menuAccessThrew=' + menuAccessThrew + ' out=' + text);

    // 3) Static check: the menu handlers now guard every direct read, and the
    //    #162 substitution is still in place for the "" the guards fall back to.
    const menu = fs.readFileSync(path.join(launcher.REPO_ROOT, 'app', 'menu', 'CommandMenu.ahk'), 'utf8');
    const cmdState = fs.readFileSync(path.join(launcher.REPO_ROOT, 'app', 'menu', 'CommandState.ahk'), 'utf8');
    if (!/cmd\.HasProp\("APIModels"\) \? cmd\.APIModels : ""/.test(menu) || !/cmd\.HasProp\("commandName"\) \? cmd\.commandName : ""/.test(menu))
      throw new Error('CommandMenu.ahk still reads cmd fields unguarded (fix incomplete)');
    if (!/cmd\.HasProp\("APIModels"\) \? cmd\.APIModels : ""/.test(cmdState))
      throw new Error('CommandState.ahk still reads cmd.APIModels unguarded (fix incomplete)');
    const rp = fs.readFileSync(path.join(launcher.REPO_ROOT, 'app', 'RequestProcessor.ahk'), 'utf8');
    if (!/APIModelsArr\s*:=\s*\[appDefaultModel\]/.test(rp))
      throw new Error('RequestProcessor.ahk no longer substitutes the app default model for empty APIModels (fix incomplete)');
    return 'set the command API Model to Default in the real Settings UI and saved (settings.json APIModels=""); the REAL SettingsApply chain now builds runtime commands with hasProp=1/hasNameProp=1/hasMenuProp=1 and cmd.APIModels / cmd.commandName / cmd.menuText read "" without throwing - the #162 default-model substitution is reachable (' +
      JSON.stringify(text.match(/msg='([^']*)'/)[1]) + ' was the pre-fix throw; now guarded)';
  }
});

scenarios.push({
  id: 27,
  name: 'Commands Advanced card collapses when you click inside it to edit a field',
  regression: true, // FIXED bug kept as a regression check (card must stay open while editing)
  mode: null,
  settings: {
    commands: [{
      commandName: 'Test Command', menuText: 'Test Command', APIModels: '',
      pasteMode: 'chat', userMessage: '{{input}}', stream: false
    }]
  },
  async body({ cdp }) {
    await openSettings(cdp);
    await openSection(cdp, 'commands');
    await cdp.waitFor('document.querySelectorAll("#commandsListBody .cmd-item").length > 0', 10000, 250, 'command list');
    await cdp.click('#commandsListBody .cmd-item');
    await sleep(400);
    // Open the Advanced card via its header.
    await cdp.click('.cmd-advanced-wrap .cmd-advanced-toggle');
    await sleep(300);
    const opened = await cdp.eval('document.querySelector(".cmd-advanced-body").style.display');
    if (opened !== 'block')
      throw new Error('advanced card did not open: ' + JSON.stringify(opened));
    // Click inside a field. _wireDetail puts the toggle listener on the whole
    // .cmd-advanced-wrap, so any click inside collapses the card.
    await cdp.click('#cmdInputBoxDefault');
    await sleep(300);
    const afterClick = await cdp.eval('document.querySelector(".cmd-advanced-body").style.display');
    // FIXED (bug #27): the toggle lives on the header only, so clicking
    // inside a field must NOT collapse the card.
    if (afterClick !== 'block')
      throw new Error('advanced card collapsed after clicking inside a field (display=' + JSON.stringify(afterClick) + ')');
    return 'clicking inside the Advanced card to edit a field keeps it open (display=' + afterClick + ')';
  }
});

scenarios.push({
  id: 36,
  name: 'Command temperature/reasoning persist when the command model equals the app default (static check)',
  regression: true, // FIXED bug kept as a regression check (default-model commands must keep their temperature/reasoning overrides)
  mode: null,
  noApp: true,
  async body() {
    const src = fs.readFileSync(path.join(launcher.REPO_ROOT, 'app', 'RequestProcessor.ahk'), 'utf8');
    const gatePos = src.indexOf('if fullAPIModelName != appDefaultModel');
    if (gatePos < 0) throw new Error('model-default gate not found in RequestProcessor.ahk');
    const gateBlock = src.slice(gatePos, gatePos + 500);
    // FIXED (bug #36): the gate now wraps ONLY modelOverride; temperature,
    // reasoning, and system overrides are persisted unconditionally, so a
    // chat-mode command whose model IS the app default keeps its overrides.
    if (gateBlock.indexOf('temperatureOverride') >= 0 || gateBlock.indexOf('reasoningOverride') >= 0 || gateBlock.indexOf('systemOverride') >= 0)
      throw new Error('overrides still inside the model-default gate (bug #36 not fixed)');
    const objPos = src.indexOf('commandThreadSettings := {');
    if (objPos < 0) throw new Error('unconditional command settings object not found in RequestProcessor.ahk');
    const objBlock = src.slice(objPos, objPos + 500);
    if (objBlock.indexOf('temperatureOverride') < 0 || objBlock.indexOf('reasoningOverride') < 0)
      throw new Error('temperature/reasoning overrides missing from the unconditional command settings object');
    return 'temperature/reasoning overrides persist outside the model-default gate; only modelOverride is gated';
  }
});

scenarios.push({
  id: 46,
  name: 'Command "Stream Response" + pasteMode replace/append builds a non-streaming request (static check)',
  regression: true, // FIXED bug kept as a regression check (replace/append must not advertise stream:true to the single-shot runner)
  mode: null,
  noApp: true,
  async body() {
    const lb = fs.readFileSync(path.join(launcher.REPO_ROOT, 'api', 'LLMRequestBuilder.ahk'), 'utf8');
    const irr = fs.readFileSync(path.join(launcher.REPO_ROOT, 'app', 'InlineRequestRunner.ahk'), 'utf8');
    // The inline runner is single-shot: it builds via createJSONRequest and
    // executes with the NON-streaming CurlBuilder.Build (not BuildStream)...
    const nonFimUsesBuild = /LLMRequestBuilder\.createJSONRequest[\s\S]*?CurlBuilder\.Build\(providerInfo, requestFile, outputFile\)/.test(irr);
    // ...and parses the whole output file as ONE JSON document.
    const parsesAsJson = /JSONResponseFromLLM := CurlExecutor\.Run[\s\S]*?jsongo\.Parse\(JSONResponseFromLLM\)/.test(irr);
    const noSseInInline = !/SSEParser/.test(irr);
    // FIXED (bug #46): the runner builds its request with stream=false, so the
    // API returns a plain JSON response the single-shot parser can read.
    const buildsWithoutStream = /createJSONRequest\(fullAPIModelName, systemMessage, captured\.userMessage,[\s\S]*?temperature, maxTokens, stop, false, thinking, thinkingLevel\)/.test(irr);
    if (!nonFimUsesBuild || !parsesAsJson || !noSseInInline || !buildsWithoutStream)
      throw new Error('inline runner stream handling not fixed: nonFimUsesBuild=' + nonFimUsesBuild +
        ' parsesAsJson=' + parsesAsJson + ' noSseInInline=' + noSseInInline + ' buildsWithoutStream=' + buildsWithoutStream);
    return 'InlineRequestRunner builds its request with stream=false (single-shot CurlBuilder.Build + JSON parse), so a replace/append command with Stream Response ON pastes its response instead of silently dropping SSE';
  }
});

scenarios.push({
  id: 50,
  name: 'Commands keep their system prompt after a settings save: bare system-message filenames resolve against default-settings/system-messages/ (static check)',
  regression: true, // FIXED bug kept as a regression check (commands must keep resolving app-default system messages)
  mode: null,
  noApp: true,
  async body() {
    const modal = fs.readFileSync(path.join(launcher.REPO_ROOT, 'webui', 'js', 'settings', 'sections', 'sysmsg-modal.js'), 'utf8');
    const cmdMenu = fs.readFileSync(path.join(launcher.REPO_ROOT, 'app', 'menu', 'CommandMenu.ahk'), 'utf8');
    const asstRepo = fs.readFileSync(path.join(launcher.REPO_ROOT, 'chat', 'db', 'AssistantRepo.ahk'), 'utf8');
    const resolver = fs.readFileSync(path.join(launcher.REPO_ROOT, 'shared', 'SystemMessageResolver.ahk'), 'utf8');
    // The settings modal saves the select's value - for app-default files that
    // is the BARE filename ("refine.txt"), not the prefixed path.
    const modalSavesValue = /sysMsgFile = fileSelect \? fileSelect\.value : ''/.test(modal);
    // FIXED: the shared resolver (SystemMessageResolver) searches
    // default-settings/system-messages/ and the user AppData folder, and both
    // the command path and the assistant path delegate to it (no more copies).
    const resolverSearchesDefaults = /A_ScriptDir "\\default-settings\\system-messages\\" filePath/.test(resolver);
    const resolverSearchesAppData = /AppInfo\.DataDir "\\system-messages\\" name/.test(resolver);
    const cmdDelegates = /SystemMessageResolver\.Resolve\(cmd\)/.test(cmdMenu);
    const assistantDelegates = /SystemMessageResolver\.Resolve\(a\)/.test(asstRepo);
    // The stock app-default files live ONLY under default-settings/system-messages/.
    const sysDir = path.join(launcher.REPO_ROOT, 'default-settings', 'system-messages');
    const bareFiles = fs.readdirSync(sysDir).filter((f) => f.endsWith('.txt'));
    const missingAtRoot = bareFiles.filter((f) => !fs.existsSync(path.join(launcher.REPO_ROOT, f)));
    // After a settings save, systemMessageFile is the bare name; the command
    // path must resolve it under default-settings/system-messages/ so the
    // command keeps its system prompt.
    if (!modalSavesValue || !resolverSearchesDefaults || !resolverSearchesAppData || !cmdDelegates || !assistantDelegates || missingAtRoot.length === 0)
      throw new Error('regression check failed: modalSavesValue=' + modalSavesValue +
        ' resolverSearchesDefaults=' + resolverSearchesDefaults + ' resolverSearchesAppData=' + resolverSearchesAppData +
        ' cmdDelegates=' + cmdDelegates + ' assistantDelegates=' + assistantDelegates + ' missingAtRoot=' + missingAtRoot.length);
    return 'modal saves bare filenames (' + bareFiles.length + ' app-default files); SystemMessageResolver searches default-settings/system-messages/ + AppData, and both command and assistant paths delegate to it';
  }
});

scenarios.push({
  id: 223,
  name: 'Two quick chat-mode commands leak the FIRST request\'s temp files - deleteTempFiles() only ever reads requestParams\' CURRENT paths (the second request\'s), so the clobbered first request\'s cURL command file (which embeds the Authorization: Bearer API key) plus its request/output/error files stay in %TEMP% forever: the bug #110 cleanup guarantee is broken by the bug #221 race',
  mode: 'sse-slow',
  regression: true, // FIXED bug #223 kept as a regression check (per-request cleanup: no leftover ChatWindow_* temp files)
  fixtures: {
    threads: [
      { id: 't-223-a', title: 'Cmd A', active_leaf_id: 'm-223-u1a' },
      { id: 't-223-b', title: 'Cmd B', active_leaf_id: 'm-223-u1b' }
    ],
    messages: [
      { id: 'm-223-u1a', thread_id: 't-223-a', role: 'user', content: 'first command request', token_count: 5, active_path_tokens: 5 },
      { id: 'm-223-u1b', thread_id: 't-223-b', role: 'user', content: 'second command request', token_count: 5, active_path_tokens: 5 }
    ]
  },
  async body({ cdp }) {
    const tmp = os.tmpdir();
    const isChatTemp = (n) => /^ChatWindow_(Req|cURL|Out|Err)_\d+\.(json|txt)$/.test(n);
    // Snapshot the pre-existing temp files (this machine already has leftovers
    // from earlier runs; only NEW files created by this run count as leaks).
    const before = new Set(fs.readdirSync(tmp).filter(isChatTemp));
    await sleep(500);
    // Command 1, then command 2 while command 1 is still streaming (bug #221 race).
    runProbe('load-thread', ['t-223-a']);
    runProbe('trigger-llm', ['1']);
    await cdp.waitFor('typeof isLoading !== "undefined" && isLoading === true', 10000, 200, 'first command in flight');
    await sleep(300);
    runProbe('load-thread', ['t-223-b']);
    runProbe('trigger-llm', ['1']);
    // Let both streams settle (sse-slow total ~3s; generous margin).
    await sleep(9000);
    const leftover = fs.readdirSync(tmp).filter((n) => isChatTemp(n) && !before.has(n));
    const withBearer = leftover.filter((n) => {
      try { return fs.readFileSync(path.join(tmp, n), 'utf8').includes('Authorization: Bearer'); } catch { return false; }
    });
    // FIXED (bug #223): each request's own temp files (including the cURL
    // command with the Authorization: Bearer key) are deleted when that
    // request completes - the per-request stream state loads THIS request's
    // paths into requestParams before deleteTempFiles runs.
    if (leftover.length > 0 || withBearer.length > 0)
      throw new Error('request temp files still leak after the two-command race (bug #223 not fixed): newLeftovers=' + JSON.stringify(leftover) + ' withBearer=' + withBearer.length);
    return 'after the two-command race: ' + leftover.length + ' new leftover ChatWindow_* temp files, ' + withBearer.length +
      ' cURL command(s) still containing "Authorization: Bearer" - every request\'s temp files (including the API-key-bearing cURL command) were deleted';
  }
});

scenarios.push({
  id: 221,
  name: 'Two quick chat-mode commands (second triggered while the first is still streaming) - the second _BuildAndFireRequest overwrites the shared requestParams _stream* keys, cURL PID and temp-file paths, so the FIRST command response is never persisted: the first chat is left hanging with only its user message (loses the first chat command)',
  mode: 'sse-slow',
  regression: true, // FIXED bug #221 kept as a regression check (per-request stream state: both command responses persist)
  fixtures: {
    threads: [
      { id: 't-221-a', title: 'Cmd A', active_leaf_id: 'm-221-u1a' },
      { id: 't-221-b', title: 'Cmd B', active_leaf_id: 'm-221-u1b' }
    ],
    messages: [
      { id: 'm-221-u1a', thread_id: 't-221-a', role: 'user', content: 'first command request', token_count: 5, active_path_tokens: 5 },
      { id: 'm-221-u1b', thread_id: 't-221-b', role: 'user', content: 'second command request', token_count: 5, active_path_tokens: 5 }
    ]
  },
  async body({ cdp, dbPath }) {
    await sleep(500);
    // Command 1: load thread A and trigger the LLM - mirrors the command path
    // processInitialRequest -> openChatWindow(threadId) + notifyTriggerLLM(1).
    const p1 = runProbe('load-thread', ['t-221-a']);
    if (!p1.posted) throw new Error('setup: load-thread probe did not post to the chat window: ' + JSON.stringify(p1));
    runProbe('trigger-llm', ['1']);
    await cdp.waitFor('typeof isLoading !== "undefined" && isLoading === true', 10000, 200, 'first command in flight');
    // The first stream is still running (sse-slow delivers chunks over ~3s).
    await sleep(300);
    // Command 2: load thread B and trigger while command 1 is still streaming.
    runProbe('load-thread', ['t-221-b']);
    runProbe('trigger-llm', ['1']);
    // Let both streams settle (sse-slow total ~3s; generous margin).
    await sleep(9000);
    const aAsst = seed.query(dbPath, "SELECT COUNT(*) AS cnt FROM messages WHERE thread_id='t-221-a' AND role='assistant'");
    const bAsst = seed.query(dbPath, "SELECT COUNT(*) AS cnt FROM messages WHERE thread_id='t-221-b' AND role='assistant'");
    const aContent = seed.query(dbPath, "SELECT content FROM messages WHERE thread_id='t-221-a' AND role='assistant'");
    const uiState = await cdp.eval('({ active: streamState.active, loading: isLoading, msgs: chatMessages.length })');
    // FIXED (bug #221): each request owns its own stream state (output file,
    // cURL PID, content, temp files), so both command responses persist into
    // their own threads even when the second fires mid-stream.
    if (aAsst[0].cnt < 1 || bAsst[0].cnt < 1)
      throw new Error('a command response was still lost (bug #221 not fixed): thread A assistant rows=' + aAsst[0].cnt +
        ' thread B assistant rows=' + bAsst[0].cnt + ' content=' + JSON.stringify(aContent));
    if (uiState.active || uiState.loading)
      throw new Error('UI not idle after both streams settled (bug #221 not fixed): ' + JSON.stringify(uiState));
    return 'command A triggered first, command B ~300ms later while A was still streaming: thread A assistant rows=' + aAsst[0].cnt +
      ' thread B assistant rows=' + bAsst[0].cnt +
      ' ui={active:' + uiState.active + ', loading:' + uiState.loading + ', msgs:' + uiState.msgs + '}' +
      ' - both command responses persisted into their own threads (per-request stream state)';
  }
});

scenarios.push({
  id: 203,
  name: 'Chat-mode command with "Stream Response" OFF still streams - processInitialRequest\'s pasteMode="chat" branch never propagates the command\'s stream flag (it only persists model/system/reasoning/temperature), while ChatWindow.ahk initializes requestParams["stream"]:=true and ChatRequestBuilder streams whenever that flag is set; a JSON-only API response is then read by the SSE parser and shown as a request failure',
  mode: null,
  noApp: true,
  regression: true, // FIXED bug #203 kept as a regression check
  settings: {},
  async body() {
    const rp = fs.readFileSync(path.join(launcher.REPO_ROOT, 'app', 'RequestProcessor.ahk'), 'utf8');
    const cw = fs.readFileSync(path.join(launcher.REPO_ROOT, 'chat', 'ChatWindow.ahk'), 'utf8');
    const crb = fs.readFileSync(path.join(launcher.REPO_ROOT, 'chat', 'ChatRequestBuilder.ahk'), 'utf8');
    const cm = fs.readFileSync(path.join(launcher.REPO_ROOT, 'ipc', 'CustomMessages.ahk'), 'utf8');
    const cipc = fs.readFileSync(path.join(launcher.REPO_ROOT, 'chat', 'ChatIPC.ahk'), 'utf8');
    const chatIdx = rp.indexOf('if pasteMode = "chat"');
    if (chatIdx < 0) throw new Error('chat branch not found (setup)');
    const chatBranch = rp.slice(chatIdx, rp.indexOf('} else {'));
    const defaultStreamTrue = /requestParams\["stream"\]\s*:=\s*true/.test(cw);
    const builderStreamsOnFlag = /if requestParams\["stream"\]\s*\{[\s\S]*?requestObj\.stream := true/.test(crb);
    const commandPassesFlag = /notifyTriggerLLM\(chatWindowhWnd,\s*stream\)/.test(chatBranch);
    const ipcCarriesFlag = /notifyTriggerLLM\(chatWindowhWnd,\s*stream\s*:=\s*true\)/.test(cm);
    const chatProcessHonorsFlag = /requestParams\["stream"\]\s*:=\s*wParam \? true : false/.test(cipc);
    const singleShotBranch = /if requestParams\["stream"\]\s*\{[\s\S]*?sendNonStreamingRequest\(&chatHistoryJSONRequest\)/.test(crb);
    // FIXED (bug #203): the command's Stream Response toggle is carried from
    // processInitialRequest -> notifyTriggerLLM wParam -> OnTriggerLLM
    // requestParams, and sendRequestToLLM routes stream=false to the
    // single-shot JSON path instead of the SSE handler.
    if (!defaultStreamTrue || !builderStreamsOnFlag || !commandPassesFlag || !ipcCarriesFlag || !chatProcessHonorsFlag || !singleShotBranch)
      throw new Error('chat-mode command stream toggle is still not propagated (fix incomplete): defaultStreamTrue=' + defaultStreamTrue +
        ' builderStreamsOnFlag=' + builderStreamsOnFlag + ' commandPassesFlag=' + commandPassesFlag +
        ' ipcCarriesFlag=' + ipcCarriesFlag + ' chatProcessHonorsFlag=' + chatProcessHonorsFlag + ' singleShotBranch=' + singleShotBranch);
    return 'ChatWindow defaults stream=true (normal chat); processInitialRequest passes the command\'s stream flag through notifyTriggerLLM; OnTriggerLLM writes requestParams["stream"] from wParam; and sendRequestToLLM routes stream=false to sendNonStreamingRequest (plain JSON) - a chat-mode command with Stream Response OFF no longer sends SSE';
  }
});

module.exports = scenarios;
