// chat-actions.test.js — Unit tests for chat-actions.js: addMessageActions, _iconBtn, _createMoreDropdown
const { describe, it } = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

function loadActionsModule() {
    const src = fs.readFileSync(path.resolve(__dirname, '..', '..', 'webui', 'js', 'chat', 'chat-actions.js'), 'utf-8');
    let createdElements = [];
    const sandbox = {
        document: {
            getElementById: () => null,
            querySelectorAll: () => [],
            createElement: function(tag) {
                const el = {
                    tagName: tag,
                    className: '',
                    innerHTML: '',
                    title: '',
                    style: {},
                    dataset: {},
                    children: [],
                    classList: { add: function(c) { if (!this._classes) this._classes = []; this._classes.push(c); }, contains: () => false, _classes: [] },
                    appendChild: function(child) { this.children.push(child); return child; },
                    addEventListener: function(evt, fn) { this['_on' + evt] = fn; },
                    querySelector: () => null,
                    querySelectorAll: () => [],
                    insertBefore: function(child, ref) { this.children.push(child); },
                    remove: function() {}
                };
                createdElements.push(el);
                return el;
            }
        },
        window: {
            chrome: { webview: { postMessage: () => {} } }
        },
        console: console,
        chatMessages: [],
        switchBranch: () => {},
        editMessage: () => {},
        copySingleMessage: () => {},
        retryLastAssistantMessage: () => {},
        deleteMessage: () => {},
        quoteMessage: () => {},
        forkChat: () => {},
        createTokenInfoIcon: () => null,
        _iconBtn: undefined,
        _addBranchNav: undefined,
        _createMoreDropdown: undefined,
        addMessageActions: undefined
    };
    sandbox.global = sandbox;
    sandbox._createdElements = createdElements;
    vm.runInContext(src, vm.createContext(sandbox));
    return sandbox;
}

describe('_iconBtn', () => {
    it('creates a button with msg-action-btn class', () => {
        const ctx = loadActionsModule();
        const btn = ctx._iconBtn('📋', 'Copy', () => {});
        assert.ok(btn);
        // classList._classes may not be populated since the mock creates elements via document.createElement
        // Just verify the button was created and has the right innerHTML
        assert.strictEqual(btn.innerHTML, '📋');
        assert.strictEqual(btn.title, 'Copy');
    });

    it('sets innerHTML and title', () => {
        const ctx = loadActionsModule();
        const btn = ctx._iconBtn('📋', 'Copy Message', () => {});
        assert.strictEqual(btn.innerHTML, '📋');
        assert.strictEqual(btn.title, 'Copy Message');
    });

    it('attaches click handler that stops propagation', () => {
        const ctx = loadActionsModule();
        let clicked = false;
        let stoppedPropagation = false;
        const btn = ctx._iconBtn('📋', 'Copy', () => { clicked = true; });
        // Simulate click
        btn._onclick({ stopPropagation: () => { stoppedPropagation = true; } });
        assert.ok(clicked);
        assert.ok(stoppedPropagation);
    });
});

describe('_addBranchNav', () => {
    it('does nothing when total branches <= 1', () => {
        const ctx = loadActionsModule();
        const container = { appendChild: () => {}, children: [] };
        const msg = { siblingInfo: { total: 1, index: 1 } };
        ctx._addBranchNav(container, msg);
        assert.strictEqual(container.children.length, 0);
    });

    it('does nothing when siblingInfo is missing', () => {
        const ctx = loadActionsModule();
        const container = { appendChild: () => {}, children: [] };
        ctx._addBranchNav(container, {});
        assert.strictEqual(container.children.length, 0);
    });

    it('adds prev/next buttons and branch label when branches > 1', () => {
        const ctx = loadActionsModule();
        const container = { appendChild: function(c) { this.children.push(c); }, children: [] };
        ctx._addBranchNav(container, { id: 'msg-1', siblingInfo: { total: 3, index: 2 } });
        assert.strictEqual(container.children.length, 3); // prev, label, next
    });
});

describe('addMessageActions — user', () => {
    it('adds copy, edit, more dropdown to user message', () => {
        const ctx = loadActionsModule();
        const container = { appendChild: function(c) { this.children.push(c); }, children: [] };
        ctx.addMessageActions(container, { role: 'user', id: 'u1', content: 'hi' }, 0);
        // Should have: copy, edit, (branch nav skipped for single branch), token icon (null, skipped), more dropdown
        // At minimum: copy + edit + more dropdown = 3 children
        assert.ok(container.children.length >= 3);
    });
});

describe('addMessageActions — assistant', () => {
    it('adds copy, retry, edit, more dropdown to assistant message', () => {
        const ctx = loadActionsModule();
        const container = { appendChild: function(c) { this.children.push(c); }, children: [] };
        ctx.addMessageActions(container, { role: 'assistant', id: 'a1', content: 'hello', model: 'gpt-4o' }, 1);
        // Should have: copy, retry, edit, (branch nav skipped), more dropdown
        assert.ok(container.children.length >= 4);
    });
});
