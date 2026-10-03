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
  const context=vm.createContext(sandbox);
  vm.runInContext(fs.readFileSync(path.resolve(__dirname,'../../webui/js/api-log-preview.js'),'utf8'),context);
  vm.runInContext(loadViewerScript(), context);
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

describe('large payload previews', () => {
  it('omits string middles while preserving payload fields and the original request', () => {
    const text='START-'+ 'm'.repeat(15000) + '-END';
    const request=JSON.stringify({model:'example',stream:true,messages:[{role:'user',content:text}],tools:[{name:'search'}]});
    const {sandbox,els}=loadViewer([{request,response:'{}',endpoint:'https://example.test/inference'}]);
    sandbox.renderTable();
    assert.ok(els.logBody.innerHTML.includes('characters omitted from preview'));
    assert.ok(els.logBody.innerHTML.includes('START-') && els.logBody.innerHTML.includes('-END'));
    assert.ok(els.logBody.innerHTML.includes('search'));
    assert.equal(sandbox.logData[0].request,request);
    assert.equal(JSON.parse(sandbox.ApiLogPreview.format(request)).stream,true);
  });

  it('Copy retrieves full archived bodies without omission markers', async () => {
    const original=JSON.stringify({messages:[{content:'FULL-MIDDLE-'+ 'x'.repeat(12000)}]});
    const {sandbox}=loadViewer([{log_id:'one',request:'preview',request_archive:'retained-request',response:'{}',endpoint:'https://example.test/responses'}]);
    sandbox.window.chrome={webview:{hostObjects:{Logs:{}}}};
    sandbox.window.chrome.webview.hostObjects.Logs.GetBody=async name=>{assert.equal(name,'retained-request');return original;};
    let copied='';
    sandbox.navigator.clipboard.writeText=async value=>{copied=value;};
    await sandbox.cp(0,{textContent:'Copy',style:{}});
    assert.ok(copied.includes('FULL-MIDDLE-'));
    assert.ok(copied.includes('x'.repeat(12000)));
    assert.ok(copied.includes('POST https://example.test/responses'));
    assert.ok(!copied.includes('omitted from preview'));
  });
});
