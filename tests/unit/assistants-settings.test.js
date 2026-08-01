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
  const grid = { innerHTML: '', appendChild: (c) => { cards.push(c); } };
  let registered = null;

  // Parse a bare <option> list. Options without an explicit value attribute
  // use their text, like a real <select>.
  function parseOptionList(source) {
    const opts = [];
    const re = /<option([^>]*)>([\s\S]*?)<\/option>/g;
    let m;
    while ((m = re.exec(source || '')) !== null) {
      const attrs = m[1] || '';
      const text = m[2].replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"');
      const vm = attrs.match(/value="([^"]*)"/);
      opts.push({ value: vm ? vm[1] : text });
    }
    return opts;
  }

  // Options come either from a <select data-field="..."> block inside the card
  // HTML, or from a bare option list once the change handler replaces the
  // Reasoning select's innerHTML.
  function parseSelectOptions(html, field) {
    const block = html.match(new RegExp('<select data-field="' + field + '">([\\s\\S]*?)</select>'));
    return parseOptionList(block ? block[1] : html);
  }

  // A select whose options live inside the card HTML (until the change
  // handler replaces the Reasoning select's innerHTML, like a real DOM).
  function makeSelect(field, cardEl) {
    let html = '';
    let selectedIndex = 0;
    const handlers = {};
    const sel = {
      dataset: { field: field },
      addEventListener: function(type, fn) { (handlers[type] = handlers[type] || []).push(fn); },
      _fire: function(type) { (handlers[type] || []).forEach(function(fn) { fn.call(sel); }); },
      get innerHTML() { return html; },
      set innerHTML(h) { html = h; },
      get options() { return parseSelectOptions(html || cardEl.innerHTML, field); },
      get selectedIndex() { return selectedIndex; },
      set selectedIndex(i) { selectedIndex = i; },
      get value() { const o = this.options; return o[selectedIndex] ? o[selectedIndex].value : ''; },
      set value(v) {
        const o = this.options;
        selectedIndex = -1;
        for (let i = 0; i < o.length; i++) {
          if (o[i].value === v) { selectedIndex = i; break; }
        }
      }
    };
    return sel;
  }

  const sandbox = {
    document: {
      getElementById: (id) => (id === 'assistantGrid' ? grid : null),
      createElement: (tag) => {
        const el = {
          tagName: tag,
          dataset: {},
          innerHTML: '',
          appendChild: () => {},
          addEventListener: () => {},
          remove: () => {},
          classList: { add: () => {}, remove: () => {}, contains: () => false, toggle: () => {} }
        };
        const baseSel = makeSelect('baseModel', el);
        const reasoningSel = makeSelect('reasoning', el);
        el.querySelectorAll = (sel) => {
          if (sel === 'select' || sel === 'input, select') return [baseSel, reasoningSel];
          if (sel === '.switch') return [];
          return [];
        };
        el.querySelector = (sel) => {
          if (sel === 'select[data-field="baseModel"]') return baseSel;
          if (sel === 'select[data-field="reasoning"]') return reasoningSel;
          if (sel === '.btn-sm.danger' || sel === '.edit-sysmsg') return { addEventListener: () => {} };
          return null;
        };
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

  it('keeps the Reasoning level when the base model changes to one that still supports it', () => {
    const { registered, cards } = loadModule();
    const models = {
      'openai/gpt-4o': { thinkingLevelMap: { low: 'LOW', medium: 'MEDIUM', high: 'HIGH' } },
      'google/gemini-2.5-flash': { thinkingLevelMap: { minimal: 'MINIMAL', low: 'LOW', high: 'HIGH' } }
    };
    const assistants = [{ id: 'a1', name: 'A', baseModel: 'openai/gpt-4o', reasoning: 'high', systemMessage: '', isDefault: false }];
    registered.load({ assistants: assistants, models: models });

    assert.strictEqual(cards.length, 1);
    const card = cards[0];
    const baseSel = card.querySelector('select[data-field="baseModel"]');
    const reasoningSel = card.querySelector('select[data-field="reasoning"]');
    assert.strictEqual(reasoningSel.value, 'high', 'card starts with its saved reasoning level');

    // User picks a different base model; the change handler must keep the
    // selected level when the new model still supports it.
    baseSel.value = 'google/gemini-2.5-flash';
    baseSel._fire('change');
    assert.strictEqual(reasoningSel.value, 'high', 'a still-supported level must not reset to Model Default');
  });

  it('falls back to Model Default when the new base model does not support the selected level', () => {
    const { registered, cards } = loadModule();
    const models = {
      'openai/gpt-4o': { thinkingLevelMap: { low: 'LOW', medium: 'MEDIUM', high: 'HIGH' } },
      'google/gemini-2.5-flash': { thinkingLevelMap: { minimal: 'MINIMAL', low: 'LOW', high: 'HIGH' } }
    };
    const assistants = [{ id: 'a1', name: 'A', baseModel: 'openai/gpt-4o', reasoning: 'medium', systemMessage: '', isDefault: false }];
    registered.load({ assistants: assistants, models: models });

    const card = cards[0];
    const baseSel = card.querySelector('select[data-field="baseModel"]');
    const reasoningSel = card.querySelector('select[data-field="reasoning"]');
    assert.strictEqual(reasoningSel.value, 'medium', 'card starts with its saved reasoning level');

    // 'medium' is supported by gpt-4o but not by gemini.
    baseSel.value = 'google/gemini-2.5-flash';
    baseSel._fire('change');
    assert.strictEqual(reasoningSel.value, '', 'an unsupported level must fall back to Model Default');
  });
});
