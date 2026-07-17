// chat-render.test.js — Unit tests for chat-render.js
const { describe, it } = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

// Simple DOM parser for innerHTML-based approach
function parseHtml(html) {
  // Basic innerHTML parsing: just detect key class names in the string
  return {
    innerHTML: html,
    className: (html.match(/class="([^"]+)"/) || [,''])[1],
    children: [],
    querySelector: function(sel) {
      if (html.indexOf(sel.replace('.','')) >= 0) {
        return { className: sel.replace('.',''), innerHTML: '', children: [], appendChild: function(){}, querySelector: function(){ return null; } };
      }
      return null;
    },
    querySelectorAll: function() { return []; }
  };
}

function loadRenderModule() {
    const src = fs.readFileSync(path.resolve(__dirname, '..', '..', 'webui', 'js', 'chat', 'chat-render.js'), 'utf-8');
    let createdElements = [];
    function makeEl(tag) {
        const el = {
            tagName: tag, className: '', innerHTML: '', id: '', textContent: '', title: '',
            style: {}, dataset: {}, children: [],
            firstElementChild: null,
            classList: { add: function(c) { el.className += ' ' + c; }, contains: function(c) { return el.className.indexOf(c) >= 0; } },
            appendChild: function(child) { el.children.push(child); return child; },
            addEventListener: function(evt, fn) {},
            querySelector: function(sel) {
              // Simple: return a child-like object if the HTML contains the selector
              if (el.innerHTML.indexOf(sel.replace('.','').replace('#','')) >= 0) {
                return { className: sel.replace('.',''), innerHTML: '', children: [], appendChild: function(){}, querySelector: function(){ return null; }, querySelectorAll: function(){ return []; } };
              }
              return null;
            },
            querySelectorAll: function() { return []; },
            insertBefore: function(child, ref) { el.children.push(child); },
            remove: function() {},
            closest: (sel) => null,
            getAttribute: () => null,
            setAttribute: function(k,v) { this[k] = v; },
            scrollIntoView: () => {},
            scrollTop: 0,
            scrollHeight: 0,
            nextSibling: null,
            firstChild: null
        };
        createdElements.push(el);
        return el;
    }
    let postedMessages = [];
    const sandbox = {
        document: {
            getElementById: (id) => {
                if (id === 'chat-messages') {
                    if (!sandbox._chatMessagesEl) sandbox._chatMessagesEl = makeEl('div');
                    return sandbox._chatMessagesEl;
                }
                return null;
            },
            querySelectorAll: () => [],
            createElement: function(tag) {
              const el = makeEl(tag);
              // Override innerHTML setter to populate firstElementChild and enable querySelector
              var _innerHTML = '';
              Object.defineProperty(el, 'innerHTML', {
                get: function() { return _innerHTML; },
                set: function(val) {
                  _innerHTML = val;
                  // Parse the class from the first element
                  var m = val.match(/class="([^"]+)"/);
                  if (m) el.firstElementChild = { className: m[1], children: [], style: {}, dataset: {}, querySelector: function(s) {
                    if (val.indexOf(s.replace('.','').replace('#','')) >= 0) {
                      return { className: s.replace('.',''), innerHTML: '', children: [], appendChild: function(){}, querySelector: function(){ return null; }, querySelectorAll: function(){ return []; }, style: {}, setAttribute: function(){}, removeAttribute: function(){} };
                    }
                    return null;
                  }, querySelectorAll: function() { return []; }, classList: { add: function(){}, contains: function(){ return false; } }, appendChild: function(c){ this.children.push(c); }, addEventListener: function(){}, remove: function(){}, insertBefore: function(){}, closest: function(){ return null; }, setAttribute: function(){}, removeAttribute: function(){} };
                }
              });
              return el;
            },
            body: { appendChild: () => {} },
            addEventListener: () => {}
        },
        window: {
            chrome: { webview: { postMessage: (msg) => postedMessages.push(JSON.parse(msg)) } },
            addEventListener: () => {},
            getSelection: () => ({ toString: () => '', removeAllRanges: () => {}, getRangeAt: () => ({ commonAncestorContainer: {}, getBoundingClientRect: () => ({}) }) })
        },
        console: console,
        chatMessages: [],
        md: { render: (c) => '<p>' + c + '</p>' },
        sessionStorage: { getItem: () => null, setItem: () => {} },
        addMessageActions: (container, msg, idx) => {},
        createTokenInfoIcon: () => null,
        hideLoadingIndicator: () => {},
        renderAttachments: () => {},
        escHtml: (s) => String(s||'').replace(/&/g,'&').replace(/</g,'<').replace(/>/g,'>'),
        Number: Number, String: String, Date: Date,
        isNaN: isNaN,
        navigator: { clipboard: { writeText: async () => {} } }
    };
    sandbox.global = sandbox;
    sandbox._createdElements = createdElements;
    sandbox._postedMessages = postedMessages;
    vm.runInContext(src, vm.createContext(sandbox));
    return sandbox;
}

