// reasoning-levels.test.js — Unit tests for the shared ReasoningLevels helper.
//
// Single source of truth for reasoning-level labels and least→most ordering,
// used by the chat sidebar, assistant settings, commands, and thread-title
// generation. Regression: options are model-scoped (no unsupported levels) and
// sorted least → most thinking.
const { describe, it } = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

function loadHelper() {
  const src = fs.readFileSync(path.resolve(__dirname, '..', '..', 'webui', 'js', 'settings', 'reasoning-levels.js'), 'utf-8');
  const sandbox = { window: {} };
  sandbox.global = sandbox;
  vm.runInContext(src, vm.createContext(sandbox));
  return sandbox.window.ReasoningLevels;
}

describe('ReasoningLevels helper', () => {
  it('labels levels', () => {
    const RL = loadHelper();
    assert.strictEqual(RL.label('none'), 'None (Disabled)');
    assert.strictEqual(RL.label('minimal'), 'Minimal');
    assert.strictEqual(RL.label('high'), 'High');
    assert.strictEqual(RL.label('max'), 'Max');
    assert.strictEqual(RL.label('unknown'), 'unknown');
  });

  it('sorts levels least to most thinking', () => {
    const RL = loadHelper();
    const sorted = RL.sortLevels(['max', 'low', 'none', 'xhigh', 'medium', 'minimal', 'high']);
    assert.strictEqual(JSON.stringify(sorted), JSON.stringify(['none', 'minimal', 'low', 'medium', 'high', 'xhigh', 'max']));
  });

  it('builds options for a model, excluding unsupported levels', () => {
    const RL = loadHelper();
    const models = { 'google/gemma-4-31b-it': { thinkingLevelMap: { minimal: 'MINIMAL', low: 'LOW', medium: 'MEDIUM', high: 'HIGH' } } };
    const html = RL.buildOptionsHtml(models, 'google/gemma-4-31b-it');
    assert.ok(html.indexOf('<option value="">Model Default</option>') >= 0, 'Model Default must be present');
    assert.ok(html.indexOf('<option value="none">') < 0, '"none" must not be offered for gemma');
    assert.ok(html.indexOf('<option value="high">High</option>') >= 0, 'gemma high must be offered');
  });

  it('builds labeled + sorted options from raw values (chat sidebar path)', () => {
    const RL = loadHelper();
    const html = RL.buildOptionsHtmlForValues(['high', 'minimal', 'low']);
    assert.ok(html.indexOf('<option value="">Model Default</option>') >= 0);
    assert.ok(html.indexOf('<option value="minimal">Minimal</option>') >= 0);
    assert.ok(html.indexOf('<option value="high">High</option>') >= 0);
    const idxMinimal = html.indexOf('<option value="minimal">');
    const idxLow = html.indexOf('<option value="low">');
    const idxHigh = html.indexOf('<option value="high">');
    assert.ok(idxMinimal < idxLow && idxLow < idxHigh, 'options must be sorted least → most thinking');
  });
});
