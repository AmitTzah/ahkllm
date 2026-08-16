// mock-llm-server.js — Local fake LLM endpoint (OpenAI-compatible).
// Modes:
//   sse-success        streaming: reasoning + content + usage + [DONE]
//   sse-reasoning-only streaming: reasoning only, empty content
//   json               non-stream chat completion
//   title              non-stream short title response (max_tokens 50)
//   sse-script         streaming with a custom chunk script (opts.script)
//   sse-midfail        streaming: one content chunk, then the socket is
//                      destroyed before [DONE] (mid-stream connection failure)
//   sse-lateerror      streaming headers + keepalive, then a JSON error body
//                      after a delay (a request that starts streaming and then
//                      fails BEFORE any content/reasoning chunk arrives)
//   sse-slow           streaming like sse-success but with ~700ms delays per
//                      chunk (total ~3s) so scenarios can act mid-stream
//   sse-error-event    streaming: one content chunk, then a REAL OpenAI-style
//                      SSE error event (`data: {"error": {...}}`) before the
//                      stream ends - providers emit exactly this when a stream
//                      fails mid-flight (rate limit / upstream error after
//                      partial tokens)
//   sse-paragraphs     streaming: three content chunks whose paragraph breaks
//                      are SINGLE newlines (a common summarize-style LLM
//                      output shape) - used to verify the chat renderer keeps
//                      the paragraph breaks visible instead of collapsing
//                      them into one block
//   sse-hang           streaming headers + a keepalive comment, then the
//                      socket is left OPEN forever - the "stalled stream"
//                      case (cURL has --connect-timeout but no --max-time)
//   sse-split-line     streaming: one SSE event whose `data:` LINE is written
//                      in TWO writes with a >poll-interval delay between, so
//                      the app's 100ms stream poll consumes the partial line
//                      and then ignores the bare remainder (the bug hunt's
//                      "data line split across poll boundaries" case)
//   sse-tool-call      streaming web-search tool loop: the FIRST request (no
//                      role:"tool" message) streams a web_search function call
//                      split across two deltas + finish_reason tool_calls; the
//                      follow-up request (contains the tool result) streams
//                      the final answer. POSTs to /responses (DeepSeek native
//                      search backend) and /search (Tavily backend) are
//                      answered from the real API shapes captured during mock
//                      setup — the headless suite never calls the real APIs.
//   json               non-stream chat completion; FIM requests (body.prompt)
//                      answered with choices[0].text (opts.fimText)
//   error-json         HTTP 401 with {"error":{"message":...}}
//   drop               accept then destroy socket without any response
//   refuse             (no server) — caller points the endpoint at a closed port
'use strict';
const http = require('node:http');
const fs = require('node:fs');

function json(data, res, status = 200) {
  const body = JSON.stringify(data);
  res.writeHead(status, { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(body) });
  res.end(body);
}

function sseChunk(res, obj) {
  res.write('data: ' + JSON.stringify(obj) + '\n\n');
}

function makeSseHandler(opts) {
  return (req, res) => {
    res.writeHead(200, {
      'Content-Type': 'text/event-stream',
      'Cache-Control': 'no-cache',
      'Connection': 'keep-alive'
    });
    const delay = (ms) => new Promise((r) => setTimeout(r, ms));
    const chunkDelay = opts.chunkDelay || 60;
    (async () => {
      if (opts.reasoning !== false) {
        sseChunk(res, { choices: [{ delta: { reasoning_content: 'Let me reason about this step by step. ' } }] });
        await delay(chunkDelay);
        sseChunk(res, { choices: [{ delta: { reasoning_content: 'First, gather the facts. ' } }] });
        await delay(chunkDelay);
      }
      if (opts.content !== '') {
        sseChunk(res, { choices: [{ delta: { content: 'Hello from the mock LLM. ' } }] });
        await delay(chunkDelay);
        sseChunk(res, { choices: [{ delta: { content: 'This is the streamed answer.' } }] });
        await delay(chunkDelay);
      }
      sseChunk(res, {
        choices: [{ delta: {}, finish_reason: 'stop' }],
        model: opts.responseModel || 'deepseek-v4-flash',
        usage: { prompt_tokens: 12, completion_tokens: 9, total_tokens: 21, prompt_tokens_details: { cached_tokens: 4 } }
      });
      await delay(40);
      res.write('data: [DONE]\n\n');
      res.end();
    })().catch(() => { try { res.end(); } catch {} });
  };
}

