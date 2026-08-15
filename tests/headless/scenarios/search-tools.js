// scenarios/search-tools.js - Web-search tool feature verification
//
// The web-search milestone (DeepSeek native search + Tavily fallback). These
// scenarios drive the REAL app against the local mock server: the mock answers
// the chat stream, the DeepSeek /responses backend, and the Tavily /search
// backend with shapes captured from the real APIs during mock setup. No real
// API calls happen in the headless suite.
'use strict';
const fs = require('node:fs');
const seed = require('../seed');
const { sleep, showChat, sendChatMessage, waitStreamingIdle } = require('./helpers');

const scenarios = [];

// Canonical function-calling order (regression): the follow-up chat request
// must carry the exchange as contiguous assistant tool_calls -> role:"tool"
// with NO search-context user message before the tool call. The context is
// persisted for future turns but excluded from the in-flight round's request.
function assertCanonicalToolOrder(log) {
  const requests = log.split('\n').filter(Boolean).map((l) => JSON.parse(l));
  const toolReq = requests.find((r) => JSON.stringify(r.body || {}).includes('"role":"tool"'));
  if (!toolReq) throw new Error('no chat request carries the tool exchange');
  const msgs = (toolReq.body && toolReq.body.messages) || [];
  const asstIdx = msgs.findIndex((m) => m && m.role === 'assistant' && m.tool_calls && m.tool_calls.length);
  const toolIdx = msgs.findIndex((m) => m && m.role === 'tool');
  if (asstIdx < 0 || toolIdx !== asstIdx + 1)
    throw new Error('tool exchange not contiguous (assistant tool_calls then tool): ' + JSON.stringify(msgs));
  const contextBefore = msgs.slice(0, asstIdx).some((m) => m && m.role === 'user' && String(m.content || '').indexOf('[Web search:') === 0);
  if (contextBefore) throw new Error('search context appears before the tool call: ' + JSON.stringify(msgs));
}

// Enable the right-rail Web Search toggle before the first message (default
// off), wait for the debounced updateModelSettings round-trip, and return the
// posted payload.
async function enableWebSearch(cdp) {
  await showChat();
  await cdp.click('#advancedToggle');
  await cdp.waitFor('document.getElementById("advancedWrap").classList.contains("open")', 5000, 200, 'advanced open');
  await cdp.clearPosted();
  await cdp.click('#advancedWrap .toggle-row .switch');
  await sleep(1000); // debounce 300ms + IPC round trip
  const posted = await cdp.postedMessages();
  const last = posted.filter((m) => m.includes('"updateModelSettings"')).pop();
  if (!last) throw new Error('no updateModelSettings posted after enabling web search');
  return JSON.parse(last);
}

