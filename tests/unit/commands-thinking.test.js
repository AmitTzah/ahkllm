// commands-thinking.test.js — Regression tests for the commands Thinking dropdown.
//
// A single model-scoped dropdown (Model Default + the model's supported levels,
// like the chat sidebar / assistant settings) replaces the old type+level pair.
// Selecting a normal level saves as {type:'enabled', level}; selecting "none"
// saves as {type:'disabled', level:'none'}; "Model Default" saves as no config.
// The options only include levels the command's model actually supports.
const { describe, it } = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

function loadModules() {
  const helperSrc = fs.readFileSync(path.resolve(__dirname, '..', '..', 'webui', 'js', 'shared', 'reasoning-levels.js'), 'utf-8');
  const sharedSrc = fs.readFileSync(path.resolve(__dirname, '..', '..', 'webui', 'js', 'shared', 'settings-shared.js'), 'utf-8');
  const coreSrc = fs.readFileSync(path.resolve(__dirname, '..', '..', 'webui', 'js', 'settings', 'sections', 'commands', 'commands-core.js'), 'utf-8');
  const actionsSrc = fs.readFileSync(path.resolve(__dirname, '..', '..', 'webui', 'js', 'settings', 'sections', 'commands', 'commands-actions.js'), 'utf-8');
  const renderSrc = fs.readFileSync(path.resolve(__dirname, '..', '..', 'webui', 'js', 'settings', 'sections', 'commands', 'commands-render.js'), 'utf-8');

  let formValues = {};
  let thinkingOptionsHtml = '';

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
  vm.runInContext(sharedSrc, ctx);
  vm.runInContext(coreSrc, ctx);
  vm.runInContext(actionsSrc, ctx);
  vm.runInContext(renderSrc, ctx);
  const C = sandbox.window.Cmds;
  // Stub DOM-touching functions so tests can drive the real logic.
  C.renderList = function() {};
  C.showPlaceholder = function() {};
  return { Cmds: C, formValues: formValues, getThinkingOptionsHtml: function() { return thinkingOptionsHtml; } };
}

describe('commands thinking dropdown', () => {
  it('offers only the levels the command model supports (no "none" for gemma)', () => {
    const ctx = loadModules();
    const C = ctx.Cmds;
    const models = {
      'google/gemma-4-31b-it': { thinkingLevelMap: { minimal: 'MINIMAL', low: 'LOW', medium: 'MEDIUM', high: 'HIGH' } }
    };
    // load() renders the first command, which populates the Thinking dropdown.
    C.load({ commands: [{ commandName: 'G', menuText: 'G', APIModels: 'google/gemma-4-31b-it' }], models: models, ui: {} });

    const html = ctx.getThinkingOptionsHtml();
    assert.ok(html.indexOf('<option value="">Model Default</option>') >= 0, 'Model Default option must be present');
    assert.ok(html.indexOf('<option value="minimal">Minimal</option>') >= 0, 'gemma minimal level must be offered');
    assert.ok(html.indexOf('<option value="high">High</option>') >= 0, 'gemma high level must be offered');
    assert.ok(html.indexOf('<option value="none">') < 0, '"none" must NOT be offered for gemma (unsupported)');
  });

  it('saves a selected level as {type:"enabled", level}', () => {
    const ctx = loadModules();
    const C = ctx.Cmds;
    C.load({ commands: [{ commandName: 'C', menuText: 'C' }], models: null, ui: {} });
    ctx.formValues['cmdThinking'] = 'high';
    C.syncDetail(0);
    const thinking = C.commands()[0].thinking;
    assert.strictEqual(thinking.type, 'enabled');
    assert.strictEqual(thinking.level, 'high');
  });

  it('loads and saves None as an explicit disabled command setting', () => {
    const ctx = loadModules();
    const C = ctx.Cmds;
    const models = {
      'openai/gpt-test': { thinkingLevelMap: { none: 'none', low: 'low', high: 'high' } }
    };
    C.load({
      commands: [{ commandName: 'C', menuText: 'C', APIModels: 'openai/gpt-test', thinking: { type: 'disabled', level: 'none' } }],
      models: models,
      ui: {}
    });
    assert.strictEqual(ctx.formValues['cmdThinking'], 'none', 'disabled+none must display as None, not Model Default');
    C.syncDetail(0);
    const thinking = C.commands()[0].thinking;
    assert.strictEqual(thinking.type, 'disabled');
    assert.strictEqual(thinking.level, 'none');
  });

  it('saves Model Default (empty) as no thinking config', () => {
    const ctx = loadModules();
    const C = ctx.Cmds;
    C.load({ commands: [{ commandName: 'C', menuText: 'C', thinking: { type: 'disabled' } }], models: null, ui: {} });
    ctx.formValues['cmdThinking'] = '';
    C.syncDetail(0);
    assert.strictEqual(C.commands()[0].thinking, '');
  });
});
