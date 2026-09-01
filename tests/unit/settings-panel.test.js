// settings-panel.test.js — Unit tests for webui/js/settings/settings-panel.js
// (tab switching, dirty tracking, save/reset flow, section module wiring)
const { describe, it } = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { installIpc } = require('./helpers/ipc-test-utils');

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
        style: {},
        classList: makeClassList(),
        disabled: false,
        scrollTop: 0,
        _listeners: {},
        attributes: {},
        getAttribute(name) { return this.attributes[name] !== undefined ? this.attributes[name] : null; },
        addEventListener(type, fn) { (this._listeners[type] = this._listeners[type] || []).push(fn); },
        fire(type) { (this._listeners[type] || []).forEach((fn) => fn.call(this)); },
    }, overrides);
}

function loadPanel({ navItems, sections, saveBtn, resetBtn, content, elements, showConfirm, withSettingsPanel } = {}) {
    const itemGeneral = makeEl({ attributes: { 'data-section': 'general' } });
    const itemModels = makeEl({ attributes: { 'data-section': 'models' } });
    const secGeneral = makeEl();
    const secModels = makeEl();
    const save = saveBtn !== undefined ? saveBtn : makeEl();
    const reset = resetBtn !== undefined ? resetBtn : makeEl();
    const contentEl = content !== undefined ? content : makeEl();
    const navItemsList = navItems || [itemGeneral, itemModels];
    const sectionsList = sections || [secGeneral, secModels];
    const els = Object.assign({
        'sec-general': secGeneral,
        'sec-models': secModels,
        'nav-general': itemGeneral,
        'nav-models': itemModels,
    }, elements || {});
    const posted = [];
    const confirmCalls = [];
    const registered = [];

    const sandbox = {
        document: {
            querySelectorAll(sel) {
                if (sel === '.settings-nav .nav-item[data-section]') return navItemsList;
                if (sel === '.section-card[id^="sec-"]') return sectionsList;
                if (sel && sel.indexOf('.settings-nav .nav-item[data-section="') === 0) {
                    const name = sel.match(/data-section="([^"]+)"/)[1];
                    return [els['nav-' + name] || null].filter(Boolean);
                }
                return [];
            },
            querySelector(sel) {
                if (sel === '.nav-footer .btn-primary') return save;
                if (sel === '.nav-footer .btn-ghost') return reset;
                if (sel === '.settings-content') return contentEl;
                if (sel && sel.indexOf('.settings-nav .nav-item[data-section="') === 0) {
                    const name = sel.match(/data-section="([^"]+)"/)[1];
                    return els['nav-' + name] || null;
                }
                return null;
            },
            getElementById(id) { return els[id] || null; },
            addEventListener() {},
        },
        window: {
            chrome: { webview: { postMessage: (msg) => posted.push(msg) } },
            _showConfirm: showConfirm || ((title, message, button, cb) => { confirmCalls.push({ title, message, button, cb }); }),
            SettingsPanel: withSettingsPanel === undefined ? { registerSection() {} } : withSettingsPanel,
        },
        console: {
            log: () => {},
            error: () => {},
        },
    };
    sandbox.global = sandbox;

    const src = fs.readFileSync(path.resolve(__dirname, '..', '..', 'webui', 'js', 'settings', 'settings-panel.js'), 'utf-8');
    const ctx = vm.createContext(sandbox);
    installIpc(ctx);
    vm.runInContext(src, ctx);

    const panel = sandbox.window.SettingsPanel;
    panel.__internals = {
        itemGeneral, itemModels, secGeneral, secModels, save, reset, contentEl, els, posted, confirmCalls,
    };
    // Public surface for tests to register fake section modules.
    panel._registerForTest = (name, mod) => panel.registerSection(name, mod);
    return panel;
}