// Scripted SSE: emits the given delta chunks (content or reasoning) with
// per-chunk delays, then usage + [DONE]. Each step: { type: 'content'|'reasoning',
// text, delay }.
function makeScriptedSseHandler(script = []) {
  return (req, res) => {
    res.writeHead(200, {
      'Content-Type': 'text/event-stream',
      'Cache-Control': 'no-cache',
      'Connection': 'keep-alive'
    });
    const delay = (ms) => new Promise((r) => setTimeout(r, ms));
    (async () => {
      for (const step of script) {
        const delta = step.type === 'reasoning' ? { reasoning_content: step.text } : { content: step.text };
        sseChunk(res, { choices: [{ delta }] });
        await delay(step.delay || 80);
      }
      sseChunk(res, {
        choices: [{ delta: {}, finish_reason: 'stop' }],
        model: 'deepseek-v4-flash',
        usage: { prompt_tokens: 24, completion_tokens: 18, total_tokens: 42, prompt_tokens_details: { cached_tokens: 6 } }
      });
      await delay(40);
      res.write('data: [DONE]\n\n');
      res.end();
    })().catch(() => { try { res.end(); } catch {} });
  };
}

// Streaming web-search tool loop (mode 'sse-tool-call'):
//   round 1 (no tool result in the conversation): the model emits a
//     web_search function call split across two deltas, then
//     finish_reason "tool_calls".
//   round 2+ (the request carries role:"tool" results): normal final answer.
function makeToolCallSseHandler(parsed, opts) {
  return (req, res) => {
    res.writeHead(200, {
      'Content-Type': 'text/event-stream',
      'Cache-Control': 'no-cache',
      'Connection': 'keep-alive'
    });
    const delay = (ms) => new Promise((r) => setTimeout(r, ms));
    const hasToolResult = (parsed.messages || []).some((m) => m && m.role === 'tool');
    const usage = { prompt_tokens: 16, completion_tokens: 10, total_tokens: 26, prompt_tokens_details: { cached_tokens: 4 } };
    (async () => {
      if (!hasToolResult) {
        // Fragment 1: call id + name; fragment 2: the arguments JSON.
        sseChunk(res, { choices: [{ delta: { tool_calls: [{ index: 0, id: 'call_search_1', type: 'function', function: { name: 'web_search', arguments: '' } }] } }] });
        await delay(60);
        sseChunk(res, { choices: [{ delta: { tool_calls: [{ index: 0, function: { arguments: JSON.stringify({ query: opts.searchQuery || 'AutoHotkey webview2' }) } }] } }] });
        await delay(60);
        sseChunk(res, { choices: [{ delta: {}, finish_reason: 'tool_calls' }], model: opts.responseModel || 'deepseek-v4-flash', usage });
      } else {
        sseChunk(res, { choices: [{ delta: { content: 'Based on the search, ' + (opts.chatText || 'here is the answer.') } }] });
        await delay(60);
        sseChunk(res, { choices: [{ delta: {}, finish_reason: 'stop' }], model: opts.responseModel || 'deepseek-v4-flash', usage });
      }
      await delay(40);
      res.write('data: [DONE]\n\n');
      res.end();
    })().catch(() => { try { res.end(); } catch {} });
  };
}

// DeepSeek native search backend (POST /responses). Shape captured from a
// real api.deepseek.com/responses call during mock setup (2026-08-15). The
// envelope ALWAYS carries an "error" key - JSON null on success (OpenAI
// Responses API shape) - and the output array interleaves reasoning,
// web_search_call and message items. Including error:null is load-bearing:
// jsongo parses JSON null as "" (empty string), and DeepSeekSearch must NOT
// treat a present-but-null error key as a failure, or every successful
// search reports "Web search failed: ".
function responsesSearchBody(opts) {
  const text = opts.searchText || 'DeepSeek native search answer: AutoHotkey v2 hosts web content with WebView2.';
  return {
    id: 'mock-response-id',
    object: 'response',
    status: 'completed',
    model: opts.responseModel || 'deepseek-v4-flash',
    error: null,
    incomplete_details: null,
    output: [{
      type: 'reasoning',
      id: 'mock-reasoning-1',
      status: 'completed',
      content: [{ type: 'reasoning_text', text: 'Let me search the web for this.' }],
      summary: []
    }, {
      type: 'web_search_call',
      id: 'call_mock_search_1',
      status: 'completed',
      action: { type: 'search', queries: [opts.searchQuery || 'AutoHotkey webview2'] }
    }, {
      type: 'message',
      id: 'mock-search-message',
      status: 'completed',
      role: 'assistant',
      content: [{ type: 'output_text', annotations: [], logprobs: [], text }]
    }],
    usage: {
      input_tokens: 4750, output_tokens: 42, total_tokens: 4792,
      input_tokens_details: { cached_tokens: 0 },
      output_tokens_details: { reasoning_tokens: 0 }
    }
  };
}

