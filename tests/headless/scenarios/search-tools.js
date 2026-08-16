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
  await cdp.clearPosted();
  await cdp.eval('document.getElementById("webSearchToggle").click()');
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
    searchReasoning: 'Let me search for this.',
    searchText: 'DeepSeek native answer: AutoHotkey v2 hosts web content with WebView2.',
    chatText: 'the answer comes from DeepSeek\'s native search.'
  },
  async body({ cdp, dbPath, mockLog }) {
    const payload = await enableWebSearch(cdp);
    if (payload.webSearch !== true) throw new Error('webSearch not enabled in payload: ' + JSON.stringify(payload));
    if ('codeExecution' in payload) throw new Error('codeExecution stub still in payload');

    await sendChatMessage(cdp, 'What is the latest AutoHotkey version?');
    // Live progress: the streaming /responses backend re-renders the search
    // card as it runs (search rounds, then the answer) - assert it appears
    // BEFORE the stream completes.
    await cdp.waitFor('document.querySelector(".msg.search-context .search-card-results") && document.querySelector(".msg.search-context .search-card-results").textContent.indexOf("related terms") >= 0', 20000, 150, 'live search progress');
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
    const requests = log.split('\n').filter(Boolean).map((l) => JSON.parse(l));
    const responsesReq = requests.find((r) => String(r.url).includes('/responses'));
    // AHK's jsongo serializes true as 1, so the wire body carries stream:1.
    if (!responsesReq || !responsesReq.body.stream) throw new Error('/responses request must be streaming');

    // The toggle persisted with the thread.
    const settings = seed.query(dbPath, 'SELECT advanced_toggles FROM chat_threads LIMIT 1');
    if (!settings.length || String(settings[0].advanced_toggles || '').indexOf('webSearch') < 0)
      throw new Error('webSearch not persisted: ' + JSON.stringify(settings[0]));

    // UI feedback: the search context renders as a collapsible card showing
    // the query, with the results hidden until the user expands them.
    const cardState = await cdp.eval(`(() => {
      var toggle = document.querySelector('.msg.search-context .search-card-toggle');
      var results = document.querySelector('.msg.search-context .search-card-results');
      if (!toggle || !results) return JSON.stringify({ missing: true });
      var hiddenBefore = results.hidden;
      toggle.click();
      var hiddenAfter = results.hidden;
      toggle.click();
      return JSON.stringify({ title: toggle.textContent, hiddenBefore: hiddenBefore, hiddenAfter: hiddenAfter });
    })()`);
    const card = JSON.parse(cardState);
    if (card.missing) {
      const dom = await cdp.eval(`(() => {
        var sc = document.querySelector('.msg.search-context');
        if (sc) return sc.outerHTML.slice(0, 800);
        return 'no .msg.search-context; total .msg nodes=' + document.querySelectorAll('.msg').length;
      })()`);
      throw new Error('search context card not rendered: ' + cardState + ' | dom=' + dom);
    }
    if (card.title.indexOf('Searched the web for:') < 0 || card.title.indexOf('AutoHotkey WebView2') < 0)
      throw new Error('search card header missing the query: ' + cardState);
    if (card.hiddenBefore !== true || card.hiddenAfter !== false)
      throw new Error('search card results did not toggle: ' + cardState);

    // The search backend call is recorded in the API log (like chat/title).
    const apiLogFile = require('node:path').join(require('node:os').tmpdir(), 'LLM_API_Log.json');
    let apiLogEntries = [];
    try { apiLogEntries = JSON.parse(fs.readFileSync(apiLogFile, 'utf8')); } catch {}
    const searchEntry = apiLogEntries.find((e) => String(e.commandName || '').indexOf('Web Search (DeepSeek)') >= 0);
    if (!searchEntry) throw new Error('DeepSeek search request not found in the API log');
    if (String(searchEntry.searchQuery || '').indexOf('AutoHotkey WebView2') < 0)
      throw new Error('API log search entry missing the query: ' + JSON.stringify(searchEntry));

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

    // The Tavily backend call is recorded in the API log.
    const apiLogFile = require('node:path').join(require('node:os').tmpdir(), 'LLM_API_Log.json');
    let apiLogEntries = [];
    try { apiLogEntries = JSON.parse(fs.readFileSync(apiLogFile, 'utf8')); } catch {}
    const searchEntry = apiLogEntries.find((e) => String(e.commandName || '').indexOf('Web Search (Tavily)') >= 0);
    if (!searchEntry) throw new Error('Tavily search request not found in the API log');
    if (String(searchEntry.searchQuery || '').indexOf('AutoHotkey WebView2') < 0)
      throw new Error('API log search entry missing the query: ' + JSON.stringify(searchEntry));

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
    await cdp.eval('document.getElementById("webSearchToggle").click()');
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

scenarios.push({
  id: 253,
  name: 'Stop mid-search: backend call cancelled, no follow-up request, card cancelled, chat usable',
  mode: 'sse-tool-call',
  settings: { threadTitles: { enabled: false } },
  mockOpts: {
    searchQuery: 'AutoHotkey WebView2',
    searchDelay: 60000, // keep the /responses stream open so Stop lands mid-search
    chatText: 'the answer comes from DeepSeek native search.'
  },
  async body({ cdp, mockLog }) {
    const payload = await enableWebSearch(cdp);
    if (payload.webSearch !== true) throw new Error('webSearch not enabled');

    await sendChatMessage(cdp, 'What is the latest AutoHotkey version?');
    // The placeholder card appears immediately; the slow mock keeps the
    // search streaming.
    await cdp.waitFor('document.querySelector(".msg.search-context .search-card-results") && document.querySelector(".msg.search-context .search-card-results").textContent.indexOf("Searching") >= 0', 15000, 150, 'searching card');
    await sleep(500);

    // Press Stop while the search backend is still running.
    await cdp.eval('window.chrome.webview.postMessage(JSON.stringify({ action: "cancelStream" }))');
    await sleep(2000);

    // The card becomes "Search cancelled." instead of a stale "Searching...".
    const cardText = await cdp.eval('document.querySelector(".msg.search-context .search-card-results") ? document.querySelector(".msg.search-context .search-card-results").textContent : ""');
    if (cardText.indexOf('Search cancelled') < 0) throw new Error('card not marked cancelled: ' + JSON.stringify(cardText));

    // No follow-up chat request - the staged tool exchange must NOT fire.
    const log = fs.readFileSync(mockLog, 'utf8');
    const chatReqs = log.split('\n').filter(Boolean).map((l) => JSON.parse(l)).filter((r) => String(r.url).includes('/chat/completions'));
    if (chatReqs.length !== 1) throw new Error('expected exactly 1 chat request (no follow-up after cancel), got ' + chatReqs.length);
    if (JSON.stringify(chatReqs[0].body).indexOf('"role":"tool"') >= 0) throw new Error('follow-up tool exchange fired after cancel');

    // The backend call was still logged (status cancelled).
    const apiLogFile = require('node:path').join(require('node:os').tmpdir(), 'LLM_API_Log.json');
    let apiLogEntries = [];
    try { apiLogEntries = JSON.parse(fs.readFileSync(apiLogFile, 'utf8')); } catch {}
    const searchEntry = apiLogEntries.find((e) => String(e.commandName || '').indexOf('Web Search (DeepSeek)') >= 0 && String(e.searchQuery || '').indexOf('AutoHotkey WebView2') >= 0);
    if (!searchEntry) throw new Error('cancelled search request not found in the API log');
    if (String(searchEntry.status) !== 'cancelled') throw new Error('expected cancelled status, got ' + JSON.stringify(searchEntry.status));

    // The chat is not broken: composer is back in Send mode.
    const sendEnabled = await cdp.eval('document.getElementById("chat-send-btn") ? !document.getElementById("chat-send-btn").disabled : false');
    if (!sendEnabled) throw new Error('composer not re-enabled after cancel');

    return 'stop mid-search: /responses killed, no follow-up request, card cancelled, search logged (status cancelled), composer usable';
  }
});

scenarios.push({
  id: 254,
  name: 'DeepSeek native search empty backend: one failure card, tool loop stops (no retry loop)',
  mode: 'sse-tool-call',
  settings: { threadTitles: { enabled: false } },
  mockOpts: {
    searchEmpty: true, // /responses completes with ZERO message items (real
                       // backend shape when it returns "no answer")
    chatText: 'the answer comes from DeepSeek native search.'
  },
  async body({ cdp, dbPath, mockLog }) {
    const payload = await enableWebSearch(cdp);
    if (payload.webSearch !== true) throw new Error('webSearch not enabled');

    await sendChatMessage(cdp, 'What is the latest AutoHotkey version?');
    // The placeholder card appears immediately, then becomes the failure card
    // once the empty backend stream completes.
    await cdp.waitFor('document.querySelector(".msg.search-context .search-card-results") && document.querySelector(".msg.search-context .search-card-results").textContent.indexOf("Searching") >= 0', 15000, 150, 'searching card');
    await cdp.waitFor('document.querySelector(".msg.search-context .search-card-results") && document.querySelector(".msg.search-context .search-card-results").textContent.indexOf("Web search failed") >= 0', 30000, 150, 'failure card');

    // Regression: a failed search round must NOT fire a follow-up request, so
    // the model cannot keep retrying (real-API report 2026-08-16: four failed
    // search cards in a row before the model gave up).
    const log = fs.readFileSync(mockLog, 'utf8');
    const chatReqs = log.split('\n').filter(Boolean).map((l) => JSON.parse(l)).filter((r) => String(r.url).includes('/chat/completions'));
    if (chatReqs.length !== 1) throw new Error('expected exactly 1 chat request (no follow-up after failed search), got ' + chatReqs.length);
    if (JSON.stringify(chatReqs[0].body).indexOf('"role":"tool"') >= 0) throw new Error('follow-up tool exchange fired after failed search');

    // The card carries the failure message, and the thread persists user +
    // failure card with NO assistant answer (the loop stopped).
    const cardText = await cdp.eval('document.querySelector(".msg.search-context .search-card-results") ? document.querySelector(".msg.search-context .search-card-results").textContent : ""');
    if (cardText.indexOf('DeepSeek returned no answer') < 0) throw new Error('failure card missing the reason: ' + JSON.stringify(cardText));
    const rows = seed.query(dbPath, 'SELECT role, content FROM messages ORDER BY created_at');
    if (rows.length !== 2) throw new Error('expected user + failure card, got ' + rows.length + ' rows');
    if (String(rows[1].content || '').indexOf('Web search failed') < 0)
      throw new Error('failure not persisted: ' + JSON.stringify(rows[1]));

    // The failed backend call is logged with status error.
    const apiLogFile = require('node:path').join(require('node:os').tmpdir(), 'LLM_API_Log.json');
    let apiLogEntries = [];
    try { apiLogEntries = JSON.parse(fs.readFileSync(apiLogFile, 'utf8')); } catch {}
    const searchEntry = apiLogEntries.find((e) => String(e.commandName || '').indexOf('Web Search (DeepSeek)') >= 0);
    if (!searchEntry) throw new Error('empty search request not found in the API log');
    if (String(searchEntry.status) !== 'error') throw new Error('expected error status, got ' + JSON.stringify(searchEntry.status));

    // The chat is not broken: composer is back in Send mode.
    const sendEnabled = await cdp.eval('document.getElementById("chat-send-btn") ? !document.getElementById("chat-send-btn").disabled : false');
    if (!sendEnabled) throw new Error('composer not re-enabled after failed search');

    return 'empty backend: one failure card, no follow-up request, failure persisted + logged, composer usable';
  }
});

scenarios.push({
  id: 255,
  name: 'DeepSeek native search multi-item stream: interim commentary excluded from the search result',
  mode: 'sse-tool-call',
  settings: { threadTitles: { enabled: false } },
  mockOpts: {
    searchQuery: 'AutoHotkey WebView2',
    // Real capture 2026-08-16: DeepSeek tags every message "final_answer" at
    // output_item.added and corrects interim commentary to "commentary" at
    // output_item.done. The tool result must contain ONLY the final answer.
    searchInterim: ['Let me search for the latest news.', 'Let me open the live coverage.'],
    searchText: 'DeepSeek native answer: AutoHotkey v2 hosts web content with WebView2.',
    chatText: 'the answer comes from DeepSeek\'s native search.'
  },
  async body({ cdp, dbPath, mockLog }) {
    const payload = await enableWebSearch(cdp);
    if (payload.webSearch !== true) throw new Error('webSearch not enabled');

    await sendChatMessage(cdp, 'What is the latest AutoHotkey version?');
    await waitStreamingIdle(cdp, 45000);

    const text = (await cdp.text('.msg.bot .msg-content')) || '';
    if (text.indexOf('Based on the search') < 0) throw new Error('final answer missing: ' + text.slice(0, 120));

    // Persisted search context: the real answer only - no interim narration.
    const rows = seed.query(dbPath, 'SELECT role, content FROM messages ORDER BY created_at');
    if (rows.length !== 3) throw new Error('expected 3 messages, got ' + rows.length);
    const context = String(rows[1].content || '');
    if (context.indexOf('DeepSeek native answer') < 0)
      throw new Error('search context missing the final answer: ' + JSON.stringify(rows[1]));
    if (context.indexOf('Let me search') >= 0 || context.indexOf('Let me open') >= 0)
      throw new Error('interim commentary leaked into the persisted search result: ' + JSON.stringify(rows[1]));

    // The follow-up chat request's role:"tool" message carries the clean
    // result too (the model must not see "Let me search..." as a search hit).
    const log = fs.readFileSync(mockLog, 'utf8');
    const toolReq = log.split('\n').filter(Boolean).map((l) => JSON.parse(l)).find((r) => JSON.stringify(r.body || {}).includes('"role":"tool"'));
    if (!toolReq) throw new Error('no follow-up request with the tool result');
    const toolMsg = (toolReq.body.messages || []).find((m) => m && m.role === 'tool');
    if (!toolMsg || String(toolMsg.content || '').indexOf('DeepSeek native answer') < 0)
      throw new Error('tool result missing the answer: ' + JSON.stringify(toolMsg));
    if (String(toolMsg.content || '').indexOf('Let me search') >= 0 || String(toolMsg.content || '').indexOf('Let me open') >= 0)
      throw new Error('interim commentary leaked into the tool result: ' + JSON.stringify(toolMsg));

    return 'multi-item stream: search result contains only the final answer (no interim commentary)';
  }
});

module.exports = scenarios;