describe('createMessageBubble — user', () => {
    it('produces a bubble with msg and you classes', () => {
        const ctx = loadRenderModule();
        const bubble = ctx.createMessageBubble({ role: 'user', content: 'Hello', id: 'u1', createdAt: '2026-01-01T13:01:00' }, 0);
        assert.ok(bubble);
        assert.ok(bubble.className.includes('msg'));
        assert.ok(bubble.className.includes('you'));
    });

    it('produces non-null bubble', () => {
        const ctx = loadRenderModule();
        const bubble = ctx.createMessageBubble({ role: 'user', content: 'Hello', id: 'msg-abc123', createdAt: '2026-01-01T13:01:00' }, 0);
        assert.ok(bubble !== null);
        assert.ok(bubble !== undefined);
        assert.ok(bubble.className.length > 0);
    });
});

describe('createMessageBubble — assistant', () => {
    it('produces a bubble with msg and bot classes', () => {
        const ctx = loadRenderModule();
        const bubble = ctx.createMessageBubble({ role: 'assistant', content: 'Hi!', model: 'gpt-4o', id: 'a1', createdAt: '2026-01-01T13:11:00' }, 1);
        assert.ok(bubble.className.includes('msg'));
        assert.ok(bubble.className.includes('bot'));
    });

    it('creates non-null bubble for assistant', () => {
        const ctx = loadRenderModule();
        const bubble = ctx.createMessageBubble({ role: 'assistant', content: 'Answer', reasoning: 'Let me think...', id: 'a1' }, 1);
        assert.ok(bubble !== null);
        assert.ok(bubble.className.includes('bot'));
    });

    it('creates non-null bubble for assistant without reasoning', () => {
        const ctx = loadRenderModule();
        const bubble = ctx.createMessageBubble({ role: 'assistant', content: 'Answer', id: 'a1' }, 1);
        assert.ok(bubble !== null);
        assert.ok(bubble.className.includes('bot'));
    });
});

describe('createMessageBubble — system', () => {
    it('produces a bubble with msg and system classes', () => {
        const ctx = loadRenderModule();
        const bubble = ctx.createMessageBubble({ role: 'system', content: 'You are helpful', id: 's1' }, 2);
        assert.ok(bubble.className.includes('msg'));
        assert.ok(bubble.className.includes('system'));
    });

    it('system bubble has correct class', () => {
        const ctx = loadRenderModule();
        const bubble = ctx.createMessageBubble({ role: 'system', content: 'You are helpful', id: 's1' }, 2);
        assert.ok(bubble.className.includes('system'));
    });
});

describe('renderChatMessages', () => {
    it('populates chat-messages container', () => {
        const ctx = loadRenderModule();
        ctx.chatMessages = [{ role: 'user', content: 'Hi', id: 'u1', createdAt: '2026-01-01T13:01:00' }];
        ctx.renderChatMessages(ctx.chatMessages);
        const container = ctx.document.getElementById('chat-messages');
        assert.ok(container.children.length >= 1);
    });
});

describe('appendChatMessage', () => {
    it('adds message to chatMessages array and DOM', () => {
        const ctx = loadRenderModule();
        ctx.chatMessages = [];
        const container = ctx.document.getElementById('chat-messages');
        ctx.appendChatMessage({ role: 'user', content: 'New', id: 'new1', createdAt: '2026-01-01T13:01:00' });
        assert.strictEqual(ctx.chatMessages.length, 1);
        assert.ok(container.children.length >= 1);
    });
});

