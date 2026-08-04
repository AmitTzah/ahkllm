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
});
