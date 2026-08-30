// hotkeys-settings.test.js - Unit tests for webui/js/settings/sections/hotkeys.js
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
        value: '', textContent: '', dataset: {}, classList: makeClassList(), _listeners: {}, focused: 0, selected: 0,
        addEventListener(type, fn) { (this._listeners[type] = this._listeners[type] || []).push(fn); },
        fire(type, event) {
            const evt = event || { target: this, preventDefault() {}, stopPropagation() {} };
            if (!evt.target) evt.target = this;
            if (!evt.preventDefault) evt.preventDefault = () => {};
            if (!evt.stopPropagation) evt.stopPropagation = () => {};
            (this._listeners[type] || []).forEach((fn) => fn.call(this, evt));
        },
        focus() { this.focused++; }, select() { this.selected++; },
        getAttribute(name) { return name === 'data-hotkey-input' ? (this.dataset.hotkeyInput || null) : null; },
        querySelector() { return null; },
    }, overrides);
}

function makeCapture(id) {
    const display = makeEl();
    const status = makeEl({ textContent: 'click to record' });
    const manualBtn = makeEl({ textContent: 'AHK' });
    const manualInput = makeEl();
    const kc = makeEl({ dataset: { hotkeyInput: id } });
    kc.querySelector = (sel) => ({ '.key-display': display, '.status': status, '.key-manual-toggle': manualBtn, '.key-manual-input': manualInput }[sel] || null);
    return { kc, display, status, manualBtn, manualInput };
}

function loadSection(opts) {
    const { els, keyCaptures, withSettingsPanel, timeoutImpl } = opts || {};
    const elementMap = els || {};
    const domContentLoaded = [];
    const registered = [];
    const dirtyCalls = [];
    const posted = [];
    const timers = [];
    const panelStub = { registerSection: (name, mod) => { registered.push({ name, mod }); }, markDirty: () => { dirtyCalls.push(true); } };
    const settingsPanel = opts && 'withSettingsPanel' in opts ? withSettingsPanel : panelStub;
    const setTimeoutStub = timeoutImpl || ((fn, delay) => { timers.push(fn); return timers.length; });
    const sandbox = {
        document: {
            getElementById: (id) => elementMap[id] || null,
            querySelectorAll: (sel) => (sel === '.key-capture' ? (keyCaptures || []) : []),
            addEventListener: (type, fn) => { if (type === 'DOMContentLoaded') domContentLoaded.push(fn); },
        },
        window: { SettingsPanel: settingsPanel, chrome: { webview: { postMessage: (msg) => posted.push(msg) } } },
        setTimeout: setTimeoutStub, console,
    };
    sandbox.global = sandbox;
    const sharedSrc = fs.readFileSync(path.resolve(__dirname, '..', '..', 'webui', 'js', 'shared', 'settings-shared.js'), 'utf-8');
    const src = fs.readFileSync(path.resolve(__dirname, '..', '..', 'webui', 'js', 'settings', 'sections', 'hotkeys.js'), 'utf-8');
    const ctx = vm.createContext(sandbox);
    vm.runInContext(sharedSrc, ctx);
    vm.runInContext(src, ctx);
    return { sandbox, registered, dirtyCalls, posted, timers, module: registered[0] ? registered[0].mod : null, fireDomReady: () => domContentLoaded.forEach((fn) => fn()) };
}

function keyEvent(key, code, mods) {
    return Object.assign({ key, code: code || '', ctrlKey: false, altKey: false, shiftKey: false, metaKey: false, preventDefault() {}, stopPropagation() {} }, mods || {});
}