describe('SettingsPanel', () => {
    it('init wires nav clicks, save/reset buttons and shows general', () => {
        const panel = loadPanel();
        const { itemGeneral, itemModels, secGeneral, secModels, save, reset, contentEl } = panel.__internals;

        panel.init();
        assert.ok(panel.__internals.posted.length === 0);
        assert.ok(secGeneral.style.display === '' || secGeneral.style.display === undefined, 'general shown by default');

        itemModels.fire('click');
        assert.ok(secModels.style.display === '');
        assert.ok(secGeneral.style.display === 'none');
        assert.ok(itemModels.classList.contains('active'));
        assert.ok(!itemGeneral.classList.contains('active'));
        assert.ok(contentEl.scrollTop === 0);

        // Second init must not rewire listeners.
        const before = itemGeneral._listeners.click.length;
        panel.init();
        assert.ok(itemGeneral._listeners.click.length === before, 'init is idempotent');

        save.disabled = true;
        panel.markDirty();
        assert.ok(save.disabled === false);
        panel.clearDirty();
        assert.ok(save.disabled === true);
    });

    it('save button click saves settings, reset button opens confirm modal', () => {
        const panel = loadPanel();
        const { save, reset, posted, confirmCalls } = panel.__internals;
        panel.init();
        panel.onSettingsReceived({ some: 'value' });

        save.fire('click');
        const msg = JSON.parse(posted[posted.length - 1]);
        assert.ok(msg.action === 'saveSettings');

        reset.fire('click');
        assert.ok(confirmCalls.length === 1);
        assert.ok(confirmCalls[0].title === 'Reset to Defaults');
        confirmCalls[0].cb();
        const resetMsg = JSON.parse(posted[posted.length - 1]);
        assert.ok(resetMsg.action === 'requestDefaultSettings');
    });

    it('init tolerates missing save/reset buttons', () => {
        const panel = loadPanel({ saveBtn: null, resetBtn: null });
        panel.init();
        assert.ok(panel.isDirty() === false);
    });

    it('showSection handles missing target, active nav and content', () => {
        const panel = loadPanel();
        const { secGeneral, secModels } = panel.__internals;
        panel.init();
        panel.showSection('does-not-exist');
        assert.ok(secGeneral.style.display === 'none');
        assert.ok(secModels.style.display === 'none');

        const noContent = loadPanel({ content: null });
        noContent.init();
        noContent.showSection('general');
        assert.ok(noContent.__internals.secGeneral.style.display === '');
    });

    it('markDirty/clearDirty guard repeated calls and missing save button', () => {
        const panel = loadPanel({ saveBtn: null });
        panel.markDirty();
        assert.ok(panel.isDirty() === true);
        panel.markDirty(); // already dirty — no-op
        assert.ok(panel.isDirty() === true);
        panel.clearDirty();
        assert.ok(panel.isDirty() === false);
    });

    it('loadSettings deep-clones defaults and clears dirty', () => {
        const panel = loadPanel();
        const settings = { nested: { value: 1 } };
        panel.markDirty();
        panel.onSettingsReceived(settings);
        assert.ok(panel.isDirty() === false);
        settings.nested.value = 999;
        panel.onSettingsReceived({ x: 1 }); // triggers loadSettings path again
        assert.ok(panel.isDirty() === false);
    });

    it('saveSettings does nothing without loaded settings', () => {
        const panel = loadPanel();
        const { posted } = panel.__internals;
        panel.saveSettings();
        assert.ok(posted.length === 0);
    });

    it('saveSettings aborts when a validator fails and selects the offending command', () => {
        const panel = loadPanel();
        const { posted, confirmCalls } = panel.__internals;
        let selectedIdx = -1;
        panel.onSettingsReceived({});
        panel.registerSection('commands', {
            validate: () => ({ valid: false, message: 'conflict!', selectIdx: 2 }),
            selectCommand: (i) => { selectedIdx = i; },
        });
        panel.saveSettings();
        assert.ok(confirmCalls.length === 1);
        assert.ok(confirmCalls[0].message === 'conflict!');
        assert.ok(selectedIdx === 2);
        assert.ok(posted.length === 0);
    });

    it('saveSettings handles validator failure without selectIdx or selectCommand', () => {
        const panel = loadPanel();
        const { confirmCalls } = panel.__internals;
        panel.onSettingsReceived({});
        panel.registerSection('bad', { validate: () => ({ valid: false }) });
        panel.registerSection('noSelect', { validate: () => ({ valid: false, selectIdx: 1 }) });
        panel.saveSettings();
        assert.ok(confirmCalls.length === 1);
        assert.ok(confirmCalls[0].message === 'Please fix the errors before saving.');
    });

    it('saveSettings collects section data and posts saveSettings message', () => {
        const panel = loadPanel();
        const { posted } = panel.__internals;
        panel.onSettingsReceived({});
        panel.registerSection('a', { save: () => ({ x: 1 }) });
        panel.registerSection('b', { save: () => null });
        panel.registerSection('c', {});
        panel.registerSection('d', { validate: () => undefined, save: () => ({ y: 2 }) });
        panel.saveSettings();
        const msg = JSON.parse(posted[posted.length - 1]);
        assert.ok(msg.action === 'saveSettings');
        assert.deepStrictEqual(msg.data, { x: 1, y: 2 });
    });

    it('resetToDefaults posts requestDefaultSettings from confirm callback', () => {
        const panel = loadPanel();
        const { posted, confirmCalls } = panel.__internals;
        panel.resetToDefaults();
        assert.ok(confirmCalls.length === 1);
        assert.ok(confirmCalls[0].button === 'Reset');
        assert.ok(posted.length === 0);
        confirmCalls[0].cb();
        assert.ok(JSON.parse(posted[posted.length - 1]).action === 'requestDefaultSettings');
    });

    it('reloadWithDefaults ignores falsy defaults, loads modules and marks dirty', () => {
        const panel = loadPanel();
        panel.reloadWithDefaults(null);
        assert.ok(panel.isDirty() === false);

        const loaded = [];
        panel.registerSection('a', { load: (d) => loaded.push(d) });
        panel.registerSection('b', {});
        const defaults = { theme: { darkMode: true } };
        panel.reloadWithDefaults(defaults);
        assert.ok(loaded.length === 1 && loaded[0] === defaults);
        assert.ok(panel.isDirty() === true);
    });

    it('handleSettingsSaved clears dirty on success and logs on failure', () => {
        const errors = [];
        const logs = [];
        const sandbox = loadPanelWithConsole({
            log: (m) => logs.push(m),
            error: (...args) => errors.push(args),
        });
        sandbox.onSettingsReceived({});
        sandbox.markDirty();
        sandbox.handleSettingsSaved({ success: true });
        assert.ok(sandbox.isDirty() === false);
        assert.ok(logs.length === 1);

        sandbox.handleSettingsSaved({ success: false, error: 'boom' });
        sandbox.handleSettingsSaved(null);
        assert.ok(errors.length === 2);
        assert.ok(errors[1][1].indexOf('unknown') >= 0);
    });

    it('onSettingsReceived loads data into every registered section module', () => {
        const panel = loadPanel();
        const loaded = [];
        panel.registerSection('a', { load: (d) => loaded.push(d) });
        const data = { theme: {} };
        panel.onSettingsReceived(data);
        assert.ok(loaded.length === 1 && loaded[0] === data);
    });
});