describe('removeLastAssistantMessage', () => {
    it('removes last assistant message from array', () => {
        const ctx = loadRenderModule();
        ctx.chatMessages = [
            { role: 'user', content: 'Hi', id: 'u1' },
            { role: 'assistant', content: 'Hey', id: 'a1' }
        ];
        ctx.removeLastAssistantMessage();
        assert.strictEqual(ctx.chatMessages.length, 1);
        assert.strictEqual(ctx.chatMessages[0].role, 'user');
    });

    it('removes only last assistant even with multiple', () => {
        const ctx = loadRenderModule();
        ctx.chatMessages = [
            { role: 'user', content: 'Q1', id: 'u1' },
            { role: 'assistant', content: 'A1', id: 'a1' },
            { role: 'user', content: 'Q2', id: 'u2' },
            { role: 'assistant', content: 'A2', id: 'a2' }
        ];
        ctx.removeLastAssistantMessage();
        assert.strictEqual(ctx.chatMessages.length, 3);
    });
});

describe('_buildMetaText', () => {
    it('returns empty for no createdAt', () => {
        const ctx = loadRenderModule();
        assert.strictEqual(ctx._buildMetaText({}), '');
    });

    it('returns user format with · prefix', () => {
        const ctx = loadRenderModule();
        const meta = ctx._buildMetaText({ role: 'user', createdAt: '2025-01-01T12:00:00' });
        assert.ok(meta.indexOf('· ') === 0);
    });

    it('returns assistant format with model prefix', () => {
        const ctx = loadRenderModule();
        const meta = ctx._buildMetaText({ role: 'assistant', model: 'deepseek-v4', createdAt: '2025-01-01T12:00:00' });
        assert.ok(meta.indexOf('deepseek-v4') >= 0);
        assert.ok(meta.indexOf('·') > 0);
    });
});

describe('_buildReasoningHtml', () => {
    it('returns empty for no reasoning', () => {
        const ctx = loadRenderModule();
        assert.strictEqual(ctx._buildReasoningHtml({}), '');
    });

    it('returns thinking block HTML when reasoning present', () => {
        const ctx = loadRenderModule();
        const html = ctx._buildReasoningHtml({ reasoning: 'Let me think...' });
        assert.ok(html.indexOf('thinking-block') >= 0);
        assert.ok(html.indexOf('open') >= 0, 'thinking block should have open attribute by default');
        assert.ok(html.indexOf('Let me think...') >= 0);
    });
});

describe('_buildAttachmentHtml', () => {
    it('returns empty for no attachments', () => {
        const ctx = loadRenderModule();
        assert.strictEqual(ctx._buildAttachmentHtml({}), '');
    });

    it('returns empty for non-user roles', () => {
        const ctx = loadRenderModule();
        assert.strictEqual(ctx._buildAttachmentHtml({ role: 'assistant', attachments: [{ attachment_type: 'image' }] }), '');
    });

    it('returns image HTML for image attachments', () => {
        const ctx = loadRenderModule();
        const html = ctx._buildAttachmentHtml({
            role: 'user',
            attachments: [{ attachment_type: 'image', base64: 'abc123', mime_type: 'image/png', original_filename: 'test.png' }]
        });
        assert.ok(html.indexOf('msg-attachment-image') >= 0);
    });
});

describe('_buildEditUiHtml', () => {
    it('returns edit UI with cancel and save buttons', () => {
        const ctx = loadRenderModule();
        const html = ctx._buildEditUiHtml({ content: 'test' });
        assert.ok(html.indexOf('msg-edit-ui') >= 0);
        assert.ok(html.indexOf('cancel-edit') >= 0);
        assert.ok(html.indexOf('save-overwrite') >= 0);
    });
});

