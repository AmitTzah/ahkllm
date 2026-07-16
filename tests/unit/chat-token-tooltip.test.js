// chat-token-tooltip.test.js — Unit tests for chat-token-tooltip.js
const { describe, it } = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

function loadModule() {
    const src = fs.readFileSync(path.resolve(__dirname, '..', '..', 'webui', 'js', 'chat', 'chat-token-tooltip.js'), 'utf-8');
    let elements = [];
    function makeEl(tag) {
        const el = { tagName: tag, className: '', innerHTML: '', textContent: '', style: {},
            classList: { add: function() {}, remove: function() {} },
            appendChild: function(c) { el.children.push(c); return c; },
            querySelector: function() { return makeEl('div'); },
            querySelectorAll: function() { return []; },
            children: [], addEventListener: function() {} };
        elements.push(el);
        return el;
    }
    const sandbox = {
        document: {
            createElement: (tag) => makeEl(tag),
            querySelectorAll: () => [],
            addEventListener: () => {}
        },
        window: { addEventListener: () => {} },
        chatMessages: [{ token_count: 100, thinking_tokens: 20, cached_tokens: 30, response_time_ms: 500, ttft_ms: 200, model: 'deepseek-v4' }],
        lucide: { createIcons: () => {} },
        formatNumber: function(n) { return String(n).replace(/\\B(?=(\\d{3})+(?!\\d))/g, ','); },
        console: console
    };
    sandbox.global = sandbox;
    sandbox._elements = elements;
    vm.runInContext(src, vm.createContext(sandbox));
    return sandbox;
}

describe('createTokenInfoIcon', () => {
    it('creates wrapper even for out-of-range index', () => {
        const ctx = loadModule();
        const icon = ctx.createTokenInfoIcon({}, 99);
        assert.ok(icon !== null);
        assert.ok(icon !== undefined);
    });

    it('creates stat-toggle button when message exists', () => {
        const ctx = loadModule();
        const msg = { token_count: 100, thinking_tokens: 50, cached_tokens: 20, response_time_ms: 500, ttft_ms: 200, model: 'gpt-4o' };
        ctx.chatMessages = [msg];
        const icon = ctx.createTokenInfoIcon(msg, 0);
        assert.ok(icon !== null);
        assert.ok(icon !== undefined);
    });
});

describe('showTokenTooltip', () => {
    it('populates popover with token stats for assistant', () => {
        const ctx = loadModule();
        const popover = { innerHTML: '' };
        const msg = { role: 'assistant', tokenCount: 500, thinkingTokens: 100, cachedTokens: 200, responseTimeMs: 1000, ttftMs: 300, model: 'deepseek-v4' };
        ctx.showTokenTooltip(popover, msg);
        assert.ok(popover.innerHTML.indexOf('500') >= 0);
        assert.ok(popover.innerHTML.indexOf('Token Usage') >= 0);
    });
});

describe('closeAllTokenTooltips', () => {
    it('does not throw', () => {
        const ctx = loadModule();
        assert.doesNotThrow(() => ctx.closeAllTokenTooltips());
    });
});
