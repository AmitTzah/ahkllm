// chat-input.test.js — Unit tests for chat-input.js: onChatSend payload, retry logic
const { describe, it } = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { installIpc } = require('./helpers/ipc-test-utils');

function loadInputModule() {
    const src = fs.readFileSync(path.resolve(__dirname, '..', '..', 'webui', 'js', 'chat', 'chat-input.js'), 'utf-8');
    let postedMessages = [];
    const sandbox = {
        document: {
            getElementById: (id) => {
                if (id === 'chat-input') return { value: 'test message', style: {}, disabled: false, focus: () => {} };
                if (id === 'chat-send-btn') return { disabled: false, textContent: '', onclick: null };
                return null;
            },
            createElement: () => ({ style: {}, appendChild: () => {}, innerHTML: '', remove: () => {} }),
            querySelectorAll: () => [],
        },
        window: { chrome: { webview: { postMessage: (msg) => { postedMessages.push(msg); } } }, addEventListener: () => {} },
        console: console,
        setTimeout: setTimeout, clearTimeout: clearTimeout,
        chatMessages: [],
        isLoading: false,
        streamState: { active: false },
        attachmentState: [],
        sessionStorage: { getItem: () => null, setItem: () => {} },
        renderChatMessages: () => {},
        onChatSend: undefined, showLoadingIndicator: undefined, hideLoadingIndicator: undefined,
        setChatButtonsEnabled: undefined, onStopStreaming: undefined,
        retryLastAssistantMessage: undefined, handleChatInputKeydown: undefined,
        autoResizeChatInput: undefined,
        getAttachmentsForSend: () => [],
        clearAttachments: () => {},
        showErrorBanner: () => {},
    };
    sandbox.global = sandbox;
    const ctx = vm.createContext(sandbox);
    installIpc(ctx);
    vm.runInContext(src, ctx);
    return { ctx: sandbox, postedMessages };
}

describe('onChatSend — payload construction', () => {
    it('sends chatSend with message text', () => {
        const { ctx, postedMessages } = loadInputModule();
        ctx.isLoading = false;
        ctx.onChatSend();
        assert.strictEqual(postedMessages.length, 1);
        const payload = JSON.parse(postedMessages[0]);
        assert.strictEqual(payload.action, 'chatSend');
        assert.strictEqual(payload.message, 'test message');
    });

    it('sends "Describe the attached content." when message is empty and attachments exist', () => {
        const { ctx, postedMessages } = loadInputModule();
        ctx.isLoading = false;
        // Mock empty input
        const origGetEl = ctx.document.getElementById;
        ctx.document.getElementById = (id) => {
            if (id === 'chat-input') return { value: '', style: {}, disabled: false, focus: () => {} };
            if (id === 'chat-send-btn') return { disabled: false, textContent: '', onclick: null };
            return origGetEl(id);
        };
        ctx.getAttachmentsForSend = () => [{ type: 'image', filename: 'test.png' }];
        ctx.onChatSend();
        const payload = JSON.parse(postedMessages[0]);
        assert.strictEqual(payload.message, 'Describe the attached content.');
        assert.ok(payload.attachments);
        assert.strictEqual(payload.attachments.length, 1);
    });

    it('calls onStopStreaming when isLoading', () => {
        const { ctx, postedMessages } = loadInputModule();
        ctx.isLoading = true;
        ctx.onChatSend();
        assert.strictEqual(postedMessages.length, 1);
        assert.strictEqual(JSON.parse(postedMessages[0]).action, 'cancelStream');
    });

    it('never sends while a stream is active even if isLoading was reset (bug #214/#218)', () => {
        const { ctx, postedMessages } = loadInputModule();
        ctx.isLoading = false;               // mismatched composer state
        ctx.streamState = { active: true };  // the first stream is still in flight
        ctx.onChatSend();
        assert.strictEqual(postedMessages.length, 1, 'no chatSend may be posted mid-stream');
        assert.strictEqual(JSON.parse(postedMessages[0]).action, 'cancelStream',
            'Enter/click during an active stream must cancel, not send a second request');
    });

    it('clears the loading indicator when the composer is enabled (bug #215)', () => {
        const { ctx } = loadInputModule();
        let hidden = 0;
        ctx.hideLoadingIndicator = () => { hidden++; };
        ctx.setChatButtonsEnabled(true);
        assert.strictEqual(hidden, 1, 'enabling the composer must remove any visible loading dots');
    });

    it('does nothing when input is empty and there are no attachments (bug #77)', () => {
        const { ctx, postedMessages } = loadInputModule();
        ctx.isLoading = false;
        ctx.chatMessages = [{ role: 'assistant', content: 'old reply', id: 'm1' }];
        let retried = 0;
        ctx.retryLastAssistantMessage = () => { retried++; };
        const origGetEl = ctx.document.getElementById;
        ctx.document.getElementById = (id) => {
            if (id === 'chat-input') return { value: '', style: {}, disabled: false, focus: () => {} };
            return origGetEl(id);
        };
        ctx.onChatSend();
        assert.strictEqual(postedMessages.length, 0, 'empty Send must not post anything');
        assert.strictEqual(retried, 0, 'empty Send must not retry the last message');
    });
});

