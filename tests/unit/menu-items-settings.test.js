// menu-items-settings.test.js — Unit tests for webui/js/settings/sections/menu-items.js
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

function makeEl(tag, overrides) {
    const el = Object.assign({
        tagName: tag,
        value: '',
        textContent: '',
        className: '',
        selected: false,
        style: {},
        children: [],
        parentNode: null,
        classList: makeClassList(),
        _listeners: {},
        addEventListener(type, fn) { (this._listeners[type] = this._listeners[type] || []).push(fn); },
        fire(type) { (this._listeners[type] || []).forEach((fn) => fn.call(this)); },
        appendChild(child) { child.parentNode = this; this.children.push(child); return child; },
        remove() {
            if (!this.parentNode) return;
            const i = this.parentNode.children.indexOf(this);
            if (i >= 0) this.parentNode.children.splice(i, 1);
        },
        querySelectorAll(sel) {
            const wanted = sel.split(',').map((s) => s.trim()).filter(Boolean);
            const out = [];
            const walk = (node) => {
                for (const child of node.children || []) {
                    if (wanted.includes(child.tagName)) out.push(child);
                    walk(child);
                }
            };
            walk(this);
            return out;
        },
    }, overrides);
    if (tag === 'select') {
        Object.defineProperty(el, 'value', {
            get() {
                const selected = el.children.find((c) => c.selected);
                if (selected) return selected.value;
                return el.children[0] ? el.children[0].value : '';
            },
            set(v) { el._valueOverride = v; },
        });
    }
    return el;
}

function loadSection(opts) {
    const { els, withSettingsPanel, addQaBtn, addTrayBtn } = opts || {};
    const elementMap = els || {};
    const domContentLoaded = [];
    const registered = [];
    const dirtyCalls = [];
    const panelStub = {
        registerSection: (name, mod) => { registered.push({ name, mod }); },
        markDirty: () => { dirtyCalls.push(true); },
    };
    const settingsPanel = opts && 'withSettingsPanel' in opts ? withSettingsPanel : panelStub;
    const timers = [];
    const loadHandlers = [];

    const sandbox = {
        document: {
            getElementById: (id) => elementMap[id] || null,
            createElement: (tag) => makeEl(tag),
            addEventListener: (type, fn) => { if (type === 'DOMContentLoaded') domContentLoaded.push(fn); },
        },
        window: {
            SettingsPanel: settingsPanel,
            addEventListener: (type, fn) => { if (type === 'load') loadHandlers.push(fn); },
        },
        setTimeout: (fn) => { timers.push(fn); },
        console,
    };
    sandbox.global = sandbox;

    const src = fs.readFileSync(path.resolve(__dirname, '..', '..', 'webui', 'js', 'settings', 'sections', 'menu-items.js'), 'utf-8');
    vm.runInContext(src, vm.createContext(sandbox));

    return {
        sandbox,
        registered,
        dirtyCalls,
        timers,
        module: registered[0] ? registered[0].mod : null,
        fireDomReady: () => domContentLoaded.forEach((fn) => fn()),
    };
}

