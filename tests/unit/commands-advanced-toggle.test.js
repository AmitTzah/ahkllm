// commands-advanced-toggle.test.js - Regression test for the Commands
// Advanced card toggle (bug #27). The toggle listener used to sit on the
// whole .cmd-advanced-wrap, so clicking inside a field collapsed the card.
// It must live on the .cmd-advanced-toggle header only.
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

  const toggleEl = { _handlers: {} };
  toggleEl.addEventListener = (ev, fn) => { toggleEl._handlers[ev] = fn; };
  const bodyEl = { style: { display: 'none' } };
  const chevronEl = { classList: { toggle: function() {} } };
  const wrap = { _handlers: {}, toggle: toggleEl };
  wrap.addEventListener = (ev, fn) => { wrap._handlers[ev] = fn; };
  wrap.querySelector = (sel) => {
    if (sel === '.cmd-advanced-toggle') return toggleEl;
    if (sel === '.cmd-advanced-body') return bodyEl;
    if (sel === '.cmd-chevron') return chevronEl;
    return null;
  };

  function makeEl() {
    return {
      value: '',
      innerHTML: '',
      style: {},
      addEventListener: function() {},
      querySelectorAll: function() { return []; },
      querySelector: function() { return null; },
      classList: { add: function() {}, remove: function() {}, contains: function() { return false; }, toggle: function() {} }
    };
  }

  const sandbox = {
    document: {
      body: {},
      getElementById: function() { return makeEl(); },
      querySelectorAll: function() { return []; },
      querySelector: function(sel) { return sel === '.cmd-advanced-wrap' ? wrap : null; },
      addEventListener: function() {},
      createElement: function() { return { style: {}, appendChild: function() {}, addEventListener: function() {} }; }
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
  C.renderList = function() {};
  C.showPlaceholder = function() {};
  return { Cmds: C, wrap: wrap, bodyEl: bodyEl };
}

describe('Commands Advanced card toggle (bug #27)', () => {
  it('attaches the toggle only to the header, not the whole wrap', () => {
    const ctx = loadModules();
    const C = ctx.Cmds;
    C.load({ commands: [{ commandName: 'C', menuText: 'C' }], models: null, ui: {} });
    C.selectCommand(0);

    // FIXED: the wrap itself must not have a click handler - the old
    // whole-wrap listener collapsed the card on any click inside a field.
    assert.strictEqual(ctx.wrap._handlers.click, undefined,
      'the .cmd-advanced-wrap must not toggle on any click');
    assert.ok(ctx.wrap.toggle._handlers.click,
      'the .cmd-advanced-toggle header must toggle the Advanced card');

    // The header toggle still works: open then close.
    ctx.wrap.toggle._handlers.click();
    assert.strictEqual(ctx.bodyEl.style.display, 'block', 'header click should open the body');
    ctx.wrap.toggle._handlers.click();
    assert.strictEqual(ctx.bodyEl.style.display, 'none', 'header click should close the body');
  });
});