describe('_saveThinkingBlockStates', () => {
    it('does not throw when no thinking blocks exist', () => {
        const ctx = loadRenderModule();
        ctx._saveThinkingBlockStates();  // should not throw
    });

    it('accumulates open state keyed by message ID into persistent record', () => {
        const ctx = loadRenderModule();
        var savedQsAll = ctx.document.querySelectorAll;
        ctx.document.querySelectorAll = function(sel) {
            if (sel === '.thinking-block') {
                return [
                    { open: true, closest: function(s) { return s === '.msg' ? { getAttribute: function(a) { return a === 'data-msg-id' ? 'msg-aaa' : null; } } : null; } },
                    { open: false, closest: function(s) { return s === '.msg' ? { getAttribute: function(a) { return a === 'data-msg-id' ? 'msg-bbb' : null; } } : null; } }
                ];
            }
            return savedQsAll(sel);
        };
        ctx._saveThinkingBlockStates();
        assert.strictEqual(ctx._persistedThinkingStates['msg-aaa'], true);
        assert.strictEqual(ctx._persistedThinkingStates['msg-bbb'], false);
        ctx.document.querySelectorAll = savedQsAll;
    });

    it('skips blocks without a parent .msg', () => {
        const ctx = loadRenderModule();
        var savedQuerySelectorAll = ctx.document.querySelectorAll;
        ctx.document.querySelectorAll = function(sel) {
            if (sel === '.thinking-block') {
                return [{ open: true, closest: function() { return null; } }];
            }
            return savedQuerySelectorAll(sel);
        };
        // Should not throw — just skips
        ctx._saveThinkingBlockStates();
        ctx.document.querySelectorAll = savedQuerySelectorAll;
    });
});

describe('_restoreThinkingBlockStates', () => {
    it('does nothing when persistent record is empty', () => {
        const ctx = loadRenderModule();
        ctx._persistedThinkingStates = {};
        ctx._restoreThinkingBlockStates();  // should not throw
    });

    it('does nothing when no thinking blocks in DOM', () => {
        const ctx = loadRenderModule();
        var container = ctx.document.getElementById('chat-messages');
        ctx._persistedThinkingStates = { 'msg-1': true };
        // container.querySelectorAll('.thinking-block') returns [] by default
        ctx._restoreThinkingBlockStates();  // should not throw
    });

    it('sets open attribute when persisted state is true', () => {
        const ctx = loadRenderModule();
        var track = { setOpenCalled: false, removeOpenCalled: false };
        var blockEl = {
            setAttribute: function(name) { if (name === 'open') track.setOpenCalled = true; },
            removeAttribute: function(name) { if (name === 'open') track.removeOpenCalled = true; },
            closest: function(s) { return s === '.msg' ? { getAttribute: function(a) { return a === 'data-msg-id' ? 'msg-1' : null; } } : null; }
        };
        var container = ctx.document.getElementById('chat-messages');
        var savedQsAll = container.querySelectorAll;
        container.querySelectorAll = function(sel) {
            if (sel === '.thinking-block') return [blockEl];
            return [];
        };
        ctx._persistedThinkingStates = { 'msg-1': true };
        ctx._restoreThinkingBlockStates();
        assert.ok(track.setOpenCalled, 'should set open attribute');
        assert.strictEqual(track.removeOpenCalled, false);
        container.querySelectorAll = savedQsAll;
    });

    it('removes open attribute when persisted state is false', () => {
        const ctx = loadRenderModule();
        var track = { setOpenCalled: false, removeOpenCalled: false };
        var blockEl = {
            setAttribute: function(name) { if (name === 'open') track.setOpenCalled = true; },
            removeAttribute: function(name) { if (name === 'open') track.removeOpenCalled = true; },
            closest: function(s) { return s === '.msg' ? { getAttribute: function(a) { return a === 'data-msg-id' ? 'msg-2' : null; } } : null; }
        };
        var container = ctx.document.getElementById('chat-messages');
        var savedQsAll = container.querySelectorAll;
        container.querySelectorAll = function(sel) {
            if (sel === '.thinking-block') return [blockEl];
            return [];
        };
        ctx._persistedThinkingStates = { 'msg-2': false };
        ctx._restoreThinkingBlockStates();
        assert.ok(track.removeOpenCalled, 'should remove open attribute');
        assert.strictEqual(track.setOpenCalled, false);
        container.querySelectorAll = savedQsAll;
    });

    it('skips blocks whose msg ID is not in persistent record', () => {
        const ctx = loadRenderModule();
        var track = { setOpenCalled: false, removeOpenCalled: false };
        var blockEl = {
            setAttribute: function(name) { if (name === 'open') track.setOpenCalled = true; },
            removeAttribute: function(name) { if (name === 'open') track.removeOpenCalled = true; },
            closest: function(s) { return s === '.msg' ? { getAttribute: function(a) { return a === 'data-msg-id' ? 'msg-unknown' : null; } } : null; }
        };
        var container = ctx.document.getElementById('chat-messages');
        var savedQsAll = container.querySelectorAll;
        container.querySelectorAll = function(sel) {
            if (sel === '.thinking-block') return [blockEl];
            return [];
        };
        ctx._persistedThinkingStates = { 'msg-1': false };  // different ID
        ctx._restoreThinkingBlockStates();
        assert.strictEqual(track.setOpenCalled, false, 'should NOT modify block with unknown ID');
        assert.strictEqual(track.removeOpenCalled, false);
        container.querySelectorAll = savedQsAll;
    });

    it('skips blocks without a parent .msg', () => {
        const ctx = loadRenderModule();
        var blockEl = { closest: function(s) { return null; }, setAttribute: function(){}, removeAttribute: function(){} };
        var container = ctx.document.getElementById('chat-messages');
        var savedQsAll = container.querySelectorAll;
        container.querySelectorAll = function(sel) {
            if (sel === '.thinking-block') return [blockEl];
            return [];
        };
        ctx._persistedThinkingStates = { 'msg-1': true };
        ctx._restoreThinkingBlockStates();  // should not throw
        container.querySelectorAll = savedQsAll;
    });
});

