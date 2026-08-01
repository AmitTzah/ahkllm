// icons-settings.test.js — Unit tests for webui/js/settings/sections/icons.js
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
        attributes: {},
        getAttribute(name) { return this.attributes[name] !== undefined ? this.attributes[name] : null; },
        addEventListener(type, fn) { (this._listeners[type] = this._listeners[type] || []).push(fn); },
        fire(type) { (this._listeners[type] || []).forEach((fn) => fn.call(this)); },
    }, overrides);
}

function loadSection(opts) {
    const { els, withSettingsPanel, buttons } = opts || {};
    const elementMap = els || {};
    const domContentLoaded = [];
    const timers = [];
    const registered = [];
    const dirtyCalls = [];
    const posted = [];
    const panelStub = {
        registerSection: (name, mod) => { registered.push({ name, mod }); },
        markDirty: () => { dirtyCalls.push(true); },
    };
    const settingsPanel = opts && 'withSettingsPanel' in opts ? withSettingsPanel : panelStub;

    const sandbox = {
        document: {
            getElementById: (id) => elementMap[id] || null,
            addEventListener: (type, fn) => { if (type === 'DOMContentLoaded') domContentLoaded.push(fn); },
        },
        window: {
            SettingsPanel: settingsPanel,
            chrome: { webview: { postMessage: (msg) => posted.push(msg) } },
        },
        setTimeout: (fn) => { timers.push(fn); },
        console,
    };
    sandbox.global = sandbox;

    const sharedSrc = fs.readFileSync(path.resolve(__dirname, '..', '..', 'webui', 'js', 'shared', 'settings-shared.js'), 'utf-8');
    const src = fs.readFileSync(path.resolve(__dirname, '..', '..', 'webui', 'js', 'settings', 'sections', 'icons.js'), 'utf-8');
    const ctx = vm.createContext(sandbox);
    vm.runInContext(sharedSrc, ctx);
    vm.runInContext(src, ctx);

    return {
        sandbox,
        registered,
        dirtyCalls,
        posted,
        timers,
        module: registered[0] ? registered[0].mod : null,
        icons: sandbox.window.SettingsIcons,
        fireDomReady: () => domContentLoaded.forEach((fn) => fn()),
    };
}

describe('Icons settings section', () => {
    it('load populates icon paths and handles missing elements', () => {
        const onEl = makeEl();
        const offEl = makeEl();
        const ctx = loadSection({ els: { iconOnPath: onEl, iconOffPath: offEl } });
        ctx.module.load({ icons: { iconOn: 'on.ico', iconOff: 'off.ico' } });
        assert.ok(onEl.value === 'on.ico');
        assert.ok(offEl.value === 'off.ico');

        ctx.module.load({ icons: {} });
        assert.ok(onEl.value === '');
        ctx.module.load(null);
        assert.ok(true);
    });

    it('save returns icon paths with empty fallback', () => {
        const ctx = loadSection({
            els: {
                iconOnPath: makeEl({ value: 'a.ico' }),
                iconOffPath: makeEl({ value: 'b.ico' }),
            },
        });
        assert.deepStrictEqual(JSON.parse(JSON.stringify(ctx.module.save())), {
            icons: { iconOn: 'a.ico', iconOff: 'b.ico' },
        });

        const empty = loadSection({});
        assert.deepStrictEqual(JSON.parse(JSON.stringify(empty.module.save())), {
            icons: { iconOn: '', iconOff: '' },
        });
    });

    it('wireDirty marks dirty on change and input', () => {
        const input = makeEl();
        const container = makeEl();
        container.querySelectorAll = (sel) => (sel === 'input, select, textarea' ? [input] : []);
        const ctx = loadSection({ els: { 'sec-icons': container } });
        ctx.fireDomReady();
        input.fire('change');
        input.fire('input');
        assert.ok(ctx.dirtyCalls.length >= 2);
    });

    it('wireDirty handles missing container', () => {
        const ctx = loadSection({});
        ctx.fireDomReady();
        assert.ok(true);
    });

    it('browse buttons post browseIcon message', () => {
        const onBtn = makeEl({ attributes: { 'data-icon-field': 'iconOn' } });
        const offBtn = makeEl({ attributes: { 'data-icon-field': 'iconOff' } });
        const container = makeEl();
        container.querySelectorAll = (sel) => (sel === 'button[data-icon-field]' ? [onBtn, offBtn] : []);
        const ctx = loadSection({ els: { 'sec-icons': container } });
        ctx.fireDomReady();

        onBtn.fire('click');
        offBtn.fire('click');
        assert.strictEqual(JSON.parse(ctx.posted[0]).action, 'browseIcon');
        assert.strictEqual(JSON.parse(ctx.posted[0]).field, 'iconOn');
        assert.strictEqual(JSON.parse(ctx.posted[1]).field, 'iconOff');
    });

    it('registers with the settings panel when available', () => {
        const ctx = loadSection({});
        assert.ok(ctx.registered.length === 1);
        assert.ok(ctx.registered[0].name === 'icons');
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
        assert.ok(ctx.registered[0].name === 'icons');
    });

    it('SettingsIcons.onFileSelected updates the matching input and marks dirty', () => {
        const onEl = makeEl();
        const ctx = loadSection({ els: { iconOnPath: onEl } });
        ctx.icons.onFileSelected('iconOn', 'new-on.ico');
        assert.ok(onEl.value === 'new-on.ico');
        assert.ok(ctx.dirtyCalls.length >= 1);

        ctx.icons.onFileSelected('iconOff', 'new-off.ico'); // element missing -> no throw
        assert.ok(true);
    });
});
