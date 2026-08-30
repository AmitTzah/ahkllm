// sysmsg-modal.test.js — Unit tests for webui/js/settings/sections/sysmsg-modal.js
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
        checked: false,
        selectedIndex: -1,
        style: {},
        classList: makeClassList(),
        dataset: {},
        _listeners: {},
        addEventListener(type, fn) { (this._listeners[type] = this._listeners[type] || []).push(fn); },
        fire(type) { (this._listeners[type] || []).forEach((fn) => fn.call(this)); },
        querySelector(sel) {
            if (sel === 'input[name="sysMsgMode"][value="file"]') return this._fileRadio || null;
            if (sel === 'input[name="sysMsgMode"][value="inline"]') return this._inlineRadio || null;
            if (sel === '.sysmsg-label') return this._label || null;
            return null;
        },
    }, overrides);
}

function loadSection(opts) {
    const { els, target, cmds, withSettingsPanel, fileRadio, inlineRadio, modal, ipc } = opts || {};
    const elementMap = els || {};
    const domContentLoaded = [];
    const dirtyCalls = [];
    const modalEl = modal !== undefined ? modal : makeEl();
    if (modalEl) {
        modalEl._fileRadio = fileRadio !== undefined ? fileRadio : makeEl();
        modalEl._inlineRadio = inlineRadio !== undefined ? inlineRadio : makeEl();
    }
    if (!elementMap.sysMsgEditModal) elementMap.sysMsgEditModal = modalEl;
    const panelStub = {
        registerSection: () => {},
        markDirty: () => { dirtyCalls.push(true); },
    };
    const settingsPanel = opts && 'withSettingsPanel' in opts ? withSettingsPanel : panelStub;

    const sandbox = {
        document: {
            getElementById: (id) => elementMap[id] || null,
            addEventListener: (type, fn) => { if (type === 'DOMContentLoaded') domContentLoaded.push(fn); },
        },
        window: {
            _sysMsgTarget: target || null,
            Cmds: cmds || null,
            SettingsPanel: settingsPanel,
            addEventListener: () => {},
        },
        console,
        Ipc: ipc || null,
    };
    sandbox.global = sandbox;

    const sharedSrc = fs.readFileSync(path.resolve(__dirname, '..', '..', 'webui', 'js', 'shared', 'settings-shared.js'), 'utf-8');
    const src = fs.readFileSync(path.resolve(__dirname, '..', '..', 'webui', 'js', 'settings', 'sections', 'sysmsg-modal.js'), 'utf-8');
    const ctx = vm.createContext(sandbox);
    vm.runInContext(sharedSrc, ctx);
    vm.runInContext(src, ctx);

    return {
        sandbox,
        dirtyCalls,
        populate: sandbox.window.populateSysMsgModal,
        fireDomReady: () => domContentLoaded.forEach((fn) => fn()),
        get modal() { return elementMap.sysMsgEditModal; },
    };
}

