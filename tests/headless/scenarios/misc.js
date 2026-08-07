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
  name: "Clearing Suspend Banner text resets the banner (SettingsApply assigns empty)",
  regression: true, // FIXED bug kept as a regression check (clearing a UI field must replace the stale global)
  mode: null,
  noApp: true,
  async body() {
    const fs = require("node:fs");
    const path = require("node:path");
    const launcher = require("../launch");
    const sa = fs.readFileSync(path.join(launcher.REPO_ROOT, "app", "settings", "SettingsApply.ahk"), "utf8");
    // FIXED (bug #61): _ApplySuspendBanner assigns the text even when empty.
    const assignsEmptyText = /if sb\.Has\("text"\)\s*\n\s*suspendBannerText := sb\["text"\]/.test(sa);
    const skipsEmpty = /sb\.Has\("text"\) && sb\["text"\] != ""/.test(sa);
    if (!assignsEmptyText || skipsEmpty)
      throw new Error("clearing suspend banner text still skipped (bug #61 not fixed): assignsEmptyText=" + assignsEmptyText + " skipsEmpty=" + skipsEmpty);
    return "SettingsApply._ApplySuspendBanner assigns the text even when empty, so clearing the field resets the banner";
  }
});

scenarios.push({
  id: 62,
  name: "Forking a chat with temperature 0 keeps the override (TreeRepo zero-safe)",
  regression: true, // FIXED bug kept as a regression check (fork must inherit a temperature 0 override)
  mode: null,
  noApp: true,
  async body() {
    const fs=require("node:fs");
    const path=require("node:path");
    const launcher=require("../launch");
    const tr=fs.readFileSync(path.join(launcher.REPO_ROOT,"chat","db","TreeRepo.ahk"),"utf8");
    // FIXED (bug #62): _CopyThreadSettings treats 0 as a valid override.
    const zeroSafe = tr.includes('if settings.temperatureOverride != ""');
    const truthyOnly = tr.includes('if settings.temperatureOverride') && !zeroSafe;
    if (!zeroSafe || truthyOnly)
      throw new Error("fork temp-0 copy not fixed (bug #62): zeroSafe=" + zeroSafe + " truthyOnly=" + truthyOnly);
    return "TreeRepo._CopyThreadSettings checks temperatureOverride != \"\" (0 is a valid override), so forking a thread with temp 0 keeps it";
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
    return "ProviderResolver.Resolve uses InStr substring ï¿½ mygpt-custom would match gpt incorrectly";
  }
});

scenarios.push({
  id: 69,
  name: "Search LIKE does not escape % _ wildcard ï¿½ searching for % returns everything",
  mode: null,
  noApp: true,
  async body() {
    const sr=require("node:fs").readFileSync(require("node:path").join(require("../launch").REPO_ROOT,"chat","db","SearchRepo.ahk"),"utf8");
    const likeLine = sr.slice(sr.indexOf("static _Like"), sr.indexOf("static _Like")+1500);
    const escapesWildcards = /StrReplace.*%/.test(likeLine) && /StrReplace.*_/.test(likeLine);
    if(escapesWildcards) throw new Error("bug not reproduced: LIKE escapes wildcards");
    return "SearchRepo._Like uses LIKE ESCAPE but safeQuery only doubles single quotes ï¿½ % remains wildcard";
  }
});

scenarios.push({
  id: 70,
  name: "Search FTS5 does not escape special characters ï¿½ C++ breaks MATCH",
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
    return "SearchRepo._FTS5 builds from raw trimmed words and only escapes single quotes ï¿½ C++ breaks MATCH";
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
    return "SettingsApply._ApplyThreadTitles only assigns when != empty ï¿½ clearing leaves stale model/prompt";
  }
});

