// assistants-settings.test.js — Unit tests for the assistants settings reasoning dropdown
//
// Regression: the Reasoning dropdown must only offer levels the base model
// actually supports (from its thinkingLevelMap), sorted least → most thinking.
// Before this fix it was a hardcoded list, which allowed configuring invalid
// values (e.g. "none" on a gemma model that doesn't support it), causing a
// thinking config to be sent even though the sidebar displayed "Model Default".
const { describe, it } = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

function loadModule() {
  const helperSrc = fs.readFileSync(path.resolve(__dirname, '..', '..', 'webui', 'js', 'settings', 'reasoning-levels.js'), 'utf-8');
  const src = fs.readFileSync(path.resolve(__dirname, '..', '..', 'webui', 'js', 'settings', 'sections', 'assistants.js'), 'utf-8');
  const cards = [];
  const noopEl = () => ({
    addEventListener: () => {}, value: '', innerHTML: '', options: [], selectedIndex: 0,
    classList: { add: () => {}, remove: () => {}, contains: () => false, toggle: () => {} }
  });
  const grid = { innerHTML: '', appendChild: (c) => { cards.push(c); } };
  let registered = null;
  const sandbox = {
    document: {
      getElementById: (id) => (id === 'assistantGrid' ? grid : null),
      createElement: (tag) => {
        const el = noopEl();
        el.tagName = tag;
        el.dataset = {};
        el.appendChild = () => {};
        el.querySelectorAll = () => [];
        el.querySelector = () => noopEl();
        return el;
      },
      addEventListener: () => {}
    },
    window: { SettingsPanel: { registerSection: (name, api) => { registered = api; }, markDirty: () => {} } },
    console: console,
    setTimeout: () => {},
    clearTimeout: () => {}
  };
  sandbox.global = sandbox;
  const context = vm.createContext(sandbox);
  vm.runInContext(helperSrc, context); // ReasoningLevels must load before assistants.js
  vm.runInContext(src, context);
  return { registered, cards };
}

function reasoningSelectHtml(cardHtml) {
  // Extract the contents of the Reasoning <select> block from the card HTML.
  const m = cardHtml.match(/<select data-field="reasoning">([\s\S]*?)<\/select>/);
  return m ? m[1] : '';
}

describe('assistants.js reasoning dropdown', () => {
  it('offers only the levels the base model supports', () => {
    const { registered, cards } = loadModule();
    const models = {
      'google/gemma-4-31b-it': { thinkingLevelMap: { minimal: 'MINIMAL', low: 'LOW', medium: 'MEDIUM', high: 'HIGH' } },
      'deepseek/deepseek-v4-pro': { thinkingLevelMap: { high: 'high', max: 'max' } }
    };
    const assistants = [{ id: 'violet', name: 'Violet', baseModel: 'google/gemma-4-31b-it', reasoning: 'none', systemMessage: '', isDefault: false }];

    registered.load({ assistants: assistants, models: models });

    assert.ok(cards.length === 1, 'expected one rendered assistant card');
    const html = reasoningSelectHtml(cards[0].innerHTML);
    assert.ok(html.indexOf('<option value="">Model Default</option>') >= 0, 'Model Default option must be present');
    assert.ok(html.indexOf('<option value="minimal">Minimal</option>') >= 0, 'gemma minimal level must be offered');
    assert.ok(html.indexOf('<option value="high">High</option>') >= 0, 'gemma high level must be offered');
    assert.ok(html.indexOf('<option value="none">') < 0, '"none" must NOT be offered for gemma (unsupported)');
  });

  it('falls back to the common list when model metadata is missing', () => {
    const { registered, cards } = loadModule();
    const assistants = [{ id: 'a1', name: 'A', baseModel: 'unknown/model', reasoning: '', systemMessage: '', isDefault: false }];

    registered.load({ assistants: assistants, models: null });

    assert.ok(cards.length === 1);
    const html = reasoningSelectHtml(cards[0].innerHTML);
    assert.ok(html.indexOf('<option value="none">') >= 0, 'fallback list should still offer none/minimal/low/medium/high');
    assert.ok(html.indexOf('<option value="high">') >= 0);
  });

  it('sorts levels least to most thinking like the chat sidebar', () => {
    const { registered, cards } = loadModule();
    // Deliberately out of order to prove sorting is applied.
    const models = {
      'openai/gpt-5.1': { thinkingLevelMap: { max: 'max', low: 'low', none: 'none', xhigh: 'xhigh', medium: 'medium', minimal: 'minimal', high: 'high' } }
    };
    const assistants = [{ id: 'a1', name: 'A', baseModel: 'openai/gpt-5.1', reasoning: '', systemMessage: '', isDefault: false }];

    registered.load({ assistants: assistants, models: models });

    assert.ok(cards.length === 1);
    const html = reasoningSelectHtml(cards[0].innerHTML);
    const expectedOrder = ['none', 'minimal', 'low', 'medium', 'high', 'xhigh', 'max'];
    let lastIndex = -1;
    expectedOrder.forEach(function(level) {
      const idx = html.indexOf('<option value="' + level + '">');
      assert.ok(idx >= 0, 'level ' + level + ' should be offered');
      assert.ok(idx > lastIndex, 'level ' + level + ' should appear after the previous (least to most)');
      lastIndex = idx;
    });
  });
});