describe('System message modal', () => {
    it('radio change swaps the visible section', () => {
        const fileRadio = makeEl();
        const inlineRadio = makeEl();
        const fileSection = makeEl();
        const inlineSection = makeEl();
        const ctx = loadSection({
            els: { smFileSection: fileSection, smInlineSection: inlineSection },
            fileRadio,
            inlineRadio,
        });
        ctx.fireDomReady();
        inlineRadio.checked = true;
        inlineRadio.fire('change');
        assert.ok(fileSection.style.display === 'none');
        assert.ok(inlineSection.style.display === '');
        inlineRadio.checked = false;
        fileRadio.checked = true;
        fileRadio.fire('change');
        assert.ok(fileSection.style.display === '');
        assert.ok(inlineSection.style.display === 'none');
    });

    it('populate opens file mode and strips directory prefix when needed', () => {
        const fileRadio = makeEl();
        const inlineRadio = makeEl({ checked: true });
        const fileSelect = makeEl();
        const fileSection = makeEl();
        const inlineSection = makeEl();
        const ctx = loadSection({
            els: {
                smFileSection: fileSection,
                smInlineSection: inlineSection,
                smFileSelect: fileSelect,
                smInlineText: makeEl(),
            },
            fileRadio,
            inlineRadio,
        });
        fileSelect.selectedIndex = -1;
        ctx.populate({ systemMessageFile: 'system-messages/refine.txt' });
        assert.ok(fileRadio.checked === true);
        assert.ok(inlineRadio.checked === false);
        assert.ok(fileSection.style.display === '');
        assert.ok(inlineSection.style.display === 'none');
        assert.ok(fileSelect.value === 'refine.txt', 'prefix stripped');
        assert.ok(ctx.modal.classList.contains('open'));
    });

    it('populate keeps full filename when select already matches', () => {
        const fileSelect = makeEl();
        fileSelect.selectedIndex = 0;
        const ctx = loadSection({ els: { smFileSelect: fileSelect } });
        ctx.populate({ systemMessageFile: 'refine.txt' });
        assert.ok(fileSelect.value === 'refine.txt');
    });

    it('populate does not strip names without a slash', () => {
        const fileSelect = makeEl();
        fileSelect.selectedIndex = -1;
        const ctx = loadSection({ els: { smFileSelect: fileSelect } });
        ctx.populate({ systemMessageFile: 'plain.txt' });
        assert.ok(fileSelect.value === 'plain.txt');
    });

    it('save preserves a custom unlisted system-message file (bug #39)', () => {
        const saveBtn = makeEl();
        const fileSelect = makeEl();
        fileSelect.selectedIndex = -1; // no option matches the custom file
        const card = makeEl();
        card._label = makeEl();
        const ctx = loadSection({
            els: { sysMsgEditSave: saveBtn, smFileSelect: fileSelect },
            target: { type: 'assistant', card },
        });
        ctx.populate({ systemMessageFile: 'default-settings/system-messages/my-custom-prompt.txt' });
        ctx.fireDomReady();
        saveBtn.fire('click');
        assert.ok(card.dataset.systemMessageFile === 'default-settings/system-messages/my-custom-prompt.txt',
            'custom file must survive the modal save, got ' + JSON.stringify(card.dataset.systemMessageFile));
    });

    it('save clears the file when the user explicitly picks "(none)"', () => {
        const saveBtn = makeEl();
        const fileSelect = makeEl();
        fileSelect.selectedIndex = 0; // "(none)" option selected
        const card = makeEl();
        card._label = makeEl();
        const ctx = loadSection({
            els: { sysMsgEditSave: saveBtn, smFileSelect: fileSelect },
            target: { type: 'assistant', card },
        });
        ctx.populate({ systemMessageFile: 'refine.txt' });
        ctx.fireDomReady();
        fileSelect.value = '';
        saveBtn.fire('click');
        assert.ok(card.dataset.systemMessageFile === '',
            'explicit "(none)" must clear the file, got ' + JSON.stringify(card.dataset.systemMessageFile));
    });

    it('populate opens inline mode and sets the inline text', () => {
        const fileRadio = makeEl({ checked: true });
        const inlineRadio = makeEl();
        const inlineText = makeEl();
        const fileSection = makeEl();
        const inlineSection = makeEl();
        const ctx = loadSection({
            els: { smInlineText: inlineText, smFileSection: fileSection, smInlineSection: inlineSection },
            fileRadio,
            inlineRadio,
        });
        ctx.populate({ systemMessage: 'You are helpful.' });
        assert.ok(inlineRadio.checked === true);
        assert.ok(fileRadio.checked === false);
        assert.ok(inlineSection.style.display === '');
        assert.ok(fileSection.style.display === 'none');
        assert.ok(inlineText.value === 'You are helpful.');
    });

    it('populate tolerates missing modal, radios, sections and text', () => {
        const ctx = loadSection({ modal: null });
        ctx.populate({ systemMessageFile: 'a.txt' });
        ctx.populate({ systemMessage: 'x' });
        assert.ok(true);
    });

    it('save does nothing without a target', () => {
        const saveBtn = makeEl();
        const ctx = loadSection({ els: { sysMsgEditSave: saveBtn }, target: null });
        ctx.fireDomReady();
        saveBtn.fire('click');
        assert.ok(ctx.dirtyCalls.length === 0);
    });

    it('save updates assistant card data and label', () => {
        const saveBtn = makeEl();
        const label = makeEl();
        const card = makeEl();
        card._label = label;
        const inlineText = makeEl({ value: 'Inline msg' });
        const inlineRadio = makeEl({ checked: true });
        const ctx = loadSection({
            els: { sysMsgEditSave: saveBtn, smInlineText: inlineText },
            inlineRadio,
            target: { type: 'assistant', card },
        });
        ctx.fireDomReady();
        saveBtn.fire('click');
        assert.ok(card.dataset.systemMessage === 'Inline msg');
        assert.ok(card.dataset.systemMessageFile === '');
        assert.ok(label.textContent.indexOf('(inline) · Inline msg') >= 0);
        assert.ok(!ctx.modal.classList.contains('open'));
        assert.ok(ctx.dirtyCalls.length >= 1);
    });

    it('save updates assistant card when label is missing', () => {
        const saveBtn = makeEl();
        const card = makeEl();
        card._label = null;
        const fileSelect = makeEl({ value: 'sys.txt' });
        const ctx = loadSection({
            els: { sysMsgEditSave: saveBtn, smFileSelect: fileSelect },
            fileRadio: makeEl(),
            inlineRadio: makeEl(),
            target: { type: 'assistant', card },
        });
        ctx.fireDomReady();
        saveBtn.fire('click');
        assert.ok(card.dataset.systemMessageFile === 'sys.txt');
        assert.ok(card.dataset.systemMessage === '');
    });

    it('save updates command via window.Cmds', () => {
        const saveBtn = makeEl();
        const commands = [{ commandName: 'A' }];
        let selectedIdx = -1;
        const cmds = {
            commands: () => commands,
            selectCommand: (i) => { selectedIdx = i; },
        };
        const inlineRadio = makeEl({ checked: true });
        const inlineText = makeEl({ value: 'Cmd msg' });
        const ctx = loadSection({
            els: { sysMsgEditSave: saveBtn, smInlineText: inlineText },
            inlineRadio,
            cmds,
            target: { type: 'command', idx: 0 },
        });
        ctx.fireDomReady();
        saveBtn.fire('click');
        assert.ok(commands[0].systemMessage === 'Cmd msg');
        assert.ok(selectedIdx === 0);
        assert.ok(ctx.dirtyCalls.length >= 1);
    });

    it('save handles command without a matching command and without Cmds', () => {
        const saveBtn = makeEl();
        const ctx = loadSection({
            els: { sysMsgEditSave: saveBtn },
            inlineRadio: makeEl({ checked: true }),
            target: { type: 'command', idx: 5 },
        });
        ctx.fireDomReady();
        saveBtn.fire('click');
        assert.ok(ctx.dirtyCalls.length >= 1);

        const saveBtn2 = makeEl();
        const ctx2 = loadSection({
            els: { sysMsgEditSave: saveBtn2 },
            cmds: null,
            target: { type: 'command', idx: 0 },
        });
        ctx2.fireDomReady();
        saveBtn2.fire('click');
        assert.ok(ctx2.dirtyCalls.length >= 1);
    });

    it('save handles missing modal by reading file select directly', () => {
        const saveBtn = makeEl();
        const fileSelect = makeEl({ value: 'file.txt' });
        const ctx = loadSection({
            els: { sysMsgEditSave: saveBtn, smFileSelect: fileSelect },
            modal: null,
            target: { type: 'command', idx: 0 },
            cmds: { commands: () => [{}], selectCommand: () => {} },
        });
        ctx.fireDomReady();
        saveBtn.fire('click');
        assert.ok(ctx.dirtyCalls.length >= 1);
    });

    it('open-folder and refresh controls send the expected IPC actions', () => {
        const actions = [];
        const openBtn = makeEl();
        const refreshBtn = makeEl();
        const ctx = loadSection({
            els: { smOpenFolder: openBtn, smRefreshFiles: refreshBtn },
            ipc: { postToHost: (action) => actions.push(action) },
        });
        ctx.fireDomReady();
        openBtn.fire('click');
        refreshBtn.fire('click');
        assert.deepStrictEqual(actions, ['openSystemMessagesFolder', 'requestSystemMessageFiles']);
    });

    it('renders bundled and custom .txt files and exposes the real user folder', () => {
        const defaults = makeEl({ innerHTML: '' });
        const users = makeEl({ innerHTML: '' });
        const folder = makeEl({ textContent: '' });
        const ctx = loadSection({ els: { smDefaultFiles: defaults, smUserFiles: users, smUserFolderPath: folder } });
        ctx.sandbox.window.updateSystemMessageFiles({
            defaultFiles: ['refine.txt'],
            userFiles: ['my-prompt.txt'],
            userFolder: 'C:\\Users\\Test\\AppData\\Roaming\\AhkLLM\\system-messages',
        });
        assert.ok(defaults.innerHTML.indexOf('default-settings/system-messages/refine.txt') >= 0);
        assert.ok(users.innerHTML.indexOf('system-messages/my-prompt.txt') >= 0);
        assert.ok(folder.textContent.indexOf('AhkLLM\\system-messages') >= 0);
    });

    it('save button handler is not wired when button is missing', () => {
        const ctx = loadSection({ els: { sysMsgEditSave: null } });
        ctx.fireDomReady();
        assert.ok(true);
    });
});
