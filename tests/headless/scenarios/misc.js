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

scenarios.push({
  id: 61,
  name: "Clearing Suspend Banner text still shows the old banner (SettingsApply skips empty)",
  mode: null,
  noApp: true,
  async body() {
    const fs = require("node:fs");
    const path = require("node:path");
    const launcher = require("../launch");
    const sa = fs.readFileSync(path.join(launcher.REPO_ROOT, "app", "settings", "SettingsApply.ahk"), "utf8");
    const bannerSkipsEmpty = /if sb\.Has\("text"\) && sb\["text"\] != ""/.test(sa);
    if (!bannerSkipsEmpty) throw new Error("bug not reproduced: banner does not skip empty");
    return "SettingsApply._ApplySuspendBanner skips empty text � clearing leaves stale banner";
  }
});

scenarios.push({
  id: 62,
  name: "Forking a chat with temperature 0 drops the override (TreeRepo skips falsy)",
  mode: null,
  noApp: true,
  async body() {
    const fs=require("node:fs");
    const path=require("node:path");
    const launcher=require("../launch");
    const tr=fs.readFileSync(path.join(launcher.REPO_ROOT,"chat","db","TreeRepo.ahk"),"utf8");
    const hasTruthy = tr.includes('if settings.temperatureOverride') && tr.includes('temperature_override');
    const notZeroSafe = !tr.includes('temperatureOverride != ""');
    if(!hasTruthy || !notZeroSafe) throw new Error("bug not reproduced hasTruthy="+hasTruthy+" notZeroSafe="+notZeroSafe);
    return "TreeRepo._CopyThreadSettings checks if settings.temperatureOverride (falsy for 0) � forking a thread with temp 0 loses it";
  }
});

