// models-pricing-refresh.test.js — Regression test for the "Fetch Latest Models" flow.
//
// The AHK side (chat/callbacks/Dispatch.ahk) sends full multi-line entries from
// scripts/models_metadata.txt as `raw`. The WebUI must extract pricing, context,
// and feature toggles from that raw text. Broken previously because raw only
// contained the model-name line ("provider/model", {) with no pricing fields.
const { describe, it } = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

function loadModule(overrides) {
    const sharedSrc = fs.readFileSync(path.resolve(__dirname, '..', '..', 'webui', 'js', 'shared', 'settings-shared.js'), 'utf-8');
    const src = fs.readFileSync(
        path.resolve(__dirname, '..', '..', 'webui', 'js', 'settings', 'sections', 'models.js'),
        'utf-8'
    );
    const els = (overrides && overrides.els) || {};
    const modelsRows = (overrides && overrides.modelsRows) || [];
    const registeredSections = {};
    const sandbox = {
        document: {
            getElementById: (id) => els[id] || null,
            querySelectorAll: (sel) => (sel === '#modelsTableBody tr' ? modelsRows : []),
            createElement: () => ({
                style: {}, innerHTML: '',
                classList: { add: () => {}, remove: () => {}, toggle: () => {} },
                querySelectorAll: () => [],
                querySelector: () => ({ addEventListener: () => {} }),
                addEventListener: () => {},
                appendChild: () => {}
            }),
            addEventListener: () => {}
        },
        window: {
            chrome: { webview: { postMessage: () => {} } },
            SettingsPanel: { registerSection: (name, mod) => { registeredSections[name] = mod; } },
            addEventListener: () => {}
        },
        setTimeout: () => {},
        clearTimeout: () => {},
        console
    };
    sandbox.global = sandbox;
    const ctx = vm.createContext(sandbox);
    vm.runInContext(sharedSrc, ctx);
    vm.runInContext(src, ctx);
    return { SM: sandbox.window.SettingsModels, sections: registeredSections };
}

function makeMainRow(displayId, provider, meta) {
    const input = (value) => ({ value, checked: false, getAttribute: () => null });
    return {
        dataset: meta ? { modelMeta: JSON.stringify(meta) } : {},
        querySelector: (sel) => {
            switch (sel) {
                case '[data-field="id"]': return input(displayId);
                case '[data-field="provider"]': return input(provider);
                default: return input('');
            }
        }
    };
}

function makeRightTbody(rows) {
    const trs = rows.map((r) => ({
        querySelector: (sel) => {
            if (sel === '[data-field="id"]') {
                return {
                    value: r.displayId,
                    getAttribute: (name) => (name === 'data-full-id' ? r.fullId : null)
                };
            }
            if (sel === '[data-field="provider"]') return { value: r.provider, getAttribute: () => null };
            return null;
        }
    }));
    return {
        children: trs,
        innerHTML: '',
        appendChild: (tr) => trs.push(tr),
        querySelector: () => null,
        querySelectorAll: (sel) => (sel === 'tr' ? trs : [])
    };
}

describe('SettingsModels.parsePricingRaw', () => {
    it('extracts pricing from a full multi-line metadata entry (Refresh-Models.ps1 output)', () => {
        const { SM } = loadModule();
        const raw = [
            '    "deepseek/deepseek-chat", {',
            '        provider: "deepseek", api: "openai-completions",',
            '        compat: Map("thinkingFormat", "deepseek", "supportsReasoningEffort", true, "supportsUsageInStreaming", true, "maxTokensField", "max_tokens"),',
            '        thinkingLevelMap: Map("high", "high", "max", "max"),',
            '        thinkingOff: "disabled",',
            '        input: 0.14, cachedInput: 0.0028, output: 0.28, context: 1000000, reasoning: true, vision: false',
            '    },'
        ].join('\n');
        const p = SM.parsePricingRaw(raw);
        assert.strictEqual(p.input, 0.14);
        assert.strictEqual(p.cachedInput, 0.0028);
        assert.strictEqual(p.output, 0.28);
        assert.strictEqual(p.context, 1000000);
        assert.strictEqual(p.reasoning, true);
        assert.strictEqual(p.vision, false);
        // Metadata fields must survive the parse so a newly added model keeps
        // its thinking levels (no default entry to refill them after save).
        assert.strictEqual(p.api, 'openai-completions');
        assert.strictEqual(p.thinkingOff, 'disabled');
        assert.strictEqual(JSON.stringify(p.compat), JSON.stringify({
            thinkingFormat: 'deepseek',
            supportsReasoningEffort: true,
            supportsUsageInStreaming: true,
            maxTokensField: 'max_tokens'
        }));
        assert.strictEqual(JSON.stringify(p.thinkingLevelMap), JSON.stringify({ high: 'high', max: 'max' }));
    });

    it('returns empty pricing for a bare entry header (old broken raw)', () => {
        const { SM } = loadModule();
        const p = SM.parsePricingRaw('    "openai/gpt-5", {');
        assert.strictEqual(p.input, undefined);
        assert.strictEqual(p.context, undefined);
        assert.strictEqual(p.reasoning, false);
    assert.strictEqual(p.vision, false);
  });
});