scenarios.push({
  id: 250,
  name: 'Web Search toggle: DeepSeek native search end-to-end (tool loop through the mock /responses backend)',
  mode: 'sse-tool-call',
  settings: { threadTitles: { enabled: false } },
  mockOpts: {
    searchQuery: 'AutoHotkey WebView2',
    searchText: 'DeepSeek native answer: AutoHotkey v2 hosts web content with WebView2.',
    chatText: 'the answer comes from DeepSeek\'s native search.'
  },
  async body({ cdp, dbPath, mockLog }) {
    const payload = await enableWebSearch(cdp);
    if (payload.webSearch !== true) throw new Error('webSearch not enabled in payload: ' + JSON.stringify(payload));
    if ('codeExecution' in payload) throw new Error('codeExecution stub still in payload');

    await sendChatMessage(cdp, 'What is the latest AutoHotkey version?');
    await waitStreamingIdle(cdp, 45000);

    // The final answer bubble rendered after the tool round.
    const text = (await cdp.text('.msg.bot .msg-content')) || '';
    if (text.indexOf('Based on the search') < 0) throw new Error('final answer missing: ' + text.slice(0, 120));

    // DB path: user -> search context -> assistant answer.
    const rows = seed.query(dbPath, 'SELECT role, content FROM messages ORDER BY created_at');
    if (rows.length !== 3) throw new Error('expected user + search context + assistant, got ' + rows.length + ' rows');
    if (rows[0].role !== 'user') throw new Error('first message not user');
    if (rows[1].role !== 'user' || String(rows[1].content || '').indexOf('[Web search: AutoHotkey WebView2]') !== 0)
      throw new Error('search context message missing: ' + JSON.stringify(rows[1]));
    // The search context must carry the REAL backend answer, not a failure
    // blob. Regression (real-API report): DeepSeek's /responses success
    // envelope includes "error":null, which jsongo parses as "" - the old
    // "error key present" check turned every success into "Web search
    // failed: " with no reason. The mock now carries error:null, so this
    // assertion catches that exact regression.
    if (String(rows[1].content || '').indexOf('DeepSeek native answer') < 0)
      throw new Error('search context carries no DeepSeek search result: ' + JSON.stringify(rows[1]));
    if (String(rows[1].content || '').indexOf('Web search failed') >= 0)
      throw new Error('search context reports a failed search: ' + JSON.stringify(rows[1]));
    if (rows[2].role !== 'assistant') throw new Error('final answer not assistant');

    // DeepSeek native backend hit the mock /responses endpoint; the follow-up
    // chat request carried the role:"tool" result back to the model.
    const log = fs.readFileSync(mockLog, 'utf8');
    if (log.indexOf('/v1/responses') < 0 && log.indexOf('/responses') < 0) throw new Error('DeepSeek /responses backend not called');
    if (log.indexOf('"type":"web_search"') < 0) throw new Error('DeepSeek /responses request did not carry the web_search tool');
    if (log.indexOf('"role":"tool"') < 0) throw new Error('tool result not returned to the model');
    assertCanonicalToolOrder(log);

    // The toggle persisted with the thread.
    const settings = seed.query(dbPath, 'SELECT advanced_toggles FROM chat_threads LIMIT 1');
    if (!settings.length || String(settings[0].advanced_toggles || '').indexOf('webSearch') < 0)
      throw new Error('webSearch not persisted: ' + JSON.stringify(settings[0]));

    return 'deepseek native search: tool call -> /responses mock -> answer persisted (3 messages, toggle persisted, no real API calls)';
  }
});

scenarios.push({
  id: 251,
  name: 'Web Search toggle: Tavily fallback end-to-end for non-DeepSeek providers (mock /search backend)',
  mode: 'sse-tool-call',
  settings: {
    threadTitles: { enabled: false },
    newChatStartsWith: 'openai/gpt-5-mini',
    tavilyApiKey: 'test-tavily-key'
  },
  mockOpts: {
    searchQuery: 'AutoHotkey WebView2',
    tavilyAnswer: 'Tavily mock answer: AutoHotkey v2 supports WebView2 for hosting web content.',
    chatText: 'the answer comes from Tavily.'
  },
  // Point the Tavily backend at the local mock (the port is only known after
  // the mock server starts, so patch settings.json after the seed writes it).
  preLaunch(dataDir, endpoint) {
    const settingsFile = require('node:path').join(dataDir, 'settings.json');
    const raw = fs.readFileSync(settingsFile, 'utf8');
    const settings = JSON.parse(raw.replace(/^\uFEFF/, ''));
    settings.tavilyEndpoint = String(endpoint).replace(/chat\/completions$/, '') + 'search';
    fs.writeFileSync(settingsFile, JSON.stringify(settings, null, 2), 'utf8');
  },
  async body({ cdp, dbPath, mockLog }) {
    const payload = await enableWebSearch(cdp);
    if (payload.webSearch !== true) throw new Error('webSearch not enabled: ' + JSON.stringify(payload));

    await sendChatMessage(cdp, 'How does AutoHotkey host web content?');
    await waitStreamingIdle(cdp, 45000);

    const text = (await cdp.text('.msg.bot .msg-content')) || '';
    if (text.indexOf('Based on the search') < 0) throw new Error('final answer missing: ' + text.slice(0, 120));

    const rows = seed.query(dbPath, 'SELECT role, content FROM messages ORDER BY created_at');
    if (rows.length !== 3) throw new Error('expected 3 messages, got ' + rows.length);
    if (rows[1].role !== 'user' || String(rows[1].content || '').indexOf('[Web search: AutoHotkey WebView2]') !== 0)
      throw new Error('search context message missing: ' + JSON.stringify(rows[1]));
    if (String(rows[1].content || '').indexOf('Tavily mock answer') < 0)
      throw new Error('search context carries no Tavily result: ' + JSON.stringify(rows[1]));
    if (String(rows[1].content || '').indexOf('Web search failed') >= 0)
      throw new Error('search context reports a failed search: ' + JSON.stringify(rows[1]));

    const log = fs.readFileSync(mockLog, 'utf8');
    if (log.indexOf('/v1/search') < 0 && log.indexOf('/search') < 0) throw new Error('Tavily /search backend not called');
    if (log.indexOf('"role":"tool"') < 0) throw new Error('tool result not returned to the model');
    assertCanonicalToolOrder(log);

    return 'tavily fallback: tool call -> mock /search -> answer persisted (no real API calls)';
  }
});

