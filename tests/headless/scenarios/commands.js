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
  name: 'Command temperature/reasoning are dropped when the command model equals the app default (static check)',
  mode: null,
  noApp: true,
  async body() {
    const src = fs.readFileSync(path.join(launcher.REPO_ROOT, 'app', 'RequestProcessor.ahk'), 'utf8');
    const gatePos = src.indexOf('if fullAPIModelName != appDefaultModel');
    if (gatePos < 0) throw new Error('model-default gate not found in RequestProcessor.ahk');
    const block = src.slice(gatePos, gatePos + 1200);
    const hasTemp = block.indexOf('temperatureOverride') >= 0;
    const hasReasoning = block.indexOf('reasoningOverride') >= 0;
    // BUG: Thread_UpdateSettings (with temperatureOverride/reasoningOverride) is
    // nested inside the "model != appDefaultModel" branch, so a chat-mode command
    // whose model IS the app default never persists its temperature/thinking and
    // the fired request silently uses defaults.
    if (!hasTemp || !hasReasoning)
      throw new Error('overrides not inside the gated block (bug not reproduced): hasTemp=' + hasTemp + ' hasReasoning=' + hasReasoning);
    return 'Thread_UpdateSettings with temperatureOverride/reasoningOverride sits inside `if fullAPIModelName != appDefaultModel`; default-model commands drop them';
  }
});

scenarios.push({
  id: 46,
  name: 'Command "Stream Response" + pasteMode replace/append silently produces no output (static check)',
  mode: null,
  noApp: true,
  async body() {
    const lb = fs.readFileSync(path.join(launcher.REPO_ROOT, 'api', 'LLMRequestBuilder.ahk'), 'utf8');
    const irr = fs.readFileSync(path.join(launcher.REPO_ROOT, 'app', 'InlineRequestRunner.ahk'), 'utf8');
    // createJSONRequest unconditionally adds stream:true to the JSON body when the
    // command's stream flag is set (no pasteMode check)...
    const bodyAddsStream = /if stream \{[\s\S]*?requestObj\.stream := true/.test(lb);
    // ...the inline runner builds the request via createJSONRequest and executes it
    // with the NON-streaming single-shot CurlBuilder.Build (not BuildStream)...
    const nonFimUsesBuild = /LLMRequestBuilder\.createJSONRequest[\s\S]*?CurlBuilder\.Build\(providerInfo, requestFile, outputFile\)/.test(irr);
    // ...and parses the whole output file as ONE JSON document.
    const parsesAsJson = /JSONResponseFromLLM := CurlExecutor\.Run[\s\S]*?jsongo\.Parse\(JSONResponseFromLLM\)/.test(irr);
    const noSseInInline = !/SSEParser/.test(irr);
    // BUG: with stream=true the API answers with SSE (multiple data: lines),
    // which jsongo.Parse cannot parse as one JSON document; ParseChatResponse is
    // skipped and success=false, so nothing is pasted and no error is shown.
    if (!bodyAddsStream || !nonFimUsesBuild || !parsesAsJson || !noSseInInline)
      throw new Error('bug not reproduced: bodyAddsStream=' + bodyAddsStream +
        ' nonFimUsesBuild=' + nonFimUsesBuild + ' parsesAsJson=' + parsesAsJson + ' noSseInInline=' + noSseInInline);
    return 'createJSONRequest adds stream:true for any pasteMode; InlineRequestRunner executes with single-shot CurlBuilder.Build and parses the whole output as one JSON document (no SSEParser) - a replace/append command with Stream Response ON receives SSE it cannot parse, so it silently pastes nothing';
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
    const resolverSearchesAppData = /A_AppData "\\LLM-AutoHotkey-Assistant\\system-messages\\" name/.test(resolver);
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

module.exports = scenarios;
