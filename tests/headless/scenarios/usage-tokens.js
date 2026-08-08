// scenarios/usage-tokens.js - Usage dashboards and token/cost accounting
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
const { sleep, showChat, sendChatMessage, waitStreamingIdle } = require('./helpers');

const scenarios = [];

scenarios.push({
  id: 9,
  name: 'Quick Access > Usage Dashboard is wired end-to-end (static check of menu -> IPC -> WebView path)',
  mode: null,
  noApp: true,
  settings: {},
  regression: true, // REFUTED bug kept as a regression check (dashboard must keep opening)
  async body() {
    // Zero-injection: assert the full wiring chain (the live check needed the
    // backtick menu, which injected keystrokes into the user's desktop).
    const rp = fs.readFileSync(path.join(launcher.REPO_ROOT, 'app', 'RequestProcessor.ahk'), 'utf8');
    const dash = fs.readFileSync(path.join(launcher.REPO_ROOT, 'app', 'viewers', 'UsageDashboard.ahk'), 'utf8');
    const cw = fs.readFileSync(path.join(launcher.REPO_ROOT, 'chat', 'ChatWindow.ahk'), 'utf8');
    const mainJs = fs.readFileSync(path.join(launcher.REPO_ROOT, 'webui', 'js', 'main.js'), 'utf8');
    const actionHandled = /command = "usage:"[\s\S]*?ShowUsageDashboard\(\)/.test(rp);
    const ipcSent = /CustomMessages\.notifyShowDashboard\(hwnd\)/.test(dash);
    const ipcHandled = /WM_SHOW_DASHBOARD[\s\S]*?postWebMessage\("showDashboard"\)/.test(cw);
    const jsShows = /case 'showDashboard':[\s\S]*?_showDashboard\(\)/.test(mainJs);
    if (!actionHandled || !ipcSent || !ipcHandled || !jsShows)
      throw new Error('Quick Access -> usage dashboard wiring broken: ' + JSON.stringify({ actionHandled, ipcSent, ipcHandled, jsShows }));
    return 'usage: action -> ShowUsageDashboard -> WM_SHOW_DASHBOARD -> showDashboard -> _showDashboard (wired; no key injection)';
  }
});

scenarios.push({
  id: 19,
  name: 'Dashboard "All Time" chart caps at 365 days while summary sums all rows',
  regression: true, // FIXED bug kept as a regression check (All Time must keep spanning the full history)
  mode: null,
  settings: {},
  fixtures: {
    chatUsage: [
      { date: seed.daysAgo(400), model: 'deepseek/deepseek-v4-flash', provider: 'deepseek', call_count: 1, prompt_tokens: 10, completion_tokens: 5, cached_tokens: 2, input_cost: 2, cached_input_cost: 0.2, output_cost: 3, total_cost: 5 },
      { date: seed.daysAgo(1), model: 'deepseek/deepseek-v4-flash', provider: 'deepseek', call_count: 1, prompt_tokens: 10, completion_tokens: 5, cached_tokens: 0, input_cost: 0.4, cached_input_cost: 0, output_cost: 0.6, total_cost: 1 }
    ]
  },
  async body({ cdp }) {
    await showChat();
    await cdp.click('#dashboard-icon');
    await cdp.waitFor('typeof allData !== "undefined" && allData.chat && allData.chat.length >= 1', 15000, 300, 'dashboard data');
    await cdp.eval('document.getElementById("timeRange").value = "all"; loadData(); true');
    await cdp.waitFor('typeof allData !== "undefined" && allData.chat.length === 2', 15000, 300, 'all-time data');
    const totalCost = await cdp.text('#totalCost');
    const labels = await cdp.eval('mainChart ? mainChart.data.labels.length : -1');
    if (totalCost !== '$6.00') throw new Error('summary total = ' + totalCost + ' (expected $6.00 = all-time)');
    if (labels !== 401) throw new Error('chart labels = ' + labels + ' (expected 401 = full history incl. the 400-day-old row)');
    const firstLabel = await cdp.eval('mainChart.data.labels[0]');
    return 'All Time: summary shows $6.00 (includes 400-day-old row) and chart spans the full history — ' + labels + ' labels, first = ' + firstLabel;
  }
});

