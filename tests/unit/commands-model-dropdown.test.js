// commands-model-dropdown.test.js — The command "API Model" field is a dropdown
// populated from the available models map (not a free-text input), so users pick
// from known models. Custom/unlisted values already saved on a command must be
// preserved (prepended as an option) instead of silently dropped on save.
const { describe, it } = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

function loadModules() {
  const helperSrc = fs.readFileSync(path.resolve(__dirname, '..', '..', 'webui', 'js', 'settings', 'reasoning-levels.js'), 'utf-8');
  const coreSrc = fs.readFileSync(path.resolve(__dirname, '..', '..', 'webui', 'js', 'settings', 'sections', 'commands', 'commands-core.js'), 'utf-8');
  const renderSrc = fs.readFileSync(path.resolve(__dirname, '..', '..', 'webui', 'js', 'settings', 'sections', 'commands', 'commands-render.js'), 'utf-8');

  let formValues = {};
  let thinkingOptionsHtml = '';
  let detailHtml = '';
  let apiModelChangeHandler = null;

  function makeEl() {
    return {
      value: '',
      innerHTML: '',
      style: {},
      addEventListener: function() {},
      querySelectorAll: function() { return []; },
      querySelector: function() { return null; },
      classList: {
        _classes: [],
        add: function(c) { if (this._classes.indexOf(c) < 0) this._classes.push(c); },
        remove: function(c) { this._classes = this._classes.filter(function(x) { return x !== c; }); },
        contains: function(c) { return this._classes.indexOf(c) >= 0; },
        toggle: function(c) { if (this.contains(c)) this.remove(c); else this.add(c); }
      }
    };
  }

  const sandbox = {
    document: {
      body: {},
      getElementById: function(id) {
        if (id === 'cmdThinking') {
          return {
            get value() { return formValues['cmdThinking'] !== undefined ? formValues['cmdThinking'] : ''; },
            set value(v) { formValues['cmdThinking'] = v; },
            set innerHTML(html) { thinkingOptionsHtml = html; },
            get innerHTML() { return thinkingOptionsHtml; }
          };
        }
        if (id === 'cmdDetail') {
          return {
            style: {},
            set innerHTML(html) { detailHtml = html; },
            get innerHTML() { return detailHtml; },
            querySelectorAll: function() { return []; },
            querySelector: function() { return null; }
          };
        }
        if (id === 'cmdApiModel') {
          return {
            get value() { return formValues['cmdApiModel'] !== undefined ? formValues['cmdApiModel'] : ''; },
            set value(v) { formValues['cmdApiModel'] = v; },
            innerHTML: '',
            style: {},
            addEventListener: function(type, fn) {
              if (type === 'change') apiModelChangeHandler = fn;
            },
            querySelectorAll: function() { return []; },
            querySelector: function() { return null; }
          };
        }
        return {
          value: formValues[id] !== undefined ? formValues[id] : '',
          innerHTML: '',
          style: {},
          addEventListener: function() {},
          querySelectorAll: function() { return []; },
          querySelector: function() { return null; },
          classList: {
            _classes: [],
            add: function(c) { if (this._classes.indexOf(c) < 0) this._classes.push(c); },
            remove: function(c) { this._classes = this._classes.filter(function(x) { return x !== c; }); },
            contains: function(c) { return this._classes.indexOf(c) >= 0; },
            toggle: function(c) { if (this.contains(c)) this.remove(c); else this.add(c); }
          },
          textContent: formValues[id + '_text'] || ''
        };
      },
      querySelectorAll: function() { return []; },
      querySelector: function() { return null; },
      addEventListener: function() {},
      createElement: function() { return { style: {} }; }
    },
    window: { Cmds: {}, SettingsPanel: { markDirty: function() {}, registerSection: function() {} } },
    console: console,
    setTimeout: setTimeout,
    clearTimeout: clearTimeout
  };
  sandbox.global = sandbox;
  const ctx = vm.createContext(sandbox);
  vm.runInContext(helperSrc, ctx);
  vm.runInContext(coreSrc, ctx);
  vm.runInContext(renderSrc, ctx);
  const C = sandbox.window.Cmds;
  // Stub DOM-touching functions so tests can drive the real logic.
  C.renderList = function() {};
  C.showPlaceholder = function() {};
  return {
    Cmds: C,
    formValues: formValues,
    getDetailHtml: function() { return detailHtml; },
    getThinkingOptionsHtml: function() { return thinkingOptionsHtml; },
    fireApiModelChange: function() {
      if (apiModelChangeHandler) apiModelChangeHandler.call({ value: formValues['cmdApiModel'] || '' });
    }
  };
}

// Extract the API Model <select> block from the rendered detail HTML.
function apiModelSelectHtml(detailHtml) {
  var m = detailHtml.match(/<select id="cmdApiModel"[^>]*>([\s\S]*?)<\/select>/);
  return m ? m[0] : '';
}

// Extract option values from a <select> block.
function optionValues(selectHtml) {
  var out = [];
  var re = /<option value="([^"]*)"([^>]*)>/g;
  var m;
  while ((m = re.exec(selectHtml)) !== null) out.push(m[1]);
  return out;
}