scenarios.push({
  id: 252,
  name: 'Web Search toggle off: web_search tool removed from subsequent API requests (on -> send -> off -> send)',
  mode: 'sse-success',
  settings: { threadTitles: { enabled: false } },
  async body({ cdp, dbPath, mockLog }) {
    const onPayload = await enableWebSearch(cdp);
    if (onPayload.webSearch !== true) throw new Error('webSearch not enabled: ' + JSON.stringify(onPayload));

    await sendChatMessage(cdp, 'first message');
    await waitStreamingIdle(cdp, 45000);

    // Toggle the same right-rail switch OFF and capture the posted payload.
    await cdp.clearPosted();
    await cdp.click('#advancedWrap .toggle-row .switch');
    await sleep(1000); // debounce 300ms + IPC round trip
    const posted = await cdp.postedMessages();
    const last = posted.filter((m) => m.includes('"updateModelSettings"')).pop();
    if (!last) throw new Error('no updateModelSettings posted after disabling web search');
    const offPayload = JSON.parse(last);
    if (offPayload.webSearch !== false) throw new Error('webSearch not false in payload: ' + JSON.stringify(offPayload));

    await sendChatMessage(cdp, 'second message');
    await waitStreamingIdle(cdp, 45000);

    // Inspect the REAL request bodies the mock server recorded: the first
    // chat request must carry the web_search tool, the second must not.
    const requests = fs.readFileSync(mockLog, 'utf8')
      .split('\n').filter(Boolean)
      .map((l) => JSON.parse(l))
      .filter((r) => String(r.url).includes('/chat/completions'));
    if (requests.length < 2) throw new Error('expected 2 chat requests, got ' + requests.length);
    const first = requests[0].body;
    const second = requests[1].body;
    if (!first.tools || !Array.isArray(first.tools) || first.tools[0].function.name !== 'web_search')
      throw new Error('first request missing web_search tool: ' + JSON.stringify(first.tools));
    if (second.tools !== undefined)
      throw new Error('second request still carries tools after toggling off: ' + JSON.stringify(second.tools));

    // The off state persisted with the thread (jsongo serializes AHK false
    // as 0, so accept any falsy value).
    const rows = seed.query(dbPath, 'SELECT advanced_toggles FROM chat_threads LIMIT 1');
    if (!rows.length) throw new Error('no thread row to check');
    let toggles = {};
    try { toggles = JSON.parse(rows[0].advanced_toggles || '{}'); } catch {}
    if (toggles.webSearch) throw new Error('webSearch not persisted as off: ' + JSON.stringify(rows[0]));

    return 'toggle off: first request carries web_search tool, second request has no tools, thread persists webSearch off';
  }
});

module.exports = scenarios;