scenarios.push({
  id: 29,
  name: 'Blank cached-input price costs 0 instead of the advertised 10% fallback',
  mode: null,
  noApp: true,
  regression: true, // FIXED: blank cachedInput now falls back to 10% (was throw)
  async body() {
    const outFile = path.join(os.tmpdir(), 'llm-cost-probe-' + process.pid + '.json');
    try { fs.unlinkSync(outFile); } catch {}
  const probe = path.join(__dirname, '..', 'probe-cost.ahk');
    const res = spawnSync(launcher.AHK, ['/ErrorStdOut', probe, outFile], { timeout: 25000, windowsHide: true, encoding: 'utf8' });
    if (res.error) throw new Error('cost probe spawn failed/timed out: ' + res.error.message);
    if (res.stderr) process.stderr.write('[probe-cost stderr] ' + res.stderr);
    const text = fs.readFileSync(outFile, 'utf-8');
    // FIXED: blank cachedInput ("" stored by the settings round-trip) now falls back to 10% (1.0) like the missing-property control, no throw.
    if (!text.includes('BUG29 throw=NO')) throw new Error('blank cachedInput should not throw after fix: ' + text);
    if (!text.includes('BUG29 missingFallback=OK')) throw new Error('missing cachedInput fallback broken: ' + text);
    if (!text.includes('blankCost=1')) throw new Error('blank cachedInput should fallback to 1 (10% of 10): ' + text);
    return text.split('\n').filter((l) => l.includes('Cost=') || l.includes('BUG29')).join(' | ');
  }
});

scenarios.push({
  id: 42,
  name: 'Usage dashboard chart date labels use the local date (no UTC day shift in UTC+x timezones)',
  regression: true, // FIXED by the step-1 IPC refactor (8df50b4): getDateRangeLabels keys labels by local date
  mode: null,
  noApp: true,
  async body() {
    const dashSrc = fs.readFileSync(path.join(launcher.REPO_ROOT, 'webui', 'js', 'usage-dashboard.js'), 'utf8');
    const m = dashSrc.match(/function getDateRangeLabels\(\) \{[\s\S]*?\n\}/);
    if (!m) throw new Error('getDateRangeLabels not found in usage-dashboard.js');
    const script = `
      const RealDate = Date;
      const fixed = new RealDate('2026-08-02T21:30:00Z'); // 2026-08-03 00:30 in UTC+3 (Asia/Jerusalem)
      const MockDate = class extends RealDate {
        constructor(...args) { if (args.length === 0) super(fixed.getTime()); else super(...args); }
      };
      global.Date = MockDate;
      global.allData = null;
      global.document = { getElementById: (id) => id === 'timeRange' ? { value: 'day' } : null };
      ${m[0]}
      console.log('LABELS ' + JSON.stringify(getDateRangeLabels()));
    `;
    const res = spawnSync(process.execPath, ['-e', script], {
      encoding: 'utf8', timeout: 15000, windowsHide: true,
      env: Object.assign({}, process.env, { TZ: 'Asia/Jerusalem' })
    });
    if (res.error || res.status !== 0)
      throw new Error('label probe failed: ' + (res.error && res.error.message) + ' ' + (res.stderr || res.stdout || ''));
    const line = String(res.stdout).split(/\r?\n/).find((l) => l.startsWith('LABELS '));
    if (!line) throw new Error('no LABELS line in probe output: ' + String(res.stdout));
    const labels = JSON.parse(line.slice(7));
    const localToday = '2026-08-03';
    const lastLabel = labels[labels.length - 1];
    // FIXED: labels are keyed by the LOCAL date (localDateKey), so a UTC+x
    // clock stuck at 2026-08-02T21:30Z must still label today "2026-08-03"
    // (the old toISOString() path produced "2026-08-02" and misplotted rows).
    if (lastLabel !== localToday)
      throw new Error('chart label for today shifted to UTC date: ' + JSON.stringify(labels) + ' (expected ' + localToday + ')');
    return 'range=day labels=' + JSON.stringify(labels) + ' — the "today" slot is labeled ' + lastLabel + ' (local date, not the UTC-shifted date)';
  }
});

