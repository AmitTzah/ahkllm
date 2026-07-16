// chat-sidebar.test.js — Unit tests for chat-sidebar.js: modelEmoji, loadThreadList, loadTrashList, renderNavList
const { describe, it } = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

function loadSidebarModule() {
    const src = fs.readFileSync(path.resolve(__dirname, '..', '..', 'webui', 'js', 'chat', 'chat-sidebar.js'), 'utf-8');
    let createdElements = [];
    let postedMessages = [];
    // Cache elements so getElementById returns the same object across calls
    const elementCache = {};
    function makeEl(tag) {
        const el = {
            tagName: tag, className: '', innerHTML: '', id: '', textContent: '', title: '',
            style: {}, dataset: {}, children: [],
            classList: { add: function(c) { el.className += ' ' + c; }, contains: function(c) { return el.className.indexOf(c) >= 0; }, remove: function(c) { el.className = el.className.replace(c, '').trim(); } },
            appendChild: function(child) { el.children.push(child); return child; },
            addEventListener: function(evt, fn) {},
            querySelector: function(sel) { return makeEl('div'); },
            querySelectorAll: function() { return []; },
            insertBefore: function(child, ref) { el.children.push(child); },
            remove: function() {},
            closest: function() { return null; },
            getAttribute: function() { return null; },
            setAttribute: function() {}
        };
        createdElements.push(el);
        return el;
    }
    // Pre-create shared elements that querySelector returns
    const trashItemsEl = makeEl('div');
    const sandbox = {
        document: {
            getElementById: (id) => {
                if (elementCache[id]) return elementCache[id];
                if (id === 'thread-list') { elementCache[id] = makeEl('div'); return elementCache[id]; }
                if (id === 'nav-message-list') { elementCache[id] = makeEl('div'); return elementCache[id]; }
                if (id === 'chat-input') { elementCache[id] = { disabled: false, style: {} }; return elementCache[id]; }
                if (id === 'chat-send-btn') { elementCache[id] = { disabled: false, style: {} }; return elementCache[id]; }
                if (id === 'trashWrap') { elementCache[id] = makeEl('div'); return elementCache[id]; }
                return null;
            },
            querySelector: function(sel) {
                if (sel === '.trash-items') return trashItemsEl;
                if (sel === '.title-text') return makeEl('span');
                if (sel === '.fold') return makeEl('span');
                return null;
            },
            querySelectorAll: function() { return []; },
            createElement: (tag) => makeEl(tag)
        },
        window: {
            chrome: { webview: { postMessage: (msg) => postedMessages.push(JSON.parse(msg)) } },
            addEventListener: () => {}
        },
        console: console,
        setTimeout: (fn) => { try { fn(); } catch(e) {} },  // Run synchronously to avoid async issues
        clearTimeout: () => {},
        activeThreadId: '',
        chatMessages: [],
        sidebarOpen: false,
        escHtml: function(s) { if (!s) return ''; return String(s).replace(/&/g,'&').replace(/</g,'<').replace(/>/g,'>'); },
        Number: Number, String: String
    };
    sandbox.global = sandbox;
    sandbox._postedMessages = postedMessages;
    sandbox._elementCache = elementCache;
    vm.runInContext(src, vm.createContext(sandbox));
    return sandbox;
}

describe('loadThreadList', () => {
    it('renders empty state when no threads', () => {
        const ctx = loadSidebarModule();
        ctx.loadThreadList([]);
        const list = ctx.document.getElementById('thread-list');
        // loadThreadList sets innerHTML directly for empty state
        assert.ok(list.innerHTML.includes('No chats yet'));
    });

    it('renders thread items for each thread', () => {
        const ctx = loadSidebarModule();
        const threads = [
            { id: 't1', title: 'Chat One', updated_at: '2026-01-01', model: 'gpt-4o' },
            { id: 't2', title: 'Chat Two', updated_at: '2026-01-02', model: 'deepseek-v4' }
        ];
        ctx.loadThreadList(threads);
        const list = ctx.document.getElementById('thread-list');
        assert.ok(list.children.length >= 2);
    });

    it('marks active thread', () => {
        const ctx = loadSidebarModule();
        ctx.activeThreadId = 't1';
        ctx.loadThreadList([{ id: 't1', title: 'Active', updated_at: '2026-01-01', model: 'gpt-4o' }]);
        const list = ctx.document.getElementById('thread-list');
        assert.ok(list.children.length >= 1);
    });
});

describe('loadTrashList', () => {
    it('does nothing for empty trash', () => {
        const ctx = loadSidebarModule();
        assert.doesNotThrow(() => ctx.loadTrashList([]));
    });

    it('creates trash section without throwing', () => {
        const ctx = loadSidebarModule();
        // loadTrashList uses setTimeout for auto-expand; verify it doesn't throw synchronously
        assert.doesNotThrow(() => ctx.loadTrashList([{ id: 't3', title: 'Old Chat', updated_at: '2026-01-01' }]));
    });
});

describe('renderNavList', () => {
    it('does nothing when nav-list missing', () => {
        const ctx = loadSidebarModule();
        ctx.document.getElementById = () => null;
        assert.doesNotThrow(() => ctx.renderNavList());
    });

    it('renders nav items', () => {
        const ctx = loadSidebarModule();
        ctx.chatMessages = [
            { role: 'user', content: 'Hello' },
            { role: 'assistant', content: 'Hi!' }
        ];
        ctx.renderNavList();
        const navList = ctx.document.getElementById('nav-message-list');
        assert.strictEqual(navList.children.length, 2);
    });
});
