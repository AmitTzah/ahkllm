// chat-undo.test.js — Unit tests for chat-undo.js: undo/redo stack
const { describe, it } = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

function loadModule() {
    const src = fs.readFileSync(path.resolve(__dirname, '..', '..', 'webui', 'js', 'chat', 'chat-undo.js'), 'utf-8');
    let postedMessages = [];
    function makeEl(tag) {
        const el = {
            tagName: tag, className: '', innerHTML: '', id: '', textContent: '', style: {},
            children: [],
            classList: { add: function() {}, remove: function() {}, contains: function() { return false; } },
            appendChild: function(c) { el.children.push(c); return c; },
            addEventListener: function() {},
            querySelector: function() { return makeEl('div'); },
            querySelectorAll: function() { return []; },
            remove: function() {},
            closest: function() { return null; }
        };
        return el;
    }
    const bodyEl = makeEl('body');
    const sandbox = {
        document: {
            body: bodyEl,
            getElementById: () => null,
            querySelector: () => null, querySelectorAll: () => [], createElement: (tag) => makeEl(tag),
            addEventListener: () => {}
        },
        window: {
            chrome: { webview: { postMessage: (msg) => postedMessages.push(JSON.parse(msg)) } },
            addEventListener: () => {}
        },
        setTimeout: (fn, ms) => { try { fn(); } catch(e) {} }, clearTimeout: () => {},
        undoStack: [], redoStack: [],
        console: console
    };
    sandbox.global = sandbox;
    sandbox._postedMessages = postedMessages;
    vm.runInContext(src, vm.createContext(sandbox));
    return sandbox;
}

describe('recordUndo', () => {
    it('pushes action to undoStack', () => {
        const ctx = loadModule();
        ctx.undoStack = [];
        ctx.recordUndo('edit', 'msg-1', { content: 'old' }, { content: 'new' });
        assert.strictEqual(ctx.undoStack.length, 1);
        assert.strictEqual(ctx.undoStack[0].action, 'edit');
    });

    it('clears redoStack on new action', () => {
        const ctx = loadModule();
        ctx.redoStack = [{ action: 'edit', messageId: 'old' }];
        ctx.recordUndo('delete', 'msg-2', { content: 'x' }, null);
        assert.strictEqual(ctx.redoStack.length, 0);
    });
});

describe('undo', () => {
    it('does nothing when stack is empty', () => {
        const ctx = loadModule();
        ctx.undoStack = [];
        assert.doesNotThrow(() => ctx.undo());
    });

    it('moves item from undo to redo stack', () => {
        const ctx = loadModule();
        ctx.undoStack = [{ action: 'edit', messageId: 'm1', beforeState: {}, afterState: {} }];
        ctx.redoStack = [];
        ctx.undo();
        assert.strictEqual(ctx.undoStack.length, 0);
        assert.strictEqual(ctx.redoStack.length, 1);
    });
});

describe('redo', () => {
    it('does nothing when redo stack is empty', () => {
        const ctx = loadModule();
        ctx.redoStack = [];
        assert.doesNotThrow(() => ctx.redo());
    });
});

describe('clearUndoStack', () => {
    it('empties both stacks', () => {
        const ctx = loadModule();
        ctx.undoStack = [1, 2];
        ctx.redoStack = [3];
        ctx.clearUndoStack();
        assert.strictEqual(ctx.undoStack.length, 0);
        assert.strictEqual(ctx.redoStack.length, 0);
    });
});

describe('undoEdit', () => {
    it('sends editMessage with beforeState content', () => {
        const ctx = loadModule();
        ctx._postedMessages.length = 0;
        ctx.undoEdit({ messageId: 'm1', beforeState: { content: 'original' } });
        const msg = ctx._postedMessages[0];
        assert.ok(msg !== undefined);
        assert.strictEqual(msg.action, 'editMessage');
        assert.strictEqual(msg.id, 'm1');
    });
});

describe('undoDelete', () => {
    it('sends undeleteMessage', () => {
        const ctx = loadModule();
        ctx._postedMessages.length = 0;
        ctx.undoDelete({ messageId: 'm1', beforeState: { content: 'deleted' } });
        const msg = ctx._postedMessages[0];
        assert.ok(msg !== undefined);
        assert.strictEqual(msg.action, 'undeleteMessage');
    });
});