describe('retryLastAssistantMessage', () => {
    it('does nothing when isLoading', () => {
        const { ctx, postedMessages } = loadInputModule();
        ctx.isLoading = true;
        ctx.retryLastAssistantMessage('msg-1');
        assert.strictEqual(postedMessages.length, 0);
    });

    it('sends retry with messageId', () => {
        const { ctx, postedMessages } = loadInputModule();
        ctx.isLoading = false;
        ctx.chatMessages = [
            { id: 'u1', role: 'user', content: 'q' },
            { id: 'msg-1', role: 'assistant', content: 'a' }
        ];
        ctx.retryLastAssistantMessage('msg-1');
        const payload = JSON.parse(postedMessages[0]);
        assert.strictEqual(payload.action, 'retry');
        assert.strictEqual(payload.messageId, 'msg-1');
    });

    it('remembers the removed messages and restores them on a failed retry (bug #169)', () => {
        const { ctx } = loadInputModule();
        ctx.isLoading = false;
        ctx.chatMessages = [
            { id: 'u1', role: 'user', content: 'q' },
            { id: 'a1', role: 'assistant', content: 'original answer' },
            { id: 'u2', role: 'user', content: 'follow-up' },
            { id: 'a2', role: 'assistant', content: 'answer two' }
        ];
        ctx.retryLastAssistantMessage('a1');
        // The retried message and everything after it leave the view:
        assert.deepStrictEqual(ctx.chatMessages.map((m) => m.id), ['u1']);
        // The failed-retry error path restores them (the DB row was intact):
        ctx.restoreRetryMessagesOnError();
        assert.deepStrictEqual(ctx.chatMessages.map((m) => m.id), ['u1', 'a1', 'u2', 'a2']);
        // A second restore is a no-op (state cleared):
        ctx.restoreRetryMessagesOnError();
        assert.deepStrictEqual(ctx.chatMessages.map((m) => m.id), ['u1', 'a1', 'u2', 'a2']);
    });

    it('restores only the last assistant when retrying without a message id', () => {
        const { ctx } = loadInputModule();
        ctx.isLoading = false;
        ctx.chatMessages = [
            { id: 'u1', role: 'user', content: 'q' },
            { id: 'a1', role: 'assistant', content: 'original answer' }
        ];
        // removeLastAssistantMessage lives in chat-render.js; mirror its
        // behavior here so the retry path can be exercised.
        ctx.removeLastAssistantMessage = () => {
            for (var i = ctx.chatMessages.length - 1; i >= 0; i--) {
                if (ctx.chatMessages[i].role === 'assistant') { ctx.chatMessages.splice(i, 1); break; }
            }
        };
        ctx.retryLastAssistantMessage('');
        assert.deepStrictEqual(ctx.chatMessages.map((m) => m.id), ['u1']);
        ctx.restoreRetryMessagesOnError();
        assert.deepStrictEqual(ctx.chatMessages.map((m) => m.id), ['u1', 'a1']);
    });
});