describe('Menu items settings section', () => {
    it('load renders quick access and tray tables', () => {
        const qaBody = makeEl('tbody');
        const trayBody = makeEl('tbody');
        const ctx = loadSection({ els: { qaTableBody: qaBody, trayTableBody: trayBody } });
        ctx.module.load({
            menuItems: {
                quickAccess: [{ menuText: 'QA', command: 'qa-cmd' }],
                tray: [{ menuText: 'Exit', action: 'exit' }],
            },
        });

        const qaRows = qaBody.querySelectorAll('tr');
        assert.ok(qaRows.length === 1);
        const qaInputs = qaRows[0].querySelectorAll('input, select');
        assert.ok(qaInputs.length === 2);
        assert.ok(qaInputs[0].value === 'QA');
        assert.ok(qaInputs[1].value === 'qa-cmd');
        assert.ok(qaRows[0].children.some((td) => td.className === 'actions'));

        const trayRows = trayBody.querySelectorAll('tr');
        assert.ok(trayRows.length === 1);
        const traySelect = trayRows[0].querySelectorAll('select')[0];
        assert.ok(traySelect.children.length === 2);
        assert.ok(traySelect.children[0].value === 'reload');
        assert.ok(traySelect.children[1].value === 'exit');
        assert.ok(traySelect.children[1].selected === true);
    });

    it('load handles missing menuItems and missing tbody', () => {
        const ctx = loadSection({});
        ctx.module.load(null);
        ctx.module.load({ other: 1 });
        assert.ok(true);
    });

    it('input and select changes mark dirty', () => {
        const qaBody = makeEl('tbody');
        const ctx = loadSection({ els: { qaTableBody: qaBody } });
        ctx.module.load({ menuItems: { quickAccess: [{ menuText: 'A', command: 'B' }], tray: [] } });
        const input = qaBody.querySelectorAll('tr')[0].querySelectorAll('input')[0];
        input.fire('input');
        assert.ok(ctx.dirtyCalls.length >= 1);
    });

    it('delete button removes the row and marks dirty', () => {
        const qaBody = makeEl('tbody');
        const ctx = loadSection({ els: { qaTableBody: qaBody } });
        ctx.module.load({ menuItems: { quickAccess: [{ menuText: 'A', command: 'B' }], tray: [] } });
        const row = qaBody.querySelectorAll('tr')[0];
        const delBtn = row.children.find((td) => td.className === 'actions').children[0];
        delBtn.fire('click');
        assert.ok(qaBody.querySelectorAll('tr').length === 0);
        assert.ok(ctx.dirtyCalls.length >= 1);
    });

    it('save reads table rows into menu items', () => {
        const qaBody = makeEl('tbody');
        const trayBody = makeEl('tbody');
        const ctx = loadSection({ els: { qaTableBody: qaBody, trayTableBody: trayBody } });
        ctx.module.load({
            menuItems: {
                quickAccess: [{ menuText: 'A', command: 'cmd1' }],
                tray: [{ menuText: 'T', action: 'exit' }],
            },
        });
        const data = JSON.parse(JSON.stringify(ctx.module.save()));
        assert.strictEqual(JSON.stringify(data), JSON.stringify({
            menuItems: {
                quickAccess: [{ menuText: 'A', command: 'cmd1' }],
                tray: [{ menuText: 'T', action: 'exit' }],
            },
        }));

        const empty = loadSection({});
        assert.deepStrictEqual(JSON.parse(JSON.stringify(empty.module.save())), {
            menuItems: { quickAccess: [], tray: [] },
        });
    });

    it('addRow appends rows for quick access and tray and marks dirty', () => {
        const qaBody = makeEl('tbody');
        const trayBody = makeEl('tbody');
        const addQa = makeEl('button');
        const addTray = makeEl('button');
        const ctx = loadSection({
            els: { qaTableBody: qaBody, trayTableBody: trayBody, addQaRow: addQa, addTrayRow: addTray },
        });
        ctx.fireDomReady();

        addQa.fire('click');
        addTray.fire('click');
        assert.ok(qaBody.querySelectorAll('tr').length === 1);
        assert.ok(trayBody.querySelectorAll('tr').length === 1);
        assert.ok(trayBody.querySelectorAll('select').length === 1);
        assert.ok(ctx.dirtyCalls.length >= 2);

        // Deleting an added row also works
        const row = qaBody.querySelectorAll('tr')[0];
        row.children.find((td) => td.className === 'actions').children[0].fire('click');
        assert.ok(qaBody.querySelectorAll('tr').length === 0);
    });

    it('addRow and wire tolerate missing tbody and buttons', () => {
        const ctx = loadSection({});
        ctx.fireDomReady();
        assert.ok(true);
    });

    it('registers with the settings panel when available', () => {
        const ctx = loadSection({});
        assert.ok(ctx.registered.length === 1);
        assert.ok(ctx.registered[0].name === 'menu');
        assert.ok(typeof ctx.registered[0].mod.load === 'function');
        assert.ok(typeof ctx.registered[0].mod.save === 'function');
    });

    it('defers registration until SettingsPanel appears', () => {
        const ctx = loadSection({ withSettingsPanel: undefined });
        assert.ok(ctx.registered.length === 0);
        assert.ok(ctx.timers.length >= 1);
        ctx.sandbox.window.SettingsPanel = {
            registerSection: (name, mod) => ctx.registered.push({ name, mod }),
            markDirty: () => {},
        };
        ctx.timers.forEach((fn) => fn());
        assert.ok(ctx.registered.length === 1);
        assert.ok(ctx.registered[0].name === 'menu');
    });
});