// Streaming DeepSeek /responses (request body has stream:true). Emits the
// real event sequence: reasoning deltas -> web_search_call lifecycle ->
// output_text deltas -> completed. Inter-event delays come from
// opts.searchDelay so scenarios can observe (or stop) mid-search.
function makeResponsesStreamHandler(parsed, opts) {
  return (req, res) => {
    res.writeHead(200, {
      'Content-Type': 'text/event-stream',
      'Cache-Control': 'no-cache',
      'Connection': 'keep-alive'
    });
    const delay = (ms) => new Promise((r) => setTimeout(r, ms));
    const step = opts.searchDelay || 120;
    const reasoning = opts.searchReasoning || 'Let me search for this.';
    const text = opts.searchText || 'DeepSeek native search answer: AutoHotkey v2 hosts web content with WebView2.';
    const reasoningOff = parsed.reasoning && parsed.reasoning.effort === 'none';
    const ev = (type, data) => res.write('event: ' + type + '\ndata: ' + JSON.stringify(data) + '\n\n');
    // Emit one streaming message item: added carries DeepSeek's optimistic
    // phase, done carries the authoritative phase. opts.searchInterim lists
    // the interim commentary texts (corrected to "commentary" at done), the
    // final message stays "final_answer". opts.searchEmpty skips the message
    // items entirely - the real backend sometimes completes with no answer
    // at all (real-API report 2026-08-16).
    const emitMessage = async (id, outputIndex, bodyText, donePhase) => {
      ev('response.output_item.added', { type: 'response.output_item.added', item: { type: 'message', id, status: 'in_progress', content: [], phase: 'final_answer', role: 'assistant' }, output_index: outputIndex });
      ev('response.content_part.added', { type: 'response.content_part.added', content_index: 0, item_id: id, output_index: outputIndex, part: { type: 'output_text', text: '' } });
      for (const token of bodyText.split(' ')) {
        ev('response.output_text.delta', { type: 'response.output_text.delta', content_index: 0, delta: token + ' ', item_id: id, output_index: outputIndex });
        await delay(step);
      }
      ev('response.output_item.done', { type: 'response.output_item.done', item: { type: 'message', id, status: 'completed', content: [{ type: 'output_text', text: bodyText }], phase: donePhase, role: 'assistant' }, output_index: outputIndex });
      await delay(step);
    };
    (async () => {
      ev('response.created', { type: 'response.created', response: { id: 'mock-resp', object: 'response', status: 'in_progress', model: opts.responseModel || 'deepseek-v4-flash' } });
      await delay(step);
      if (!reasoningOff) {
        ev('response.output_item.added', { type: 'response.output_item.added', item: { type: 'reasoning', id: 'r1', status: 'in_progress', content: [], summary: [] }, output_index: 0 });
        ev('response.content_part.added', { type: 'response.content_part.added', content_index: 0, item_id: 'r1', output_index: 0, part: { type: 'reasoning_text', text: '' } });
        for (const token of reasoning.split(' ')) {
          ev('response.reasoning_text.delta', { type: 'response.reasoning_text.delta', content_index: 0, delta: token + ' ', item_id: 'r1', output_index: 0 });
          await delay(step);
        }
      }
      ev('response.web_search_call.in_progress', { type: 'response.web_search_call.in_progress', item_id: 'call_1', output_index: 1 });
      await delay(step);
      ev('response.web_search_call.searching', { type: 'response.web_search_call.searching', item_id: 'call_1', output_index: 1 });
      await delay(step * 2);
      ev('response.web_search_call.completed', { type: 'response.web_search_call.completed', item_id: 'call_1', output_index: 1 });
      await delay(step);
      if (opts.searchEmpty) {
        // Real backend shape when it returns "no answer": the stream runs the
        // search lifecycle and completes with ZERO message items.
        ev('response.completed', { type: 'response.completed', response: { id: 'mock-resp', object: 'response', status: 'completed', model: opts.responseModel || 'deepseek-v4-flash' } });
        res.end();
        return;
      }
      let outputIndex = 2;
      for (const interim of opts.searchInterim || []) {
        await emitMessage('interim_' + outputIndex, outputIndex, interim, 'commentary');
        outputIndex++;
      }
      await emitMessage('m1', outputIndex, text, 'final_answer');
      ev('response.completed', { type: 'response.completed', response: { id: 'mock-resp', object: 'response', status: 'completed', model: opts.responseModel || 'deepseek-v4-flash' } });
      res.end();
    })().catch(() => { try { res.end(); } catch {} });
  };
}