scenarios.push({
  id: 63,
  name: "Thread pricing unit falls back incorrectly when cachedInput is empty string",
  mode: null,
  noApp: true,
  async body() {
    const fs = require("node:fs");
    const path = require("node:path");
    const launcher = require("../launch");
    const tr = fs.readFileSync(path.join(launcher.REPO_ROOT, "chat", "db", "TreeRepo.ahk"), "utf8");
    const hasFallback = /cachedInput: pricing\.HasOwnProp\("cachedInput"\) \? pricing\.cachedInput : \(pricing\.HasOwnProp\("input"\) \? pricing\.input \* 0\.1/.test(tr);
    if (!hasFallback) throw new Error("bug not reproduced: fallback not found");
    return "TreeRepo GetThreadStats pricingUnit treats cachedInput=\"\" as 0 instead of 10% fallback";
  }
});



scenarios.push({
  id: 64,
  name: "Context Used excludes thinking tokens (header underreports)",
  mode: null,
  noApp: true,
  async body() {
    const sc=fs.readFileSync(require("path").join(require("../launch").REPO_ROOT,"chat","streaming","StreamCompletion.ahk"),"utf8");
    const hasVisibleOnly = /token_count: Max\(0, completionTokens - thinkingTokens\)/.test(sc);
    const mr2=fs.readFileSync(require("path").join(require("../launch").REPO_ROOT,"chat","db","MessageRepo.ahk"),"utf8");
    const activeExcludesThinking = /activePathTokens := msgObj\.prompt_tokens \+ tc/.test(mr2);
    const tr=fs.readFileSync(require("path").join(require("../launch").REPO_ROOT,"chat","db","TreeRepo.ahk"),"utf8");
    const readsActivePath = /active_path_tokens/.test(tr);
    if(!hasVisibleOnly || !activeExcludesThinking || !readsActivePath) throw new Error("bug not reproduced");
    return "MessageRepo stores token_count = completion-thinking and active_path_tokens = prompt+visible; header Context Used never counts thinking";
  }
});

scenarios.push({
  id: 65,
  name: "Hard-delete leaves cumulative token/cost counters stale (header stays inflated)",
  mode: null,
  noApp: true,
  async body() {
    const fs2=require("node:fs");
    const path2=require("node:path");
    const launcher2=require("../launch");
    const mr=fs2.readFileSync(path2.join(launcher2.REPO_ROOT,"chat","db","MessageRepo.ahk"),"utf8");
    const hd=mr.slice(mr.indexOf("static HardDelete"), mr.indexOf("static HardDelete")+3000);
    if(/cumulative_/.test(hd)) throw new Error("bug not reproduced: touches cumulative");
    return "HardDelete recomputes active_path_tokens but never updates cumulative_* counters";
  }
});

scenarios.push({
  id: 66,
  name: "Header tooltip typo Culminative",
  mode: null,
  noApp: true,
  async body() {
    const fs3=require("node:fs");
    const path3=require("node:path");
    const launcher3=require("../launch");
    const fmt=fs3.readFileSync(path3.join(launcher3.REPO_ROOT,"webui","js","chat","chat-format.js"),"utf8");
    if(!/Culminative/.test(fmt)) throw new Error("bug not reproduced");
    return "chat-format.js tooltip has Culminative (should be Cumulative)";
  }
});



scenarios.push({
  id: 67,
  regression: true,
  name: "Mock SSE usage (prompt 12, completion 9, cached 4) is stored accurately and header reflects it",
  mode: "sse-success",
  settings: {},
  fixtures: {
    threads: [{ id: "t-usage-67", title: "Usage Parse Check", active_leaf_id: "m-usage-67" }],
    messages: [{ id: "m-usage-67", thread_id: "t-usage-67", role: "user", content: "hello" }]
  },
  async body({ cdp, dbPath }) {
    const seed=require("../seed");
    await cdp.waitFor('document.querySelectorAll("#thread-list .chat-item").length > 0', 15000, 300, "thread list");
    await cdp.click('#thread-list .chat-item');
    await cdp.waitFor('document.querySelectorAll("#chat-messages .msg").length >= 1', 15000, 300, "thread loaded");
    await cdp.eval('document.getElementById("chat-input").value=""');
    await cdp.type("#chat-input", "verify usage parse");
    await cdp.click("#chat-send-btn");
    await cdp.waitFor('typeof streamState !== "undefined" && !streamState.active', 30000, 300, "stream done");
    await new Promise(r=>setTimeout(r,800));
    const msgs=seed.query(dbPath, "SELECT role, token_count, thinking_tokens, cached_tokens, active_path_tokens FROM messages WHERE thread_id='t-usage-67' ORDER BY created_at");
    const asst=msgs.filter(m=>m.role==="assistant").pop();
    if(!asst) throw new Error("no assistant: "+JSON.stringify(msgs));
    if(asst.token_count !== 9) throw new Error("assistant token_count wrong: "+JSON.stringify(asst));
    if(asst.cached_tokens !== 4) throw new Error("cached_tokens wrong: "+JSON.stringify(asst));
    if(asst.active_path_tokens !== 21) throw new Error("active_path wrong: "+JSON.stringify(asst));
    const barTitles=await cdp.eval('[...document.querySelectorAll("#tokenBar .tu-item")].map(e=>e.title)');
    const barText=await cdp.eval('document.getElementById("tokenBar").innerText');
    const hasContext=barText.includes("21") || barTitles.join(" ").includes("21");
    if(!hasContext) throw new Error("header missing 21: bar="+JSON.stringify(barText)+" titles="+JSON.stringify(barTitles));
    return "assistant stored token_count=9 cached=4 active=21 header shows 21";
  }
});
scenarios.push({
  id: 68,
  name: "ProviderResolver legacy prefix uses substring InStr, not prefix check",
  mode: null,
  noApp: true,
  async body() {
    const pr=require("node:fs").readFileSync(require("node:path").join(require("../launch").REPO_ROOT,"api","ProviderResolver.ahk"),"utf8");
    const hasSubstring = /if InStr\(modelId, prefix\)/.test(pr);
    const hasPrefixCheck = /SubStr\(modelId, 1,/.test(pr) || /InStr\(modelId, prefix\) = 1/.test(pr);
    if(!hasSubstring || hasPrefixCheck) throw new Error("bug not reproduced hasSubstring="+hasSubstring+" hasPrefixCheck="+hasPrefixCheck);
    return "ProviderResolver.Resolve uses InStr substring � mygpt-custom would match gpt incorrectly";
  }
});

scenarios.push({
  id: 69,
  name: "Search LIKE does not escape % _ wildcard � searching for % returns everything",
  mode: null,
  noApp: true,
  async body() {
    const sr=require("node:fs").readFileSync(require("node:path").join(require("../launch").REPO_ROOT,"chat","db","SearchRepo.ahk"),"utf8");
    const likeLine = sr.slice(sr.indexOf("static _Like"), sr.indexOf("static _Like")+1500);
    const escapesWildcards = /StrReplace.*%/.test(likeLine) && /StrReplace.*_/.test(likeLine);
    if(escapesWildcards) throw new Error("bug not reproduced: LIKE escapes wildcards");
    return "SearchRepo._Like uses LIKE ESCAPE but safeQuery only doubles single quotes � % remains wildcard";
  }
});

scenarios.push({
  id: 70,
  name: "Search FTS5 does not escape special characters � C++ breaks MATCH",
  mode: null,
  noApp: true,
  async body() {
    const fs=require("node:fs");
    const path=require("node:path");
    const launcher=require("../launch");
    const sr=fs.readFileSync(path.join(launcher.REPO_ROOT,"chat","db","SearchRepo.ahk"),"utf8");
    const fts=sr.slice(sr.indexOf("static _FTS5"), sr.indexOf("static _FTS5")+2500);
    const buildsRaw = /ftsExpr \.= trimmed/.test(fts);
    const escapesDouble = /StrReplace\(ftsExpr, "\""/.test(fts);
    if(!buildsRaw || escapesDouble) throw new Error("bug not reproduced buildsRaw="+buildsRaw+" escapesDouble="+escapesDouble);
    return "SearchRepo._FTS5 builds from raw trimmed words and only escapes single quotes � C++ breaks MATCH";
  }
});

scenarios.push({
  id: 71,
  name: "Clearing Thread Title Generation model/prompt leaves stale global",
  mode: null,
  noApp: true,
  async body() {
    const sa=require("node:fs").readFileSync(require("node:path").join(require("../launch").REPO_ROOT,"app","settings","SettingsApply.ahk"),"utf8");
    const skipsModel = /if tt\.Has\("model"\) && tt\["model"\] != ""/.test(sa);
    const skipsPrompt = /if tt\.Has\("prompt"\) && tt\["prompt"\] != ""/.test(sa);
    if(!skipsModel || !skipsPrompt) throw new Error("bug not reproduced");
    return "SettingsApply._ApplyThreadTitles only assigns when != empty � clearing leaves stale model/prompt";
  }
});

scenarios.push({
  id: 72,
  name: "SystemMessageResolver UNC path treated as relative � \\\\server\\share broken",
  mode: null,
  noApp: true,
  async body() {
    const sr=require("node:fs").readFileSync(require("node:path").join(require("../launch").REPO_ROOT,"shared","SystemMessageResolver.ahk"),"utf8");
    const checksColon = /if !InStr\(filePath, ":"\)/.test(sr);
    const handlesUNC = /\\\\/.test(sr) || /InStr\(filePath, "\\\\/.test(sr);
    if(!checksColon || handlesUNC) throw new Error("bug not reproduced checksColon="+checksColon+" handlesUNC="+handlesUNC);
    return "SystemMessageResolver.Resolve checks InStr(filePath, \":\") to detect absolute � UNC \\\\server\\share has no colon and is searched as relative";
  }
});

scenarios.push({
  id: 73,
  name: "GoogleChatCompletions disabled config missing include_thoughts for 2.x",
  mode: null,
  noApp: true,
  async body() {
    const gc=require("node:fs").readFileSync(require("node:path").join(require("../launch").REPO_ROOT,"api","handlers","GoogleChatCompletions.ahk"),"utf8");
    const disabledStart = gc.indexOf("static DisabledConfig");
    const disabledEnd = gc.indexOf("static ThinkingConfig", disabledStart);
    const disabled = gc.slice(disabledStart, disabledEnd);
    const hasBudget0 = /thinking_budget: 0/.test(disabled);
    const hasInclude = /include_thoughts/.test(disabled);
    if(!hasBudget0 || hasInclude) throw new Error("bug not reproduced hasBudget0="+hasBudget0+" hasInclude="+hasInclude);
    return "GoogleChatCompletions.DisabledConfig returns {thinking_budget:0} without include_thoughts";;
  }
});

scenarios.push({
  id: 74,
  name: "SettingsApply providerMap stale when all prefixes cleared",
  mode: null,
  noApp: true,
  async body() {
    const sa=require("node:fs").readFileSync(require("node:path").join(require("../launch").REPO_ROOT,"app","settings","SettingsApply.ahk"),"utf8");
    const hasGuard = /if newProviderMap\.Count > 0/.test(sa) && /providerMap := newProviderMap/.test(sa);
    const hasElseClear = /else.*providerMap.*Map\(\)/.test(sa) || /providerMap := Map\(\)/.test(sa);
    if(!hasGuard || hasElseClear) throw new Error("bug not reproduced hasGuard="+hasGuard+" hasElseClear="+hasElseClear);
    return "SettingsApply._ApplyProviders only overwrites providerMap when Count>0 � clearing all prefixes leaves old map";
  }
});

scenarios.push({
  id: 75,
  name: "GoogleChatCompletions budget table uses substring InStr, not prefix/contains check",
  mode: null,
  noApp: true,
  async body() {
    const gc=require("node:fs").readFileSync(require("node:path").join(require("../launch").REPO_ROOT,"api","handlers","GoogleChatCompletions.ahk"),"utf8");
    const hasSubstring = /if InStr\(modelId, "2\.5-pro"\)/.test(gc);
    const hasExact = /modelId = "2\.5-pro"/.test(gc);
    if(!hasSubstring) throw new Error("bug not reproduced");
    return "GoogleChatCompletions._BudgetTable uses InStr substring � my2.5-pro would match 2.5-pro incorrectly";
  }
});

module.exports = scenarios;