describe('renderChatMessages preserves thinking block state', () => {
    it('does not throw with messages containing reasoning', () => {
        const ctx = loadRenderModule();
        ctx.chatMessages = [
            { role: 'user', content: 'Hi', id: 'u1', createdAt: '2026-01-01T13:01:00' },
            { role: 'assistant', content: 'Answer', reasoning: 'Let me think...', model: 'gpt-4o', id: 'a1', createdAt: '2026-01-01T13:02:00' }
        ];
        ctx.renderChatMessages(ctx.chatMessages);
        var container = ctx.document.getElementById('chat-messages');
        assert.ok(container.children.length >= 2, 'should render 2 messages');
    });

    it('restores persisted collapsed state on re-render', () => {
        const ctx = loadRenderModule();
        ctx.chatMessages = [
            { role: 'assistant', content: 'Answer', reasoning: 'Let me think...', model: 'gpt-4o', id: 'a1', createdAt: '2026-01-01T13:02:00' }
        ];

        // User collapsed a1 previously
        ctx._persistedThinkingStates['a1'] = false;

        // Override container.querySelectorAll to return a tracking block for the restore phase
        var container = ctx.document.getElementById('chat-messages');
        var restoreCalled = false;
        var track = { setOpenCalled: false, removeOpenCalled: false };
        var blockEl = {
            setAttribute: function(name) { if (name === 'open') track.setOpenCalled = true; },
            removeAttribute: function(name) { if (name === 'open') track.removeOpenCalled = true; },
            closest: function(s) { return s === '.msg' ? { getAttribute: function(a) { return a === 'data-msg-id' ? 'a1' : null; } } : null; }
        };
        var savedQsAll = container.querySelectorAll;
        container.querySelectorAll = function(sel) {
            if (sel === '.thinking-block') { restoreCalled = true; return [blockEl]; }
            return savedQsAll(sel);
        };

        ctx.renderChatMessages(ctx.chatMessages);
        assert.ok(restoreCalled, 'restore should scan DOM for thinking blocks');
        assert.ok(track.removeOpenCalled, 'should restore collapsed state from persistent record');
        container.querySelectorAll = savedQsAll;
    });

    it('does not throw when rendering empty messages array', () => {
        const ctx = loadRenderModule();
        ctx.renderChatMessages([]);
        var container = ctx.document.getElementById('chat-messages');
        assert.strictEqual(container.children.length, 0);
    });
});