describe('Shortcuts settings section', () => {
    it('load populates global shortcuts and the Open Chat menu key', () => {
        const els = { hkMain: makeEl(), hkReload: makeEl(), hkCloseWindows: makeEl(), hkSuspend: makeEl(), chatShortcut: makeEl() };
        const ctx = loadSection({ els });
        ctx.module.load({ hotkeys: { main: '!m', reload: '^r', closeWindows: '^w' }, chatShortcut: '9' });
        assert.strictEqual(els.hkMain.value, '!m');
        assert.strictEqual(els.hkReload.value, '^r');
        assert.strictEqual(els.hkCloseWindows.value, '^w');
        assert.strictEqual(els.hkSuspend.value, '');
        assert.strictEqual(els.chatShortcut.value, '9');
    });

    it('save returns global shortcuts plus the Open Chat menu key', () => {
        const els = { hkMain: makeEl({ value: '!m' }), hkReload: makeEl({ value: '~^!r' }), hkCloseWindows: makeEl({ value: '~^w' }), hkSuspend: makeEl({ value: 'CapsLock & `' }), chatShortcut: makeEl({ value: '9' }) };
        const ctx = loadSection({ els });
        assert.deepStrictEqual(JSON.parse(JSON.stringify(ctx.module.save())), { hotkeys: { main: '!m', reload: '~^!r', closeWindows: '~^w', suspend: 'CapsLock & `' }, chatShortcut: '9' });
        const empty = loadSection({});
        assert.deepStrictEqual(JSON.parse(JSON.stringify(empty.module.save())), { hotkeys: { main: '', reload: '', closeWindows: '', suspend: '' }, chatShortcut: '' });
    });

    it('formats AHK syntax as readable shortcut labels', () => {
        const ctx = loadSection({});
        assert.strictEqual(ctx.module.formatForDisplay('^!r'), 'Ctrl + Alt + R');
        assert.strictEqual(ctx.module.formatForDisplay('~^w'), 'Ctrl + W');
        assert.strictEqual(ctx.module.formatForDisplay('CapsLock & `'), 'Caps Lock + Backtick');
        assert.strictEqual(ctx.module.formatForDisplay(''), 'None');
    });

    it('records a key combination and preserves the pass-through prefix', () => {
        const hidden = makeEl({ value: '~^w' });
        const cap = makeCapture('hkCloseWindows');
        const ctx = loadSection({ els: { hkCloseWindows: hidden }, keyCaptures: [cap.kc] });
        ctx.fireDomReady();
        cap.kc.fire('click');
        assert.ok(cap.kc.classList.contains('listening'));
        cap.kc.fire('keydown', keyEvent('R', 'KeyR', { ctrlKey: true, altKey: true }));
        assert.strictEqual(hidden.value, '~^!r');
        assert.strictEqual(cap.display.textContent, 'Ctrl + Alt + R');
        assert.ok(!cap.kc.classList.contains('listening'));
        assert.ok(cap.kc.classList.contains('pending'));
        assert.strictEqual(cap.status.textContent, 'Save Changes to apply');
        assert.ok(ctx.dirtyCalls.length >= 1);
    });

    it('escape cancels capture and backspace clears a shortcut', () => {
        const hidden = makeEl({ value: '^!r' });
        const cap = makeCapture('hkReload');
        const ctx = loadSection({ els: { hkReload: hidden }, keyCaptures: [cap.kc] });
        ctx.fireDomReady();
        cap.kc.fire('click');
        cap.kc.fire('keydown', keyEvent('Escape', 'Escape'));
        assert.strictEqual(hidden.value, '^!r');
        cap.kc.fire('click');
        cap.kc.fire('keydown', keyEvent('Backspace', 'Backspace'));
        assert.strictEqual(hidden.value, '');
        assert.strictEqual(cap.display.textContent, 'None');
    });

    it('advanced AHK mode edits the raw saved value', () => {
        const hidden = makeEl({ value: '`' });
        const cap = makeCapture('hkMain');
        const ctx = loadSection({ els: { hkMain: hidden }, keyCaptures: [cap.kc] });
        ctx.fireDomReady();
        cap.manualBtn.fire('click');
        assert.ok(cap.kc.classList.contains('manual-open'));
        assert.strictEqual(cap.manualInput.value, '`');
        cap.manualInput.value = 'CapsLock & `';
        cap.manualInput.fire('input');
        assert.strictEqual(hidden.value, 'CapsLock & `');
        assert.strictEqual(cap.display.textContent, 'Caps Lock + Backtick');
        cap.manualBtn.fire('click');
        assert.ok(!cap.kc.classList.contains('manual-open'));
    });

    it('shows pending status until refreshed settings are loaded after save', () => {
        const hidden = makeEl({ value: '^!r' });
        const cap = makeCapture('hkReload');
        const ctx = loadSection({ els: { hkReload: hidden }, keyCaptures: [cap.kc] });
        ctx.fireDomReady();
        cap.kc.fire('click');
        cap.kc.fire('keydown', keyEvent('K', 'KeyK', { ctrlKey: true }));
        assert.ok(cap.kc.classList.contains('pending'));
        assert.strictEqual(cap.status.textContent, 'Save Changes to apply');

        ctx.module.load({ hotkeys: { reload: '^k' } });
        assert.ok(!cap.kc.classList.contains('pending'));
        assert.strictEqual(cap.status.textContent, 'click to record');
    });

    it('wireDirty marks dirty on input and handles missing container', () => {
        const input = makeEl();
        const container = makeEl();
        container.querySelectorAll = (sel) => (sel === 'input, select, textarea' ? [input] : []);
        const ctx = loadSection({ els: { 'sec-hotkeys': container } });
        ctx.fireDomReady();
        input.fire('input');
        assert.ok(ctx.dirtyCalls.length >= 1);
        const missing = loadSection({ els: { 'sec-hotkeys': null } });
        missing.fireDomReady();
        assert.ok(true);
    });

    it('wireKeyCaptures handles captures without a storage input', () => {
        const cap = makeCapture('missing');
        const ctx = loadSection({ keyCaptures: [cap.kc] });
        ctx.fireDomReady();
        cap.kc.fire('click');
        cap.kc.fire('keydown', keyEvent('R', 'KeyR', { ctrlKey: true }));
        assert.ok(true);
    });

    it('registers with the settings panel when available', () => {
        const ctx = loadSection({});
        assert.strictEqual(ctx.registered.length, 1);
        assert.strictEqual(ctx.registered[0].name, 'hotkeys');
        assert.strictEqual(typeof ctx.registered[0].mod.load, 'function');
        assert.strictEqual(typeof ctx.registered[0].mod.save, 'function');
    });

    it('defers registration until SettingsPanel appears', () => {
        const ctx = loadSection({ withSettingsPanel: undefined });
        assert.strictEqual(ctx.registered.length, 0);
        assert.ok(ctx.timers.length >= 1);
        ctx.sandbox.window.SettingsPanel = { registerSection: (name, mod) => ctx.registered.push({ name, mod }), markDirty: () => {} };
        ctx.timers.forEach((fn) => fn());
        assert.strictEqual(ctx.registered.length, 1);
        assert.strictEqual(ctx.registered[0].name, 'hotkeys');
    });
});
