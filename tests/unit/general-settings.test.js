// general-settings.test.js — Unit tests for webui/js/settings/sections/general.js
const { describe, it } = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

function makeClassList(initial) {
    const classes = initial ? initial.slice() : [];
    return {
        add(c) { if (!classes.includes(c)) classes.push(c); },
        remove(c) { const i = classes.indexOf(c); if (i >= 0) classes.splice(i, 1); },
        contains(c) { return classes.includes(c); },
        toggle(c) { if (this.contains(c)) this.remove(c); else this.add(c); },
    };
}

function makeEl(overrides) {
    return Object.assign({
        value: '',
        innerHTML: '',
        children: [],
        classList: makeClassList(),
        style: {},
        _listeners: {},
        addEventListener(type, fn) { (this._listeners[type] = this._listeners[type] || []).push(fn); },
        fire(type) { (this._listeners[type] || []).forEach((fn) => fn.call(this)); },
        appendChild(child) { this.children.push(child); return child; },
    }, overrides);
}

function loadSection(opts) {
    const { els, withSettingsPanel } = opts || {};
    const elementMap = els || {};
    const domContentLoaded = [];
    const timers = [];
    const registered = [];
    const dirtyCalls = [];

    const panelStub = {
        registerSection: (name, mod) => { registered.push({ name, mod }); },
        markDirty: () => { dirtyCalls.push(true); },
    };
    const settingsPanel = opts && 'withSettingsPanel' in opts ? withSettingsPanel : panelStub;

    const sandbox = {
        document: {
            getElementById: (id) => elementMap[id] || null,
            createElement: () => makeEl(),
            addEventListener: (type, fn) => { if (type === 'DOMContentLoaded') domContentLoaded.push(fn); },
        },
        window: {
            SettingsPanel: settingsPanel,
        },
        setTimeout: (fn) => { timers.push(fn); },
        console,
    };
    sandbox.global = sandbox;

    const sharedSrc = fs.readFileSync(path.resolve(__dirname, '..', '..', 'webui', 'js', 'shared', 'settings-shared.js'), 'utf-8');
    const src = fs.readFileSync(path.resolve(__dirname, '..', '..', 'webui', 'js', 'settings', 'sections', 'general.js'), 'utf-8');
    const ctx = vm.createContext(sandbox);
    vm.runInContext(sharedSrc, ctx);
    vm.runInContext(src, ctx);

    const registeredModule = settingsPanel ? registered[0] && registered[0].mod : null;
    return {
        sandbox,
        panelStub,
        registered,
        dirtyCalls,
        domContentLoaded,
        timers,
        module: registeredModule || (registered[0] && registered[0].mod),
        fireDomReady: () => domContentLoaded.forEach((fn) => fn()),
    };
}

