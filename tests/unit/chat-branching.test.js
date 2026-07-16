// chat-branching.test.js — Unit tests for chat-branching.js: renderChatTree, renderTreeNode, updateBranchInfo, forkChat
const { describe, it } = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

function loadBranchingModule() {
    const src = fs.readFileSync(path.resolve(__dirname, '..', '..', 'webui', 'js', 'chat', 'chat-branching.js'), 'utf-8');
    let postedMessages = [];
    let createdElements = [];
    function makeEl(tag) {
        const el = {
            tagName: tag, className: '', innerHTML: '', id: '', textContent: '', title: '',
            style: {}, dataset: {}, children: [],
            classList: { add: function(c) { el.className += ' ' + c; }, contains: function(c) { return el.className.indexOf(c) >= 0; }, remove: () => {} },
            appendChild: function(child) { el.children.push(child); return child; },
            addEventListener: function(evt, fn) {},
            querySelector: () => null,
            querySelectorAll: () => [],
            insertBefore: function(child, ref) { el.children.push(child); },
            remove: function() {},
            closest: () => null,
            getAttribute: () => null,
            setAttribute: () => {},
            scrollIntoView: () => {},
            focus: () => {},
            select: () => {}
        };
        createdElements.push(el);
        return el;
    }
    const sandbox = {
        document: {
            getElementById: (id) => {
                if (id === 'chat-messages') {
                    if (!sandbox._chatMessagesEl) sandbox._chatMessagesEl = makeEl('div');
                    return sandbox._chatMessagesEl;
                }
                if (id === 'treeOverlay') {
                    if (!sandbox._treeOverlayEl) sandbox._treeOverlayEl = makeEl('div');
                    sandbox._treeOverlayEl.classList.contains = function(c) { return this.className.indexOf(c) >= 0; };
                    sandbox._treeOverlayEl.classList.remove = function(c) { this.className = this.className.replace(c, '').trim(); };
                    return sandbox._treeOverlayEl;
                }
                return null;
            },
            querySelector: (sel) => {
                if (sel === '.tree-canvas') {
                    if (!sandbox._treeCanvasEl) sandbox._treeCanvasEl = makeEl('div');
                    return sandbox._treeCanvasEl;
                }
                if (sel === '.tree-modal-sub') {
                    if (!sandbox._treeSubEl) sandbox._treeSubEl = makeEl('span');
                    return sandbox._treeSubEl;
                }
                return null;
            },
            querySelectorAll: () => [],
            createElement: (tag) => makeEl(tag),
            createElementNS: function(ns, tag) {
              var el = makeEl(tag);
              el.setAttribute = function(k, v) { this['_attr_' + k] = v; };
              el.getAttribute = function(k) { return this['_attr_' + k]; };
              return el;
            },
            body: { appendChild: () => {}, removeChild: () => {} },
            addEventListener: function() {}
        },
        window: {
            chrome: { webview: { postMessage: (msg) => postedMessages.push(JSON.parse(msg)) } },
            addEventListener: () => {},
            getSelection: () => ({ toString: () => '', removeAllRanges: () => {}, getRangeAt: () => ({ commonAncestorContainer: {}, getBoundingClientRect: () => ({ left: 0, top: 0, bottom: 0 }) }) })
        },
        console: console,
        escHtml: function(s) { if (!s) return ''; return String(s).replace(/&/g,'&').replace(/</g,'<').replace(/>/g,'>'); },
        chatMessages: [],
        isLoading: false,
        activeThreadId: '',
        md: { render: (c) => '<p>' + c + '</p>' },
        sessionStorage: { getItem: () => null, setItem: () => {} },
        _editingMessageId: null,
        _removedAttachmentIds: [],
        _editAttachments: [],
        _editExtractPromises: [],
        _editHashPromises: [],
        recordUndo: () => {},
        showErrorBanner: () => {},
        MAX_FILE_SIZE: 52428800,
        getAttachmentTypeFromMime: () => 'text_file',
        Number: Number, String: String,
        crypto: { subtle: { digest: () => Promise.resolve(new Uint8Array([1,2,3])) } },
        Promise: Promise,
        Array: Array,
        alert: () => {},
        confirm: () => true
    };
    sandbox.global = sandbox;
    sandbox._postedMessages = postedMessages;
    sandbox._createdElements = createdElements;
    vm.runInContext(src, vm.createContext(sandbox));
    return sandbox;
}

