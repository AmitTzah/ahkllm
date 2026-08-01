// hotkeys-settings.test.js — Unit tests for webui/js/settings/sections/hotkeys.js
const { describe, it } = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

function makeClassList() {
    const classes = [];
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
        classList: makeClassList(),
        _listeners: {},
        focused: 0,
        selected: 0,
        addEventListener(type, fn) { (this._listeners[type] = this._listeners[type] || []).push(fn); },
        fire(type) { (this._listeners[type] || []).forEach((fn) => fn.call(this)); },
        focus() { this.focused++; },
        select() { this.selected++; },
    }, overrides);
}

function loadSection(opts) {
    const { els, keyCaptures, withSettingsPanel, restartBtn, timeoutImpl } = opts || {};
    const elementMap = els || {};
    const domContentLoaded = [];
    const registered = [];
    const dirtyCalls = [];
    const posted = [];
    const timers = [];
    const panelStub = {
        registerSection: (name, mod) => { registered.push({ name, mod }); },
        markDirty: () => { dirtyCalls.push(true); },
    };
    const settingsPanel = opts && 'withSettingsPanel' in opts ? withSettingsPanel : panelStub;
    const setTimeoutStub = timeoutImpl || ((fn, delay) => { timers.push(fn); return timers.length; });

    const sandbox = {
        document: {
            getElementById: (id) => elementMap[id] || null,
            querySelectorAll: (sel) => (sel === '.key-capture' ? (keyCaptures || []) : []),
            addEventListener: (type, fn) => { if (type === 'DOMContentLoaded') domContentLoaded.push(fn); },
        },
        window: {
            SettingsPanel: settingsPanel,
            chrome: { webview: { postMessage: (msg) => posted.push(msg) } },
        },
        setTimeout: setTimeoutStub,
        console,
    };
    sandbox.global = sandbox;

    const src = fs.readFileSync(path.resolve(__dirname, '..', '..', 'webui', 'js', 'settings', 'sections', 'hotkeys.js'), 'utf-8');
    vm.runInContext(src, vm.createContext(sandbox));

    return {
        sandbox,
        registered,
        dirtyCalls,
        posted,
        timers,
        module: registered[0] ? registered[0].mod : null,
        fireDomReady: () => domContentLoaded.forEach((fn) => fn()),
    };
}

describe('Hotkeys settings section', () => {
    it('load populates all hotkey fields and skips undefined values', () => {
        const els = {
            hkMain: makeEl(),
            hkReload: makeEl(),
            hkCloseWindows: makeEl(),
            hkSuspend: makeEl(),
        };
        const ctx = loadSection({ els });
        ctx.module.load({ hotkeys: { main: 'Alt+M', reload: 'Ctrl+R', closeWindows: 'Ctrl+W' } });
        assert.ok(els.hkMain.value === 'Alt+M');
        assert.ok(els.hkReload.value === 'Ctrl+R');
        assert.ok(els.hkCloseWindows.value === 'Ctrl+W');
        assert.ok(els.hkSuspend.value === '', 'undefined value not applied');
    });

    it('load handles missing data and elements', () => {
        const ctx = loadSection({});
        ctx.module.load(null);
        ctx.module.load({});
        ctx.module.load({ hotkeys: {} });
        assert.ok(true);
    });

    it('save returns all four hotkeys with empty fallback', () => {
        const els = {
            hkMain: makeEl({ value: 'Alt+M' }),
            hkReload: makeEl({ value: 'Ctrl+R' }),
            hkCloseWindows: makeEl({ value: 'Ctrl+W' }),
            hkSuspend: makeEl({ value: 'Ctrl+S' }),
        };
        const ctx = loadSection({ els });
        assert.deepStrictEqual(JSON.parse(JSON.stringify(ctx.module.save())), {
            hotkeys: { main: 'Alt+M', reload: 'Ctrl+R', closeWindows: 'Ctrl+W', suspend: 'Ctrl+S' },
        });

        const empty = loadSection({});
        assert.deepStrictEqual(JSON.parse(JSON.stringify(empty.module.save())), {
            hotkeys: { main: '', reload: '', closeWindows: '', suspend: '' },
        });
    });

    it('wireDirty marks dirty on input and handles missing container', () => {
        const input = makeEl();
        const container = makeEl();
        container.querySelectorAll = (sel) => (sel === 'input' ? [input] : []);
        const ctx = loadSection({ els: { 'sec-hotkeys': container } });
        ctx.fireDomReady();
        input.fire('input');
        assert.ok(ctx.dirtyCalls.length >= 1);

        const missing = loadSection({ els: { 'sec-hotkeys': null } });
        missing.fireDomReady(); // must not throw
        assert.ok(true);
    });

    it('wireKeyCaptures wires click, focus and blur handlers', () => {
        const inp = makeEl();
        const kc = makeEl();
        kc.querySelector = (sel) => (sel === 'input' ? inp : null);
        const ctx = loadSection({ keyCaptures: [kc] });
        ctx.fireDomReady();

        kc.fire('click');
        assert.ok(inp.focused === 1);
        assert.ok(inp.selected === 1);

        inp.fire('focus');
        assert.ok(kc.classList.contains('listening'));
        inp.fire('blur');
        assert.ok(!kc.classList.contains('listening'));
    });

    it('wireKeyCaptures handles captures without an input', () => {
        const kc = makeEl();
        kc.querySelector = () => null;
        const ctx = loadSection({ keyCaptures: [kc] });
        ctx.fireDomReady();
        kc.fire('click'); // no input -> click handler returns quietly
        assert.ok(true);
    });

    it('restart button posts reloadScript', () => {
        const restartBtn = makeEl();
        const ctx = loadSection({ restartBtn });
        ctx.sandbox.document.getElementById = (id) => (id === 'restartNowBtn' ? restartBtn : null);
        ctx.fireDomReady();
        restartBtn.fire('click');
        assert.strictEqual(JSON.parse(ctx.posted[0]).action, 'reloadScript');
    });

    it('DOMContentLoaded tolerates missing restart button', () => {
        const ctx = loadSection({});
        ctx.fireDomReady();
        assert.ok(true);
    });

    it('registers with the settings panel when available', () => {
        const ctx = loadSection({});
        assert.ok(ctx.registered.length === 1);
        assert.ok(ctx.registered[0].name === 'hotkeys');
        assert.ok(typeof ctx.registered[0].mod.load === 'function');
        assert.ok(typeof ctx.registered[0].mod.save === 'function');
    });

    it('defers registration until SettingsPanel appears', () => {
        const ctx = loadSection({ withSettingsPanel: undefined });
        assert.ok(ctx.registered.length === 0);
        assert.ok(ctx.timers.length >= 1, 'registration retry scheduled');
        ctx.sandbox.window.SettingsPanel = {
            registerSection: (name, mod) => ctx.registered.push({ name, mod }),
            markDirty: () => {},
        };
        ctx.timers.forEach((fn) => fn());
        assert.ok(ctx.registered.length === 1);
        assert.ok(ctx.registered[0].name === 'hotkeys');
    });
});