describe('General settings section', () => {
    it('load populates thread title, api log, trash and shortcut fields', () => {
        const toggle = makeEl({ classList: makeClassList() });
        const fields = makeEl({ classList: makeClassList(['fields-disabled']) });
        const modelSel = makeEl({ innerHTML: '' });
        const prompt = makeEl({ value: 'Summarize' });
        const maxTok = makeEl({ value: '123' });
        const logEntries = makeEl({ value: '5' });
        const trashDays = makeEl({ value: '7' });
        const shortcut = makeEl({ value: 'Ctrl+Space' });
        const optionEls = [];
        const els = {
            titleGenToggle: toggle,
            titleGenFields: fields,
            titleGenModel: modelSel,
            titleGenPrompt: prompt,
            titleGenMaxTokens: maxTok,
            apiLogMaxEntries: logEntries,
            trashRetentionDays: trashDays,
            chatShortcut: shortcut,
        };
        const ctx = loadSection({ els });
        ctx.fireDomReady();

        // document.createElement('option') is used by fillSelect — patch it
        // after load so the loaded module sees option elements.
        ctx.sandbox.document.createElement = () => {
            const opt = makeEl();
            opt.value = '';
            opt.textContent = '';
            optionEls.push(opt);
            return opt;
        };

        ctx.module.load({
            threadTitles: { enabled: true, model: 'new-model', prompt: 'Tl;dr', maxTokens: 75 },
            models: { 'gpt-5': {}, 'anthropic/claude-new': {}, 'deepseek/deepseek-v4-flash': {} },
            apiLogs: { maxEntries: 40 },
            trash: { retentionDays: 14 },
            chatShortcut: 'Ctrl+Alt+C',
        });

        assert.ok(toggle.classList.contains('on'));
        assert.ok(!fields.classList.contains('fields-disabled'));
        assert.ok(modelSel.innerHTML === '');
        assert.ok(prompt.value === 'Tl;dr');
        assert.ok(String(maxTok.value) === '75');
        assert.ok(String(logEntries.value) === '40');
        assert.ok(String(trashDays.value) === '14');
        assert.ok(shortcut.value === 'Ctrl+Alt+C');
        // fillSelect unshifted the unknown current model and set the value.
        assert.ok(modelSel.value === 'new-model');
        assert.ok(optionEls.length === 4, 'four model options created');
        assert.ok(optionEls[0].value === 'new-model');
    });

    it('load handles disabled thread titles', () => {
        const toggle = makeEl({ classList: makeClassList(['on']) });
        const fields = makeEl({ classList: makeClassList() });
        const ctx = loadSection({ els: { titleGenToggle: toggle, titleGenFields: fields } });
        ctx.module.load({ threadTitles: { enabled: false, model: '', prompt: '', maxTokens: 50 } });
        assert.ok(!toggle.classList.contains('on'));
        assert.ok(fields.classList.contains('fields-disabled'));
    });

    it('load tolerates missing data and missing elements', () => {
        const ctx = loadSection({});
        ctx.module.load(null);
        ctx.module.load({});
        ctx.module.load({ threadTitles: { enabled: true }, apiLogs: {}, trash: {}, chatShortcut: 'x' });
        assert.ok(true);
    });

    it('save collects values with defaults and fallbacks', () => {
        const toggle = makeEl({ classList: makeClassList(['on']) });
        const ctx = loadSection({
            els: {
                titleGenToggle: toggle,
                titleGenModel: makeEl({ value: 'gpt-5' }),
                titleGenPrompt: makeEl({ value: 'Sum' }),
                titleGenMaxTokens: makeEl({ value: '99' }),
                apiLogMaxEntries: makeEl({ value: '12' }),
                trashRetentionDays: makeEl({ value: '3' }),
                chatShortcut: makeEl({ value: 'Alt+Z' }),
            },
        });
        const data = ctx.module.save();
        assert.strictEqual(JSON.stringify(data), JSON.stringify({
            threadTitles: { enabled: true, model: 'gpt-5', prompt: 'Sum', maxTokens: 99 },
            apiLogs: { maxEntries: 12 },
            trash: { retentionDays: 3 },
            chatShortcut: 'Alt+Z',
        }));
    });

    it('save falls back to defaults when elements are missing or values are invalid', () => {
        const ctx = loadSection({
            els: {
                titleGenMaxTokens: makeEl({ value: 'abc' }),
                apiLogMaxEntries: makeEl({ value: '' }),
                trashRetentionDays: makeEl({ value: 'x' }),
            },
        });
        const data = ctx.module.save();
        assert.ok(data.threadTitles.enabled === true, 'toggle missing -> enabled default true');
        assert.ok(data.threadTitles.model === 'deepseek/deepseek-v4-flash');
        assert.ok(data.threadTitles.prompt === '');
        assert.ok(data.threadTitles.maxTokens === 50);
        assert.ok(data.apiLogs.maxEntries === 20);
        assert.ok(data.trash.retentionDays === 30);
        assert.ok(data.chatShortcut === '');
    });

    it('wireToggle toggles fields and marks dirty on click', () => {
        const toggle = makeEl({ classList: makeClassList() });
        const fields = makeEl({ classList: makeClassList(['fields-disabled']) });
        const ctx = loadSection({ els: { titleGenToggle: toggle, titleGenFields: fields } });
        ctx.fireDomReady();

        toggle.fire('click');
        assert.ok(toggle.classList.contains('on'));
        assert.ok(!fields.classList.contains('fields-disabled'));
        assert.ok(ctx.dirtyCalls.length >= 1);

        toggle.fire('click');
        assert.ok(!toggle.classList.contains('on'));
        assert.ok(fields.classList.contains('fields-disabled'));
    });

    it('wireToggle and wireDirty handle missing elements', () => {
        const container = makeEl();
        const ctx = loadSection({ els: { secGeneral: container } });
        ctx.fireDomReady(); // no toggle/fields, no inputs — must not throw
        assert.ok(true);
    });

    it('wireDirty marks dirty on change and input for every field', () => {
        const input = makeEl();
        const select = makeEl();
        const textarea = makeEl();
        const container = makeEl();
        container.querySelectorAll = (sel) => (sel === 'input, select, textarea' ? [input, select, textarea] : []);
        const ctx = loadSection({ els: { 'sec-general': container } });
        ctx.fireDomReady();

        input.fire('change');
        select.fire('input');
        textarea.fire('change');
        assert.ok(ctx.dirtyCalls.length >= 3);
    });

    it('registers with the settings panel when available', () => {
        const ctx = loadSection({});
        assert.ok(ctx.registered.length === 1);
        assert.ok(ctx.registered[0].name === 'general');
        assert.ok(typeof ctx.registered[0].mod.load === 'function');
        assert.ok(typeof ctx.registered[0].mod.save === 'function');
    });

    it('defers registration until SettingsPanel appears', () => {
        const ctx = loadSection({ withSettingsPanel: undefined });
        assert.ok(ctx.registered.length === 0);
        assert.ok(ctx.timers.length >= 1, 'registration retry scheduled');
        ctx.sandbox.window.SettingsPanel = ctx.panelStub;
        ctx.timers.forEach((fn) => fn());
        assert.ok(ctx.registered.length === 1);
        assert.ok(ctx.registered[0].name === 'general');
    });
});