scenarios.push({
  id: 72,
  name: "SystemMessageResolver UNC path treated as relative ï¿½ \\\\server\\share broken",
  mode: null,
  noApp: true,
  async body() {
    const sr=require("node:fs").readFileSync(require("node:path").join(require("../launch").REPO_ROOT,"shared","SystemMessageResolver.ahk"),"utf8");
    const checksColon = /if !InStr\(filePath, ":"\)/.test(sr);
    const handlesUNC = /\\\\/.test(sr) || /InStr\(filePath, "\\\\/.test(sr);
    if(!checksColon || handlesUNC) throw new Error("bug not reproduced checksColon="+checksColon+" handlesUNC="+handlesUNC);
    return "SystemMessageResolver.Resolve checks InStr(filePath, \":\") to detect absolute ï¿½ UNC \\\\server\\share has no colon and is searched as relative";
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
    return "SettingsApply._ApplyProviders only overwrites providerMap when Count>0 ï¿½ clearing all prefixes leaves old map";
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
    return "GoogleChatCompletions._BudgetTable uses InStr substring ï¿½ my2.5-pro would match 2.5-pro incorrectly";
  }
});

scenarios.push({
  id: 76,
  name: "initChatMode guard prevents activeThreadId update when already set ï¿½ stale thread",
  mode: null,
  noApp: true,
  async body() {
    const cc=require("node:fs").readFileSync(require("node:path").join(require("../launch").REPO_ROOT,"webui","js","chat","chat-core.js"),"utf8");
    const hasGuard = /if \(data && data\.threadId && !activeThreadId\)/.test(cc);
    const hasDirectAssign = /activeThreadId = data\.threadId/.test(cc);
    // Guard means if activeThreadId already holds old thread's id, new thread's id is ignored
    if(!hasGuard || !hasDirectAssign) throw new Error("bug not reproduced hasGuard="+hasGuard);
    return "chat-core.js initChatMode only sets activeThreadId when !activeThreadId ï¿½ stale if already set";
  }
});

scenarios.push({
  id: 77,
  name: "onChatSend empty input with existing messages triggers retry instead of no-op",
  mode: null,
  noApp: true,
  async body() {
    const ci=require("node:fs").readFileSync(require("node:path").join(require("../launch").REPO_ROOT,"webui","js","chat","chat-input.js"),"utf8");
    const hasEmptyRetry = /if \(chatMessages && chatMessages\.length > 0\)/.test(ci) && /retryLastAssistantMessage/.test(ci) && /Ipc\.postToHost\('retry'/.test(ci);
    const hasTrimCheck = /var message = input\.value\.trim\(\)/.test(ci);
    if(!hasEmptyRetry || !hasTrimCheck) throw new Error("bug not reproduced");
    return "chat-input.js onChatSend: empty trimmed message + attachments 0 falls through to retry last assistant ï¿½ empty Send unexpectedly re-fires";
  }
});

scenarios.push({
  id: 78,
  name: "Right-rail temperature 0 shows Default instead of 0.0 (falsy check)",
  mode: null,
  noApp: true,
  async body() {
    const cfg=require("node:fs").readFileSync(require("node:path").join(require("../launch").REPO_ROOT,"webui","js","chat","model-picker","model-picker-config.js"),"utf8");
    const hasFalsy = /var hasTemp = settings\.temperature && settings\.temperature !==/.test(cfg);
    const handlesZero = /settings\.temperature != "" && settings\.temperature !== undefined/.test(cfg) || /hasTemp =.*temperature.*!= ""/.test(cfg) && !/settings\.temperature &&/.test(cfg);
    if(!hasFalsy) throw new Error("bug not reproduced hasFalsy false");
    // hasFalsy true means 0 is treated as falsy -> shows Default
    return "model-picker-config.js hasTemp = settings.temperature && ... ï¿½ 0 is falsy, shows Default";
  }
});

scenarios.push({
  id: 79,
  name: "SettingsPersistence.Load does not strip UTF-8 BOM before JSON parse ï¿½ settings may be lost",
  mode: null,
  noApp: true,
  async body() {
    const sp=require("node:fs").readFileSync(require("node:path").join(require("../launch").REPO_ROOT,"app","settings","SettingsPersistence.ahk"),"utf8");
    const loadsRaw = /raw := FileRead\(path, "UTF-8"\)/.test(sp);
    const stripsBOM = /Strip.*BOM|SubStr\(raw, 1, 1\) =/.test(sp) || /BOM/.test(sp);
    const parsesDirect = /parsed := jsongo\.Parse\(raw\)/.test(sp);
    if(!loadsRaw || !parsesDirect || stripsBOM) throw new Error("bug not reproduced loadsRaw="+loadsRaw+" parsesDirect="+parsesDirect+" stripsBOM="+stripsBOM);
    return "SettingsPersistence.Load reads with FileRead UTF-8 and parses directly without stripping BOM ï¿½ BOM would cause parse failure";
  }
});

scenarios.push({
  id: 80,
  name: "ThreadRepo SoftDelete/Restore/Delete/Update do not escape threadId ï¿½ SQL injection via crafted id",
  mode: null,
  noApp: true,
  async body() {
    const tr=require("node:fs").readFileSync(require("node:path").join(require("../launch").REPO_ROOT,"chat","db","ThreadRepo.ahk"),"utf8");
    const soft = tr.slice(tr.indexOf("static SoftDelete"), tr.indexOf("static SoftDelete")+800);
    const hasEscapeSoft = /SQLite\.Escape\(threadId\)/.test(soft);
    const hasDirectSoft = /WHERE id='" threadId "'/.test(soft);
    const upd = tr.slice(tr.indexOf("static Update(threadId"), tr.indexOf("static Update(threadId")+800);
    const hasEscapeUpd = /SQLite\.Escape\(threadId\)/.test(upd);
    if(hasEscapeSoft || !hasDirectSoft) throw new Error("bug not reproduced soft hasEscape="+hasEscapeSoft);
    if(hasEscapeUpd) throw new Error("bug not reproduced update hasEscape");
    return "ThreadRepo SoftDelete/Restore/Delete/Update use WHERE id='\" threadId \"' without SQLite.Escape ï¿½ crafted threadId with ' could inject";
  }
});

scenarios.push({
  id: 81,
  name: "Branch _setupSiblingGroup UPDATE does not escape msg.id ï¿½ SQL injection via crafted message id",
  mode: null,
  noApp: true,
  async body() {
    const br=require("node:fs").readFileSync(require("node:path").join(require("../launch").REPO_ROOT,"chat","callbacks","Branch.ahk"),"utf8");
    const snippet = br.slice(br.indexOf("_setupSiblingGroup"), br.indexOf("_setupSiblingGroup")+800);
    const hasEscape = /SQLite\.Escape(msg.id)/.test(snippet);
    const hasDirect = /WHERE id='" msg.id "'/.test(snippet);
    if(hasEscape || !hasDirect) throw new Error("bug not reproduced hasEscape="+hasEscape);
    return 'Branch._setupSiblingGroup does UPDATE ... WHERE id=' + "'msg.id' without SQLite.Escape";
  }
});

scenarios.push({
  id: 82,
  name: "Usage dashboard provider/model filter XSS ï¿½ option values not escaped",
  mode: null,
  noApp: true,
  async body() {
    const dash=require("node:fs").readFileSync(require("node:path").join(require("../launch").REPO_ROOT,"webui","js","usage-dashboard.js"),"utf8");
    const hasEsc = /escHtml\(p\)/.test(dash) || /escHtml\(m\)/.test(dash);
    const hasRaw = /provSel\.innerHTML \+=.*\'<option value="\'\+p\+/.test(dash);
    if(hasEsc || !hasRaw) throw new Error("bug not reproduced hasEsc="+hasEsc+" hasRaw="+hasRaw);
    return "usage-dashboard.js populateFilters does provSel.innerHTML += '<option value=\"'+p+'\">'+p without escHtml ï¿½ XSS via provider/model name";
  }
});

scenarios.push({
  id: 83,
  name: "Threadmap who XSS ï¿½ model name not escaped in nav list",
  mode: null,
  noApp: true,
  async body() {
    const tm=require("node:fs").readFileSync(require("node:path").join(require("../launch").REPO_ROOT,"webui","js","chat","chat-threadmap.js"),"utf8");
    const hasEsc = /escHtml\(who\)/.test(tm);
    const hasRawWho = /item\.innerHTML =.*\+ who \+/.test(tm);
    if(hasEsc || !hasRawWho) throw new Error("bug not reproduced hasEsc="+hasEsc+" hasRawWho="+hasRawWho);
    return "chat-threadmap.js renderNavList does item.innerHTML = ... + who + ... without escHtml ï¿½ model name XSS";
  }
});

scenarios.push({
  id: 84,
  name: "ApiLogsViewer esc() does not escape single quote ï¿½ title attribute break",
  mode: null,
  noApp: true,
  async body() {
    const html=require("node:fs").readFileSync(require("node:path").join(require("../launch").REPO_ROOT,"webui","api-logs.html"),"utf8");
    const escBody = html.slice(html.indexOf("function esc(s)"), html.indexOf("function esc(s)")+500);
    const missingSingle = /\[&<>"]/.test(escBody) && escBody.indexOf("&#39;") < 0;
    if(!missingSingle) throw new Error("bug not reproduced");
    return "webui/api-logs.html esc() missing single quote ï¿½ title attribute breaks on '";
  }
});

scenarios.push({
  id: 86,
  name: "FIM fallback renderMarkdown XSS ï¿½ md.render with html:true for non-chat content",
  mode: null,
  noApp: true,
  async body() {
    const cc=require("node:fs").readFileSync(require("node:path").join(require("../launch").REPO_ROOT,"webui","js","chat","chat-core.js"),"utf8");
    const hasMdRender = /contentElement\.innerHTML = result/.test(cc) && /md\.render\(contentToRender\)/.test(cc);
    const hasHtmlTrue = /markdownit\(\{[^}]*html: true/.test(require("node:fs").readFileSync(require("node:path").join(require("../launch").REPO_ROOT,"webui","js","main.js"),"utf8"));
    if(!hasMdRender || !hasHtmlTrue) throw new Error("bug not reproduced");
    return "chat-core.js renderMarkdown does md.render(content) with html:true and innerHTML ï¿½ FIM fallback XSS same as #57";
  }
});

scenarios.push({
  id: 87,
  name: "UsageRepo lastMonth SQL uses UTC date('now') while dashboard labels use local ï¿½ off by timezone",
  mode: null,
  noApp: true,
  async body() {
    const ur=require("node:fs").readFileSync(require("node:path").join(require("../launch").REPO_ROOT,"chat","db","UsageRepo.ahk"),"utf8");
    const hasUTC = /date\('now', 'start of month'/.test(ur);
    const dash=require("node:fs").readFileSync(require("node:path").join(require("../launch").REPO_ROOT,"webui","js","usage-dashboard.js"),"utf8");
    const hasLocal = /getDateRangeLabels/.test(dash) && /new Date\(/.test(dash);
    if(!hasUTC || !hasLocal) throw new Error("bug not reproduced");
    return "UsageRepo _WhereDate lastMonth uses UTC date('now') while getDateRangeLabels uses local new Date() ï¿½ timezone mismatch";
  }
});

scenarios.push({
  id: 88,
  name: "UsageRepo month (last 30 days) SQL uses UTC while dashboard uses local ï¿½ timezone mismatch",
  mode: null,
  noApp: true,
  async body() {
    const ur=require("node:fs").readFileSync(require("node:path").join(require("../launch").REPO_ROOT,"chat","db","UsageRepo.ahk"),"utf8");
    const has30UTC = /date\('now', '-30 days'\)/.test(ur);
    const dash=require("node:fs").readFileSync(require("node:path").join(require("../launch").REPO_ROOT,"webui","js","usage-dashboard.js"),"utf8");
    const has30Local = /days = 30/.test(dash) && /new Date/.test(dash);
    if(!has30UTC || !has30Local) throw new Error("bug not reproduced");
    return "UsageRepo _WhereDate month uses UTC date('now','-30 days') while dashboard month uses local today minus 30 days";
  }
});

scenarios.push({
  id: 89,
  name: "CurlBuilder API key with double quote breaks cURL Authorization header",
  mode: null,
  noApp: true,
  async body() {
    const cb=require("node:fs").readFileSync(require("node:path").join(require("../launch").REPO_ROOT,"api","CurlBuilder.ahk"),"utf8");
    const hasBearer = /Authorization: Bearer.*providerInfo\.apiKey/.test(cb);
    const escapes = /Escape.*apiKey/.test(cb) || /StrReplace.*apiKey.*"/.test(cb);
    if(!hasBearer || escapes) throw new Error("bug not reproduced hasBearer="+hasBearer+" escapes="+escapes);
    return "CurlBuilder interpolates apiKey into Authorization header without escaping double quote";
  }
});

scenarios.push({
  id: 90,
  name: "SettingsService SaveFromWebView with empty data corrupts settings via string iteration",
  mode: null,
  noApp: true,
  async body() {
    const sm=require("node:fs").readFileSync(require("node:path").join(require("../launch").REPO_ROOT,"app","settings","SettingsMerge.ahk"),"utf8");
    const hasOverrideLoop = /for k, v in incoming/.test(sm);
    const checksIsMap = /if IsObject\(incoming\)/.test(sm);
    if(!hasOverrideLoop || checksIsMap) throw new Error("bug not reproduced");
    return "SettingsMerge.Override iterates over incoming without IsObject check ï¿½ empty string would iterate chars";
  }
});

scenarios.push({
  id: 91,
  name: "InputWindow validateInputAndHide treats \"0\" as empty ï¿½ !value falsy",
  mode: null,
  noApp: true,
  async body() {
    const iw=require("node:fs").readFileSync(require("node:path").join(require("../launch").REPO_ROOT,"app","InputWindow.ahk"),"utf8");
    const hasFalsy = /if !this\.EditControl\.Value/.test(iw);
    if(!hasFalsy) throw new Error("bug not reproduced");
    return "InputWindow.validateInputAndHide does if !this.EditControl.Value ï¿½ \"0\" is falsy";
  }
});

scenarios.push({
  id: 92,
  name: "Models save ensureFullId ignores provider dropdown change when id already contains slash",
  mode: null,
  noApp: true,
  async body() {
    const m=require("node:fs").readFileSync(require("node:path").join(require("../launch").REPO_ROOT,"webui","js","settings","sections","models.js"),"utf8");
    const hasEnsure = /function ensureFullId\(id, provider\)/.test(m) && /if \(id\.indexOf\('\/'\) >= 0\) return id/.test(m);
    if(!hasEnsure) throw new Error("bug not reproduced");
    return "models.js ensureFullId returns id as-is when it contains '/', so changing provider dropdown does not update fullId";
  }
});

scenarios.push({
  id: 93,
  name: "SettingsDefaults GetDefaults shallow copies Map values ï¿½ mutating snapshot corrupts pristine defaults",
  mode: null,
  noApp: true,
  async body() {
    const sd=require("node:fs").readFileSync(require("node:path").join(require("../launch").REPO_ROOT,"app","settings","SettingsDefaults.ahk"),"utf8");
    const hasShallow = /snapshot\[k\] := v/.test(sd);
    const doesDeep = /snapshot\[k\] := .*Clone/.test(sd);
    if(!hasShallow || doesDeep) throw new Error("bug not reproduced hasShallow="+hasShallow+" doesDeep="+doesDeep);
    return "SettingsDefaults.GetDefaults shallow copies _initialDefaults values ï¿½ nested Maps share reference";
  }
});

scenarios.push({
  id: 94,
  name: "SettingsDefaults _DefaultsAssistants generates new UUID each call ï¿½ defaults not stable",
  mode: null,
  noApp: true,
  async body() {
    const sd=require("node:fs").readFileSync(require("node:path").join(require("../launch").REPO_ROOT,"app","settings","SettingsDefaults.ahk"),"utf8");
    const hasUUID = /SettingsPersistence\._UUID\(\)/.test(sd) && /_DefaultsAssistants/.test(sd);
    if(!hasUUID) throw new Error("bug not reproduced");
    return "SettingsDefaults._DefaultsAssistants calls SettingsPersistence._UUID() for each assistant id on every GetDefaults ï¿½ defaults have non-deterministic ids";
  }
});


scenarios.push({
  id: 95,
  name: "Usage dashboard model heading XSS — model id not escaped in section header",
  mode: null,
  noApp: true,
  async body() {
    const fs=require("node:fs");
    const path=require("node:path");
    const launcher=require("../launch");
    const dash=fs.readFileSync(path.join(launcher.REPO_ROOT,"webui","js","usage-dashboard.js"),"utf8");
    const hasRawInner = /div\.innerHTML = .<h6>.+model/.test(dash);
    const sec = dash.slice(dash.indexOf("model-section"), dash.indexOf("model-section")+3000);
    const hasEsc = /escHtml\(model\)/.test(sec);
    if(!hasRawInner || hasEsc) throw new Error("bug not reproduced hasRawInner="+hasRawInner+" hasEsc="+hasEsc);
    return "usage-dashboard.js div.innerHTML = '<h6>'+model without escHtml — XSS";
  }
});

scenarios.push({
  id: 96,
  name: "AttachmentRepo SQL injection via unescaped msgId",
  mode: null,
  noApp: true,
  async body() {
    const fs=require("node:fs");
    const path=require("node:path");
    const launcher=require("../launch");
    const ar=fs.readFileSync(path.join(launcher.REPO_ROOT,"chat","db","AttachmentRepo.ahk"),"utf8");
    const unsafe = /WHERE message_id='" msgId "'/.test(ar);
    const hasEsc = /SQLite\.Escape\(msgId\)/.test(ar.slice(ar.indexOf("static Insert"), ar.indexOf("static Insert")+800));
    if(!unsafe || hasEsc) throw new Error("bug not reproduced unsafe="+unsafe);
    return "AttachmentRepo Insert/GetByMessage interpolates msgId without Escape";
  }
});

scenarios.push({
  id: 97,
  name: "SettingsPersistence.Save non-atomic FileDelete then FileAppend",
  mode: null,
  noApp: true,
  async body() {
    const fs=require("node:fs");
    const path=require("node:path");
    const launcher=require("../launch");
    const sp=fs.readFileSync(path.join(launcher.REPO_ROOT,"app","settings","SettingsPersistence.ahk"),"utf8");
    const hasPattern = /FileDelete\(path\)/.test(sp) && /FileAppend\(jsonStr, path/.test(sp);
    if(!hasPattern) throw new Error("bug not reproduced");
    return "SettingsPersistence.Save FileDelete then FileAppend non-atomic";
  }
});

scenarios.push({
  id: 98,
  name: "StreamHandler cancel leaks state — no cleanup after wasCancelled",
  mode: null,
  noApp: true,
  async body() {
    const fs=require("node:fs");
    const path=require("node:path");
    const launcher=require("../launch");
    const sh=fs.readFileSync(path.join(launcher.REPO_ROOT,"chat","streaming","StreamHandler.ahk"),"utf8");
    const hasBug = /if wasCancelled\s*\{\s*\n?\s*_handleStreamCancelled\(\)\s*\n\s*return/.test(sh);
    const hasCleanupBetween = /if wasCancelled[\s\S]*?_cleanupStreamState[\s\S]*?return/.test(sh.slice(sh.indexOf("if wasCancelled"), sh.indexOf("if wasCancelled")+500));
    // More precise: block between wasCancelled and return should not contain cleanup
    const idx = sh.indexOf("if wasCancelled");
    const block = sh.slice(idx, sh.indexOf("return", idx)+20);
    const hasCleanupInBlock = /_cleanupStreamState/.test(block);
    if(!hasBug || hasCleanupInBlock) throw new Error("bug not reproduced hasBug="+hasBug+" hasCleanupInBlock="+hasCleanupInBlock);
    return "StreamHandler _finalizeStreaming wasCancelled branch calls _handleStreamCancelled then return without _cleanupStreamState — leaks _stream* keys";
  }
});
scenarios.push({
  id: 99,
  name: "MessageRepo.Insert parent_id/sibling_group SQL injection via unescaped interpolation",
  mode: null,
  noApp: true,
  async body() {
    const fs=require("node:fs");
    const path=require("node:path");
    const launcher=require("../launch");
    const mr=fs.readFileSync(path.join(launcher.REPO_ROOT,"chat","db","MessageRepo.ahk"),"utf8");
    const parentRaw = /safeParent := msgObj\.HasProp\("parent_id"\) && msgObj\.parent_id \? "'" msgObj\.parent_id "'"/.test(mr);
    const siblingRaw = /safeSiblingGroup := msgObj\.HasProp\("sibling_group"\) && msgObj\.sibling_group \? "'" msgObj\.sibling_group "'"/.test(mr);
    if (!parentRaw || !siblingRaw) throw new Error("bug not reproduced parentRaw="+parentRaw+" siblingRaw="+siblingRaw);
    const hasEsc = /SQLite\.Escape\(msgObj\.parent_id\)/.test(mr) || /SQLite\.Escape\(msgObj\.sibling_group\)/.test(mr);
    if (hasEsc) throw new Error("already fixed");
    return "MessageRepo.Insert builds safeParent/safeSiblingGroup without SQLite.Escape";
  }
});

scenarios.push({
  id: 100,
  name: "LLMRequestBuilder._FixStreamBoolean naive StrReplace corrupts user content",
  mode: null,
  noApp: true,
  async body() {
    const fs=require("node:fs");
    const path=require("node:path");
    const launcher=require("../launch");
    const lb=fs.readFileSync(path.join(launcher.REPO_ROOT,"api","LLMRequestBuilder.ahk"),"utf8");
    const hasFix = /static _FixStreamBoolean\(jsonStr\)/.test(lb) && /StrReplace\(jsonStr,.*stream/.test(lb);
    if (!hasFix) throw new Error("bug not reproduced");
    return "LLMRequestBuilder._FixStreamBoolean does global StrReplace stream 1->true";
  }
});

scenarios.push({
  id: 101,
  name: "SettingsApply._ApplyCommands _SetIfTruthy drops false for stream/isFIM",
  mode: null,
  noApp: true,
  async body() {
    const fs=require("node:fs");
    const path=require("node:path");
    const launcher=require("../launch");
    const sa=fs.readFileSync(path.join(launcher.REPO_ROOT,"app","settings","SettingsApply.ahk"),"utf8");
    const hasHelper = /static _SetIfTruthy\(cmd, c, key\)/.test(sa) && /if c\.Has\(key\) && c\[key\]/.test(sa);
    const callsTruthy = /_SetIfTruthy\(cmd, c, "stream"\)/.test(sa);
    if (!hasHelper || !callsTruthy) throw new Error("bug not reproduced");
    return "SettingsApply uses _SetIfTruthy for stream/isFIM — false dropped";
  }
});

scenarios.push({
  id: 102,
  name: "UsageRepo provider LIKE uses SQLite.Escape but not wildcard-escape %_",
  mode: null,
  noApp: true,
  async body() {
    const fs=require("node:fs");
    const path=require("node:path");
    const launcher=require("../launch");
    const ur=fs.readFileSync(path.join(launcher.REPO_ROOT,"chat","db","UsageRepo.ahk"),"utf8");
    const hasLike = /providerChatClause := providerFilter \? "AND model LIKE/.test(ur);
    if (!hasLike) throw new Error("bug not reproduced");
    const escapes = /StrReplace.*providerFilter.*%/.test(ur);
    if (escapes) throw new Error("already escapes");
    return "UsageRepo provider LIKE not escaping % _";
  }
});

scenarios.push({
  id: 103,
  name: "TreeRepo.GetThreadStats pricingUnit picks first message model, not active model",
  mode: null,
  noApp: true,
  async body() {
    const fs=require("node:fs");
    const path=require("node:path");
    const launcher=require("../launch");
    const tr=fs.readFileSync(path.join(launcher.REPO_ROOT,"chat","db","TreeRepo.ahk"),"utf8");
    const hasFirst = /SELECT model FROM messages WHERE thread_id='" threadId "' AND model IS NOT NULL.*LIMIT 1/.test(tr);
    if (!hasFirst) throw new Error("bug not reproduced");
    return "TreeRepo.GetThreadStats pricingUnit LIMIT 1 first model";
  }
});





scenarios.push({
  id: 107,
  name: "TreeRepo._RecomputeActivePath recomputes active_path as prefix sum, losing prompt_tokens for assistants",
  mode: null,
  noApp: true,
  async body() {
    const fs=require("node:fs");
    const path=require("node:path");
    const launcher=require("../launch");
    const tr=fs.readFileSync(path.join(launcher.REPO_ROOT,"chat","db","TreeRepo.ahk"),"utf8");
    const defIdx=tr.indexOf("static _RecomputeActivePath");
    const body=tr.slice(defIdx, defIdx+600);
    const hasPrefix = body.includes('prev += msg.HasProp("token_count")');
    const hasPrompt = body.includes("prompt_tokens");
    if(!hasPrefix) throw new Error("bug not reproduced: no prev+= token_count");
    if(hasPrompt) throw new Error("bug not reproduced: recompute handles prompt_tokens");
    return "_RecomputeActivePath does prev+=token_count only — assistant prompt_tokens lost after delete/edit";
  }
});

scenarios.push({
  id: 108,
  name: "main.js IPC fallback calls arbitrary window[target] without allowlist — XSS can invoke any global",
  mode: null,
  noApp: true,
  async body() {
    const fs=require("node:fs");
    const path=require("node:path");
    const launcher=require("../launch");
    const main=fs.readFileSync(path.join(launcher.REPO_ROOT,"webui","js","main.js"),"utf8");
    const hasFallback = /if \(typeof window\[target\] === .function.\)/.test(main) && /window\[target\]\(/.test(main);
    if(!hasFallback) throw new Error("bug not reproduced: no window[target] fallback");
    return "main.js default: case calls window[target](...data) for any undeclared target — arbitrary global invocation";
  }
});

scenarios.push({
  id: 109,
  name: "Sidebar folderId and 15+ ChatDB call sites interpolate raw ids without SQLite.Escape",
  mode: null,
  noApp: true,
  async body() {
    const fs=require("node:fs");
    const path=require("node:path");
    const launcher=require("../launch");
    const sidebar=fs.readFileSync(path.join(launcher.REPO_ROOT,"chat/callbacks/Sidebar.ahk"),"utf8");
    const hasFolderRaw = sidebar.includes("DELETE FROM chat_folders WHERE id=''\" params[\"folderId\"] \"''\"") || sidebar.includes("params[\"folderId\"]") && sidebar.includes("DELETE FROM chat_folders");
    // Simpler: check raw interpolation without SQLite.Escape
    const hasUnescaped = /WHERE id=.\" threadId/.test(sidebar) || /WHERE id=.\" params\["folderId"\]/.test(sidebar);
    const hasEscaped = /SQLite\.Escape\(params\["folderId"\]\)/.test(sidebar);
    if(!sidebar.includes("params[\"folderId\"]") || hasEscaped) throw new Error("bug not reproduced: folderId escaped or not found");
    // Also check MessageRepo still has 15+ unescaped
    const mr=fs.readFileSync(path.join(launcher.REPO_ROOT,"chat/db/MessageRepo.ahk"),"utf8");
    const unescapedCount = (mr.match(/WHERE id=.\" msgId/g) || []).length;
    if(unescapedCount < 3) throw new Error("bug not reproduced: unescaped msgId count low "+unescapedCount);
    return "Sidebar folderId raw + MessageRepo "+unescapedCount+" raw msgId WHERE id=''...'' — same class as #80/#99";
  }
});


scenarios.push({
  id: 110,
  name: "Chat streaming temp files with API keys not deleted after success — credential leak in %TEMP%",
  mode: null,
  noApp: true,
  async body() {
    const fs=require("node:fs");
    const path=require("node:path");
    const launcher=require("../launch");
    const sc=fs.readFileSync(path.join(launcher.REPO_ROOT,"chat","streaming","StreamCompletion.ahk"),"utf8");
    const sh=fs.readFileSync(path.join(launcher.REPO_ROOT,"chat","streaming","StreamHandler.ahk"),"utf8");
    const hasDeleteOnSuccess = /_handleStreamComplete[\s\S]{0,800}deleteTempFiles/.test(sc);
    const hasDeleteOnCancel = /_handleStreamCancelled[\s\S]{0,400}deleteTempFiles/.test(fs.readFileSync(path.join(launcher.REPO_ROOT,"chat","streaming","StreamError.ahk"),"utf8"));
    const buildsCurlWithKey = /providerInfo\.apiKey/.test(fs.readFileSync(path.join(launcher.REPO_ROOT,"api","CurlBuilder.ahk"),"utf8"));
    if(hasDeleteOnSuccess) throw new Error("bug not reproduced: success deletes temp files");
    if(!hasDeleteOnCancel) throw new Error("cancel should delete but missing");
    if(!buildsCurlWithKey) throw new Error("CurlBuilder not building with apiKey");
    return "StreamCompletion._handleStreamComplete does not call deleteTempFiles — cURL files with Bearer apiKey remain in TEMP after success";
  }
});

scenarios.push({
  id: 111,
  name: "ApiLogger LogRequest non-atomic overwrite — crash mid-write corrupts log file",
  mode: null,
  noApp: true,
  async body() {
    const fs=require("node:fs");
    const path=require("node:path");
    const launcher=require("../launch");
    const al=fs.readFileSync(path.join(launcher.REPO_ROOT,"api","ApiLogger.ahk"),"utf8");
    const hasOverwrite = /FileOpen\(this\.logFilePath, "w"/.test(al) && /Write\(jsongo\.Stringify\(logs\)\)/.test(al);
    const hasAtomic = /FileMove|FileAppend.*tmp|atomic/.test(al);
    if(!hasOverwrite) throw new Error("bug not reproduced: no overwrite");
    if(hasAtomic) throw new Error("already atomic");
    return "ApiLogger.LogRequest does FileOpen w + Write without temp rename — crash corrupts log";
  }
});

scenarios.push({
  id: 112,
  name: "CurlBuilder does not validate empty endpoint — malformed cURL with no URL",
  mode: null,
  noApp: true,
  async body() {
    const fs=require("node:fs");
    const path=require("node:path");
    const launcher=require("../launch");
    const cb=fs.readFileSync(path.join(launcher.REPO_ROOT,"api","CurlBuilder.ahk"),"utf8");
    const hasEndpointCheck = /if !providerInfo\.endpoint/.test(cb) || /if providerInfo\.endpoint = ""/.test(cb);
    const buildsWithEndpoint = /providerInfo\.endpoint/.test(cb);
    if(hasEndpointCheck) throw new Error("already validates endpoint");
    if(!buildsWithEndpoint) throw new Error("no endpoint usage");
    return "CurlBuilder.Build concatenates providerInfo.endpoint without empty check — empty endpoint yields POST with no URL";
  }
});

module.exports = scenarios;




