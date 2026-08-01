// commands-save-reorder.test.js — Regression test for _selectedIdx remapping
// after drag-reorder + save. Verifies that reordering commands via drag-drop
// followed by save does not corrupt command data.
const { describe, it } = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

function loadCommandsCoreWithMocks() {
    const sharedSrc = fs.readFileSync(
        path.resolve(__dirname, '..', '..', 'webui', 'js', 'shared', 'settings-shared.js'),
        'utf-8'
    );
    const coreSrc = fs.readFileSync(
        path.resolve(__dirname, '..', '..', 'webui', 'js', 'settings', 'sections', 'commands', 'commands-core.js'),
        'utf-8'
    );

    // Form values that syncDetail reads from DOM — we control these per-test
    let formValues = {};

    const sandbox = {
        document: {
            body: {},
            getElementById: function(id) {
                // syncDetail reads form values — return mock elements
                return {
                    value: formValues[id] !== undefined ? formValues[id] : '',
                    classList: {
                        _classes: [],
                        add: function(c) { if (this._classes.indexOf(c) < 0) this._classes.push(c); },
                        remove: function(c) { this._classes = this._classes.filter(function(x) { return x !== c; }); },
                        contains: function(c) { return this._classes.indexOf(c) >= 0; },
                        toggle: function(c) { if (this.contains(c)) this.remove(c); else this.add(c); }
                    },
                    textContent: formValues[id + '_text'] || ''
                };
            },
            querySelectorAll: function(sel) {
                // #cmdTags .badge — return empty for tag collection
                return [];
            },
            querySelector: function() { return null; },
            addEventListener: function() {},
            createElement: function() { return { style: {} }; }
        },
        window: {
            Cmds: {},
            SettingsPanel: {
                markDirty: function() {},
                registerSection: function() {}
            }
        },
        console: console,
        setTimeout: setTimeout,
        clearTimeout: clearTimeout
    };
    sandbox.global = sandbox;

    const ctx = vm.createContext(sandbox);

    // Load shared helpers, then core module — creates window.Cmds with save, load, etc.
    vm.runInContext(sharedSrc, ctx);
    vm.runInContext(coreSrc, ctx);

    const C = sandbox.window.Cmds;

    // Mock renderList — just tracks the last rendered index
    let lastRenderedIdx = -1;
    C.renderList = function(idx) {
        lastRenderedIdx = idx;
    };

    // Mock syncDetail — reads from formValues and writes to _commands[_selectedIdx]
    C.syncDetail = function() {
        var i = C.selectedIdx();
        if (i < 0 || i >= C.commands().length) return;
        var cmd = C.commands()[i];
        cmd.commandName = formValues['cmdDetailTitle'] || cmd.commandName;
        cmd.menuText = formValues['cmdMenuLabel'] || cmd.menuText;
        cmd.APIModels = formValues['cmdApiModel'] || cmd.APIModels;
        cmd.pasteMode = formValues['cmdPasteMode'] || cmd.pasteMode;
        cmd.userMessage = formValues['cmdUserMessage'] || cmd.userMessage;
        cmd.isFIM = formValues['cmdFim_on'] || false;
        cmd.stream = formValues['cmdStream_on'] || false;
        cmd.showInputBox = formValues['cmdShowInputBox_on'] || false;
        cmd.tags = formValues['cmdTags'] || [];
        // Re-render to update DOM data-index attributes
        C.renderList(i);
    };

    // Mock showPlaceholder
    C.showPlaceholder = function() {};

    // Mock selectCommand — sets selectedIdx and syncs
    C.selectCommand = function(idx) {
        if (idx < 0 || idx >= C.commands().length) return;
        C.syncDetail();
        C.setSelectedIdx(idx);
        C.renderList(idx);
    };

    return {
        Cmds: C,
        formValues: formValues,
        getLastRenderedIdx: function() { return lastRenderedIdx; }
    };
}

