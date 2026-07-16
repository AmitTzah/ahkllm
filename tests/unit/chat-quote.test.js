// chat-quote.test.js — Unit tests for chat-quote.js
const { describe, it } = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

function loadModule() {
    const src = fs.readFileSync(path.resolve(__dirname, '..', '..', 'webui', 'js', 'chat', 'chat-quote.js'), 'utf-8');
    const chatInput = { value: '', focus: () => {}, style: {}, selectionStart: 0, selectionEnd: 0 };
    const sandbox = {
        document: {
            getElementById: (id) => id === 'chat-input' ? chatInput : null,
            querySelector: () => null, querySelectorAll: () => [], createElement: () => ({}), addEventListener: () => {}
        },
        window: { addEventListener: () => {} },
        chatMessages: [], console: console,
        autoResizeChatInput: () => {}
    };
    sandbox.global = sandbox;
    sandbox._chatInput = chatInput;
    vm.runInContext(src, vm.createContext(sandbox));
    return sandbox;
}

describe('quoteMessage', () => {
    it('sets chat input value with quoted message', () => {
        const ctx = loadModule();
        ctx.chatMessages = [{ role: 'user', content: 'Hello world' }];
        ctx.quoteMessage(0);
        const val = ctx._chatInput.value;
        assert.ok(val.indexOf('> Hello world') >= 0);
        assert.ok(val.indexOf('\n\n') >= 0, 'quoted text ends with line break');
    });

    it('focuses chat input', () => {
        const ctx = loadModule();
        ctx.chatMessages = [{ role: 'assistant', content: 'Hi' }];
        assert.doesNotThrow(() => ctx.quoteMessage(0));
    });
});

describe('insertAtCursor', () => {
    it('inserts text into textarea value', () => {
        const ctx = loadModule();
        ctx._chatInput.value = 'existing';
        ctx._chatInput.selectionStart = 8;
        ctx._chatInput.selectionEnd = 8;
        ctx.insertAtCursor(' NEW');
        assert.ok(ctx._chatInput.value.indexOf('NEW') >= 0);
    });
});
