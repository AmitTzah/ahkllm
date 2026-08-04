// regression/fork-function.test.js — Regression: forkChat() exists and sends correct payload
// Bug: forkChat() was called from chat-actions.js but never defined (commit 2ee32fe)
const { describe, it } = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { installIpc } = require('./helpers/ipc-test-utils');

function loadBranchingModule() {
    const src = fs.readFileSync(path.resolve(__dirname, '..', '..', 'webui', 'js', 'chat', 'chat-branching.js'), 'utf-8');
    let postedMessages = [];
    const sandbox = {
        document: {
            getElementById: () => null, createElement: () => ({ style: {}, appendChild: () => {}, querySelector: () => null, querySelectorAll: () => [], addEventListener: () => {} }),
            querySelectorAll: () => [], createTextNode: () => ({}),
        },
        window: {
            chrome: { webview: { postMessage: (msg) => { postedMessages.push(msg); } } },
            addEventListener: () => {},
        },
        console: console,
        crypto: { subtle: { digest: async () => new Uint8Array(32).buffer } },
        btoa: (s) => Buffer.from(s, 'binary').toString('base64'),
        setTimeout: setTimeout,
        Promise: Promise,
        Uint8Array: Uint8Array,
        ArrayBuffer: ArrayBuffer,
        Array: Array,
        chatMessages: [],
        isLoading: false,
        md: { render: (c) => c },
        _editingMessageId: null,
        _removedAttachmentIds: [],
        _editAttachments: [],
        _editExtractPromises: [],
        _editHashPromises: [],
        getAttachmentTypeFromMime: () => 'text_file',
        pdfjsLib: undefined,
        mammoth: undefined,
        MAX_FILE_SIZE: 50 * 1024 * 1024,
        _attachmentIdCounter: 0,
        showErrorBanner: () => {},
        editMessage: undefined, forkChat: undefined, commitEdit: undefined, deleteMessage: undefined,
        switchBranch: undefined, toggleTreeModal: undefined, openTreeModal: undefined,
        closeTreeModal: undefined, renderChatTree: undefined, renderTreeNode: undefined,
        updateBranchInfo: undefined,
    };
    sandbox.global = sandbox;
    const ctx = vm.createContext(sandbox);
    installIpc(ctx);
    vm.runInContext(src, ctx);
    return { ctx: sandbox, postedMessages };
}

describe('forkChat — regression: function is defined', () => {
    it('forkChat function exists', () => {
        const { ctx } = loadBranchingModule();
        assert.strictEqual(typeof ctx.forkChat, 'function');
    });

    it('forkChat sends correct payload when not loading', () => {
        const { ctx, postedMessages } = loadBranchingModule();
        ctx.chatMessages = [{ id: 'msg-123', content: 'test', role: 'user' }];
        ctx.isLoading = false;
        ctx.forkChat(0);
        assert.strictEqual(postedMessages.length, 1);
        const payload = JSON.parse(postedMessages[0]);
        assert.strictEqual(payload.action, 'forkChat');
        assert.strictEqual(payload.id, 'msg-123');
    });

    it('forkChat does nothing when isLoading', () => {
        const { ctx, postedMessages } = loadBranchingModule();
        ctx.chatMessages = [{ id: 'msg-123', content: 'test' }];
        ctx.isLoading = true;
        ctx.forkChat(0);
        assert.strictEqual(postedMessages.length, 0);
    });

    it('forkChat does nothing for invalid index', () => {
        const { ctx, postedMessages } = loadBranchingModule();
        ctx.chatMessages = [];
        ctx.isLoading = false;
        ctx.forkChat(0);
        assert.strictEqual(postedMessages.length, 0);
    });
});
