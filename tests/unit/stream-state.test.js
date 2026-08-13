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
        hideLoadingIndicator: () => {},
        // Mirrors production: enabling the composer clears any visible
        // loading dots (bug #215) - the stream-level tests below rely on it.
        setChatButtonsEnabled: (enabled) => { if (enabled) sandbox.hideLoadingIndicator(); },
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

describe('createStreamingBubble author label escaping (bug #208)', () => {
    // Bug #208: the streaming bubble's author label used to be concatenated
    // into innerHTML without escaping, so an assistant/model name containing
    // HTML (e.g. <img onerror=...>) was parsed and its handlers executed.
    // Load stream.js with a document mock that captures the bubble HTML.
    function loadBubbleHarness() {
        const src = fs.readFileSync(path.resolve(__dirname, '..', '..', 'webui', 'js', 'chat', 'stream.js'), 'utf-8');
        let capturedHtml = '';
        const fakeContentDiv = { innerHTML: '' };
        const fakeBubble = {
            dataset: {},
            querySelector: (sel) => (sel === '.msg-content' ? fakeContentDiv : null),
            querySelectorAll: () => [],
            insertBefore: () => {},
        };
        const template = {
            set innerHTML(v) { capturedHtml = String(v); },
            get innerHTML() { return capturedHtml; },
            firstElementChild: fakeBubble,
        };
        const sandbox = {
            document: {
                getElementById: (id) => (id === 'chat-messages' ? { appendChild: () => {} } : null),
                createElement: () => template,
                querySelectorAll: () => [],
                querySelector: () => null,
                addEventListener: () => {},
            },
            window: { addEventListener: () => {} },
            console,
            md: { render: (c) => c },
            setTimeout,
            clearTimeout,
            chatMessages: [],
            sessionStorage: { getItem: () => null, setItem: () => {} },
            // Same escape helper chat-core.js provides in the real page.
            escHtml: (s) => String(s || '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;'),
            hideLoadingIndicator: () => {},
            setChatButtonsEnabled: () => {},
        };
        sandbox.global = sandbox;
        vm.runInContext(src, vm.createContext(sandbox));
        // stream.js declares `var streamState = {...}` at load, which replaces
        // the sandbox value - set the display name the way onStreamModelName
        // does before the bubble is created.
        sandbox.streamState.modelName = '<img src="x" onerror="window.__xssPwned=1">';
        return { sandbox, html: () => capturedHtml };
    }

    it('escapes the author label so markup in a model/assistant name cannot execute', () => {
        const h = loadBubbleHarness();
        const bubble = h.sandbox.createStreamingBubble();
        const html = h.html();
        // The injected name must be rendered as inert text: no raw <img> tag,
        // and the escaped entity must be present in the author span.
        assert.strictEqual(html.indexOf('<img'), -1, 'raw <img> must not appear in the bubble HTML');
        assert.ok(html.indexOf('&lt;img') >= 0, 'author name must be HTML-escaped: ' + html);
        assert.ok(html.indexOf('window.__xssPwned=1') >= 0, 'the payload text should still be visible as text');
        // The author span's textContent (once parsed) is the original name.
        assert.ok(typeof bubble === 'object', 'createStreamingBubble should still return the bubble');
    });

    it('keeps a plain assistant name unchanged', () => {
        const h = loadBubbleHarness();
        h.sandbox.streamState.modelName = 'DeepSeek V4 Flash';
        h.sandbox.createStreamingBubble();
        const html = h.html();
        assert.ok(html.indexOf('>DeepSeek V4 Flash<') >= 0, 'plain names must render as-is: ' + html);
        assert.strictEqual(html.indexOf('&lt;'), -1, 'plain names must not be over-escaped');
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

describe('_streamBelongsToCurrentPath (bug #195)', () => {
    it('rejects a response whose parent is not the current last message', () => {
        const ctx = loadStreamModule();
        ctx.chatMessages = [{ id: 'b-last', role: 'user', content: 'B' }];
        assert.strictEqual(ctx._streamBelongsToCurrentPath({ id: 'a-msg', parentId: 'a-parent' }), false);
    });

    it('accepts a response whose parent is the current last message', () => {
        const ctx = loadStreamModule();
        ctx.chatMessages = [{ id: 'a-parent', role: 'user', content: 'A' }];
        assert.strictEqual(ctx._streamBelongsToCurrentPath({ id: 'a-msg', parentId: 'a-parent' }), true);
    });

    it('accepts a root retry when the UI path was emptied', () => {
        const ctx = loadStreamModule();
        ctx.chatMessages = [];
        assert.strictEqual(ctx._streamBelongsToCurrentPath({ id: 'root-retry', parentId: '' }), true);
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

describe('onStreamDone thread scoping (bug #195)', () => {
    it('does not persist another thread/branch response into the current array', () => {
        const ctx = loadStreamModule();
        ctx.activeThreadId = 't-B';
        ctx.chatMessages = [{ id: 'b-user', role: 'user', content: 'B question' }];
        ctx.streamState.active = true;
        ctx.streamState.bubble = null;
        ctx.streamState.contentBuffer = 'A answer';
        ctx.streamState.thinkingBuffer = '';
        ctx.streamState.modelName = 'm';
        ctx.streamState.userScrolledUp = false;
        ctx.streamState.contentDiv = null;
        ctx.streamState.thinkingDetails = null;
        ctx.onStreamDone({ model: 'm', threadId: 't-A', dbMsg: { id: 'a-msg', parentId: 'a-user' } });
        assert.strictEqual(ctx.chatMessages.length, 1, 'wrong-thread response must not be pushed into chatMessages');
        assert.strictEqual(ctx.streamState.active, false, 'stream state still cleans up');
    });

    it('hides the loading indicator when a NON-current stream completes (bug #215)', () => {
        const ctx = loadStreamModule();
        ctx.activeThreadId = 't-B';
        ctx.chatMessages = [{ id: 'b-user', role: 'user', content: 'B question' }];
        ctx.streamState.active = true;
        ctx.streamState.bubble = null;
        ctx.streamState.contentBuffer = 'A answer';
        ctx.streamState.thinkingBuffer = '';
        ctx.streamState.modelName = 'm';
        ctx.streamState.userScrolledUp = false;
        ctx.streamState.contentDiv = null;
        ctx.streamState.thinkingDetails = null;
        let hidden = 0;
        ctx.hideLoadingIndicator = () => { hidden++; };
        ctx.onStreamDone({ model: 'm', threadId: 't-A', dbMsg: { id: 'a-msg', parentId: 'a-user' } });
        assert.strictEqual(ctx.chatMessages.length, 1, 'wrong-thread response must not be pushed into chatMessages');
        assert.strictEqual(ctx.streamState.active, false);
        assert.ok(hidden > 0, 'completing the non-current stream must clear the visible loading dots');
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