scenarios.push({
  id: 52,
  name: 'Usage dashboard counts command thinking tokens once (completion_tokens already includes thinking)',
  regression: true, // FIXED bug kept as a regression check (command completion_tokens must not be double-counted)
  mode: null,
  settings: {},
  fixtures: {
    chatUsage: [
      { date: seed.daysAgo(0), model: 'gpt-5-mini', provider: 'openai', call_count: 1, prompt_tokens: 10, completion_tokens: 100, thinking_tokens: 40, cached_tokens: 0, input_cost: 0, cached_input_cost: 0, output_cost: 0, total_cost: 0 }
    ]
  },
  async body({ cdp, dbPath }) {
    // Insert a command_usage row with the SAME shape the app writes for inline
    // commands: completion_tokens is the FULL completion (thinking included,
    // per ResponseParser.ParseChatResponse) plus a separate thinking_tokens
    // column. The fixtures builder has no commandUsage support, so insert it
    // directly before the dashboard loads.
    const { DatabaseSync } = require('node:sqlite');
    const db = new DatabaseSync(dbPath);
    db.exec("INSERT INTO command_usage (date, model, provider, command_name, call_count, prompt_tokens, completion_tokens, thinking_tokens, cached_tokens, input_cost, cached_input_cost, output_cost, total_cost, total_response_time_ms, total_ttft_ms) VALUES ('" + seed.daysAgo(0) + "', 'gpt-5-mini', 'openai', 'Test', 1, 10, 100, 40, 0, 0, 0, 0, 0, 0, 0)");
    db.close();

    await showChat();
    await cdp.click('#dashboard-icon');
    await cdp.waitFor('typeof allData !== "undefined" && allData.chat && allData.commands && allData.chat.length >= 1 && allData.commands.length >= 1', 15000, 300, 'dashboard data');
    await cdp.eval('document.getElementById("timeRange").value = "all"; loadData(); true');
    await cdp.waitFor('typeof allData !== "undefined" && allData.chat.length === 1 && allData.commands.length === 1', 15000, 300, 'all-time data');
    await sleep(500); // let the async host-object query + render settle
    const totalTokens = await cdp.text('#totalTokens');
    // FIXED (bug #52): renderSummary and renderModelSections count
    // command_usage.completion_tokens once (it already includes thinking,
    // matching chat's output_tokens).
    if (totalTokens !== '220')
      throw new Error('command thinking tokens still double-counted (bug #52 not fixed): ' + totalTokens);
    return 'chat row (prompt 10 + completion 100) + command row (prompt 10 + completion 100 + thinking 40): dashboard Total Tokens = ' + totalTokens +
      ' (220 = counted once; 260 = thinking double-counted for the command)';
  }
});

scenarios.push({
  id: 53,
  name: 'Dashboard "Last 24 Hours" summary matches the chart (local today only)',
  regression: true, // FIXED bug kept as a regression check (day-range summary must not over-count yesterday)
  mode: null,
  settings: {},
  fixtures: {
    chatUsage: [
      { date: seed.daysAgo(1), model: 'deepseek/deepseek-v4-flash', provider: 'deepseek', call_count: 1, prompt_tokens: 100, completion_tokens: 50, cached_tokens: 0, input_cost: 1, cached_input_cost: 0, output_cost: 1, total_cost: 2 },
      { date: seed.daysAgo(0), model: 'deepseek/deepseek-v4-flash', provider: 'deepseek', call_count: 1, prompt_tokens: 50, completion_tokens: 25, cached_tokens: 0, input_cost: 1, cached_input_cost: 0, output_cost: 1, total_cost: 2 }
    ]
  },
  async body({ cdp }) {
    await showChat();
    await cdp.click('#dashboard-icon');
    await cdp.waitFor('typeof allData !== "undefined" && allData.chat && allData.chat.length >= 2', 15000, 300, 'dashboard data');
    await cdp.eval('document.getElementById("timeRange").value = "day"; loadData(); true');
    // Wait for the DAY render specifically: the day chart has exactly one
    // "today" label (the month render, which also passes the data-count check,
    // has 30 labels and would race with this assertion).
    await cdp.waitFor('mainChart && mainChart.data.labels.length === 1', 15000, 300, 'day-range chart rendered');
    const totalCost = await cdp.text('#totalCost');
    const labels = await cdp.eval('mainChart.data.labels.length');
    // FIXED (bug #53): the "day" SQL filter now uses the LOCAL today date
    // (usage rows are stored with local dates and the chart plots one local
    // "today" label), so the summary matches the chart.
    if (totalCost !== '$2.00')
      throw new Error('day summary still over-counts yesterday (bug #53 not fixed): cost=' + totalCost + ' labels=' + labels);
    return 'seeded yesterday + today rows (total $4.00): "Last 24 Hours" summary shows ' + totalCost +
      ' (today only) while the chart has ' + labels + ' label(s) - summary matches the chart';
  }
});

