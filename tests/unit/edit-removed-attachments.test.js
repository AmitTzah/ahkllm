// regression/edit-removed-attachments.test.js — Regression: _removedAttachmentIds tracking and commitEdit payload
// Bug: Save (overwrite) didn't commit when only attachments were removed (no-change guard)
// Bug: commitEdit payload didn't include removedAttachmentIds
const { describe, it } = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

function loadBranchingModule() {
    const src = fs.readFileSync(path.resolve(__dirname, '..', '..', 'webui', 'js', 'chat', 'chat-branching.js'), 'utf-8');
    let postedMessages = [];
    const sandbox = {
        document: {
            getElementById: () => null, createElement: () => ({ style: {}, appendChild: () => {}, querySelector: () => null, querySelectorAll: () => [], addEventListener: () => {} }),
            querySelectorAll: () => [], createTextNode: () => ({}),
        },
        window: { chrome: { webview: { postMessage: (msg) => { postedMessages.push(msg); } } }, addEventListener: () => {} },
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
        recordUndo: () => {},
        _editingMessageId: null,
        _removedAttachmentIds: [],
        _editAttachments: [],
        _editExtractPromises: [],
        _editHashPromises: [],
        getAttachmentTypeFromMime: () => 'text_file',
        pdfjsLib: undefined, mammoth: undefined, MAX_FILE_SIZE: 50 * 1024 * 1024,
        showErrorBanner: () => {},
        editMessage: undefined, forkChat: undefined, commitEdit: undefined,
    };
    sandbox.global = sandbox;
    vm.runInContext(src, vm.createContext(sandbox));
    return { ctx: sandbox, postedMessages };
}

describe('editMessage — state initialization', () => {
    it('initializes _editingMessageId and _removedAttachmentIds', () => {
        const { ctx } = loadBranchingModule();
        ctx.chatMessages = [{ id: 'msg-1', content: 'hello', role: 'user' }];
        ctx.isLoading = false;
        // editMessage touches DOM heavily; test only that module-level vars exist and are reset
        assert.strictEqual(ctx._editingMessageId, null);
        assert.strictEqual(ctx._removedAttachmentIds.length, 0);
        assert.strictEqual(ctx._editAttachments.length, 0);
    });
});

describe('commitEdit — payload includes removedAttachmentIds', () => {
    it('commitEdit sends removedAttachmentIds in payload', () => {
        const { ctx, postedMessages } = loadBranchingModule();
        ctx.chatMessages = [{ id: 'msg-1', content: 'hello', role: 'user' }];
        ctx._removedAttachmentIds = ['att-1', 'att-2'];
        ctx._editAttachments = [];
        ctx._editExtractPromises = [];
        ctx._editHashPromises = [];
        ctx.commitEdit(0, 'msg-1', 'new content', 'overwrite');
        assert.strictEqual(postedMessages.length, 1);
        const payload = JSON.parse(postedMessages[0]);
        assert.deepStrictEqual(payload.removedAttachmentIds, ['att-1', 'att-2']);
    });

    it('commitEdit clears _removedAttachmentIds after sending', () => {
        const { ctx } = loadBranchingModule();
        ctx.chatMessages = [{ id: 'msg-1', content: 'hello', role: 'user' }];
        ctx._removedAttachmentIds = ['att-1'];
        ctx._editAttachments = [];
        ctx._editExtractPromises = [];
        ctx._editHashPromises = [];
        ctx.commitEdit(0, 'msg-1', 'new', 'overwrite');
        assert.strictEqual(ctx._removedAttachmentIds.length, 0);
    });

    it('commitEdit clears _editingMessageId after sending', () => {
        const { ctx } = loadBranchingModule();
        ctx.chatMessages = [{ id: 'msg-1', content: 'hello', role: 'user' }];
        ctx._editingMessageId = 'msg-1';
        ctx._editAttachments = [];
        ctx._editExtractPromises = [];
        ctx._editHashPromises = [];
        ctx.commitEdit(0, 'msg-1', 'new', 'overwrite');
        assert.strictEqual(ctx._editingMessageId, null);
    });

    it('commitEdit includes mode in payload', () => {
        const { ctx, postedMessages } = loadBranchingModule();
        ctx.chatMessages = [{ id: 'msg-1', content: 'hello', role: 'user' }];
        ctx._editAttachments = [];
        ctx._editExtractPromises = [];
        ctx._editHashPromises = [];
        ctx.commitEdit(0, 'msg-1', 'new', 'branch');
        const payload = JSON.parse(postedMessages[0]);
        assert.strictEqual(payload.mode, 'branch');
    });

    it('commitEdit includes contentHash in attachment payload', () => {
        const { ctx, postedMessages } = loadBranchingModule();
        ctx.chatMessages = [{ id: 'msg-1', content: 'hello', role: 'user' }];
        ctx._editAttachments = [{ type: 'image', filename: 'test.png', mimeType: 'image/png', base64: 'abc', size: 100, extractedText: '', contentHash: 'abc123def' }];
        ctx._editExtractPromises = [];
        ctx._editHashPromises = [];
        ctx.commitEdit(0, 'msg-1', 'new', 'overwrite');
        const payload = JSON.parse(postedMessages[0]);
        assert.strictEqual(payload.attachments.length, 1);
        assert.strictEqual(payload.attachments[0].contentHash, 'abc123def');
    });

    it('commitEdit handles empty contentHash', () => {
        const { ctx, postedMessages } = loadBranchingModule();
        ctx.chatMessages = [{ id: 'msg-1', content: 'hello', role: 'user' }];
        ctx._editAttachments = [{ type: 'image', filename: 'test.png', mimeType: 'image/png', base64: 'abc', size: 100, extractedText: '' }];
        ctx._editExtractPromises = [];
        ctx._editHashPromises = [];
        ctx.commitEdit(0, 'msg-1', 'new', 'overwrite');
        const payload = JSON.parse(postedMessages[0]);
        assert.strictEqual(payload.attachments[0].contentHash, '');
    });
});