describe('renderChatTree', () => {
    it('renders empty message for null tree', () => {
        const ctx = loadBranchingModule();
        const container = ctx.document.querySelector('.tree-canvas');
        ctx.renderChatTree(null);
        assert.ok(container.innerHTML.includes('No messages yet'));
    });

    it('renders empty message for empty array', () => {
        const ctx = loadBranchingModule();
        const container = ctx.document.querySelector('.tree-canvas');
        ctx.renderChatTree([]);
        assert.ok(container.innerHTML.includes('No messages yet'));
    });

    it('renders absolutely-positioned nodes for each root', () => {
        const ctx = loadBranchingModule();
        const tree = [
            { id: 'n1', role: 'user', content_preview: 'Hello', children: [], sibling_group: null, sibling_index: 0 }
        ];
        const container = ctx.document.querySelector('.tree-canvas');
        ctx.renderChatTree(tree);
        // Container should have nodes + SVG
        var nodes = container.children; // includes SVG + tree-node divs
        assert.ok(nodes.length >= 2); // SVG + at least 1 node
    });
});

describe('tree helpers', () => {
    it('_countTreeNodes counts recursively', () => {
        const ctx = loadBranchingModule();
        var tree = [
            { id: 'n1', role: 'user', content_preview: 'Q', children: [
                { id: 'n2', role: 'assistant', content_preview: 'A', children: [] }
            ]}
        ];
        assert.strictEqual(ctx._countTreeNodes(tree), 2);
    });

    it('_collectActivePath uses chatMessages as active path', () => {
        const ctx = loadBranchingModule();
        ctx.chatMessages = [
            { id: 'n1', role: 'user' },
            { id: 'n3', role: 'assistant' }  // n3 is active (n2 is sibling from old branch)
        ];
        var ids = {};
        ctx._collectActivePath(ids);
        assert.strictEqual(ids['n1'], true);
        assert.strictEqual(ids['n3'], true);
        assert.strictEqual(ids['n2'], undefined); // not in active path
    });
});

describe('_findDefaultLeaf', () => {
    it('follows last-child chain to bottom', () => {
        const ctx = loadBranchingModule();
        var tree = [
            { id: 'n1', role: 'user', content_preview: 'Q', children: [
                { id: 'n2', role: 'assistant', content_preview: 'A1', children: [] },
                { id: 'n3', role: 'assistant', content_preview: 'A2', children: [
                    { id: 'n4', role: 'assistant', content_preview: 'A2a', children: [] }
                ] }
            ]}
        ];
        // n3 is last child, and n4 is last child of n3
        assert.strictEqual(ctx._findDefaultLeaf('n1', tree), 'n4');
    });

    it('returns self if no children', () => {
        const ctx = loadBranchingModule();
        var tree = [{ id: 'n1', role: 'user', content_preview: 'Q', children: [] }];
        assert.strictEqual(ctx._findDefaultLeaf('n1', tree), 'n1');
    });

    it('returns null for not-found id', () => {
        const ctx = loadBranchingModule();
        var tree = [{ id: 'n1', role: 'user', content_preview: 'Q', children: [] }];
        assert.strictEqual(ctx._findDefaultLeaf('n99', tree), null);
    });
});

describe('_inheritModels', () => {
    it('fills missing model from parent', () => {
        const ctx = loadBranchingModule();
        var tree = [
            { id: 'n1', role: 'assistant', model: 'gpt-4o', content_preview: 'A', children: [
                { id: 'n2', role: 'assistant', model: '', content_preview: 'B', children: [] }
            ]}
        ];
        ctx._inheritModels(tree, '');
        assert.strictEqual(tree[0].children[0].model, 'gpt-4o');
    });

    it('leaves existing model alone', () => {
        const ctx = loadBranchingModule();
        var tree = [
            { id: 'n1', role: 'assistant', model: 'claude', content_preview: 'A', children: [
                { id: 'n2', role: 'assistant', model: 'gemini', content_preview: 'B', children: [] }
            ]}
        ];
        ctx._inheritModels(tree, '');
        assert.strictEqual(tree[0].children[0].model, 'gemini');
    });
});

describe('forkChat', () => {
    it('does nothing when isLoading', () => {
        const ctx = loadBranchingModule();
        ctx.isLoading = true;
        ctx.chatMessages = [{ id: 'm1', role: 'user', content: 'hi' }];
        ctx.forkChat(0);
        assert.strictEqual(ctx._postedMessages.length, 0);
    });

    it('does nothing for invalid index', () => {
        const ctx = loadBranchingModule();
        ctx.chatMessages = [];
        ctx.forkChat(0);
        assert.strictEqual(ctx._postedMessages.length, 0);
    });
});