scenarios.push({
  id: 118,
  name: 'Editing an assistant message with "Save as Branch" records a fake API request in the usage dashboard (no API call happens)',
  mode: null,
  settings: {},
  fixtures: {
    threads: [{ id: 't-fake-118', title: 'Branch Edit Assistant', active_leaf_id: 'm-118-a1' }],
    messages: [
      { id: 'm-118-u1', thread_id: 't-fake-118', role: 'user', content: 'original question', token_count: 12, active_path_tokens: 12 },
      { id: 'm-118-a1', thread_id: 't-fake-118', role: 'assistant', content: 'original answer', model: 'deepseek/deepseek-v4-flash', parent_id: 'm-118-u1', token_count: 9, active_path_tokens: 21 }
    ]
  },
  async body({ cdp, dbPath }) {
    await showChat();
    await cdp.waitFor('document.querySelectorAll("#thread-list .chat-item").length > 0', 15000, 300, 'thread list');
    await cdp.click('#thread-list .chat-item');
    await cdp.waitFor('document.querySelectorAll("#chat-messages .msg").length >= 2', 15000, 300, 'thread loaded');
    await sleep(700);
    // Edit the assistant message and save it as a NEW BRANCH - this is a pure
    // local DB operation: no LLM request is fired for role=assistant.
    await cdp.click('#chat-messages .msg:nth-child(2) .msg-action-btn[title="Edit"]');
    await cdp.waitFor('document.querySelector("#chat-messages .msg:nth-child(2)").classList.contains("editing")', 5000, 200, 'edit ui open');
    await cdp.type('#chat-messages .msg:nth-child(2) .msg-edit-textarea', 'edited answer branch');
    await cdp.click('#chat-messages .msg:nth-child(2) .save-branch');
    // The new message is a sibling of the edited assistant (same parent u1),
    // so the active path becomes [u1, new message].
    await cdp.waitFor('chatMessages.length === 2 && chatMessages[1] && chatMessages[1].content === "edited answer branch"', 15000, 300, 'branch message created');
    await sleep(700);

    const rows = seed.query(dbPath, "SELECT call_count, prompt_tokens, completion_tokens, cached_tokens FROM chat_usage WHERE model='deepseek/deepseek-v4-flash'");
    // BUG: MessageRepo.Insert upserts chat_usage for ANY assistant insert with
    // a model, even when no API call was made (branch-edit inserts have no
    // prompt/completion data). The dashboard then shows a request that never
    // happened. Correct state: zero chat_usage rows.
    if (rows.length !== 1 || rows[0].call_count !== 1 || rows[0].prompt_tokens !== 0 || rows[0].completion_tokens !== 0)
      throw new Error('fake request state not reproduced: ' + JSON.stringify(rows));
    const thread = seed.query(dbPath, 'SELECT cumulative_input_tokens, cumulative_output_tokens FROM chat_threads WHERE id = ?', ['t-fake-118'])[0];
    return 'assistant branch-edit produced a chat_usage row (call_count=1, 0 tokens) - dashboard API Requests +1 with no API call; thread cumulative counters stay ' +
      JSON.stringify(thread);
  }
});

