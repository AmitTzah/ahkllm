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
  name: "Thread pricing unit falls back to 10% when cachedInput is empty string",
  regression: true, // FIXED bug kept as a regression check (empty cachedInput must fall back to 10% of input)
  mode: null,
  noApp: true,
  async body() {
    const fs = require("node:fs");
    const path = require("node:path");
    const launcher = require("../launch");
    const tr = fs.readFileSync(path.join(launcher.REPO_ROOT, "chat", "db", "TreeRepo.ahk"), "utf8");
    // FIXED (bug #63): a stored "" is treated as missing.
    const emptySafe = /cachedInput: pricing\.HasOwnProp\("cachedInput"\) && pricing\.cachedInput != ""/.test(tr);
    if (!emptySafe) throw new Error("cachedInput empty fallback not fixed (bug #63): emptySafe=" + emptySafe);
    return "TreeRepo GetThreadStats pricingUnit treats cachedInput=\"\" as missing and falls back to 10% of input";
  }
});



scenarios.push({
  id: 64,
  name: "Context Used includes thinking tokens (header reports full context)",
  regression: true, // FIXED bug kept as a regression check (active_path_tokens must include thinking)
  mode: null,
  noApp: true,
  async body() {
    const sc=fs.readFileSync(require("path").join(require("../launch").REPO_ROOT,"chat","streaming","StreamCompletion.ahk"),"utf8");
    // token_count stays visible-only (that is the message body output).
    const hasVisibleOnly = /token_count: Max\(0, completionTokens - thinkingTokens\)/.test(sc);
    const mr2=fs.readFileSync(require("path").join(require("../launch").REPO_ROOT,"chat","db","MessageRepo.ahk"),"utf8");
    // FIXED (bug #64): active_path_tokens = prompt + visible + thinking.
    const activeIncludesThinking = /activePathTokens := msgObj\.prompt_tokens \+ tc \+ tht/.test(mr2);
    const tr=fs.readFileSync(require("path").join(require("../launch").REPO_ROOT,"chat","db","TreeRepo.ahk"),"utf8");
    // _RecomputeActivePath adds thinking to the prefix sums too.
    const recomputeIncludesThinking = /prev \+= msg\.HasProp\("thinking_tokens"\) \? msg\.thinking_tokens : 0/.test(tr);
    if(!hasVisibleOnly || !activeIncludesThinking || !recomputeIncludesThinking) throw new Error("bug #64 not fixed: visibleOnly=" + hasVisibleOnly + " activeIncludesThinking=" + activeIncludesThinking + " recomputeIncludesThinking=" + recomputeIncludesThinking);
    return "MessageRepo active_path_tokens includes thinking (prompt + visible + thinking) and _RecomputeActivePath adds thinking to prefix sums, so the header Context Used counts reasoning tokens";
  }
});

scenarios.push({
  id: 65,
  name: "Hard-delete recomputes cumulative token/cost counters",
  regression: true, // FIXED bug kept as a regression check (hard delete must decrement the header totals)
  mode: null,
  noApp: true,
  async body() {
    const fs2=require("node:fs");
    const path2=require("node:path");
    const launcher2=require("../launch");
    const mr=fs2.readFileSync(path2.join(launcher2.REPO_ROOT,"chat","db","MessageRepo.ahk"),"utf8");
    const hd=mr.slice(mr.indexOf("static HardDelete"), mr.indexOf("static HardDelete")+3000);
    // FIXED (bug #65): HardDelete recomputes the cumulative counters.
    const recomputes = hd.includes("_RecomputeCumulativeCounters(");
    if(!recomputes) throw new Error("bug #65 not fixed: HardDelete does not recompute cumulative counters");
    return "HardDelete recomputes cumulative_* counters (via _RecomputeCumulativeCounters) so the header totals drop with the deleted message";
  }
});

