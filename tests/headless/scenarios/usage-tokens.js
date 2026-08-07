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
const { sleep, showChat } = require('./helpers');

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
  name: 'Usage dashboard double-counts thinking tokens for command usage (completion_tokens already includes thinking)',
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
    // BUG: renderSummary adds completion_tokens + thinking_tokens for commands
    // (cmdOutput = completion + thinking) even though command_usage
    // completion_tokens already includes thinking. The equivalent chat row is
    // counted once (output_tokens), so the same 100-token response with 40
    // thinking tokens is counted as 140 for commands vs 100 for chat.
    if (totalTokens === '220')
      throw new Error('command thinking tokens were not double-counted (bug not reproduced): ' + totalTokens);
    return 'chat row (prompt 10 + completion 100) + command row (prompt 10 + completion 100 + thinking 40): dashboard Total Tokens = ' + totalTokens +
      ' (220 = counted once; 260 = thinking double-counted for the command)';
  }
});

scenarios.push({
  id: 53,
  name: 'Dashboard "Last 24 Hours" spans two calendar days - summary counts yesterday while the chart only plots today',
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
    // BUG: the "day" SQL filter is date >= date('now','-1 day') - yesterday's
    // 00:00 UTC through now (up to ~48 hours) - so the summary counts both
    // seeded days, while getDateRangeLabels('day') produces ONE label (today),
    // so yesterday's usage is counted in the summary but never plotted.
    if (totalCost !== '$4.00')
      throw new Error('day summary no longer over-counts yesterday (bug not reproduced): cost=' + totalCost + ' labels=' + labels);
    return 'seeded yesterday + today rows (total $4.00): "Last 24 Hours" summary shows $' + totalCost +
      ' (both days) while the chart has ' + labels + ' label(s) (today only)';
  }
});

module.exports = scenarios;