scenarios.push({
  id: 119,
  name: 'Live exchange: token counters, header tooltips and dashboard all agree (regression check for the usage pipeline)',
  regression: true, // guards the end-to-end usage accounting: insert -> chat_usage -> header -> dashboard
  mode: 'sse-success',
  settings: {},
  async body({ cdp, dbPath }) {
    await showChat();
    // Fresh profile: send the first message (mock usage: prompt 12, completion 9, cached 4).
    await sendChatMessage(cdp, 'count my tokens');
    await waitStreamingIdle(cdp, 40000);
    await sleep(1200);

    const rows = seed.query(dbPath, "SELECT model, prompt_tokens, completion_tokens, cached_tokens, call_count FROM chat_usage");
    if (rows.length !== 1 || rows[0].prompt_tokens !== 12 || rows[0].completion_tokens !== 9 || rows[0].cached_tokens !== 4 || rows[0].call_count !== 1)
      throw new Error('chat_usage row wrong: ' + JSON.stringify(rows));
    const msgs = seed.query(dbPath, "SELECT role, token_count, thinking_tokens, cached_tokens, prompt_tokens, active_path_tokens FROM messages ORDER BY created_at");
    if (msgs.length !== 2) throw new Error('expected 2 messages, got ' + msgs.length);
    const asst = msgs[1];
    if (asst.role !== 'assistant' || asst.prompt_tokens !== 12 || asst.token_count !== 9 || asst.active_path_tokens !== 21)
      throw new Error('assistant token fields wrong: ' + JSON.stringify(asst));
    const thread = seed.query(dbPath, 'SELECT cumulative_input_tokens, cumulative_output_tokens, cumulative_cached_tokens FROM chat_threads')[0];
    if (thread.cumulative_input_tokens !== 12 || thread.cumulative_output_tokens !== 9 || thread.cumulative_cached_tokens !== 4)
      throw new Error('thread cumulative counters wrong: ' + JSON.stringify(thread));

    // Header token bar: context 21, input 12, output 9, cache 4.
    const bar = await cdp.eval('document.getElementById("tokenBar").textContent');
    if (String(bar).indexOf('21') < 0 || String(bar).indexOf('\u2191 12') < 0 || String(bar).indexOf('\u2193 9') < 0 || String(bar).indexOf('4') < 0)
      throw new Error('header token bar wrong: ' + JSON.stringify(bar));
    // Cost tooltip and totals must agree with the DB (input+cached split).
    const costTip = await cdp.attr('#tokenBar .tu-item:last-child', 'title');
    if (!costTip || costTip.indexOf('Input: $') < 0 || costTip.indexOf('Cached: $') < 0 || costTip.indexOf('Output: $') < 0)
      throw new Error('cost tooltip malformed: ' + JSON.stringify(costTip));

    // Per-message token popover on the assistant bubble.
    await cdp.click('#chat-messages .msg:nth-child(2) .stat-btn');
    await cdp.waitFor('document.querySelector(".stat-toggle.pop-open") !== null', 5000, 200, 'popover open');
    const pop = await cdp.text('.stat-toggle.pop-open .stat-popover');
    if (String(pop).indexOf('Output: 9 tokens') < 0 || String(pop).indexOf('Cache: 4 tokens') < 0)
      throw new Error('assistant token popover wrong: ' + JSON.stringify(pop));

    // Dashboard: 1 call, 21 total tokens.
    await cdp.click('#dashboard-icon');
    await cdp.waitFor('typeof allData !== "undefined" && allData.chat && allData.chat.length >= 1', 15000, 300, 'dashboard data');
    await sleep(600);
    const totalTokens = await cdp.text('#totalTokens');
    const totalCalls = await cdp.text('#totalCalls');
    if (totalTokens !== '21' || totalCalls !== '1')
      throw new Error('dashboard totals wrong: tokens=' + totalTokens + ' calls=' + totalCalls);
    return 'live exchange: chat_usage row=' + JSON.stringify(rows[0]) + ', thread counters=' + JSON.stringify(thread) +
      ', header=' + JSON.stringify(bar) + ', popover=' + JSON.stringify(pop) + ', dashboard tokens=' + totalTokens + ' calls=' + totalCalls;
  }
});