describe('OpenRouter synthetic model metadata', () => {
  it('keeps openrouter/free vision-capable in the generator and generated defaults', () => {
    const generator = fs.readFileSync(path.resolve(__dirname, '..', '..', 'scripts', 'Refresh-Models.ps1'), 'utf8');
    const generated = fs.readFileSync(path.resolve(__dirname, '..', '..', 'default-settings', 'DefaultModels.ahk'), 'utf8');
    assert.match(generator, /openrouter\/free[\s\S]*?vision: true/,
      'Refresh-Models.ps1 must emit the synthetic router with vision:true');
    assert.match(generated, /"openrouter\/free", \{[\s\S]*?reasoning: false, vision: true/,
      'DefaultModels.ahk must retain vision:true for openrouter/free');
  });
});

describe('SettingsModels.filterAvailableModels', () => {
  it('returns all models for an empty or whitespace query', () => {
    const { SM } = loadModule();
    const list = [{ id: 'openai/gpt-5' }, { id: 'deepseek/deepseek-chat' }];
    assert.strictEqual(SM.filterAvailableModels(list, '').length, 2);
    assert.strictEqual(SM.filterAvailableModels(list, '   ').length, 2);
  });

  it('matches provider prefix, model id, and is case-insensitive', () => {
    const { SM } = loadModule();
    const list = [
      { id: 'openai/gpt-5' },
      { id: 'deepseek/deepseek-chat' },
      { id: 'openai/gpt-4o' }
    ];
    assert.deepStrictEqual(SM.filterAvailableModels(list, 'deepseek').map((m) => m.id), ['deepseek/deepseek-chat']);
    assert.deepStrictEqual(SM.filterAvailableModels(list, 'gpt-5').map((m) => m.id), ['openai/gpt-5']);
    assert.deepStrictEqual(SM.filterAvailableModels(list, 'GPT-4').map((m) => m.id), ['openai/gpt-4o']);
  });

  it('does not mutate the input list', () => {
    const { SM } = loadModule();
    const list = [{ id: 'openai/gpt-5' }, { id: 'deepseek/deepseek-chat' }];
    const copy = list.slice();
    SM.filterAvailableModels(list, 'gpt');
    assert.deepStrictEqual(list, copy);
  });
});

describe('SettingsModels.buildAddButton', () => {
  it('renders an enabled + Add button for models not yet added', () => {
    const { SM } = loadModule();
    const html = SM.buildAddButton('openai/gpt-5', false);
    assert.ok(html.indexOf('+ Add') >= 0);
    assert.ok(html.indexOf('disabled') < 0);
    assert.ok(html.indexOf('data-id="openai/gpt-5"') >= 0);
  });

  it('renders a disabled Added button for models already in the list', () => {
    const { SM } = loadModule();
    const html = SM.buildAddButton('openai/gpt-5', true);
    assert.ok(html.indexOf('Added') >= 0);
    assert.ok(html.indexOf('disabled') >= 0);
  });

  it('escapes the model id in the data attribute', () => {
    const { SM } = loadModule();
    const html = SM.buildAddButton('openai/"weird"', false);
    assert.ok(html.indexOf('&quot;') >= 0);
  });
});

describe('added-state id normalization', () => {
  it('collects existing settings models as full provider/model ids', () => {
    const { SM } = loadModule({ modelsRows: [makeMainRow('gemini-3-flash-preview', 'google')] });
    const models = SM.collectCurrentModels();
    assert.strictEqual(models.length, 1);
    assert.strictEqual(models[0].id, 'google/gemini-3-flash-preview');
    assert.strictEqual(models[0].displayId, 'gemini-3-flash-preview');
  });

  it('rightPanelIds falls back to the provider column when the stored id has no prefix', () => {
    const tbody = makeRightTbody([
      { displayId: 'gemini-3-flash-preview', fullId: 'gemini-3-flash-preview', provider: 'google' },
      { displayId: 'gpt-5', fullId: 'openai/gpt-5', provider: 'openai' }
    ]);
    const { SM } = loadModule({ els: { refreshRightTbody: tbody } });
    assert.deepStrictEqual([...SM.rightPanelIds()], ['google/gemini-3-flash-preview', 'openai/gpt-5']);
  });

  it('addFromRefresh refuses a model already present with a full id', () => {
    const tbody = makeRightTbody([
      { displayId: 'gemini-3-flash-preview', fullId: 'google/gemini-3-flash-preview', provider: 'google' }
    ]);
    let appended = 0;
    tbody.appendChild = () => { appended++; };
    const { SM } = loadModule({ els: { refreshRightTbody: tbody } });
    SM.addFromRefresh('google/gemini-3-flash-preview');
    assert.strictEqual(appended, 0);
  });

  it('rightPanelIds uses the edited id, not the stale data-full-id (bug #40)', () => {
    const tbody = makeRightTbody([
      { displayId: 'renamed-model-id', fullId: 'openai/gpt-5', provider: 'openai' }
    ]);
    const { SM } = loadModule({ els: { refreshRightTbody: tbody } });
    assert.deepStrictEqual([...SM.rightPanelIds()], ['openai/renamed-model-id']);
  });

  it('rightPanelIds keeps the unedited full id when the input is untouched', () => {
    const tbody = makeRightTbody([
      { displayId: 'gemini-3-flash-preview', fullId: 'google/gemini-3-flash-preview', provider: 'google' }
    ]);
    const { SM } = loadModule({ els: { refreshRightTbody: tbody } });
    assert.deepStrictEqual([...SM.rightPanelIds()], ['google/gemini-3-flash-preview']);
  });

  it('saveRefresh writes the edited model id to the main table (bug #40)', () => {
    const rightTbody = makeRightTbody([
      { displayId: 'renamed-model-id', fullId: 'openai/gpt-5', provider: 'openai' }
    ]);
    const appended = [];
    const mainTbody = {
      innerHTML: '',
      appendChild: (tr) => appended.push(tr),
      querySelectorAll: () => []
    };
    const { SM } = loadModule({
      els: {
        refreshRightTbody: rightTbody,
        modelsTableBody: mainTbody,
        refreshModal: { classList: { remove: () => {} } }
      }
    });
    SM.saveRefresh();
    assert.strictEqual(appended.length, 1);
    assert.ok(appended[0].innerHTML.indexOf('renamed-model-id') >= 0,
        'main table row must use the edited id, got ' + JSON.stringify(appended[0].innerHTML));
    assert.ok(appended[0].innerHTML.indexOf('value="openai/gpt-5"') < 0,
        'the stale data-full-id must not win on save');
  });
});

describe('ensureFullId provider precedence (bug #92)', () => {
  it('rebuilds the full id from the provider dropdown even when the id contains /', () => {
    const row = makeMainRow('openai/gpt-4', 'google');
    const { SM } = loadModule({ modelsRows: [row] });
    const models = SM.collectCurrentModels();
    assert.strictEqual(models.length, 1);
    assert.strictEqual(models[0].id, 'google/gpt-4');
  });

  it('keeps the id as-is when no provider is selected', () => {
    const row = makeMainRow('openai/gpt-4', '');
    const { SM } = loadModule({ modelsRows: [row] });
    const models = SM.collectCurrentModels();
    assert.strictEqual(models[0].id, 'openai/gpt-4');
  });
});

describe('new model metadata survives a settings save round-trip', () => {
  const meta = {
    api: 'openai-completions',
    compat: { thinkingFormat: 'openai', supportsReasoningEffort: true },
    thinkingLevelMap: { low: 'low', high: 'high' },
    thinkingOff: 'none'
  };

  it('collectCurrentModels keeps stashed api/compat/thinkingLevelMap/thinkingOff', () => {
    const { SM } = loadModule({ modelsRows: [makeMainRow('gpt-brand-new', 'openai', meta)] });
    const models = SM.collectCurrentModels();
    assert.strictEqual(models.length, 1);
    assert.strictEqual(models[0].id, 'openai/gpt-brand-new');
    assert.strictEqual(models[0].api, 'openai-completions');
    assert.strictEqual(JSON.stringify(models[0].thinkingLevelMap), JSON.stringify({ low: 'low', high: 'high' }));
    assert.strictEqual(JSON.stringify(models[0].compat), JSON.stringify(meta.compat));
    assert.strictEqual(models[0].thinkingOff, 'none');
  });

  it('the models section save() re-emits stashed metadata for a new id', () => {
    const { sections } = loadModule({ modelsRows: [makeMainRow('gpt-brand-new', 'openai', meta)] });
    const out = sections.models.save();
    const entry = out.models['openai/gpt-brand-new'];
    assert.ok(entry, 'new model must be present in the save payload');
    assert.strictEqual(entry.api, 'openai-completions');
    assert.strictEqual(JSON.stringify(entry.thinkingLevelMap), JSON.stringify({ low: 'low', high: 'high' }));
    assert.strictEqual(JSON.stringify(entry.compat), JSON.stringify(meta.compat));
    assert.strictEqual(entry.thinkingOff, 'none');
  });
});

describe('Models context field focus/blur keeps the k/M suffix (bug #158)', () => {
  it('blur does not collapse "128K" to 128', () => {
    const sharedSrc = fs.readFileSync(path.resolve(__dirname, '..', '..', 'webui', 'js', 'shared', 'settings-shared.js'), 'utf-8');
    const src = fs.readFileSync(path.resolve(__dirname, '..', '..', 'webui', 'js', 'settings', 'sections', 'models.js'), 'utf-8');

    function makeEl(value, raw) {
      const el = {
        value,
        raw: raw !== undefined ? String(raw) : null,
        listeners: {},
        classList: { add() {}, remove() {}, toggle() {} },
        dataset: {}
      };
      el.getAttribute = (n) => (n === 'data-context-raw' || n === 'data-price-raw') ? el.raw : null;
      el.setAttribute = (n, v) => { if (n === 'data-context-raw' || n === 'data-price-raw') el.raw = String(v); };
      el.addEventListener = (t, fn) => { el.listeners[t] = fn; };
      el.focus = () => { if (el.listeners.focus) el.listeners.focus(); };
      el.blur = () => { if (el.listeners.blur) el.listeners.blur(); };
      return el;
    }

    let trRef = null;
    const idEl = makeEl('deepseek-v4-flash');
    const providerEl = makeEl('deepseek');
    const inputEl = makeEl('0.14', '0.14');
    const cachedEl = makeEl('', '');
    const outputEl = makeEl('0.28', '0.28');
    const contextEl = makeEl('128K');
    const visionEl = makeEl('on', 'on');
    const reasoningEl = makeEl('on', 'on');
    const fields = {
      '[data-field="id"]': idEl,
      '[data-field="provider"]': providerEl,
      '[data-field="input"]': inputEl,
      '[data-field="cachedInput"]': cachedEl,
      '[data-field="output"]': outputEl,
      '[data-field="context"]': contextEl,
      '[data-field="vision"]': visionEl,
      '[data-field="reasoning"]': reasoningEl
    };
    const tr = {
      dataset: {},
      innerHTML: '',
      querySelector: (sel) => fields[sel] || null,
      querySelectorAll: () => Object.values(fields),
      addEventListener() {},
      remove() {}
    };
    fields['.btn-sm.danger'] = makeEl('');
    const tbody = { innerHTML: '', appendChild(child) { trRef = child; } };
    const registeredSections = {};
    const sandbox = {
      document: {
        getElementById: (id) => (id === 'modelsTableBody' ? tbody : null),
        querySelectorAll: (sel) => (sel === '#modelsTableBody tr' ? (trRef ? [trRef] : []) : []),
        createElement: () => tr,
        addEventListener: () => {}
      },
      window: {
        chrome: { webview: { postMessage: () => {} } },
        SettingsPanel: { registerSection: (name, mod) => { registeredSections[name] = mod; } },
        addEventListener: () => {}
      },
      setTimeout: () => {},
      clearTimeout: () => {},
      console
    };
    sandbox.global = sandbox;
    const ctx = vm.createContext(sandbox);
    vm.runInContext(sharedSrc, ctx);
    vm.runInContext(src, ctx);

    const mod = registeredSections.models;
    mod.load({
      providers: { deepseek: {} },
      models: { 'deepseek/deepseek-v4-flash': { provider: 'deepseek', input: 0.14, cachedInput: '', output: 0.28, context: 128000, vision: false, reasoning: true } }
    });
    assert.strictEqual(contextEl.value, '128K');

    // A mere focus + blur must not shrink the saved context 1000x:
    contextEl.focus();
    contextEl.blur();
    assert.strictEqual(contextEl.value, '128K', 'display should keep the K suffix after blur');
    const saved = mod.save();
    assert.strictEqual(saved.models['deepseek/deepseek-v4-flash'].context, 128000,
        'context must survive focus/blur (128000), got ' + saved.models['deepseek/deepseek-v4-flash'].context);
  });
});

describe('Models price field "$" paste and blank blur (bug #164)', () => {
  function loadPriceModule() {
    const sharedSrc = fs.readFileSync(path.resolve(__dirname, '..', '..', 'webui', 'js', 'shared', 'settings-shared.js'), 'utf-8');
    const src = fs.readFileSync(path.resolve(__dirname, '..', '..', 'webui', 'js', 'settings', 'sections', 'models.js'), 'utf-8');

    function makeEl(value, raw) {
      const el = {
        value,
        raw: raw !== undefined ? String(raw) : null,
        listeners: {},
        classList: { add() {}, remove() {}, toggle() {} },
        dataset: {}
      };
      el.getAttribute = (n) => (n === 'data-context-raw' || n === 'data-price-raw') ? el.raw : null;
      el.setAttribute = (n, v) => { if (n === 'data-context-raw' || n === 'data-price-raw') el.raw = String(v); };
      el.addEventListener = (t, fn) => { el.listeners[t] = fn; };
      el.focus = () => { if (el.listeners.focus) el.listeners.focus(); };
      el.blur = () => { if (el.listeners.blur) el.listeners.blur(); };
      return el;
    }

    let trRef = null;
    const idEl = makeEl('deepseek-v4-flash');
    const providerEl = makeEl('deepseek');
    const inputEl = makeEl('$0.50', '0.5');
    const cachedEl = makeEl('', '');
    const outputEl = makeEl('0.28', '0.28');
    const contextEl = makeEl('');
    const visionEl = makeEl('on', 'on');
    const reasoningEl = makeEl('on', 'on');
    const fields = {
      '[data-field="id"]': idEl,
      '[data-field="provider"]': providerEl,
      '[data-field="input"]': inputEl,
      '[data-field="cachedInput"]': cachedEl,
      '[data-field="output"]': outputEl,
      '[data-field="context"]': contextEl,
      '[data-field="vision"]': visionEl,
      '[data-field="reasoning"]': reasoningEl
    };
    const tr = {
      dataset: {},
      innerHTML: '',
      querySelector: (sel) => fields[sel] || null,
      querySelectorAll: () => Object.values(fields),
      addEventListener() {},
      remove() {}
    };
    fields['.btn-sm.danger'] = makeEl('');
    const tbody = { innerHTML: '', appendChild(child) { trRef = child; } };
    const registeredSections = {};
    const sandbox = {
      document: {
        getElementById: (id) => (id === 'modelsTableBody' ? tbody : null),
        querySelectorAll: (sel) => (sel === '#modelsTableBody tr' ? (trRef ? [trRef] : []) : []),
        createElement: () => tr,
        addEventListener: () => {}
      },
      window: {
        chrome: { webview: { postMessage: () => {} } },
        SettingsPanel: { registerSection: (name, mod) => { registeredSections[name] = mod; } },
        addEventListener: () => {}
      },
      setTimeout: () => {},
      clearTimeout: () => {},
      console
    };
    sandbox.global = sandbox;
    const ctx = vm.createContext(sandbox);
    vm.runInContext(sharedSrc, ctx);
    vm.runInContext(src, ctx);
    return { mod: registeredSections.models, inputEl };
  }

  it('keeps a "$"-prefixed paste as the real price (0.5, not 0)', () => {
    const { mod, inputEl } = loadPriceModule();
    mod.load({
      providers: { deepseek: {} },
      models: { 'deepseek/deepseek-v4-flash': { provider: 'deepseek', input: 0.5, cachedInput: '', output: 0.28, context: '', vision: false, reasoning: true } }
    });
    assert.strictEqual(inputEl.value, '$0.50');
    inputEl.focus();
    inputEl.value = '$0.5';
    inputEl.blur();
    const saved = mod.save();
    assert.strictEqual(saved.models['deepseek/deepseek-v4-flash'].input, 0.5,
        'the $ paste must not zero the price (bug #164)');
  });

  it('keeps a blank price blank instead of saving 0', () => {
    const { mod, inputEl } = loadPriceModule();
    mod.load({
      providers: { deepseek: {} },
      models: { 'deepseek/deepseek-v4-flash': { provider: 'deepseek', input: 0.5, cachedInput: '', output: 0.28, context: '', vision: false, reasoning: true } }
    });
    inputEl.focus();
    inputEl.value = '';
    inputEl.blur();
    const saved = mod.save();
    assert.strictEqual(saved.models['deepseek/deepseek-v4-flash'].input, '',
        'a blank blur must keep the field blank, not save 0 (bug #164)');
  });
});
