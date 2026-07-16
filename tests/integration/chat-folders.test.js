// chat-folders.test.js — Integration tests for folder-aware thread list (new _threadMeta + loadThreadList with folders)
const { describe, it } = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

function loadSidebarModule() {
    const src = fs.readFileSync(path.resolve(__dirname, '..', '..', 'webui', 'js', 'chat', 'chat-sidebar.js'), 'utf-8');
    let createdElements = [];
    let postedMessages = [];
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
            getAttribute: function(attr) { return el['_attr_' + attr] || null; },
            setAttribute: function(attr, v) { el['_attr_' + attr] = v; }
        };
        createdElements.push(el);
        return el;
    }
    const trashItemsEl = makeEl('div');
    const sandbox = {
        document: {
            getElementById: (id) => {
                if (elementCache[id]) return elementCache[id];
                if (id === 'thread-list') { elementCache[id] = makeEl('div'); return elementCache[id]; }
                if (id === 'nav-message-list') { elementCache[id] = makeEl('div'); return elementCache[id]; }
                if (id === 'trashWrap') { elementCache[id] = makeEl('div'); return elementCache[id]; }
                return null;
            },
            querySelector: function(sel) {
                if (sel === '.trash-items') return trashItemsEl;
                if (sel === '.title-text') {
                    if (!sandbox._titleEl) sandbox._titleEl = makeEl('span');
                    return sandbox._titleEl;
                }
                if (sel === '.fold') {
                    if (!sandbox._foldEl) sandbox._foldEl = makeEl('span');
                    return sandbox._foldEl;
                }
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
        setTimeout: (fn) => { try { fn(); } catch(e) {} },
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

describe('loadThreadList with folders', () => {
    it('populates _threadMeta from threads array', () => {
        const ctx = loadSidebarModule();
        const threads = [
            { id: 't1', title: 'Chat One', folder_id: '', folder_name: '', updated_at: '2026-01-01', model: 'gpt-4o' },
            { id: 't2', title: 'Chat Two', folder_id: 'f1', folder_name: 'Work', updated_at: '2026-01-02', model: 'deepseek-v4' }
        ];
        const folders = [{ id: 'f1', name: 'Work' }];
        ctx.loadThreadList(threads, folders);
        assert.strictEqual(ctx._threadMeta['t1'].title, 'Chat One');
        assert.strictEqual(ctx._threadMeta['t1'].folder, '');
        assert.strictEqual(ctx._threadMeta['t2'].title, 'Chat Two');
        assert.strictEqual(ctx._threadMeta['t2'].folder, 'Work');
    });

    it('renders folder sections', () => {
        const ctx = loadSidebarModule();
        const threads = [
            { id: 't1', title: 'Chat One', folder_id: 'f1', folder_name: 'Work', updated_at: '2026-01-01', model: 'gpt-4o' }
        ];
        const folders = [{ id: 'f1', name: 'Work' }];
        ctx.loadThreadList(threads, folders);
        const list = ctx.document.getElementById('thread-list');
        // Should have a .folder div (not just unfiled)
        assert.ok(list.children.length >= 1);
    });

    it('renders unfiled threads outside folders', () => {
        const ctx = loadSidebarModule();
        const threads = [
            { id: 't1', title: 'Unfiled Chat', folder_id: '', folder_name: '', updated_at: '2026-01-01', model: 'gpt-4o' }
        ];
        ctx.loadThreadList(threads, []);
        const list = ctx.document.getElementById('thread-list');
        assert.ok(list.children.length >= 1);
    });

    it('updates topbar title for active thread', () => {
        const ctx = loadSidebarModule();
        ctx.activeThreadId = 't1';
        const threads = [
            { id: 't1', title: 'My Chat', folder_id: '', folder_name: '', updated_at: '2026-01-01', model: 'gpt-4o' }
        ];
        ctx.loadThreadList(threads, []);
        const titleEl = ctx.document.querySelector('.title-text');
        assert.strictEqual(titleEl.textContent, 'My Chat');
    });

    it('updateTopbarTitle handles external data from AHK', () => {
        const ctx = loadSidebarModule();
        ctx.activeThreadId = 't1';
        ctx.updateTopbarTitle({ text: 'Generated Title', folder: 'Work' });
        assert.strictEqual(ctx._threadMeta['t1'].title, 'Generated Title');
        assert.strictEqual(ctx._threadMeta['t1'].folder, 'Work');
    });
});