scenarios.push({
  id: 123,
  name: '"Save as Branch" on an assistant message drops the branch copy\'s token metadata (Context Used falls back to the parent, token popover is blank)',
  mode: null,
  settings: {},
  fixtures: {
    threads: [{
      id: 't-branch-123', title: 'Branch Token Loss', active_leaf_id: 'm-123-a1',
      cumulative_input_tokens: 12, cumulative_output_tokens: 9
    }],
    messages: [
      { id: 'm-123-u1', thread_id: 't-branch-123', role: 'user', content: 'original question', token_count: 12, active_path_tokens: 12 },
      { id: 'm-123-a1', thread_id: 't-branch-123', role: 'assistant', content: 'original answer', model: 'deepseek/deepseek-v4-flash', parent_id: 'm-123-u1', token_count: 9, active_path_tokens: 21 }
    ]
  },
  async body({ cdp, dbPath }) {
    await showChat();
    await cdp.waitFor('document.querySelectorAll("#thread-list .chat-item").length > 0', 15000, 300, 'thread list');
    await cdp.click('#thread-list .chat-item');
    await cdp.waitFor('document.querySelectorAll("#chat-messages .msg").length >= 2', 15000, 300, 'thread loaded');
    await sleep(700);
    // Header context before the branch: the a1 leaf carries 21 (prompt 12 + output 9).
    const barBefore = await cdp.text('#tokenBar .tu-item:first-child .tu-val');
    if (String(barBefore).indexOf('21') !== 0)
      throw new Error('expected header context 21 before branch edit, got ' + JSON.stringify(barBefore));
    // Edit the assistant and save it as a NEW BRANCH (a pure local copy).
    await cdp.click('#chat-messages .msg:nth-child(2) .msg-action-btn[title="Edit"]');
    await cdp.waitFor('document.querySelector("#chat-messages .msg:nth-child(2)").classList.contains("editing")', 5000, 200, 'edit ui open');
    await cdp.type('#chat-messages .msg:nth-child(2) .msg-edit-textarea', 'edited answer branch');
    await cdp.click('#chat-messages .msg:nth-child(2) .save-branch');
    await cdp.waitFor('chatMessages.length === 2 && chatMessages[1] && chatMessages[1].content === "edited answer branch"', 15000, 300, 'branch message created');
    await sleep(900);

    const rows = seed.query(dbPath, "SELECT token_count, prompt_tokens, thinking_tokens, cached_tokens, active_path_tokens FROM messages WHERE content='edited answer branch'");
    if (rows.length !== 1) throw new Error('branch copy row missing: ' + JSON.stringify(rows));
    const r = rows[0];
    // BUG: Edit.ahk branch mode inserts the copy with NO token fields, so
    // MessageRepo.Insert computes active_path_tokens from the PARENT only
    // (12) instead of copying the edited message's ground truth (21), and the
    // copy carries zero token attribution (token_count/prompt_tokens=0).
    if (Number(r.active_path_tokens) === 21 || Number(r.token_count) === 9)
      throw new Error('branch copy kept token metadata (bug may be fixed): ' + JSON.stringify(r));
    if (Number(r.active_path_tokens) !== 12)
      throw new Error('branch copy active_path_tokens = ' + r.active_path_tokens + ' (expected the buggy parent value 12)');
    // Header now shows the LOWER parent context (12), not the copied message's 21.
    const barAfter = await cdp.text('#tokenBar .tu-item:first-child .tu-val');
    if (String(barAfter).indexOf('12') !== 0)
      throw new Error('header context after branch edit = ' + JSON.stringify(barAfter) + ' (expected the buggy 12)');
    // Per-message popover on the branch copy: token attribution is blank.
    await cdp.click('#chat-messages .msg:nth-child(2) .stat-btn');
    await cdp.waitFor('document.querySelector(".stat-toggle.pop-open") !== null', 5000, 200, 'popover open');
    const pop = await cdp.text('.stat-toggle.pop-open .stat-popover');
    if (String(pop).indexOf('Output: 0 tokens') < 0)
      throw new Error('branch popover does not show blank tokens: ' + JSON.stringify(pop));
    return 'branch copy DB=' + JSON.stringify(r) + ', header context before=' + JSON.stringify(barBefore) +
      ' after=' + JSON.stringify(barAfter) + ' popover=' + JSON.stringify(pop) + ' (copy lost a1\'s 21/9 attribution)';
  }
});

