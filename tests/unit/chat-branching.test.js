// chat-branching.test.js — Unit tests for chat-branching.js: renderChatTree, renderTreeNode, updateBranchInfo, forkChat
const { describe, it } = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

function loadBranchingModule() {
    const src = fs.readFileSync(path.resolve(__dirname, '..', '..', 'webui', 'js', 'chat', 'chat-branching.js'), 'utf-8')
        + '\n' + fs.readFileSync(path.resolve(__dirname, '..', '..', 'webui', 'js', 'chat', 'chat-tree-modal.js'), 'utf-8');
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

describe('_layoutTreeNodes', () => {
    // Layout constants mirrored from chat-tree-modal.js (_layoutTreeNodes).
    // MUST be kept in sync with the source — they are function-locals there.
    const NODE_H = 90;
    const SIBLING_GAP = 160;

    function layout(ctx, tree) {
        var svgPaths = [], allNodes = [];
        ctx._layoutTreeNodes(tree, 0, 60, {}, svgPaths, allNodes);
        return allNodes;
    }

    function assertNoColumnOverlap(allNodes) {
        // Group nodes by column (left), sort by top, and require the sibling
        // cushion (SIBLING_GAP - NODE_H) between consecutive vertical spans.
        var byColumn = {};
        allNodes.forEach(function(n) {
            (byColumn[n.left] = byColumn[n.left] || []).push(n);
        });
        Object.keys(byColumn).forEach(function(col) {
            var nodes = byColumn[col].sort(function(a, b) { return a.top - b.top; });
            for (var i = 1; i < nodes.length; i++) {
                var gap = nodes[i].top - (nodes[i - 1].top + NODE_H);
                assert.ok(gap >= SIBLING_GAP - NODE_H,
                    'nodes "' + nodes[i - 1].id + '" and "' + nodes[i].id + '" in column ' + col +
                    ' are only ' + gap + 'px apart (need >= ' + (SIBLING_GAP - NODE_H) + 'px)');
            }
        });
    }

    it('regression: child of edited branch does not overlap retried response of original branch', () => {
        // Repro: send "hi", retry assistant (2/2), edit "hi" -> "hello" saved as branch.
        // TreeRepo sorts newest-first: "hello" subtree renders above "hi" subtree.
        const ctx = loadBranchingModule();
        var tree = [
            { id: 'hello', role: 'user', content_preview: 'hello', children: [
                { id: 'respH', role: 'assistant', content_preview: 'Hello! How can I help?', children: [] }
            ]},
            { id: 'hi', role: 'user', content_preview: 'hi', children: [
                { id: 'resp2', role: 'assistant', content_preview: 'Hi there! (2/2)', children: [] },
                { id: 'resp1', role: 'assistant', content_preview: 'Hey! (1/2)', children: [] }
            ]}
        ];
        var allNodes = layout(ctx, tree);
        var respH = allNodes.find(function(n) { return n.id === 'respH'; });
        var resp2 = allNodes.find(function(n) { return n.id === 'resp2'; });
        assert.ok(respH && resp2, 'both assistant nodes must be laid out');
        assert.strictEqual(respH.left, resp2.left, 'both assistant nodes share a column');
        var gap = resp2.top - (respH.top + NODE_H);
        assert.ok(gap >= SIBLING_GAP - NODE_H,
            'child of "hello" must not overlap 2/2 response of "hi" (gap was ' + gap + 'px)');
        assertNoColumnOverlap(allNodes);
    });

    it('keeps sibling cushion between child subtrees of the same parent', () => {
        const ctx = loadBranchingModule();
        var tree = [
            { id: 'q', role: 'user', content_preview: 'Q', children: [
                { id: 'a2', role: 'assistant', content_preview: 'A2', children: [] },
                { id: 'a1', role: 'assistant', content_preview: 'A1', children: [] }
            ]}
        ];
        assertNoColumnOverlap(layout(ctx, tree));
    });

    it('single root still starts at startY and returns correct subtree bottom', () => {
        const ctx = loadBranchingModule();
        var tree = [
            { id: 'only', role: 'user', content_preview: 'Q', children: [] }
        ];
        var allNodes = [];
        var bottom = ctx._layoutTreeNodes(tree, 0, 60, {}, [], allNodes);
        assert.strictEqual(allNodes.length, 1);
        assert.strictEqual(allNodes[0].top, 60);
        assert.strictEqual(bottom, 60 + NODE_H, 'single leaf root returns startY + NODE_H');
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
