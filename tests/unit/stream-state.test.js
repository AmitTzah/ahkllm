// stream-state.test.js — Unit tests for stream.js: state machine, persist, cancel
const { describe, it } = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

function loadStreamModule() {
    const src = fs.readFileSync(path.resolve(__dirname, '..', '..', 'webui', 'js', 'chat', 'stream.js'), 'utf-8');
    let postedMessages = [];
    const sandbox = {
        document: {
            getElementById: () => null, createElement: () => ({ style: {}, appendChild: () => {}, querySelector: () => null, querySelectorAll: () => [], insertBefore: () => {} }),
            querySelectorAll: () => [],
            querySelector: () => null,
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

describe('onStreamDone reasoning-only responses', () => {
    function makeBubble() {
        const shared = { textContent: '' };
        return {
            dataset: {},
            querySelector(sel) {
                return sel === '.msg-content' ? shared : shared;
            },
            querySelectorAll: () => [],
        };
    }

    it('persists the message and adds actions when only thinking was streamed', () => {
        const ctx = loadStreamModule();
        ctx.chatMessages = [{ role: 'user', content: 'think only please' }];
        const bubble = makeBubble();
        ctx.streamState.active = true;
        ctx.streamState.bubble = bubble;
        ctx.streamState.contentDiv = { innerHTML: '' };
        ctx.streamState.thinkingDetails = { querySelector: () => ({ innerHTML: '', remove: () => {} }) };
        ctx.streamState.contentBuffer = '';
        ctx.streamState.thinkingBuffer = 'reasoning text';
        ctx.streamState.modelName = 'thinking-model';
        let actionsAdded = 0;
        ctx.addStreamingActions = (b, idx) => { actionsAdded++; assert.strictEqual(b, bubble); assert.strictEqual(idx, 1); };

        ctx.onStreamDone({ model: 'thinking-model', dbMsg: { id: 'm-reasoning-1', reasoning: 'reasoning text' } });

        assert.strictEqual(ctx.chatMessages.length, 2);
        assert.strictEqual(ctx.chatMessages[1].role, 'assistant');
        assert.strictEqual(ctx.chatMessages[1].content, '');
        assert.strictEqual(ctx.chatMessages[1].id, 'm-reasoning-1');
        assert.strictEqual(ctx.chatMessages[1].reasoning, 'reasoning text');
        assert.strictEqual(actionsAdded, 1);
    });
});

describe('_updateUserTokenCount', () => {
    it('applies a zero contribution to the last user message (bug #150)', () => {
        const ctx = loadStreamModule();
        ctx.chatMessages = [
            { id: 'u1', role: 'user', tokenCount: 12 },
            { id: 'a1', role: 'assistant' },
            { id: 'u2b', role: 'user', tokenCount: 7 },
            { id: 'a2b', role: 'assistant' }
        ];
        ctx._updateUserTokenCount({ userTokenCount: 0 });
        assert.strictEqual(ctx.chatMessages[2].tokenCount, 0);
    });

    it('applies a positive contribution to the last user message', () => {
        const ctx = loadStreamModule();
        ctx.chatMessages = [{ id: 'u1', role: 'user', tokenCount: 7 }];
        ctx._updateUserTokenCount({ userTokenCount: 9 });
        assert.strictEqual(ctx.chatMessages[0].tokenCount, 9);
    });

    it('skips when userTokenCount is absent', () => {
        const ctx = loadStreamModule();
        ctx.chatMessages = [{ id: 'u1', role: 'user', tokenCount: 5 }];
        ctx._updateUserTokenCount({});
        assert.strictEqual(ctx.chatMessages[0].tokenCount, 5);
    });
});

describe('retry restore state cleared on success (bug #169)', () => {
    it('onStreamDone clears the pending retry-restore messages', () => {
        const ctx = loadStreamModule();
        ctx._retryRemovedMessages = [{ id: 'a1', role: 'assistant' }];
        ctx.chatMessages = [{ role: 'user', content: 'q' }];
        ctx.streamState.active = true;
        ctx.streamState.bubble = null;
        ctx.streamState.contentBuffer = 'new answer';
        ctx.streamState.thinkingBuffer = '';
        ctx.streamState.modelName = 'm';
        ctx.streamState.userScrolledUp = false;
        ctx.streamState.contentDiv = null;
        ctx.streamState.thinkingDetails = null;
        ctx.onStreamDone({ model: 'm' });
        assert.strictEqual(ctx._retryRemovedMessages, null);
    });
});
