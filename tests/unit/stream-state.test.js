// stream-state.test.js — Unit tests for stream.js: state machine, persist, cancel
const { describe, it } = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

function loadStreamModule() {
    const src = fs.readFileSync(path.resolve(__dirname, '..', '..', 'webui', 'js', 'stream.js'), 'utf-8');
    let postedMessages = [];
    const sandbox = {
        document: {
            getElementById: () => null, createElement: () => ({ style: {}, appendChild: () => {}, querySelector: () => null, querySelectorAll: () => [], insertBefore: () => {} }),
            querySelectorAll: () => [],
        },
        window: { addEventListener: () => {} },
        console: console,
        md: { render: (c) => c },
        setTimeout: setTimeout, clearTimeout: clearTimeout,
        chatMessages: [],
        sessionStorage: { getItem: () => null, setItem: () => {} },
        streamState: undefined,
        scrollToBottom: undefined, startStreaming: undefined, onStreamContent: undefined,
        onStreamReasoning: undefined, _persistStreamedMessage: undefined,
        onStreamDone: undefined, cancelStreaming: undefined,
        createStreamingBubble: undefined, createThinkingBlock: undefined,
        handleStreamMessage: undefined, addStreamingActions: undefined,
        hideLoadingIndicator: () => {}, setChatButtonsEnabled: () => {},
        addMessageActions: () => {},
    };
    sandbox.global = sandbox;
    vm.runInContext(src, vm.createContext(sandbox));
    return sandbox;
}

describe('streamState defaults', () => {
    it('initializes with active=false', () => {
        const ctx = loadStreamModule();
        assert.strictEqual(ctx.streamState.active, false);
    });

    it('initializes with empty buffers', () => {
        const ctx = loadStreamModule();
        assert.strictEqual(ctx.streamState.contentBuffer, '');
        assert.strictEqual(ctx.streamState.thinkingBuffer, '');
    });

    it('initializes with userScrolledUp=false', () => {
        const ctx = loadStreamModule();
        assert.strictEqual(ctx.streamState.userScrolledUp, false);
    });
});

describe('_persistStreamedMessage dedup', () => {
    it('adds message to chatMessages', () => {
        const ctx = loadStreamModule();
        ctx.chatMessages = [];
        ctx.streamState.bubble = { dataset: {} };
        ctx._persistStreamedMessage('hello', 'gpt-4o', { id: 'msg-1' });
        assert.strictEqual(ctx.chatMessages.length, 1);
        assert.strictEqual(ctx.chatMessages[0].content, 'hello');
        assert.strictEqual(ctx.chatMessages[0].model, 'gpt-4o');
    });

    it('deduplicates by id', () => {
        const ctx = loadStreamModule();
        ctx.chatMessages = [{ id: 'msg-1', role: 'assistant', content: 'hello' }];
        ctx.streamState.bubble = { dataset: {} };
        ctx._persistStreamedMessage('hello again', 'gpt-4o', { id: 'msg-1' });
        assert.strictEqual(ctx.chatMessages.length, 1); // should not add duplicate
    });

    it('deduplicates by content when no id', () => {
        const ctx = loadStreamModule();
        ctx.chatMessages = [{ role: 'assistant', content: 'hello' }];
        ctx.streamState.bubble = { dataset: {} };
        ctx._persistStreamedMessage('hello', 'gpt-4o', null);
        assert.strictEqual(ctx.chatMessages.length, 1); // should not add duplicate
    });

    it('adds new message when content differs and no id', () => {
        const ctx = loadStreamModule();
        ctx.chatMessages = [{ role: 'assistant', content: 'old' }];
        ctx.streamState.bubble = { dataset: {} };
        ctx._persistStreamedMessage('new', 'gpt-4o', null);
        assert.strictEqual(ctx.chatMessages.length, 2);
    });

    it('sets dataset.msgId on bubble', () => {
        const ctx = loadStreamModule();
        ctx.chatMessages = [];
        ctx.streamState.bubble = { dataset: {} };
        ctx._persistStreamedMessage('hello', 'gpt-4o', { id: 'msg-99' });
        assert.strictEqual(ctx.streamState.bubble.dataset.msgId, 'msg-99');
    });
});

describe('cancelStreaming state', () => {
    it('does nothing when not active', () => {
        const ctx = loadStreamModule();
        ctx.streamState.active = false;
        ctx.cancelStreaming({});
        assert.strictEqual(ctx.streamState.active, false);
    });

    it('sets active to false when active', () => {
        const ctx = loadStreamModule();
        ctx.streamState.active = true;
        ctx.streamState.contentBuffer = 'partial';
        ctx.streamState.contentDiv = { innerHTML: '' };
        ctx.cancelStreaming({});
        assert.strictEqual(ctx.streamState.active, false);
    });
});