scenarios.push({
  id: 66,
  name: "Header tooltip says Cumulative (typo fixed)",
  regression: true, // FIXED bug kept as a regression check (tooltip must not be misspelled)
  mode: null,
  noApp: true,
  async body() {
    const fs3=require("node:fs");
    const path3=require("node:path");
    const launcher3=require("../launch");
    const fmt=fs3.readFileSync(path3.join(launcher3.REPO_ROOT,"webui","js","chat","chat-format.js"),"utf8");
    // FIXED (bug #66): the tooltip reads "Cumulative".
    if(/Culminative/.test(fmt)) throw new Error("bug #66 not fixed: Culminative still present");
    if(!/Cumulative Input\/output token usage/.test(fmt)) throw new Error("bug #66 not fixed: corrected label missing");
    return "chat-format.js tooltip reads 'Cumulative Input/output token usage across all conversation branches'";
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
  name: "ProviderResolver legacy prefix match is prefix-only",
  regression: true, // FIXED bug kept as a regression check (substring matches must not resolve to the wrong provider)
  mode: null,
  noApp: true,
  async body() {
    const pr=require("node:fs").readFileSync(require("node:path").join(require("../launch").REPO_ROOT,"api","ProviderResolver.ahk"),"utf8");
    // FIXED (bug #68): legacy short ids match by prefix only.
    const hasPrefixCheck = /SubStr\(modelId, 1, StrLen\(prefix\)\) = prefix/.test(pr);
    const hasSubstring = /if InStr\(modelId, prefix\)/.test(pr);
    if(!hasPrefixCheck || hasSubstring) throw new Error("bug #68 not fixed: hasPrefixCheck=" + hasPrefixCheck + " hasSubstring=" + hasSubstring);
    return "ProviderResolver.Resolve matches legacy short ids by prefix only, so mygpt-custom no longer resolves to the gpt provider";
  }
});

scenarios.push({
  id: 69,
  name: "Search LIKE escapes % _ \\ wildcards (literal search)",
  regression: true, // FIXED bug kept as a regression check (LIKE must match user input literally)
  mode: null,
  noApp: true,
  async body() {
    const sr=require("node:fs").readFileSync(require("node:path").join(require("../launch").REPO_ROOT,"chat","db","SearchRepo.ahk"),"utf8");
    // FIXED (bug #69): _EscapeLike escapes \ % _ before building the LIKE.
    const escapesBackslash = /StrReplace\(value, "\\", "\\\\"\)/.test(sr);
    const escapesPercent = /StrReplace\(value, "%", "\\%"\)/.test(sr);
    const escapesUnderscore = /StrReplace\(value, "_", "\\_"\)/.test(sr);
    const usesEscaped = sr.includes("_EscapeLike(safeQuery)");
    if(!escapesBackslash || !escapesPercent || !escapesUnderscore || !usesEscaped)
      throw new Error("bug #69 not fixed: backslash=" + escapesBackslash + " percent=" + escapesPercent + " underscore=" + escapesUnderscore + " usesEscaped=" + usesEscaped);
    return "SearchRepo._EscapeLike escapes \\ % _ (used by _Like and _Titles), so searching for % matches only literal percent";
  }
});

scenarios.push({
  id: 70,
  name: "Search FTS5 quotes terms so special characters do not break MATCH",
  regression: true, // FIXED bug kept as a regression check (FTS5 must not choke on special chars)
  mode: null,
  noApp: true,
  async body() {
    const fs=require("node:fs");
    const path=require("node:path");
    const launcher=require("../launch");
    const sr=fs.readFileSync(path.join(launcher.REPO_ROOT,"chat","db","SearchRepo.ahk"),"utf8");
    const fts=sr.slice(sr.indexOf("static _FTS5"), sr.indexOf("static _FTS5")+2500);
    // FIXED (bug #70): terms are quoted for FTS5 MATCH.
    const quotesTerms = /_FTS5QuoteTerm\(trimmed\)/.test(fts);
    const buildsRaw = /ftsExpr \.= trimmed/.test(fts);
    if(!quotesTerms || buildsRaw) throw new Error("bug #70 not fixed: quotesTerms=" + quotesTerms + " buildsRaw=" + buildsRaw);
    return "SearchRepo._FTS5 quotes each term (_FTS5QuoteTerm), so C++ / quoted queries no longer break MATCH";
  }
});

scenarios.push({
  id: 71,
  name: "Clearing Thread Title Generation fields resets the globals",
  regression: true, // FIXED bug kept as a regression check (family #61: cleared fields must reset globals)
  mode: null,
  noApp: true,
  async body() {
    const sa=require("node:fs").readFileSync(require("node:path").join(require("../launch").REPO_ROOT,"app","settings","SettingsApply.ahk"),"utf8");
    // FIXED (bug #71): _ApplyThreadTitles assigns even when empty.
    const assignsModel = /if tt\.Has\("model"\)\s*\n\s*titleGenModel := tt\["model"\]/.test(sa);
    const assignsPrompt = /if tt\.Has\("prompt"\)\s*\n\s*titleGenSystemPrompt := tt\["prompt"\]/.test(sa);
    const skipsModel = /tt\.Has\("model"\) && tt\["model"\] != ""/.test(sa);
    const skipsPrompt = /tt\.Has\("prompt"\) && tt\["prompt"\] != ""/.test(sa);
    if(!assignsModel || !assignsPrompt || skipsModel || skipsPrompt)
      throw new Error("bug #71 not fixed: assignsModel=" + assignsModel + " assignsPrompt=" + assignsPrompt + " skipsModel=" + skipsModel + " skipsPrompt=" + skipsPrompt);
    return "SettingsApply._ApplyThreadTitles assigns cleared values, so title-gen fields reset instead of keeping stale globals";
  }
});

scenarios.push({
  id: 72,
  name: "SystemMessageResolver treats UNC paths as absolute",
  regression: true, // FIXED bug kept as a regression check (UNC paths must be read as-is)
  mode: null,
  noApp: true,
  async body() {
    const sr=require("node:fs").readFileSync(require("node:path").join(require("../launch").REPO_ROOT,"shared","SystemMessageResolver.ahk"),"utf8");
    const checksColon = /if !InStr\(filePath, ":"\)/.test(sr);
    const handlesUnc = /SubStr\(filePath, 1, 1\) = "\\"/.test(sr);
    if(!checksColon || !handlesUnc) throw new Error("bug #72 not fixed: checksColon=" + checksColon + " handlesUnc=" + handlesUnc);
    return "SystemMessageResolver.Resolve treats \\\\server\\share (UNC) and rooted paths as absolute and reads them as-is";
  }
});

scenarios.push({
  id: 73,
  name: "GoogleChatCompletions disabled config includes include_thoughts:false for 2.x",
  regression: true, // FIXED bug kept as a regression check (disabled config must be symmetric with enabled)
  mode: null,
  noApp: true,
  async body() {
    const gc=require("node:fs").readFileSync(require("node:path").join(require("../launch").REPO_ROOT,"api","handlers","GoogleChatCompletions.ahk"),"utf8");
    const disabledStart = gc.indexOf("static DisabledConfig");
    const disabledEnd = gc.indexOf("static ThinkingConfig", disabledStart);
    const disabled = gc.slice(disabledStart, disabledEnd);
    const hasBudget0 = /thinking_budget: 0/.test(disabled);
    const hasIncludeFalse = /include_thoughts: false/.test(disabled);
    if(!hasBudget0 || !hasIncludeFalse) throw new Error("bug #73 not fixed: hasBudget0=" + hasBudget0 + " hasIncludeFalse=" + hasIncludeFalse);
    return "GoogleChatCompletions.DisabledConfig returns {include_thoughts:false, thinking_budget:0} for Gemini 2.x";
  }
});

scenarios.push({
  id: 74,
  name: "SettingsApply clears providerMap when all prefixes are explicitly cleared",
  regression: true, // FIXED bug kept as a regression check (empty prefix sets must clear the map)
  mode: null,
  noApp: true,
  async body() {
    const sa=require("node:fs").readFileSync(require("node:path").join(require("../launch").REPO_ROOT,"app","settings","SettingsApply.ahk"),"utf8");
    // FIXED (bug #74): explicit prefixes (even empty) rebuild providerMap.
    const hasExplicitCheck = /hasExplicitPrefixes/.test(sa);
    const stillGuarded = /if newProviderMap\.Count > 0/.test(sa);
    if(!hasExplicitCheck || stillGuarded) throw new Error("bug #74 not fixed: hasExplicitCheck=" + hasExplicitCheck + " stillGuarded=" + stillGuarded);
    return "SettingsApply._ApplyProviders assigns providerMap whenever prefixes are explicitly defined (an empty set clears it)";
  }
});

scenarios.push({
  id: 75,
  name: "GoogleChatCompletions budget table matches the Gemini family",
  regression: true, // FIXED bug kept as a regression check (budget table must not match arbitrary substrings)
  mode: null,
  noApp: true,
  async body() {
    const gc=require("node:fs").readFileSync(require("node:path").join(require("../launch").REPO_ROOT,"api","handlers","GoogleChatCompletions.ahk"),"utf8");
    const hasSubstring = /if InStr\(modelId, "2\.5-pro"\)/.test(gc);
    const hasFamily = /if InStr\(modelId, "gemini-2\.5-pro"\)/.test(gc);
    if(hasSubstring || !hasFamily) throw new Error("bug #75 not fixed: hasSubstring=" + hasSubstring + " hasFamily=" + hasFamily);
    return "GoogleChatCompletions._BudgetTable matches the gemini-2.5-pro family (not any substring), so my2.5-pro falls back to generic";
  }
});

scenarios.push({
  id: 76,
  name: "initChatMode always updates activeThreadId on thread switch",
  regression: true, // FIXED bug kept as a regression check (loaded thread must become active even when one was already set)
  mode: null,
  noApp: true,
  async body() {
    const cc=require("node:fs").readFileSync(require("node:path").join(require("../launch").REPO_ROOT,"webui","js","chat","chat-core.js"),"utf8");
    const hasGuard = /if \(data && data\.threadId && !activeThreadId\)/.test(cc);
    const assigns = /if \(data && data\.threadId\)\s*\{\s*activeThreadId = data\.threadId/.test(cc);
    if(hasGuard || !assigns) throw new Error("bug #76 not fixed: hasGuard=" + hasGuard + " assigns=" + assigns);
    return "initChatMode always updates activeThreadId from the loaded thread, so thread switches/search/sends target the right thread";
  }
});

scenarios.push({
  id: 77,
  name: "onChatSend empty input is a no-op (no accidental retry)",
  regression: true, // FIXED bug kept as a regression check (empty Send must not re-fire the last message)
  mode: null,
  noApp: true,
  async body() {
    const ci=require("node:fs").readFileSync(require("node:path").join(require("../launch").REPO_ROOT,"webui","js","chat","chat-input.js"),"utf8");
    // FIXED (bug #77): empty Send returns early.
    const hasNoOp = ci.includes("Bug #77");
    const stillRetries = ci.includes("retryLastAssistantMessage(lastMsg.id)") || ci.includes("Ipc.postToHost('retry')");
    if(!hasNoOp || stillRetries) throw new Error("bug #77 not fixed: hasNoOp=" + hasNoOp + " stillRetries=" + stillRetries);
    return "chat-input.js onChatSend returns early for empty input, so an empty Send no longer retries the last message";
  }
});

scenarios.push({
  id: 78,
  name: "Right-rail temperature 0 shows 0.0 (falsy check fixed)",
  regression: true, // FIXED bug kept as a regression check (0 must be a valid displayed temperature)
  mode: null,
  noApp: true,
  async body() {
    const cfg=require("node:fs").readFileSync(require("node:path").join(require("../launch").REPO_ROOT,"webui","js","chat","model-picker","model-picker-config.js"),"utf8");
    // FIXED (bug #78): hasTemp uses explicit empty checks so 0 is valid.
    const hasFalsy = /var hasTemp = settings\.temperature &&/.test(cfg);
    const handlesZero = /settings\.temperature !== '' && settings\.temperature !== undefined/.test(cfg);
    if(hasFalsy || !handlesZero) throw new Error("bug #78 not fixed: hasFalsy=" + hasFalsy + " handlesZero=" + handlesZero);
    return "model-picker-config.js hasTemp uses explicit empty checks, so a 0 override shows 0.0 instead of Default";
  }
});

scenarios.push({
  id: 79,
  name: "SettingsPersistence.Load strips a UTF-8 BOM before parsing",
  regression: true, // FIXED bug kept as a regression check (BOM'd settings files must load)
  mode: null,
  noApp: true,
  async body() {
    const sp=require("node:fs").readFileSync(require("node:path").join(require("../launch").REPO_ROOT,"app","settings","SettingsPersistence.ahk"),"utf8");
    const loadsRaw = /raw := FileRead\(path, "UTF-8"\)/.test(sp);
    const stripsBOM = /Chr\(0xFEFF\)/.test(sp) || /FEFF/.test(sp);
    const parsesDirect = /parsed := jsongo\.Parse\(raw\)/.test(sp);
    if(!loadsRaw || !stripsBOM || !parsesDirect) throw new Error("bug #79 not fixed: loadsRaw=" + loadsRaw + " stripsBOM=" + stripsBOM + " parsesDirect=" + parsesDirect);
    return "SettingsPersistence.Load strips a leading UTF-8 BOM (Chr(0xFEFF)) before jsongo.Parse, so BOM'd settings files load normally";
  }
});

scenarios.push({
  id: 80,
  name: "ThreadRepo escapes threadId in mutators (SQL injection fixed)",
  regression: true, // FIXED bug kept as a regression check (security: crafted ids must not inject SQL)
  mode: null,
  noApp: true,
  async body() {
    const tr=require("node:fs").readFileSync(require("node:path").join(require("../launch").REPO_ROOT,"chat","db","ThreadRepo.ahk"),"utf8");
    const soft = tr.slice(tr.indexOf("static SoftDelete"), tr.indexOf("static SoftDelete")+800);
    const hasEscapeSoft = /SQLite\.Escape\(threadId\)/.test(soft);
    const hasDirectSoft = /WHERE id='" threadId "'/.test(soft);
    const upd = tr.slice(tr.indexOf("static Update(threadId"), tr.indexOf("static Update(threadId")+800);
    const hasEscapeUpd = /SQLite\.Escape\(threadId\)/.test(upd);
    if(!hasEscapeSoft || hasDirectSoft) throw new Error("bug #80 not fixed: soft escapes=" + hasEscapeSoft + " direct=" + hasDirectSoft);
    if(!hasEscapeUpd) throw new Error("bug #80 not fixed: update escapes=" + hasEscapeUpd);
    return "ThreadRepo SoftDelete/Restore/Delete/Update escape threadId (SQLite.Escape), so crafted ids cannot inject SQL";
  }
});

scenarios.push({
  id: 81,
  name: "Branch _setupSiblingGroup escapes msg.id (SQL injection fixed)",
  regression: true, // FIXED bug kept as a regression check (security: crafted message ids must not inject SQL)
  mode: null,
  noApp: true,
  async body() {
    const br=require("node:fs").readFileSync(require("node:path").join(require("../launch").REPO_ROOT,"chat","callbacks","Branch.ahk"),"utf8");
    const snippet = br.slice(br.indexOf("_setupSiblingGroup"), br.indexOf("_setupSiblingGroup")+800);
    const hasEscape = /SQLite\.Escape\(msg\.id\)/.test(snippet);
    const hasDirect = /WHERE id='" msg\.id "'/.test(snippet);
    if(!hasEscape || hasDirect) throw new Error("bug #81 not fixed: hasEscape=" + hasEscape + " hasDirect=" + hasDirect);
    return "Branch._setupSiblingGroup escapes msg.id (SQLite.Escape), so crafted message ids cannot inject SQL";
  }
});

scenarios.push({
  id: 82,
  name: "Usage dashboard filter dropdowns escape provider/model names (XSS fixed)",
  regression: true, // FIXED bug kept as a regression check (security: option values/labels must be escaped)
  mode: null,
  noApp: true,
  async body() {
    const dash=require("node:fs").readFileSync(require("node:path").join(require("../launch").REPO_ROOT,"webui","js","usage-dashboard.js"),"utf8");
    const hasEsc = /escHtml\(p\)/.test(dash) && /escHtml\(m\)/.test(dash);
    const hasRaw = /provSel\.innerHTML \+=.*'<option value="'\+p\+/.test(dash);
    if(!hasEsc || hasRaw) throw new Error("bug #82 not fixed: hasEsc=" + hasEsc + " hasRaw=" + hasRaw);
    return "usage-dashboard.js populateFilters escapes provider/model option values and labels (escHtml), so names render as inert text";
  }
});

scenarios.push({
  id: 83,
  name: "Threadmap who label escapes the model name (XSS fixed)",
  regression: true, // FIXED bug kept as a regression check (security: model names in the nav list must be escaped)
  mode: null,
  noApp: true,
  async body() {
    const tm=require("node:fs").readFileSync(require("node:path").join(require("../launch").REPO_ROOT,"webui","js","chat","chat-threadmap.js"),"utf8");
    const hasEsc = /escHtml\(who\)/.test(tm);
    const hasRawWho = /item\.innerHTML =.*\+ who \+/.test(tm);
    if(!hasEsc || hasRawWho) throw new Error("bug #83 not fixed: hasEsc=" + hasEsc + " hasRawWho=" + hasRawWho);
    return "chat-threadmap.js renderNavList escapes the who label (escHtml(who)), so model names render as inert text";
  }
});

scenarios.push({
  id: 84,
  name: "ApiLogsViewer esc() escapes single quotes (title attribute safe)",
  regression: true, // FIXED bug kept as a regression check (security: esc must handle ')
  mode: null,
  noApp: true,
  async body() {
    const html=require("node:fs").readFileSync(require("node:path").join(require("../launch").REPO_ROOT,"webui","api-logs.html"),"utf8");
    const escBody = html.slice(html.indexOf("function esc(s)"), html.indexOf("function esc(s)")+500);
    const escapesQuote = /&#39;/.test(escBody);
    const hasQuoteInRegex = /\[&<>"']/.test(escBody);
    if(!escapesQuote || !hasQuoteInRegex) throw new Error("bug #84 not fixed: escapesQuote=" + escapesQuote + " hasQuoteInRegex=" + hasQuoteInRegex);
    return "webui/api-logs.html esc() escapes single quotes (&#39;), so title attributes cannot be broken";
  }
});

scenarios.push({
  id: 86,
  name: "FIM fallback renderMarkdown uses the html:false markdown renderer (XSS fixed)",
  regression: true, // REFUTED as a duplicate of #57 (fixed in 05e2ccb); kept as a regression check for the FIM fallback path
  mode: null,
  noApp: true,
  async body() {
    const cc=require("node:fs").readFileSync(require("node:path").join(require("../launch").REPO_ROOT,"webui","js","chat","chat-core.js"),"utf8");
    const hasMdRender = /contentElement\.innerHTML = result/.test(cc) && /md\.render\(contentToRender\)/.test(cc);
    const main=require("node:fs").readFileSync(require("node:path").join(require("../launch").REPO_ROOT,"webui","js","main.js"),"utf8");
    const htmlSafe = /html: false/.test(main);
    const htmlTrue = /markdownit\(\{[^}]*html: true/.test(main);
    if(!hasMdRender || !htmlSafe || htmlTrue) throw new Error("bug #86/#57 not fixed: hasMdRender=" + hasMdRender + " htmlSafe=" + htmlSafe + " htmlTrue=" + htmlTrue);
    return "chat-core.js renderMarkdown renders via the html:false md instance (fixed by #57), so FIM fallback content is inert";
  }
});

scenarios.push({
  id: 87,
  name: "UsageRepo lastMonth filter uses local boundaries (matches local labels)",
  regression: true, // FIXED bug kept as a regression check (lastMonth must use local calendar dates)
  mode: null,
  noApp: true,
  async body() {
    const ur=require("node:fs").readFileSync(require("node:path").join(require("../launch").REPO_ROOT,"chat","db","UsageRepo.ahk"),"utf8");
    const urBlock = ur.slice(ur.indexOf("static _WhereDate"), ur.indexOf("static _WhereDate")+1400);
    const lastMonthUsesLocal = /dateColumn " >= '" lastMonthStart "' AND " dateColumn " < '" monthStart "'"/.test(urBlock);
    const queryPassesLocal = /lastMonthStart := FormatTime\(DateAdd\(A_Now, -1/.test(ur);
    if(!lastMonthUsesLocal || !queryPassesLocal) throw new Error("bug #87 not fixed: lastMonthUsesLocal=" + lastMonthUsesLocal + " queryPassesLocal=" + queryPassesLocal);
    return "UsageRepo lastMonth filter uses local month boundaries (FormatTime/DateAdd), matching the dashboard labels";
  }
});

scenarios.push({
  id: 88,
  name: "UsageRepo month (last 30 days) filter uses the local cutoff (matches dashboard)",
  regression: true, // FIXED with bug #87 (local monthCutoff) - kept as a regression check
  mode: null,
  noApp: true,
  async body() {
    const ur=require("node:fs").readFileSync(require("node:path").join(require("../launch").REPO_ROOT,"chat","db","UsageRepo.ahk"),"utf8");
    const monthBlock = ur.slice(ur.indexOf('if range = "month"'), ur.indexOf('if range = "month"')+220);
    const usesLocal = /monthCutoff \? "'" monthCutoff "'"/.test(monthBlock);
    const queryPassesLocal = /monthCutoff := FormatTime\(DateAdd\(A_Now, -29/.test(ur);
    if(!usesLocal || !queryPassesLocal) throw new Error("bug #88 not fixed: usesLocal=" + usesLocal + " queryPassesLocal=" + queryPassesLocal);
    return "UsageRepo month (last 30 days) filter uses the local cutoff (FormatTime/DateAdd), matching the dashboard labels";
  }
});

scenarios.push({
  id: 89,
  name: "CurlBuilder sanitizes the API key in the Authorization header (injection fixed)",
  regression: true, // FIXED bug kept as a regression check (security: crafted keys must not break/inject the curl command)
  mode: null,
  noApp: true,
  async body() {
    const cb=require("node:fs").readFileSync(require("node:path").join(require("../launch").REPO_ROOT,"api","CurlBuilder.ahk"),"utf8");
    const hasSanitize = /_SafeApiKey/.test(cb);
    const rawInterp = /Authorization: Bearer ' providerInfo\.apiKey '/.test(cb);
    if(!hasSanitize || rawInterp) throw new Error("bug #89 not fixed: hasSanitize=" + hasSanitize + " rawInterp=" + rawInterp);
    return "CurlBuilder sanitizes the API key (_SafeApiKey strips \\\" % & | < > ^) before embedding it in the Authorization header";
  }
});

scenarios.push({
  id: 90,
  name: "SettingsMerge.Override guards non-object incoming (settings safe)",
  regression: true, // FIXED bug kept as a regression check (non-object payloads must not pollute settings)
  mode: null,
  noApp: true,
  async body() {
    const sm=require("node:fs").readFileSync(require("node:path").join(require("../launch").REPO_ROOT,"app","settings","SettingsMerge.ahk"),"utf8");
    const overrideBlock = sm.slice(sm.indexOf("static Override"), sm.indexOf("static Override")+300);
    const hasGuard = /if !IsObject\(incoming\)/.test(overrideBlock);
    const rawIter = /for k, v in incoming/.test(overrideBlock) && !hasGuard;
    if(!hasGuard || rawIter) throw new Error("bug #90 not fixed: hasGuard=" + hasGuard + " rawIter=" + rawIter);
    return "SettingsMerge.Override guards non-object incoming payloads (IsObject), so a crafted empty-string payload cannot pollute settings";
  }
});

scenarios.push({
  id: 91,
  name: "InputWindow validateInputAndHide accepts '0' as valid input",
  regression: true, // FIXED bug kept as a regression check ("0" must not be treated as empty)
  mode: null,
  noApp: true,
  async body() {
    const iw=require("node:fs").readFileSync(require("node:path").join(require("../launch").REPO_ROOT,"app","InputWindow.ahk"),"utf8");
    const block = iw.slice(iw.indexOf("validateInputAndHide"), iw.indexOf("validateInputAndHide")+300);
    const usesTrim = /Trim\(this\.EditControl\.Value\) = ""/.test(block);
    const falsyCheck = /if !this\.EditControl\.Value/.test(block);
    if(!usesTrim || falsyCheck) throw new Error("bug #91 not fixed: usesTrim=" + usesTrim + " falsyCheck=" + falsyCheck);
    return "InputWindow.validateInputAndHide treats only empty/whitespace as empty, so '0' is accepted";
  }
});

scenarios.push({
  id: 92,
  name: "Models ensureFullId rebuilds from the provider dropdown (prefix updated)",
  regression: true, // FIXED bug kept as a regression check (selected provider must win over an embedded prefix)
  mode: null,
  noApp: true,
  async body() {
    const m=require("node:fs").readFileSync(require("node:path").join(require("../launch").REPO_ROOT,"webui","js","settings","sections","models.js"),"utf8");
    const block = m.slice(m.indexOf("function ensureFullId"), m.indexOf("function ensureFullId")+300);
    const stripsPrefix = /id = id\.slice\(slash \+ 1\)/.test(block);
    const earlyReturn = /if \(id\.indexOf\('\/'\) >= 0\) return id/.test(block);
    if(!stripsPrefix || earlyReturn) throw new Error("bug #92 not fixed: stripsPrefix=" + stripsPrefix + " earlyReturn=" + earlyReturn);
    return "models.js ensureFullId rebuilds the full id from the provider dropdown (strips embedded prefix), so changing the provider updates the saved id";
  }
});

scenarios.push({
  id: 93,
  name: "SettingsDefaults GetDefaults deep-clones snapshots (hardening)",
  regression: true, // FIXED bug kept as a regression check (snapshot mutations must not corrupt pristine defaults)
  mode: null,
  noApp: true,
  async body() {
    const sd=require("node:fs").readFileSync(require("node:path").join(require("../launch").REPO_ROOT,"app","settings","SettingsDefaults.ahk"),"utf8");
    const doesDeep = /snapshot\[k\] := SettingsDefaults\._DeepClone\(v\)/.test(sd);
    const hasShallow = /snapshot\[k\] := v/.test(sd);
    if(!doesDeep || hasShallow) throw new Error("bug #93 not fixed: doesDeep=" + doesDeep + " hasShallow=" + hasShallow);
    return "SettingsDefaults.GetDefaults deep-clones nested Maps/Arrays, so mutating a snapshot cannot corrupt the pristine defaults";
  }
});

scenarios.push({
  id: 94,
  name: "SettingsDefaults GetDefaults is stable after caching (UUID churn refuted)",
  regression: true, // REFUTED: UUIDs are generated only when building defaults; after CacheInitialDefaults the cached snapshot is returned
  mode: null,
  noApp: true,
  async body() {
    const sd=require("node:fs").readFileSync(require("node:path").join(require("../launch").REPO_ROOT,"app","settings","SettingsDefaults.ahk"),"utf8");
    const caches = /CacheInitialDefaults\(\)/.test(sd) && /_initialDefaultsCaptured/.test(sd);
    const cachedReturn = /snapshot := Map\(\)/.test(sd) && /_initialDefaults/.test(sd);
    if(!caches || !cachedReturn) throw new Error("bug #94 not fixed: caches=" + caches + " cachedReturn=" + cachedReturn);
    return "SettingsDefaults caches the pristine defaults at startup and GetDefaults returns the cached snapshot, so assistant ids are stable after caching (UUID churn refuted)";
  }
});


scenarios.push({
  id: 95,
  name: "Usage dashboard model heading escapes the model id (XSS fixed)",
  regression: true, // FIXED bug kept as a regression check (security: model headings must be escaped)
  mode: null,
  noApp: true,
  async body() {
    const fs=require("node:fs");
    const path=require("node:path");
    const launcher=require("../launch");
    const dash=fs.readFileSync(path.join(launcher.REPO_ROOT,"webui","js","usage-dashboard.js"),"utf8");
    const sec = dash.slice(dash.indexOf("model-section"), dash.indexOf("model-section")+3000);
    const hasEsc = /escHtml\(model\)/.test(sec);
    const hasRawInner = /div\.innerHTML = .<h6>.+model \+/.test(sec);
    if(!hasEsc || hasRawInner) throw new Error("bug #95 not fixed: hasEsc=" + hasEsc + " hasRawInner=" + hasRawInner);
    return "usage-dashboard.js renderModelSections escapes the model heading (escHtml(model)), so model ids render as inert text";
  }
});

scenarios.push({
  id: 96,
  name: "AttachmentRepo escapes msgId/threadId in every statement (SQL injection fixed)",
  regression: true, // FIXED bug kept as a regression check (security: crafted ids must stay literal)
  mode: null,
  noApp: true,
  async body() {
    const fs=require("node:fs");
    const path=require("node:path");
    const launcher=require("../launch");
    const ar=fs.readFileSync(path.join(launcher.REPO_ROOT,"chat","db","AttachmentRepo.ahk"),"utf8");
    const cd=fs.readFileSync(path.join(launcher.REPO_ROOT,"chat","db","ChatDB.ahk"),"utf8");
    // FIXED (bug #96): every msgId/threadId literal is escaped.
    const insertEsc = /static Insert\(msgId, attObj\)[\s\S]{0,900}SQLite\.Escape\(msgId\)/.test(ar);
    const rawInsert = /VALUES\('" id "', '" msgId "'/.test(ar);
    const getEsc = /static GetByMessage\(msgId\)[\s\S]{0,300}SQLite\.Escape\(msgId\)/.test(ar);
    const getThreadEsc = /static GetByThread\(threadId\)[\s\S]{0,300}SQLite\.Escape\(threadId\)/.test(ar);
    const delEsc = /static DeleteByMessage\(msgId\)[\s\S]{0,500}SQLite\.Escape\(msgId\)/.test(ar);
    const copyEsc = /static CopyForMessage\(sourceMsgId, targetMsgId\)[\s\S]{0,400}SQLite\.Escape\(sourceMsgId\)[\s\S]{0,700}SQLite\.Escape\(targetMsgId\)/.test(ar);
    const ftsSyncEsc = /static FTS_Sync\(msgId, content\)[\s\S]{0,400}SQLite\.Escape\(msgId\)/.test(cd);
    const ftsRemoveEsc = /static FTS_Remove\(msgId\)[\s\S]{0,200}SQLite\.Escape\(msgId\)/.test(cd);
    const rawWhere = /WHERE message_id='" msgId "'/.test(ar);
    if(!insertEsc || rawInsert || !getEsc || !getThreadEsc || !delEsc || !copyEsc || !ftsSyncEsc || !ftsRemoveEsc || rawWhere)
      throw new Error("bug #96 not fixed: insertEsc="+insertEsc+" rawInsert="+rawInsert+" getEsc="+getEsc+" getThreadEsc="+getThreadEsc+" delEsc="+delEsc+" copyEsc="+copyEsc+" ftsSyncEsc="+ftsSyncEsc+" ftsRemoveEsc="+ftsRemoveEsc+" rawWhere="+rawWhere);
    return "AttachmentRepo/ChatDB escape msgId/threadId in Insert, GetByMessage, GetByThread, DeleteByMessage, CopyForMessage, FTS_Sync, FTS_Remove - crafted ids stay literal";
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




