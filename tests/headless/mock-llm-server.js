// mock-llm-server.js — Local fake LLM endpoint (OpenAI-compatible).
// Modes:
//   sse-success        streaming: reasoning + content + usage + [DONE]
//   sse-reasoning-only streaming: reasoning only, empty content
//   json               non-stream chat completion
//   title              non-stream short title response (max_tokens 50)
//   sse-script         streaming with a custom chunk script (opts.script)
//   sse-midfail        streaming: one content chunk, then the socket is
//                      destroyed before [DONE] (mid-stream connection failure)
//   sse-slow           streaming like sse-success but with ~700ms delays per
//                      chunk (total ~3s) so scenarios can act mid-stream
//   sse-hang           streaming headers + a keepalive comment, then the
//                      socket is left OPEN forever - the "stalled stream"
//                      case (cURL has --connect-timeout but no --max-time)
//   sse-split-line     streaming: one SSE event whose `data:` LINE is written
//                      in TWO writes with a >poll-interval delay between, so
//                      the app's 100ms stream poll consumes the partial line
//                      and then ignores the bare remainder (the bug hunt's
//                      "data line split across poll boundaries" case)
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
        model: 'deepseek-v4-flash',
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

// startMockServer(mode, logFile, opts)
//   opts.chatText  - content used by the JSON chat response.
//   opts.fimText   - choices[0].text used when the JSON body carries a
//                    FIM `prompt` field (FIM requests land on the same URL).
//   opts.fimTextMap - [{ match, text }] picked by substring against the FIM
//                    prompt, first match wins; falls back to opts.fimText.
//   opts.script    - chunk script for mode 'sse-script'.
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
          fs.appendFileSync(logFile, JSON.stringify({ modeUsed, body: parsed }) + '\n');
        } catch {}
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
      if (mode === 'sse-slow') {
        makeSseHandler({ reasoning: true, content: 'yes', chunkDelay: 700 })(req, res);
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
        makeSseHandler({ reasoning: true, content: 'yes' })(req, res);
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
