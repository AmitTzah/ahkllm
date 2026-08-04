// integration/edit-send-flow.test.js -- Cross-module integration tests
// Tests payload construction across attachment -> send and edit -> commit flows
const { describe, it } = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { installIpc } = require('../unit/helpers/ipc-test-utils');

function loadModule(filePath, extraGlobals = {}) {
    const src = fs.readFileSync(path.resolve(__dirname, '..', '..', 'webui', 'js', filePath), 'utf-8');
    let postedMessages = [];
    const sandbox = {
        document: {
            getElementById: () => null, createElement: () => ({ style: {}, appendChild: () => {}, querySelector: () => null, querySelectorAll: () => [], addEventListener: () => {} }),
            querySelectorAll: () => [],
        },
        window: { chrome: { webview: { postMessage: (m) => { postedMessages.push(m); } } }, addEventListener: () => {} },
        console: { log: () => {}, error: () => {} },
        crypto: { subtle: { digest: async () => new Uint8Array(32).buffer } },
        btoa: (s) => Buffer.from(s, 'binary').toString('base64'),
        setTimeout: setTimeout, Promise: Promise,
        Uint8Array: Uint8Array, ArrayBuffer: ArrayBuffer, Array: Array,
        chatMessages: [], isLoading: false, attachmentState: [], _attachmentIdCounter: 0,
        _editingMessageId: null, _removedAttachmentIds: [],
        streamState: { active: false, contentBuffer: '', thinkingBuffer: '', userScrolledUp: false, bubble: null, contentDiv: null, thinkingDetails: null, modelName: '' },
        sessionStorage: { getItem: () => null, setItem: () => {} },
        md: { render: (c) => c },
        MAX_FILE_SIZE: 50 * 1024 * 1024, ALLOWED_EXTENSIONS: [],
        getAttachmentTypeFromMime: () => 'text_file', findAttachmentById: () => null,
        renderAttachmentBar: () => {}, showErrorBanner: () => {},
        clearAttachments: () => {},
        ...extraGlobals,
    };
    sandbox.global = sandbox;
    const ctx = vm.createContext(sandbox);
    installIpc(ctx);
    vm.runInContext(src, ctx);
    return { ctx: sandbox, postedMessages };
}

describe('Edit -> Commit integration', () => {
    it('commitEdit payload includes removedAttachmentIds', () => {
        const { ctx, postedMessages } = loadModule('chat/chat-branching.js');
        ctx.chatMessages = [{ id: 'msg-1', content: 'hello', role: 'user' }];
        ctx._removedAttachmentIds = ['att-old-1', 'att-old-2'];
        ctx.commitEdit(0, 'msg-1', 'edited', 'overwrite');

        const payload = JSON.parse(postedMessages[0]);
        assert.strictEqual(payload.action, 'editMessage');
        assert.strictEqual(payload.mode, 'overwrite');
        assert.deepStrictEqual(payload.removedAttachmentIds, ['att-old-1', 'att-old-2']);
    });

    it('commitEdit clears all state after sending', () => {
        const { ctx } = loadModule('chat/chat-branching.js');
        ctx.chatMessages = [{ id: 'msg-1', content: 'hello', role: 'user' }];
        ctx._removedAttachmentIds = ['att-x'];
        ctx._editingMessageId = 'msg-1';
        ctx.commitEdit(0, 'msg-1', 'new', 'overwrite');

        assert.strictEqual(ctx._editingMessageId, null);
        assert.strictEqual(ctx._removedAttachmentIds.length, 0);
    });
});

describe('Attachment -> Send integration', () => {
    it('getAttachmentsForSend includes contentHash in output', () => {
        const { ctx } = loadModule('chat/attachments/chat-attachments.js');
        ctx.attachmentState = [{
            _id: 1, type: 'image', filename: 'test.png', mimeType: 'image/png',
            base64: 'data', size: 500, extractedText: '', contentHash: 'sendHash456', loading: false
        }];
        const result = ctx.getAttachmentsForSend();
        assert.strictEqual(result.length, 1);
        assert.strictEqual(result[0].contentHash, 'sendHash456');
        assert.strictEqual(result[0].extractedText, '');
    });

    it('getAttachmentsForSend skips loading attachments (no base64)', () => {
        const { ctx } = loadModule('chat/attachments/chat-attachments.js');
        ctx.attachmentState = [
            { _id: 1, type: 'image', filename: 'ready.png', base64: 'data', size: 100, loading: false },
            { _id: 2, type: 'pdf', filename: 'loading.pdf', base64: null, size: 200, loading: true },
        ];
        const result = ctx.getAttachmentsForSend();
        assert.strictEqual(result.length, 1);
    });
});

describe('Stream state integration', () => {
    it('_persistStreamedMessage applies dbMsg fields to message', () => {
        const { ctx } = loadModule('chat/stream.js');
        ctx.chatMessages = [];
        ctx.streamState.bubble = { dataset: {} };
        ctx._persistStreamedMessage('response', 'gpt-4o', {
            id: 'db-1', siblingInfo: { index: 2, total: 3 }, reasoning: 'thought...'
        });
        const msg = ctx.chatMessages[0];
        assert.strictEqual(msg.id, 'db-1');
        assert.strictEqual(msg.siblingInfo.index, 2);
        assert.strictEqual(msg.reasoning, 'thought...');
    });
});
