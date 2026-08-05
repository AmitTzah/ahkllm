// scenarios/misc.js - Icons, model-id parsing, vision gating, API logs
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
const { CDP } = require('../cdp');
const launcher = require('../launch');
const { sleep, runIconCheck, readJsonFile, showChat, sendChatMessage, waitStreamingIdle } = require('./helpers');

const scenarios = [];

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
    const mangled = runIconCheck(absIco);
    if (mangled.hCustom === 0) throw new Error('direct LoadPicture of the chosen icon failed; probe=' + JSON.stringify(mangled));
    if (mangled.hMangled !== 0) throw new Error('mangled path unexpectedly loaded; probe=' + JSON.stringify(mangled));
    if (mangled.customApplied !== 1) throw new Error('custom icon NOT applied to chat window; probe=' + JSON.stringify(mangled));
    if (mangled.renderFailed === 1) throw new Error('icon render failed 3x; probe=' + JSON.stringify(mangled));
    return 'absolute icon path: direct LoadPicture ok (h=' + mangled.hCustom + '), mangled path h=' + mangled.hMangled + ', custom icon applied to chat window (customApplied=1)';
  }
});

scenarios.push({
  id: 43,
  name: 'Short-form model ids keep thinking metadata (provider prefix not required)',
  regression: true, // FIXED by the ModelId consolidation (step 5)
  mode: 'sse-success',
  settings: {},
  fixtures: {
    threads: [{
      id: 't-think-43', title: 'Short Model Think', active_leaf_id: 'm-think-43',
      model_override: 'deepseek-v4-pro', reasoning_override: 'high'
    }],
    messages: [{ id: 'm-think-43', thread_id: 't-think-43', role: 'user', content: 'hello' }]
  },
  async body({ cdp, mockLog }) {
    await showChat();
    await cdp.waitFor('document.querySelectorAll("#thread-list .chat-item").length > 0', 15000, 300, 'thread list');
    await cdp.click('#thread-list .chat-item');
    await cdp.waitFor('document.querySelectorAll("#chat-messages .msg").length >= 1', 15000, 300, 'thread loaded');
    await sleep(700);
    // FIXED (ModelId.Lookup): the models map is keyed by full ids, but the
    // short form now resolves to its full key, so the right rail gets the
    // model's thinking levels.
    const optionCount = await cdp.eval('document.getElementById("reasoningDropdown") ? document.getElementById("reasoningDropdown").options.length : -1');
    if (optionCount < 2)
      throw new Error('right-rail thinking dropdown has no levels for the short-form model: options=' + optionCount);
    // Send a message and inspect the actual request sent to the (mock) API.
    await sendChatMessage(cdp, 'second message');
    await waitStreamingIdle(cdp, 30000);
    await sleep(500);
    const lines = fs.readFileSync(mockLog, 'utf8').split(/\r?\n/).filter(Boolean);
    const chatReq = lines.map((l) => JSON.parse(l)).find((e) => e.body && e.body.stream === true);
    if (!chatReq) throw new Error('no streaming chat request was logged; lines=' + lines.length);
    const b = chatReq.body;
    // FIXED: the reasoning override must now reach the request for the
    // short-form id.
    if (!b.thinking && !b.reasoning_effort)
      throw new Error('thinking was dropped for the short-form model: ' + JSON.stringify(b));
    return 'thread model_override=deepseek-v4-pro + reasoning_override=high: right-rail dropdown has ' + optionCount +
      ' option(s), and the sent request carries thinking config (model=' + b.model + ')';
  }
});

scenarios.push({
  id: 51,
  name: 'Vision gate accepts short-form model ids (provider prefix not required) - static check',
  regression: true, // FIXED by the ModelId consolidation (step 5)
  mode: null,
  noApp: true,
  async body() {
    const au = fs.readFileSync(path.join(launcher.REPO_ROOT, 'shared', 'AttachmentUtils.ahk'), 'utf8');
    const crb = fs.readFileSync(path.join(launcher.REPO_ROOT, 'chat', 'ChatRequestBuilder.ahk'), 'utf8');
    const rp = fs.readFileSync(path.join(launcher.REPO_ROOT, 'app', 'RequestProcessor.ahk'), 'utf8');
    const dm = fs.readFileSync(path.join(launcher.REPO_ROOT, 'default-settings', 'DefaultModels.ahk'), 'utf8');
    // FIXED: HasVision resolves through ModelId.Lookup, which accepts short
    // ids (the old models.Has-only check refused short ids - bug #51).
    const hasShortFormFallback = /static HasVision\(modelName\) \{[\s\S]*?ModelResolver\.Lookup\(models, modelName\)/.test(au);
    // Both the chat attachment gate and the command screenshot gate pass the
    // raw model name straight through.
    const chatGateUsesRawName = /_ProcessAttachmentsForLastUser\(&apiMessages, modelName\)[\s\S]*?AttachmentUtils\.HasVision\(modelName\)/.test(crb);
    const commandGateUsesRawName = /AttachmentUtils\.HasVision\(APIModelsArr\[1\]\)/.test(rp);
    // A vision-capable model exists, keyed ONLY by its full "provider/model" id.
    const m = dm.match(/"openai\/gpt-4\.1-mini", \{([\s\S]*?)\n    \},/);
    const fullEntryHasVision = !!m && /vision: true/.test(m[1]);
    const shortKeyExists = /^\s*"gpt-4\.1-mini", \{/m.test(dm);
    if (!hasShortFormFallback || !chatGateUsesRawName || !commandGateUsesRawName || !fullEntryHasVision || shortKeyExists)
      throw new Error('short-form vision fallback missing: hasShortFormFallback=' + hasShortFormFallback +
        ' chatGateUsesRawName=' + chatGateUsesRawName + ' commandGateUsesRawName=' + commandGateUsesRawName +
        ' fullEntryHasVision=' + fullEntryHasVision + ' shortKeyExists=' + shortKeyExists);
    return 'AttachmentUtils.HasVision resolves short ids via ModelId.Lookup, so "gpt-4.1-mini" finds the vision:true openai/gpt-4.1-mini entry; both gates still pass the raw id, which now works';
  }
});

module.exports = scenarios;