scenarios.push({
  id: 127,
  name: 'Complex branched tree stays DB-consistent: FTS == messages, valid parents/leaf, and token counters match the API calls (regression audit)',
  regression: true, // guards DB integrity + token accounting through send/retry/branch-edit flows
  mode: 'sse-success',
  settings: {},
  async body({ cdp, dbPath }) {
    await showChat();
    // Exchange 1.
    await sendChatMessage(cdp, 'first question');
    await waitStreamingIdle(cdp, 40000);
    // Exchange 2.
    await sendChatMessage(cdp, 'second question');
    await waitStreamingIdle(cdp, 40000);
    await sleep(900);
    // Retry the last assistant (creates a sibling branch).
    await cdp.click('#chat-messages .msg:last-child .msg-action-btn[title="Retry"]');
    await waitStreamingIdle(cdp, 40000);
    await sleep(900);
    // Edit the LAST USER message and save as a NEW BRANCH (fires a real call).
    const userIdx = await cdp.eval('chatMessages.length - 2');
    await cdp.click('#chat-messages .msg:nth-child(' + (userIdx + 1) + ') .msg-action-btn[title="Edit"]');
    await cdp.waitFor('document.querySelector("#chat-messages .msg:nth-child(' + (userIdx + 1) + ')").classList.contains("editing")', 5000, 200, 'edit ui open');
    await cdp.type('#chat-messages .msg:nth-child(' + (userIdx + 1) + ') .msg-edit-textarea', 'second question (branch)');
    await cdp.click('#chat-messages .msg:nth-child(' + (userIdx + 1) + ') .save-branch');
    await waitStreamingIdle(cdp, 40000);
    await sleep(1200);

    const dbPath_ = dbPath;
    const counts = seed.query(dbPath_, "SELECT (SELECT COUNT(*) FROM messages) AS msgs, (SELECT COUNT(*) FROM messages_fts) AS fts");
    if (counts[0].msgs !== counts[0].fts)
      throw new Error('FTS out of sync: messages=' + counts[0].msgs + ' fts=' + counts[0].fts);
    // Every message's parent must live in the same thread.
    const badParent = seed.query(dbPath_, "SELECT m.id FROM messages m LEFT JOIN messages p ON p.id = m.parent_id WHERE m.parent_id IS NOT NULL AND (p.id IS NULL OR p.thread_id <> m.thread_id)");
    if (badParent.length)
      throw new Error('dangling/cross-thread parents: ' + JSON.stringify(badParent));
    // The active leaf must exist.
    const badLeaf = seed.query(dbPath_, "SELECT t.id FROM chat_threads t LEFT JOIN messages m ON m.id = t.active_leaf_id WHERE t.active_leaf_id IS NOT NULL AND m.id IS NULL");
    if (badLeaf.length)
      throw new Error('threads with dangling active_leaf: ' + JSON.stringify(badLeaf));
    // Thread cumulative counters must equal the per-message API ground truth.
    const sums = seed.query(dbPath_, "SELECT COALESCE(SUM(prompt_tokens),0) AS inp, COALESCE(SUM(token_count + thinking_tokens),0) AS outp FROM messages WHERE role='assistant'");
    const thread = seed.query(dbPath_, 'SELECT cumulative_input_tokens, cumulative_output_tokens FROM chat_threads')[0];
    if (Number(thread.cumulative_input_tokens) !== Number(sums[0].inp) || Number(thread.cumulative_output_tokens) !== Number(sums[0].outp))
      throw new Error('thread counters mismatch: thread=' + JSON.stringify(thread) + ' assistant-sums=' + JSON.stringify(sums[0]));
    // Usage dashboard row: 4 API calls (2 sends + retry + user-branch-edit),
    // each mock call = prompt 12 / completion 9 / cached 4.
    const usage = seed.query(dbPath_, 'SELECT call_count, prompt_tokens, completion_tokens, cached_tokens FROM chat_usage');
    if (usage.length !== 1 || usage[0].call_count !== 4 || usage[0].prompt_tokens !== 48 || usage[0].completion_tokens !== 36 || usage[0].cached_tokens !== 16)
      throw new Error('chat_usage wrong: ' + JSON.stringify(usage));
    return 'messages=' + counts[0].msgs + ' fts=' + counts[0].fts + ' parents/leaf valid, counters=' +
      JSON.stringify(thread) + ' match assistant sums=' + JSON.stringify(sums[0]) + ', chat_usage=' + JSON.stringify(usage[0]);
  }
});

