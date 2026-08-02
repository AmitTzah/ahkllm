// ui-theme-settings.test.js — Unit tests for webui/js/settings/sections/ui-theme.js
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
    const { els, withSettingsPanel, documentElement } = opts || {};
    const elementMap = els || {};
    const domContentLoaded = [];
    const timers = [];
    const registered = [];
    const dirtyCalls = [];
    const cssProps = {};
    const rootStyle = {
        setProperty: (name, value) => { cssProps[name] = value; },
    };
    const panelStub = {
        registerSection: (name, mod) => { registered.push({ name, mod }); },
        markDirty: () => { dirtyCalls.push(true); },
    };
    const settingsPanel = opts && 'withSettingsPanel' in opts ? withSettingsPanel : panelStub;

    const sandbox = {
        document: {
            getElementById: (id) => elementMap[id] || null,
            createElement: (tag) => makeEl(),
            documentElement: documentElement || { style: rootStyle },
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
    const src = fs.readFileSync(path.resolve(__dirname, '..', '..', 'webui', 'js', 'settings', 'sections', 'ui-theme.js'), 'utf-8');
    const ctx = vm.createContext(sandbox);
    vm.runInContext(sharedSrc, ctx);
    vm.runInContext(src, ctx);

    return {
        sandbox,
        registered,
        dirtyCalls,
        timers,
        cssProps,
        module: registered[0] ? registered[0].mod : null,
        fireDomReady: () => domContentLoaded.forEach((fn) => fn()),
    };
}

describe('UI & theme settings section', () => {
    it('load applies response font, font size and CSS variable', () => {
        const ctx = loadSection({
            els: {
                responseFont: makeEl(),
                responseFontSize: makeEl(),
            },
        });
        ctx.module.load({ theme: { darkMode: false }, ui: { responseFont: 'Segoe UI, sans-serif', responseFontSize: '18' } });
        assert.ok(ctx.sandbox.document.getElementById('responseFont').value === 'Segoe UI');
        assert.ok(ctx.cssProps['--chat-font-family'] === 'Segoe UI, sans-serif');
        assert.ok(ctx.sandbox.document.getElementById('responseFontSize').value === '18');
    });

    it('load applies input window and suspend banner fields', () => {
        const els = {
            iwBackground: makeEl(),
            iwBackgroundHex: makeEl(),
            iwFontSize: makeEl(),
            iwFontColor: makeEl(),
            iwFontFace: makeEl(),
            iwWidth: makeEl(),
            iwHeight: makeEl(),
            sbText: makeEl(),
            sbFontSize: makeEl(),
            sbFontColor: makeEl(),
            sbFontFace: makeEl(),
            sbBackground: makeEl(),
            sbBackgroundHex: makeEl(),
        };
        const ctx = loadSection({ els });
        ctx.module.load({
            theme: { darkMode: false },
            ui: {
                inputWindow: {
                    background: '0x123456', fontSize: '14', fontColor: '#fff', fontFace: 'mono',
                    width: '600', height: '300',
                },
                suspendBanner: {
                    text: 'Suspended', fontSize: '12', textColor: '#000', fontFace: 'sans',
                    background: '0xABCDEF',
                },
            },
        });
        assert.ok(els.iwBackground.value === '#123456');
        assert.ok(els.iwBackgroundHex.value === '0x123456');
        assert.ok(els.iwFontSize.value === '14');
        assert.ok(els.iwFontColor.value === '#fff');
        assert.ok(els.iwFontFace.value === 'mono');
        assert.ok(els.iwWidth.value === '600');
        assert.ok(els.iwHeight.value === '300');
        assert.ok(els.sbText.value === 'Suspended');
        assert.ok(els.sbBackground.value === '#ABCDEF');
        assert.ok(els.sbBackgroundHex.value === '0xABCDEF');
    });

    it('load uses default colors when background is falsy', () => {
        const els = { iwBackground: makeEl(), sbBackground: makeEl() };
        const ctx = loadSection({ els });
        ctx.module.load({ theme: {}, ui: { inputWindow: { background: '' }, suspendBanner: { background: '' } } });
        assert.ok(els.iwBackground.value === '#FFFFFF');
        assert.ok(els.sbBackground.value === '#FFDF00');
    });

    it('load tolerates missing data and missing elements', () => {
        const ctx = loadSection({});
        ctx.module.load(null);
        ctx.module.load({});
        ctx.module.load({ theme: {}, ui: {} });
        assert.ok(true);
    });

    it('save collects ui values', () => {
        const ctx = loadSection({
            els: {
                responseFont: makeEl({ value: 'Calibri' }),
                responseFontSize: makeEl({ value: '16' }),
                iwBackground: makeEl({ value: '#334455' }),
                iwFontSize: makeEl({ value: '13' }),
                iwFontColor: makeEl({ value: '#eee' }),
                iwFontFace: makeEl({ value: 'mono' }),
                iwWidth: makeEl({ value: '640' }),
                iwHeight: makeEl({ value: '320' }),
                sbText: makeEl({ value: 'Paused' }),
                sbFontSize: makeEl({ value: '11' }),
                sbFontColor: makeEl({ value: '#111' }),
                sbFontFace: makeEl({ value: 'sans' }),
                sbBackground: makeEl({ value: '#112233' }),
            },
        });
        const data = JSON.parse(JSON.stringify(ctx.module.save()));
        assert.strictEqual(JSON.stringify(data), JSON.stringify({
            ui: {
                responseFont: 'Calibri',
                responseFontSize: '16',
                inputWindow: {
                    background: '0x334455', fontSize: '13', fontColor: '#eee', fontFace: 'mono',
                    width: 640, height: 320,
                },
                suspendBanner: {
                    text: 'Paused', fontSize: '11', textColor: '#111', fontFace: 'sans',
                    background: '0x112233',
                },
            },
        }));
    });

    it('save falls back to defaults when elements are missing or values are invalid', () => {
        const ctx = loadSection({
            els: {
                iwWidth: makeEl({ value: 'abc' }),
                iwHeight: makeEl({ value: '' }),
            },
        });
        const data = JSON.parse(JSON.stringify(ctx.module.save()));
        assert.ok(data.ui.inputWindow.width === 500);
        assert.ok(data.ui.inputWindow.height === 250);
        assert.ok(data.ui.inputWindow.background === '0x');
        assert.ok(data.ui.suspendBanner.background === '0x');
    });

    it('wireColorPair syncs hex display and marks dirty', () => {
        const colorEl = makeEl();
        const hexEl = makeEl();
        const ctx = loadSection({ els: { iwBackground: colorEl, iwBackgroundHex: hexEl } });
        ctx.fireDomReady();
        colorEl.value = '#AABBCC';
        colorEl.fire('input');
        assert.ok(hexEl.value === '0xAABBCC');
        assert.ok(ctx.dirtyCalls.length >= 1);
    });

    it('wireDirty marks dirty for fields, switches and response font size', () => {
        const input = makeEl();
        const sw = makeEl({ classList: makeClassList(['switch']) });
        const fontSizeSel = makeEl();
        const container = makeEl();
        container.querySelectorAll = (sel) => (sel === 'input, select, textarea' ? [input] : sel === '.switch' ? [sw] : []);
        const ctx = loadSection({ els: { 'sec-ui': container, responseFontSize: fontSizeSel } });
        ctx.fireDomReady();
        input.fire('change');
        input.fire('input');
        sw.fire('click');
        fontSizeSel.fire('change');
        assert.ok(ctx.dirtyCalls.length >= 4);
    });

    it('wireDirty and wireResponseFontSize handle missing elements', () => {
        const ctx = loadSection({});
        ctx.fireDomReady();
        assert.ok(true);
    });

    it('registers with the settings panel when available', () => {
        const ctx = loadSection({});
        assert.ok(ctx.registered.length === 1);
        assert.ok(ctx.registered[0].name === 'ui');
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
        assert.ok(ctx.registered[0].name === 'ui');
    });
});
