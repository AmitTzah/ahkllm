// api-logs-viewer.test.js — Regression test for webui/api-logs.html
//
// Bug: the viewer rendered the latency column from entry.latencyMs, but every
// logger writes responseTimeMs — so the column always showed "-". The viewer
// must render the field the loggers actually write.
const { describe, it } = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

function loadViewerScript() {
  const html = fs.readFileSync(path.resolve(__dirname, '..', '..', 'webui', 'api-logs.html'), 'utf-8');
  const m = html.match(/<script>([\s\S]*?)<\/script>/);
  assert.ok(m, 'inline viewer script must exist');
  return m[1];
}

function makeEl(overrides = {}) {
  return Object.assign({
    style: {},
    innerHTML: '',
    textContent: '',
    querySelectorAll: () => []
  }, overrides);
}

function loadViewer(logData) {
  const els = {
    logTable: makeEl(),
    emptyState: makeEl(),
    logBody: makeEl(),
    entryCount: makeEl()
  };
  const sandbox = {
    document: { getElementById: (id) => els[id] || null },
    window: { addEventListener: () => {} },
    navigator: { clipboard: { writeText: async () => {} } },
    setTimeout: () => {},
    console
  };
  sandbox.global = sandbox;
  vm.runInContext(loadViewerScript(), vm.createContext(sandbox));
  sandbox.logData = logData;
  return { sandbox, els };
}

describe('API Logs viewer latency column', () => {
  it('renders responseTimeMs (the field loggers write), not latencyMs', () => {
    const { sandbox, els } = loadViewer([
      {
        timestamp: '2026-08-02 10:00:00',
        commandName: 'Chat',
        model: 'deepseek/deepseek-v4-flash',
        status: 'success',
        endpoint: 'http://127.0.0.1:9999/v1/chat/completions',
        responseTimeMs: 1672,
        request: '{}',
        response: '{}'
      }
    ]);
    sandbox.renderTable();
    const html = els.logBody.innerHTML;
    assert.ok(html.indexOf('1.7 s') >= 0, 'latency cell should format responseTimeMs, got: ' + html);
    assert.ok(html.indexOf('latencyMs') < 0, 'viewer must not read latencyMs');
  });

  it('shows "-" only when responseTimeMs is absent', () => {
    const { sandbox, els } = loadViewer([
      { timestamp: 't', commandName: 'c', model: 'm', status: 'success', endpoint: 'e', request: '{}', response: '{}' }
    ]);
    sandbox.renderTable();
    assert.ok(els.logBody.innerHTML.indexOf('>-</td>') >= 0, 'missing duration should render "-"');
  });
});

describe('esc', () => {
  it('escapes single quotes (bug #84)', () => {
    const { sandbox } = loadViewer([]);
    assert.strictEqual(sandbox.esc("a'b"), 'a&#39;b');
  });

  it('escapes angle brackets, ampersands and double quotes', () => {
    const { sandbox } = loadViewer([]);
    assert.strictEqual(sandbox.esc('<b title="x">a&b</b>'), '&#60;b title=&#34;x&#34;&#62;a&#38;b&#60;/b&#62;');
  });
});
