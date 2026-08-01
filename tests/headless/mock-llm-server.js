// mock-llm-server.js — Local fake LLM endpoint (OpenAI-compatible).
// Modes:
//   sse-success        streaming: reasoning + content + usage + [DONE]
//   sse-reasoning-only streaming: reasoning only, empty content
//   json               non-stream chat completion
//   title              non-stream short title response (max_tokens 50)
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
    (async () => {
      if (opts.reasoning !== false) {
        sseChunk(res, { choices: [{ delta: { reasoning_content: 'Let me reason about this step by step. ' } }] });
        await delay(60);
        sseChunk(res, { choices: [{ delta: { reasoning_content: 'First, gather the facts. ' } }] });
        await delay(60);
      }
      if (opts.content !== '') {
        sseChunk(res, { choices: [{ delta: { content: 'Hello from the mock LLM. ' } }] });
        await delay(60);
        sseChunk(res, { choices: [{ delta: { content: 'This is the streamed answer.' } }] });
        await delay(60);
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

function startMockServer(mode = 'sse-success', logFile = '') {
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
        const title = parsed.max_tokens === 50;
        json({
          choices: [{ message: { content: title ? 'Mock Auto Title' : 'Hello from the mock LLM (non-stream).' }, finish_reason: 'stop' }],
          model: 'deepseek-v4-flash',
          usage: { prompt_tokens: 8, completion_tokens: title ? 5 : 12, total_tokens: 20, prompt_tokens_details: { cached_tokens: 3 } }
        }, res);
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