describe('commands API Model dropdown', () => {
  it('renders API Model as a <select> populated with every available model', () => {
    const ctx = loadModules();
    const C = ctx.Cmds;
    const models = {
      'deepseek/deepseek-v4-flash': { provider: 'deepseek' },
      'openai/gpt-4o': { provider: 'openai' },
      'google/gemini-2.5-flash': { provider: 'google' }
    };
    C.load({ commands: [{ commandName: 'A', menuText: 'A', APIModels: 'openai/gpt-4o' }], models: models, ui: {} });

    const detail = ctx.getDetailHtml();
    const selectHtml = apiModelSelectHtml(detail);
    assert.ok(selectHtml, 'detail must contain an API Model <select>');
    assert.ok(detail.indexOf('id="cmdApiModel"') >= 0, 'API Model element must be present');
    assert.ok(detail.indexOf('input type="text" id="cmdApiModel"') < 0, 'API Model must NOT be a free-text input');

    const values = optionValues(selectHtml);
    // Sorted model keys + leading "Default" entry
    assert.strictEqual(values[0], '', 'first option must be the empty Default entry');
    assert.ok(values.indexOf('deepseek/deepseek-v4-flash') >= 0, 'deepseek model must be listed');
    assert.ok(values.indexOf('openai/gpt-4o') >= 0, 'openai model must be listed');
    assert.ok(values.indexOf('google/gemini-2.5-flash') >= 0, 'google model must be listed');
    // Sorted order: deepseek < google < openai
    assert.ok(values.indexOf('deepseek/deepseek-v4-flash') < values.indexOf('google/gemini-2.5-flash'), 'models must be sorted');
    assert.ok(values.indexOf('google/gemini-2.5-flash') < values.indexOf('openai/gpt-4o'), 'models must be sorted');
  });

  it('pre-selects the command\u2019s current model in the dropdown', () => {
    const ctx = loadModules();
    const C = ctx.Cmds;
    const models = { 'deepseek/deepseek-v4-flash': {}, 'openai/gpt-4o': {} };
    C.load({ commands: [{ commandName: 'A', menuText: 'A', APIModels: 'openai/gpt-4o' }], models: models, ui: {} });

    const selectHtml = apiModelSelectHtml(ctx.getDetailHtml());
    assert.ok(/<option value="openai\/gpt-4o" selected>/.test(selectHtml),
      'the command\u2019s current model option must carry the selected attribute');
  });

  it('preserves an unlisted/custom model value by prepending it as an option', () => {
    const ctx = loadModules();
    const C = ctx.Cmds;
    const models = { 'openai/gpt-4o': {} };
    // 'my-custom-model' is not in the models map — it must not be dropped.
    C.load({ commands: [{ commandName: 'A', menuText: 'A', APIModels: 'my-custom-model' }], models: models, ui: {} });

    const selectHtml = apiModelSelectHtml(ctx.getDetailHtml());
    const values = optionValues(selectHtml);
    assert.ok(values.indexOf('my-custom-model') >= 0, 'custom model value must be preserved as an option');
    assert.ok(/<option value="my-custom-model" selected>/.test(selectHtml),
      'custom model value must be the selected option');
  });

  it('falls back to Default entry when the command has no model', () => {
    const ctx = loadModules();
    const C = ctx.Cmds;
    const models = { 'openai/gpt-4o': {} };
    C.load({ commands: [{ commandName: 'A', menuText: 'A', APIModels: '' }], models: models, ui: {} });

    const selectHtml = apiModelSelectHtml(ctx.getDetailHtml());
    assert.ok(/<option value="" selected>/.test(selectHtml), 'Default entry must be selected when model is empty');
  });

  it('saves the selected dropdown value back to the command', () => {
    const ctx = loadModules();
    const C = ctx.Cmds;
    C.load({ commands: [{ commandName: 'A', menuText: 'A', APIModels: '' }], models: { 'openai/gpt-4o': {} }, ui: {} });
    // User picks a model from the dropdown; syncDetail reads the select value.
    ctx.formValues['cmdApiModel'] = 'openai/gpt-4o';
    C.syncDetail(0);
    assert.strictEqual(C.commands()[0].APIModels, 'openai/gpt-4o');
  });

  it('rebuilds the Thinking dropdown when the selected model changes', () => {
    const ctx = loadModules();
    const C = ctx.Cmds;
    const models = {
      'openai/gpt-4o': { thinkingLevelMap: { low: 'LOW', medium: 'MEDIUM', high: 'HIGH' } },
      'google/gemini-2.5-flash': { thinkingLevelMap: { minimal: 'MINIMAL', low: 'LOW', high: 'HIGH' } }
    };
    C.load({ commands: [{ commandName: 'A', menuText: 'A', APIModels: 'openai/gpt-4o' }], models: models, ui: {} });

    // Initial thinking options reflect the command's saved model (gpt-4o).
    const initial = ctx.getThinkingOptionsHtml();
    assert.ok(initial.indexOf('value="medium"') >= 0, 'gpt-4o supports a medium thinking level');

    // User picks a different model from the dropdown; the change handler must
    // rebuild the Thinking dropdown to that model's supported levels.
    ctx.formValues['cmdApiModel'] = 'google/gemini-2.5-flash';
    ctx.fireApiModelChange();
    const updated = ctx.getThinkingOptionsHtml();
    assert.ok(updated.indexOf('value="minimal"') >= 0, 'gemini must offer its minimal thinking level after change');
    assert.ok(updated.indexOf('value="medium"') < 0, 'gemini does not support medium — it must not be offered after change');
    assert.ok(updated.indexOf('Model Default') >= 0, 'thinking dropdown must include Model Default');
  });
});
