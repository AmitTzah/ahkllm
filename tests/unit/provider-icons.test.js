// provider-icons.test.js — provider transport must win over model-vendor heuristics
const { describe, it } = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

function loadProviderIcons() {
  const src = fs.readFileSync(path.resolve(__dirname, '..', '..', 'webui', 'js', 'chat', 'provider-icons.js'), 'utf8');
  const sandbox = { window: {}, Number, String };
  vm.runInContext(src, vm.createContext(sandbox));
  return sandbox.window.ProviderIcons;
}

describe('ProviderIcons', () => {
  it('uses the outer OpenRouter transport for nested model ids', () => {
    const icons = loadProviderIcons();
    assert.strictEqual(icons.key('openrouter/openai/gpt-5.6-sol'), 'openrouter');
    assert.ok(icons.file('openrouter/anthropic/claude-sonnet').endsWith('openrouter.ico'));
  });

  it('lets an explicit provider override model-name heuristics', () => {
    const icons = loadProviderIcons();
    assert.strictEqual(icons.key('claude-sonnet-4', 'openrouter'), 'openrouter');
    assert.ok(icons.html('gpt-5.6-sol', 'openrouter', 18).includes('openrouter.ico'));
  });

  it('keeps normal direct-provider icons unchanged', () => {
    const icons = loadProviderIcons();
    assert.strictEqual(icons.key('openai/gpt-5.6-sol'), 'openai');
    assert.strictEqual(icons.key('google/gemini-2.5-flash'), 'google');
    assert.strictEqual(icons.key('anthropic/claude-sonnet-4'), 'anthropic');
  });
});


describe('provider icon script order', () => {
  it('loads before model-picker consumers in index.html', () => {
    const html = fs.readFileSync(path.resolve(__dirname, '..', '..', 'webui', 'index.html'), 'utf8');
    const helperPos = html.indexOf('js/chat/provider-icons.js');
    const pickerPos = html.indexOf('js/chat/model-picker/model-picker.js');
    assert.ok(helperPos >= 0 && pickerPos > helperPos, 'provider-icons.js must load before model-picker.js');
  });
});


describe('provider icon visual sizing', () => {
  it('gives plain provider icons the same outer footprint as padded OpenRouter badges', () => {
    const icons = loadProviderIcons();
    const direct = icons.style('openai/gpt-5.6-sol', 'openai', 20);
    const routed = icons.style('gpt-5.6-sol', 'openrouter', 20);
    assert.ok(direct.includes('width:24px;height:24px'), direct);
    assert.ok(routed.includes('width:20px;height:20px'), routed);
    assert.ok(routed.includes('padding:2px'), routed);
  });
});