describe('commands save reorder — _selectedIdx remapping', () => {
    it('should remap _selectedIdx after save with reordered group orders', () => {
        const ctx = loadCommandsCoreWithMocks();
        const C = ctx.Cmds;

        // Set up two commands: FIM fill (idx 0) and Rephrase (idx 1)
        const fimCmd = { commandName: 'FIM Fill', menuText: 'FIM Fill', APIModels: 'deepseek-v4', pasteMode: 'chat', stream: false, isFIM: true, showInputBox: false, userMessage: 'FIM prompt', tags: [] };
        const rephraseCmd = { commandName: 'Rephrase', menuText: 'Rephrase', APIModels: 'gpt-4o', pasteMode: 'replace', stream: true, isFIM: false, showInputBox: true, userMessage: 'Rephrase prompt', tags: [] };

        C.setCommands([fimCmd, rephraseCmd]);
        C.setSubmenuOrder([]);
        C.setGroupOrders({ '__main__': [0, 1] });
        C.setSelectedIdx(0); // FIM fill is selected
        C.ensureGroupOrders();

        // Populate form values to match FIM fill
        ctx.formValues['cmdDetailTitle'] = 'FIM Fill';
        ctx.formValues['cmdMenuLabel'] = 'FIM Fill';
        ctx.formValues['cmdApiModel'] = 'deepseek-v4';
        ctx.formValues['cmdPasteMode'] = 'chat';
        ctx.formValues['cmdUserMessage'] = 'FIM prompt';

        // Simulate drag: FIM fill dragged below Rephrase
        // groupOrders reflects DOM order after drag
        C.setGroupOrders({ '__main__': [1, 0] }); // Rephrase first, FIM fill second
        C.ensureGroupOrders();

        // Save — this should rebuild _commands with Rephrase at 0, FIM fill at 1
        // AND remap _selectedIdx from 0 to 1
        C.save();

        // _selectedIdx should be remapped from 0 (old FIM fill position) to 1 (new FIM fill position)
        assert.strictEqual(C.selectedIdx(), 1,
            'After save with reordered commands, _selectedIdx should be remapped to FIM fill\'s new position (1), got ' + C.selectedIdx());

        // Commands should be in the new order
        assert.strictEqual(C.commands().length, 2, 'Should still have 2 commands');
        assert.strictEqual(C.commands()[0].commandName, 'Rephrase', 'Rephrase should be at index 0');
        assert.strictEqual(C.commands()[1].commandName, 'FIM Fill', 'FIM Fill should be at index 1');
    });

    it('should NOT corrupt command data on double-save after reorder', () => {
        const ctx = loadCommandsCoreWithMocks();
        const C = ctx.Cmds;

        // Set up two commands
        const fimCmd = { commandName: 'FIM Fill', menuText: 'FIM Fill', APIModels: 'deepseek-v4', pasteMode: 'chat', stream: false, isFIM: true, showInputBox: false, userMessage: 'FIM prompt', tags: [] };
        const rephraseCmd = { commandName: 'Rephrase', menuText: 'Rephrase', APIModels: 'gpt-4o', pasteMode: 'replace', stream: true, isFIM: false, showInputBox: true, userMessage: 'Rephrase prompt', tags: [] };

        C.setCommands([fimCmd, rephraseCmd]);
        C.setSubmenuOrder([]);
        C.setGroupOrders({ '__main__': [0, 1] });
        C.setSelectedIdx(0); // FIM fill selected
        C.ensureGroupOrders();

        // Populate form values for FIM fill (this is what the detail panel shows)
        ctx.formValues['cmdDetailTitle'] = 'FIM Fill';
        ctx.formValues['cmdMenuLabel'] = 'FIM Fill';
        ctx.formValues['cmdApiModel'] = 'deepseek-v4';
        ctx.formValues['cmdPasteMode'] = 'chat';
        ctx.formValues['cmdUserMessage'] = 'FIM prompt';

        // FIRST SAVE: Simulate drag — FIM fill dragged below Rephrase
        C.setGroupOrders({ '__main__': [1, 0] });
        C.ensureGroupOrders();
        const result1 = C.save();

        // After first save: _selectedIdx should be 1 (FIM fill's new position)
        assert.strictEqual(C.selectedIdx(), 1,
            'selectedIdx should be 1 after first reorder save, got ' + C.selectedIdx());
        assert.strictEqual(C.commands()[0].commandName, 'Rephrase', 'Rephrase at 0');
        assert.strictEqual(C.commands()[1].commandName, 'FIM Fill', 'FIM Fill at 1');

        // SECOND SAVE: Without any drag (form still shows FIM Fill data).
        // This is the critical scenario — before the fix, syncDetail would write
        // FIM Fill's form data to _commands[_selectedIdx] where _selectedIdx
        // was stale (still 0, pointing to Rephrase in the new array), overwriting Rephrase.
        // With the fix, _selectedIdx is already remapped to 1 (FIM Fill's new position),
        // so syncDetail writes FIM Fill data to FIM Fill — no corruption.
        C.save();

        // Verify no corruption
        assert.strictEqual(C.commands().length, 2, 'Should still have 2 commands');
        assert.strictEqual(C.commands()[0].commandName, 'Rephrase',
            'Rephrase should NOT have been overwritten by FIM Fill data. Got: ' + C.commands()[0].commandName);
        assert.strictEqual(C.commands()[1].commandName, 'FIM Fill',
            'FIM Fill should still be FIM Fill. Got: ' + C.commands()[1].commandName);
        // Verify the data values are preserved
        assert.strictEqual(C.commands()[0].userMessage, 'Rephrase prompt',
            'Rephrase userMessage should be preserved. Got: ' + C.commands()[0].userMessage);
        assert.strictEqual(C.commands()[1].userMessage, 'FIM prompt',
            'FIM Fill userMessage should be preserved. Got: ' + C.commands()[1].userMessage);
    });

    it('should correctly remap _selectedIdx after multiple sequential reorders', () => {
        const ctx = loadCommandsCoreWithMocks();
        const C = ctx.Cmds;

        // Three commands
        const cmdA = { commandName: 'A', menuText: 'A', APIModels: '', pasteMode: 'chat', stream: false, isFIM: false, showInputBox: false, userMessage: 'msgA', tags: [] };
        const cmdB = { commandName: 'B', menuText: 'B', APIModels: '', pasteMode: 'chat', stream: false, isFIM: false, showInputBox: false, userMessage: 'msgB', tags: [] };
        const cmdC = { commandName: 'C', menuText: 'C', APIModels: '', pasteMode: 'chat', stream: false, isFIM: false, showInputBox: false, userMessage: 'msgC', tags: [] };

        C.setCommands([cmdA, cmdB, cmdC]);
        C.setSubmenuOrder([]);
        C.setGroupOrders({ '__main__': [0, 1, 2] });
        C.setSelectedIdx(0); // A selected
        C.ensureGroupOrders();

        // Populate form values for A
        ctx.formValues['cmdDetailTitle'] = 'A';
        ctx.formValues['cmdUserMessage'] = 'msgA';

        // First reorder: drag A below B → [B, A, C]
        C.setGroupOrders({ '__main__': [1, 0, 2] });
        C.ensureGroupOrders();
        C.save();

        assert.strictEqual(C.selectedIdx(), 1, 'A should be remapped to index 1, got ' + C.selectedIdx());
        assert.strictEqual(C.commands()[0].commandName, 'B');
        assert.strictEqual(C.commands()[1].commandName, 'A');
        assert.strictEqual(C.commands()[2].commandName, 'C');

        // Second reorder: drag A below C → [B, C, A]
        // groupOrders now uses new indices: A is at 1, C at 2
        C.setGroupOrders({ '__main__': [0, 2, 1] });
        C.ensureGroupOrders();

        // Form still shows A's data (user never clicked another command)
        ctx.formValues['cmdDetailTitle'] = 'A';
        ctx.formValues['cmdUserMessage'] = 'msgA';

        C.save();

        assert.strictEqual(C.selectedIdx(), 2, 'A should be remapped to index 2, got ' + C.selectedIdx());
        assert.strictEqual(C.commands()[0].commandName, 'B');
        assert.strictEqual(C.commands()[1].commandName, 'C');
        assert.strictEqual(C.commands()[2].commandName, 'A');

        // Verify no data corruption
        assert.strictEqual(C.commands()[0].userMessage, 'msgB');
        assert.strictEqual(C.commands()[1].userMessage, 'msgC');
        assert.strictEqual(C.commands()[2].userMessage, 'msgA');
    });
});