function loadPanelWithConsole(consoleMock) {
    const itemGeneral = makeEl({ attributes: { 'data-section': 'general' } });
    const secGeneral = makeEl();
    const save = makeEl();
    const reset = makeEl();
    const posted = [];
    const els = { 'sec-general': secGeneral, 'nav-general': itemGeneral };
    const sandbox = {
        document: {
            querySelectorAll(sel) {
                if (sel === '.settings-nav .nav-item[data-section]') return [itemGeneral];
                if (sel === '.section-card[id^="sec-"]') return [secGeneral];
                return [];
            },
            querySelector(sel) {
                if (sel === '.nav-footer .btn-primary') return save;
                if (sel === '.nav-footer .btn-ghost') return reset;
                if (sel === '.settings-content') return makeEl();
                if (sel && sel.indexOf('.settings-nav .nav-item[data-section="') === 0) {
                    const name = sel.match(/data-section="([^"]+)"/)[1];
                    return els['nav-' + name] || null;
                }
                return null;
            },
            getElementById(id) { return id === 'sec-general' ? secGeneral : null; },
            addEventListener() {},
        },
        window: {
            chrome: { webview: { postMessage: (msg) => posted.push(msg) } },
            _showConfirm() {},
            SettingsPanel: { registerSection() {} },
        },
        console: consoleMock,
    };
    sandbox.global = sandbox;
    const src = fs.readFileSync(path.resolve(__dirname, '..', '..', 'webui', 'js', 'settings', 'settings-panel.js'), 'utf-8');
    const ctx = vm.createContext(sandbox);
    installIpc(ctx);
    vm.runInContext(src, ctx);
    return sandbox.window.SettingsPanel;
}


describe('SettingsPanel late settings snapshot protection', () => {
    it('does not overwrite dirty edits with an unsolicited late appSettings snapshot', () => {
        const panel = loadPanel();
        const loaded = [];
        panel.registerSection('fake', { load: (data) => loaded.push(data) });
        panel.onSettingsReceived({ ui: { responseFont: 'Inter' } });
        panel.markDirty();
        panel.onSettingsReceived({ ui: { responseFont: 'Inter-late' } });
        assert.strictEqual(loaded.length, 1);
        assert.strictEqual(loaded[0].ui.responseFont, 'Inter');
        assert.strictEqual(panel.isDirty(), true);
    });

    it('accepts the settings refresh emitted while a save is in flight', () => {
        const panel = loadPanel();
        const loaded = [];
        panel.registerSection('fake', {
            load: (data) => loaded.push(data),
            save: () => ({ ui: { responseFont: 'Georgia' } }),
        });
        panel.onSettingsReceived({ ui: { responseFont: 'Inter' } });
        panel.markDirty();
        panel.saveSettings();
        panel.onSettingsReceived({ ui: { responseFont: 'Georgia' } });
        assert.strictEqual(loaded.length, 2);
        assert.strictEqual(loaded[1].ui.responseFont, 'Georgia');
        assert.strictEqual(panel.isDirty(), false);
    });
});
