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
    // BUG: the card collapses while the user is trying to edit a field.
    if (afterClick !== 'none')
      throw new Error('advanced card stayed open after clicking inside (bug not reproduced): ' + JSON.stringify(afterClick));
    return 'clicking inside the Advanced card to edit a field collapsed it (display=' + afterClick + ')';
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
  name: 'Commands lose their system prompt after a settings save: bare system-message filenames cannot be resolved by the command path (static check)',
  mode: null,
  noApp: true,
  async body() {
    const modal = fs.readFileSync(path.join(launcher.REPO_ROOT, 'webui', 'js', 'settings', 'sections', 'sysmsg-modal.js'), 'utf8');
    const cmdMenu = fs.readFileSync(path.join(launcher.REPO_ROOT, 'app', 'menu', 'CommandMenu.ahk'), 'utf8');
    const asstRepo = fs.readFileSync(path.join(launcher.REPO_ROOT, 'chat', 'db', 'AssistantRepo.ahk'), 'utf8');
    // The settings modal saves the select's value - for app-default files that
    // is the BARE filename ("refine.txt"), not the prefixed path.
    const modalSavesValue = /sysMsgFile = fileSelect \? fileSelect\.value : ''/.test(modal);
    // The command path resolves relative files only against A_ScriptDir...
    const commandResolvesAgainstScriptDir = /if !InStr\(filePath, ":"\) && !InStr\(filePath, "\\\\"\)[\s\S]*?filePath := A_ScriptDir "\\\\" filePath/.test(cmdMenu);
    // ...and has no default-settings/system-messages/ or AppData search (unlike the assistant path).
    const commandSearchesSysMsgDir = /A_ScriptDir[^\n]*system-messages|A_AppData[^\n]*system-messages/.test(cmdMenu);
    const assistantSearches = /A_ScriptDir "\\default-settings\\system-messages\\" filePath/.test(asstRepo);
    // The stock app-default files live ONLY under default-settings/system-messages/.
    const sysDir = path.join(launcher.REPO_ROOT, 'default-settings', 'system-messages');
    const bareFiles = fs.readdirSync(sysDir).filter((f) => f.endsWith('.txt'));
    const missingAtRoot = bareFiles.filter((f) => !fs.existsSync(path.join(launcher.REPO_ROOT, f)));
    // BUG: after any settings save of a command that uses an app-default file,
    // systemMessageFile becomes the bare name; at trigger time the command path
    // looks for repo\refine.txt (missing) instead of repo\default-settings\system-messages\refine.txt,
    // so FileRead throws -> MsgBox + empty inline fallback -> the command runs
    // without its system prompt.
    if (!modalSavesValue || !commandResolvesAgainstScriptDir || commandSearchesSysMsgDir || !assistantSearches || missingAtRoot.length === 0)
      throw new Error('bug not reproduced: modalSavesValue=' + modalSavesValue +
        ' commandResolvesAgainstScriptDir=' + commandResolvesAgainstScriptDir +
        ' commandSearchesSysMsgDir=' + commandSearchesSysMsgDir +
        ' assistantSearches=' + assistantSearches + ' missingAtRoot=' + missingAtRoot.length);
    return 'modal saves bare filenames (' + bareFiles.length + ' app-default files); command _resolveSystemMessage only prepends A_ScriptDir (no default-settings/system-messages search) while the assistant path searches default-settings/system-messages/; e.g. ' +
      bareFiles[0] + ' exists only under default-settings/system-messages/ -> commands lose their system prompt after a settings save';
  }
});

module.exports = scenarios;