describe('replaceMessagesAfter preserves thinking block state', () => {
    it('does not affect sibling branch (different IDs, independent state)', () => {
        const ctx = loadRenderModule();
        ctx.chatMessages = [
            { role: 'user', content: 'Q1', id: 'u1', createdAt: '2026-01-01T13:01:00' },
            { role: 'assistant', content: 'A1', reasoning: 'thinking...', model: 'gpt-4o', id: 'a1', createdAt: '2026-01-01T13:02:00' }
        ];
        ctx.renderChatMessages(ctx.chatMessages);

        // User collapsed a1
        ctx._persistedThinkingStates['a1'] = false;

        // Branch switch: a1 replaced with a1-b (different ID, no persisted state)
        var container = ctx.document.getElementById('chat-messages');
        var track = { setOpenCalled: false, removeOpenCalled: false };
        var blockA1b = {
            setAttribute: function(name) { if (name === 'open') track.setOpenCalled = true; },
            removeAttribute: function(name) { if (name === 'open') track.removeOpenCalled = true; },
            closest: function(s) { return s === '.msg' ? { getAttribute: function(a) { return a === 'data-msg-id' ? 'a1-b' : null; } } : null; }
        };
        var savedQsAll = container.querySelectorAll;
        container.querySelectorAll = function(sel) {
            if (sel === '.thinking-block') return [blockA1b];
            if (sel === '.msg') return container.children;
            return savedQsAll(sel);
        };

        var newMessages = [
            { role: 'user', content: 'Q1', id: 'u1', createdAt: '2026-01-01T13:01:00' },
            { role: 'assistant', content: 'A1-branch-B', reasoning: 'different...', model: 'gpt-4o', id: 'a1-b', createdAt: '2026-01-01T13:03:00' }
        ];
        ctx.replaceMessagesAfter(1, newMessages, 1);

        // a1-b is NOT in persistent record — should NOT be modified
        assert.strictEqual(track.setOpenCalled, false, 'a1-b should NOT be collapsed (no persisted state)');
        assert.strictEqual(track.removeOpenCalled, false);
        container.querySelectorAll = savedQsAll;
    });

    it('restores collapsed state when switching back to original branch', () => {
        const ctx = loadRenderModule();
        ctx.chatMessages = [
            { role: 'assistant', content: 'A1', reasoning: 'thinking...', model: 'gpt-4o', id: 'a1', createdAt: '2026-01-01T13:02:00' }
        ];
        ctx.renderChatMessages(ctx.chatMessages);

        // User collapsed a1
        ctx._persistedThinkingStates['a1'] = false;

        var container = ctx.document.getElementById('chat-messages');
        var track = { setOpenCalled: false, removeOpenCalled: false };
        var blockA1 = {
            setAttribute: function(name) { if (name === 'open') track.setOpenCalled = true; },
            removeAttribute: function(name) { if (name === 'open') track.removeOpenCalled = true; },
            closest: function(s) { return s === '.msg' ? { getAttribute: function(a) { return a === 'data-msg-id' ? 'a1' : null; } } : null; }
        };
        var savedQsAll = container.querySelectorAll;
        container.querySelectorAll = function(sel) {
            if (sel === '.thinking-block') return [blockA1];
            if (sel === '.msg') return container.children;
            return savedQsAll(sel);
        };

        ctx.replaceMessagesAfter(0,
            [{ role: 'assistant', content: 'A1', reasoning: 'thinking...', model: 'gpt-4o', id: 'a1', createdAt: '2026-01-01T13:02:00' }], 0);

        assert.ok(track.removeOpenCalled, 'should restore collapsed state when switching back');
        assert.strictEqual(track.setOpenCalled, false);
        container.querySelectorAll = savedQsAll;
    });

    it('handles empty newMessages correctly', () => {
        const ctx = loadRenderModule();
        ctx.chatMessages = [
            { role: 'user', content: 'Q1', id: 'u1', createdAt: '2026-01-01T13:01:00' }
        ];
        ctx.renderChatMessages(ctx.chatMessages);
        ctx.replaceMessagesAfter(0, [], 0);
    });
});
