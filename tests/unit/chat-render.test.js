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
                      return { className: s.replace('.',''), innerHTML: '', children: [], appendChild: function(){}, querySelector: function(){ return null; }, querySelectorAll: function(){ return []; }, style: {} };
                    }
                    return null;
                  }, querySelectorAll: function() { return []; }, classList: { add: function(){}, contains: function(){ return false; } }, appendChild: function(c){ this.children.push(c); }, addEventListener: function(){}, remove: function(){}, insertBefore: function(){}, closest: function(){ return null; } };
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
