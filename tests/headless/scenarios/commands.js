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
const launcher = require('../launch');
const { sleep, runThinkingProbe, openSettings, openSection } = require('./helpers');

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
  id: 203,
  name: 'Chat-mode command with "Stream Response" OFF still streams - processInitialRequest\'s pasteMode="chat" branch never propagates the command\'s stream flag (it only persists model/system/reasoning/temperature), while ChatWindow.ahk initializes requestParams["stream"]:=true and ChatRequestBuilder streams whenever that flag is set; a JSON-only API response is then read by the SSE parser and shown as a request failure',
  mode: null,
  noApp: true,
  settings: {},
  async body() {
    const rp = fs.readFileSync(path.join(launcher.REPO_ROOT, 'app', 'RequestProcessor.ahk'), 'utf8');
    const cw = fs.readFileSync(path.join(launcher.REPO_ROOT, 'chat', 'ChatWindow.ahk'), 'utf8');
    const crb = fs.readFileSync(path.join(launcher.REPO_ROOT, 'chat', 'ChatRequestBuilder.ahk'), 'utf8');
    const chatIdx = rp.indexOf('if pasteMode = "chat"');
    if (chatIdx < 0) throw new Error('chat branch not found (setup)');
    const chatBranch = rp.slice(chatIdx, rp.indexOf('} else {'));
    const defaultStreamTrue = /requestParams\["stream"\]\s*:=\s*true/.test(cw);
    const builderStreamsOnFlag = /if requestParams\["stream"\]\s*\{[\s\S]*?requestObj\.stream := true/.test(crb);
    const chatBranchPropagatesStream = /requestParams\["stream"\]|stream:\s*stream|Thread_UpdateSettings[\s\S]{0,200}stream/.test(chatBranch);
    // BUG present: the chat branch stores commandThreadSettings without any
    // stream field, the chat process defaults stream:=true, and the builder
    // honors that flag - so the command's Stream Response toggle is dead for
    // pasteMode=chat and a non-streaming API response is misparsed as SSE.
    if (!defaultStreamTrue || !builderStreamsOnFlag || chatBranchPropagatesStream)
      throw new Error('chat-mode command stream flag is not dead (bug not reproduced): defaultStreamTrue=' + defaultStreamTrue +
        ' builderStreamsOnFlag=' + builderStreamsOnFlag + ' chatBranchPropagatesStream=' + chatBranchPropagatesStream);
    return 'ChatWindow defaults requestParams["stream"]=true; ChatRequestBuilder streams when that flag is set; and processInitialRequest\'s chat branch never writes the command\'s stream toggle into requestParams/thread settings - a chat-mode command with Stream Response OFF still sends stream:true and fails on JSON-only responses';
  }
});

module.exports = scenarios;