// Tavily fallback backend (POST /search). Shape captured from a real
// api.tavily.com/search call during mock setup.
function tavilySearchBody(parsed, opts) {
  const query = (parsed && parsed.query) || 'AutoHotkey webview2';
  const answer = opts.tavilyAnswer || 'AutoHotkey v2 supports WebView2 for hosting web content using Microsoft Edge\'s Chromium engine.';
  return {
    query,
    follow_up_questions: null,
    answer,
    images: [],
    results: [
      {
        url: 'https://github.com/example/ahk-webview2',
        title: 'ahk2_lib/WebView2 — AutoHotkey WebView2 bindings',
        content: 'The Microsoft Edge WebView2 control enables you to host web content in your application using Edge Chromium as the rendering engine.',
        score: 0.6496014,
        raw_content: null,
        id: 'mock-tavily-00'
      }
    ],
    response_time: 0.5,
    request_id: 'mock-tavily-request'
  };
}

// startMockServer(mode, logFile, opts)
//   opts.chatText  - content used by the JSON chat response.
//   opts.fimText   - choices[0].text used when the JSON body carries a
//                    FIM `prompt` field (FIM requests land on the same URL).
//   opts.fimTextMap - [{ match, text }] picked by substring against the FIM
//                    prompt, first match wins; falls back to opts.fimText.
//   opts.script    - chunk script for mode 'sse-script'.
//   opts.echoModel - echo the REQUEST's model in the streaming finish chunk
//                    (real APIs do this; lets scenarios verify per-command
//                    model attribution end-to-end). Default: the hardcoded
//                    'deepseek-v4-flash' response model.
function startMockServer(mode = 'sse-success', logFile = '', opts = {}) {
  const server = http.createServer((req, res) => {
    let body = '';
    req.on('data', (c) => { body += c; });
    req.on('end', () => {
      let parsed = {};
      try { parsed = JSON.parse(body); } catch {}
      if (logFile) {
        try {
          const modeUsed = parsed.stream ? 'sse' : (parsed.max_tokens === 50 ? 'title' : 'json');
          fs.appendFileSync(logFile, JSON.stringify({ modeUsed, url: req.url, body: parsed }) + '\n');
        } catch {}
      }
      // Emulate the real providers' JSON-Schema validation for function tools.
      // AHK's jsongo serializes `false` as 0, and DeepSeek rejects
      // additionalProperties:0 with exactly this error — enforcing it here
      // keeps the headless suite honest: an invalid tool schema now FAILS the
      // scenario instead of passing silently (regression: web-search schema).
      if (parsed.tools && Array.isArray(parsed.tools)) {
        for (const tool of parsed.tools) {
          if (tool && tool.function && tool.function.parameters &&
              typeof tool.function.parameters.additionalProperties !== 'undefined') {
            const ap = tool.function.parameters.additionalProperties;
            if (ap !== true && ap !== false && (typeof ap !== 'object' || ap === null)) {
              json({
                error: {
                  message: `Invalid schema for function '${tool.function.name || 'unknown'}': ${JSON.stringify(ap)} is not of types "boolean", "object"`,
                  type: 'invalid_request_error'
                }
              }, res, 400);
              return;
            }
          }
        }
      }
      // Backend routing used by the web-search tool loop: DeepSeek native
      // search calls the /responses endpoint, Tavily the /search endpoint.
      // Both are answered from the real captured shapes — no real API calls
      // happen in the headless suite.
      if (req.url.includes('/responses')) {
        if (parsed.stream) {
          makeResponsesStreamHandler(parsed, opts)(req, res);
          return;
        }
        json(responsesSearchBody(opts), res);
        return;
      }
      if (req.url.endsWith('/search')) {
        json(tavilySearchBody(parsed, opts), res);
        return;
      }
      if (mode === 'drop') {
        req.socket.destroy();
        return;
      }
      if (mode === 'error-json') {
        json({ error: { message: 'invalid api key (mock)' } }, res, 401);
        return;
      }
      if (mode === 'json' || mode === 'title') {
        // FIM requests (createFIMRequest) post a `prompt` field; answer with
        // choices[0].text, which ResponseParser.ParseFIMResponse expects.
        if (parsed.prompt != null) {
          let fimText = opts.fimText || 'mock FIM fill';
          for (const entry of opts.fimTextMap || []) {
            if (String(parsed.prompt).includes(entry.match)) { fimText = entry.text; break; }
          }
          json({
            choices: [{ text: fimText }],
            model: 'deepseek-v4-flash'
          }, res);
          return;
        }
        const title = parsed.max_tokens === 50;
        json({
          choices: [{ message: { content: title ? 'Mock Auto Title' : (opts.chatText || 'Hello from the mock LLM (non-stream).') }, finish_reason: 'stop' }],
          model: 'deepseek-v4-flash',
          usage: { prompt_tokens: 8, completion_tokens: title ? 5 : 12, total_tokens: 20, prompt_tokens_details: { cached_tokens: 3 } }
        }, res);
        return;
      }
      if (mode === 'sse-script') {
        makeScriptedSseHandler(opts.script || [])(req, res);
        return;
      }
      if (mode === 'sse-tool-call') {
        makeToolCallSseHandler(parsed, opts)(req, res);
        return;
      }
      if (mode === 'sse-midfail') {
        // Partial content is delivered, then the connection dies before the
        // finish/usage chunk or [DONE] - the mid-stream failure case.
        res.writeHead(200, {
          'Content-Type': 'text/event-stream',
          'Cache-Control': 'no-cache',
          'Connection': 'keep-alive'
        });
        const delay = (ms) => new Promise((r) => setTimeout(r, ms));
        (async () => {
          sseChunk(res, { choices: [{ delta: { content: 'Partial answer before the connection died. ' } }] });
          await delay(120);
          // End the stream cleanly with an HTTP error body (realistic provider
          // failure after partial tokens) instead of a raw socket destroy,
          // which left cURL hanging in this environment.
          try { res.write(JSON.stringify({ error: { message: 'upstream error after partial content' } })); res.end(); } catch {}
        })().catch(() => { try { res.end(); } catch {} });
        return;
      }
      if (mode === 'sse-lateerror') {
        // Streaming-looking headers + keepalive, then a JSON error body after
        // a delay. The app's poll sees no content/reasoning before the cURL
        // exits, so _finalizeStreaming takes the error path (_handleStreamError)
        // - unlike sse-midfail, whose content chunk routes to the completion
        // handler. Used by scenario 216 to fail a retry AFTER a thread switch.
        res.writeHead(200, {
          'Content-Type': 'text/event-stream',
          'Cache-Control': 'no-cache',
          'Connection': 'keep-alive'
        });
        const delay = (ms) => new Promise((r) => setTimeout(r, ms));
        (async () => {
          res.write(': keepalive\n\n');
          await delay(opts.lateErrorDelay || 1500);
          try {
            res.write(JSON.stringify({ error: { message: 'late stream failure (mock)' } }));
            res.end();
          } catch {}
        })().catch(() => { try { res.end(); } catch {} });
        return;
      }
      if (mode === 'sse-slow') {
        makeSseHandler({ reasoning: true, content: 'yes', chunkDelay: 700, responseModel: opts.echoModel ? parsed.model : '' })(req, res);
        return;
      }
      if (mode === 'sse-error-event') {
        // A streaming response that delivers real content and then fails with
        // a proper SSE `data: {"error": ...}` event (the same shape OpenAI
        // sends when a stream errors after partial tokens).
        res.writeHead(200, {
          'Content-Type': 'text/event-stream',
          'Cache-Control': 'no-cache',
          'Connection': 'keep-alive'
        });
        const delay = (ms) => new Promise((r) => setTimeout(r, ms));
        (async () => {
          sseChunk(res, { choices: [{ delta: { content: 'Partial answer before the error event. ' } }] });
          await delay(150);
          res.write('data: {"error":{"message":"upstream exploded (mock)"}}\n\n');
          await delay(40);
          res.end();
        })().catch(() => { try { res.end(); } catch {} });
        return;
      }
      if (mode === 'sse-paragraphs') {
        // Summarize-style output: paragraphs separated by single \n (soft
        // breaks). markdown-it puts all of them in ONE <p>, and the app's CSS
        // collapses the soft breaks to spaces - the renderer loses the
        // paragraph structure the model returned.
        res.writeHead(200, {
          'Content-Type': 'text/event-stream',
          'Cache-Control': 'no-cache',
          'Connection': 'keep-alive'
        });
        const delay = (ms) => new Promise((r) => setTimeout(r, ms));
        (async () => {
          sseChunk(res, { choices: [{ delta: { content: 'First paragraph of the summary.\n' } }] });
          await delay(60);
          sseChunk(res, { choices: [{ delta: { content: 'Second paragraph of the summary.\n' } }] });
          await delay(60);
          sseChunk(res, { choices: [{ delta: { content: 'Third paragraph of the summary.' } }] });
          await delay(40);
          sseChunk(res, {
            choices: [{ delta: {}, finish_reason: 'stop' }],
            model: 'deepseek-v4-flash',
            usage: { prompt_tokens: 8, completion_tokens: 12, total_tokens: 20, prompt_tokens_details: { cached_tokens: 2 } }
          });
          await delay(40);
          res.write('data: [DONE]\n\n');
          res.end();
        })().catch(() => { try { res.end(); } catch {} });
        return;
      }
      if (mode === 'sse-hang') {
        res.writeHead(200, {
          'Content-Type': 'text/event-stream',
          'Cache-Control': 'no-cache',
          'Connection': 'keep-alive'
        });
        res.write(': keepalive\n\n');
        // Intentionally never end the stream - the app's stream poll has no
        // overall timeout, so this verifies the stuck-forever behavior.
        return;
      }
      if (mode === 'sse-split-line') {
        // One event whose JSON spans two writes with a gap larger than the
        // app's 100ms poll interval: the first poll reads
        // `data: {"choices":[{"delta":{"content":"SPLIT-LEFT"}},` (invalid
        // JSON -> SSEParser ignores it) and the next poll reads the bare
        // remainder `{"delta":{"content":"-RIGHT"}}]}` (no `data: ` prefix ->
        // ignored). The payload is silently lost. Normal chunks before/after
        // keep the stream non-empty and finalizable.
        res.writeHead(200, {
          'Content-Type': 'text/event-stream',
          'Cache-Control': 'no-cache',
          'Connection': 'keep-alive'
        });
        const delay = (ms) => new Promise((r) => setTimeout(r, ms));
        (async () => {
          sseChunk(res, { choices: [{ delta: { content: 'Hello from the mock LLM. ' } }] });
          await delay(150);
          res.write('data: {"choices":[{"delta":{"content":"SPLIT-LEFT"}},');
          // The partial line must sit in the output file across at least one
          // 100ms poll before the second half arrives.
          await delay(450);
          res.write('{"delta":{"content":"-RIGHT"}}]}\n\n');
          await delay(80);
          sseChunk(res, {
            choices: [{ delta: {}, finish_reason: 'stop' }],
            model: 'deepseek-v4-flash',
            usage: { prompt_tokens: 12, completion_tokens: 12, total_tokens: 24, prompt_tokens_details: { cached_tokens: 4 } }
          });
          await delay(40);
          res.write('data: [DONE]\n\n');
          res.end();
        })().catch(() => { try { res.end(); } catch {} });
        return;
      }
      if (mode === 'sse-success') {
        makeSseHandler({ reasoning: true, content: 'yes', chunkDelay: opts.chunkDelay || 60, responseModel: opts.echoModel ? parsed.model : '' })(req, res);
        return;
      }
      if (mode === 'sse-reasoning-only') {
        makeSseHandler({ reasoning: true, content: '' })(req, res);
        return;
      }
      json({ error: { message: 'unknown mock mode: ' + mode } }, res, 500);
    });
  });
  return new Promise((resolve) => {
    server.listen(0, '127.0.0.1', () => {
      resolve({ server, port: server.address().port });
    });
  });
}

module.exports = { startMockServer };