scenarios.push({
  id: 132,
  regression: true, // mid-path retry audit: sibling branch created in the middle of the tree stays DB-consistent
  name: 'Mid-conversation Retry creates a sibling branch in the middle of the tree and keeps counters/usage consistent (audit)',
  mode: 'sse-success',
  settings: {},
  async body({ cdp, dbPath }) {
    await showChat();
    // Exchange 1.
    await sendChatMessage(cdp, 'first question');
    await waitStreamingIdle(cdp, 40000);
    // Exchange 2.
    await sendChatMessage(cdp, 'second question');
    await waitStreamingIdle(cdp, 40000);
    await sleep(900);
    // Retry the FIRST assistant (mid-path retry): the new answer becomes a
    // sibling of a1 with parent u1, and u2/a2 move off the active path.
    await cdp.click('#chat-messages .msg:nth-child(2) .msg-action-btn[title="Retry"]');
    await waitStreamingIdle(cdp, 40000);
    await sleep(1200);

    const counts = seed.query(dbPath, "SELECT (SELECT COUNT(*) FROM messages) AS msgs, (SELECT COUNT(*) FROM messages_fts) AS fts");
    if (counts[0].msgs !== 5) throw new Error('expected 5 messages (u1,a1,u2,a2,a1b), got ' + counts[0].msgs);
    if (counts[0].msgs !== counts[0].fts) throw new Error('FTS out of sync: ' + JSON.stringify(counts[0]));
    const badParent = seed.query(dbPath, "SELECT m.id FROM messages m LEFT JOIN messages p ON p.id = m.parent_id WHERE m.parent_id IS NOT NULL AND (p.id IS NULL OR p.thread_id <> m.thread_id)");
    if (badParent.length) throw new Error('dangling/cross-thread parents: ' + JSON.stringify(badParent));
    const badLeaf = seed.query(dbPath, "SELECT t.id FROM chat_threads t LEFT JOIN messages m ON m.id = t.active_leaf_id WHERE t.active_leaf_id IS NOT NULL AND m.id IS NULL");
    if (badLeaf.length) throw new Error('dangling active_leaf: ' + JSON.stringify(badLeaf));
    // The retried answer must be a sibling of a1 (same parent u1, sibling group).
    const sibs = seed.query(dbPath, "SELECT sibling_group, sibling_index FROM messages WHERE parent_id = (SELECT id FROM messages WHERE role='user' AND content='first question') ORDER BY sibling_index");
    if (sibs.length !== 2 || sibs[0].sibling_group !== sibs[1].sibling_group)
      throw new Error('retried answer is not a sibling of a1: ' + JSON.stringify(sibs));
    // Counters == assistant ground truth sums (3 API calls, mock: 12/9/4 each).
    const sums = seed.query(dbPath, "SELECT COALESCE(SUM(prompt_tokens),0) AS inp, COALESCE(SUM(token_count + thinking_tokens),0) AS outp, COALESCE(SUM(cached_tokens),0) AS ckt FROM messages WHERE role='assistant'");
    const thread = seed.query(dbPath, 'SELECT cumulative_input_tokens, cumulative_output_tokens, cumulative_cached_tokens FROM chat_threads')[0];
    if (Number(thread.cumulative_input_tokens) !== Number(sums[0].inp) || Number(thread.cumulative_output_tokens) !== Number(sums[0].outp) || Number(thread.cumulative_cached_tokens) !== Number(sums[0].ckt))
      throw new Error('thread counters mismatch: thread=' + JSON.stringify(thread) + ' assistant-sums=' + JSON.stringify(sums[0]));
    const usage = seed.query(dbPath, 'SELECT call_count, prompt_tokens, completion_tokens, cached_tokens FROM chat_usage')[0];
    if (!usage || usage.call_count !== 3 || usage.prompt_tokens !== 36 || usage.completion_tokens !== 27 || usage.cached_tokens !== 12)
      throw new Error('chat_usage wrong after mid-path retry: ' + JSON.stringify(usage));
    return 'mid-path retry: messages=' + counts[0].msgs + ' fts=' + counts[0].fts + ' siblings=' +
      JSON.stringify(sibs) + ' counters=' + JSON.stringify(thread) + ' match sums=' + JSON.stringify(sums[0]) +
      ' chat_usage=' + JSON.stringify(usage);
  }
});

module.exports = scenarios;
