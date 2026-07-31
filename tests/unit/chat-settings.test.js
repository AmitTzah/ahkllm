// chat-settings.test.js — Unit tests for chat-settings.js: populateAssistantDropdown, model card, popover
const { describe, it } = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

function loadSettingsModule() {
    const src = fs.readFileSync(path.resolve(__dirname, '..', '..', 'webui', 'js', 'chat', 'settings', 'chat-settings.js'), 'utf-8');
    const sandbox = {
        document: {
            getElementById: () => null,
            querySelector: () => null,
            querySelectorAll: () => [],
            createElement: (tag) => ({ tagName: tag, className: '', innerHTML: '', textContent: '', style: {}, classList: { add: () => {}, remove: () => {} }, appendChild: (c) => {}, addEventListener: () => {}, setAttribute: () => {}, getAttribute: () => null }),
            addEventListener: () => {}
        },
        window: { chrome: { webview: { postMessage: () => {} } }, addEventListener: () => {} },
        console: console,
        lucide: { createIcons: () => {} },
        setTimeout: (fn) => { try { fn(); } catch(e) {} },
        clearTimeout: () => {}
    };
    sandbox.global = sandbox;
    vm.runInContext(src, vm.createContext(sandbox));
    return sandbox;
}

describe('populateAssistantDropdown', () => {
    it('stores assistant list on window._assistantList', () => {
        const ctx = loadSettingsModule();
        ctx.window._assistantList = undefined;
        const assistants = [{ id: 'a1', name: 'Violet', base_model: 'gpt-4o' }];
        ctx.populateAssistantDropdown(assistants);
        assert.ok(ctx.window._assistantList);
        assert.strictEqual(ctx.window._assistantList.length, 1);
    });

    it('handles empty list', () => {
        const ctx = loadSettingsModule();
        assert.doesNotThrow(() => ctx.populateAssistantDropdown([]));
    });
});

describe('_providerIconFile', () => {
    it('returns deepseek icon for deepseek models', () => {
        const ctx = loadSettingsModule();
        assert.ok(ctx._providerIconFile('deepseek/deepseek-v4').indexOf('deepseek.ico') >= 0);
    });

    it('returns openai icon for gpt models', () => {
        const ctx = loadSettingsModule();
        assert.ok(ctx._providerIconFile('openai/gpt-4o').indexOf('openai.ico') >= 0);
    });

    it('returns google icon for gemini models', () => {
        const ctx = loadSettingsModule();
        assert.ok(ctx._providerIconFile('google/gemini-2.5-flash').indexOf('google.ico') >= 0);
    });

    it('returns anthropic icon for claude models', () => {
        const ctx = loadSettingsModule();
        assert.ok(ctx._providerIconFile('anthropic/claude-3').indexOf('anthropic.ico') >= 0);
    });

    it('returns openrouter icon for unknown models', () => {
        const ctx = loadSettingsModule();
        assert.ok(ctx._providerIconFile('unknown/model').indexOf('openrouter.ico') >= 0);
    });
});

describe('_updateModelCard', () => {
    it('does not throw when card missing', () => {
        const ctx = loadSettingsModule();
        ctx.window._currentSettings = { model: 'deepseek/deepseek-v4', assistantName: '' };
        assert.doesNotThrow(() => ctx._updateModelCard());
    });
});

describe('_sendAllSettings', () => {
    it('does not throw (debounced)', () => {
        const ctx = loadSettingsModule();
        ctx.window._currentSettings = { model: 'test', systemMessage: '', reasoning: '', temperature: '' };
        assert.doesNotThrow(() => ctx._sendAllSettings());
    });
});

describe('_makeModelClickHandler — clears assistant overrides', () => {
    it('should clear systemMessage, reasoning, and temperature when switching from assistant to model', () => {
        const ctx = loadSettingsModule();
        // Simulate an assistant being active with overrides set
        ctx.window._currentSettings = {
            model: 'deepseek/deepseek-v4-pro',
            systemMessage: 'You are a helpful assistant.',
            reasoning: 'high',
            temperature: '0.7',
            assistantName: 'Violet',
            assistantBaseModel: 'openai/gpt-4o',
            assistantDescription: 'A creative writing assistant'
        };

        // Capture postMessage calls to verify what gets sent
        var postMessageCalls = [];
        ctx.window.chrome.webview.postMessage = function(msg) { postMessageCalls.push(msg); };

        // Create a mock element with parent (needed for classList.remove on siblings)
        var mockParent = {
            querySelectorAll: function() { return []; }
        };
        var mockEl = {
            parentElement: mockParent,
            classList: { add: function() {} }
        };

        // Invoke the click handler
        var handler = ctx._makeModelClickHandler(mockEl, 'google/gemini-2.5-flash');
        handler();

        // Verify _currentSettings was properly cleared
        assert.strictEqual(ctx.window._currentSettings.model, 'google/gemini-2.5-flash');
        assert.strictEqual(ctx.window._currentSettings.assistantName, '');
        assert.strictEqual(ctx.window._currentSettings.assistantBaseModel, '');
        assert.strictEqual(ctx.window._currentSettings.assistantDescription, '');
        assert.strictEqual(ctx.window._currentSettings.systemMessage, '');
        assert.strictEqual(ctx.window._currentSettings.reasoning, '');
        assert.strictEqual(ctx.window._currentSettings.temperature, '');
    });

    it('should clear systemMessage even when switching model-to-model (no assistant was active)', () => {
        const ctx = loadSettingsModule();
        // Simulate model-to-model switch with a custom system message
        ctx.window._currentSettings = {
            model: 'deepseek/deepseek-v4-pro',
            systemMessage: 'Custom system message',
            reasoning: 'medium',
            temperature: '1.2',
            assistantName: '',
            assistantBaseModel: '',
            assistantDescription: ''
        };

        var postMessageCalls = [];
        ctx.window.chrome.webview.postMessage = function(msg) { postMessageCalls.push(msg); };

        var mockParent = {
            querySelectorAll: function() { return []; }
        };
        var mockEl = {
            parentElement: mockParent,
            classList: { add: function() {} }
        };

        var handler = ctx._makeModelClickHandler(mockEl, 'anthropic/claude-3');
        handler();

        // Previous overrides should also be cleared on model-to-model switch
        assert.strictEqual(ctx.window._currentSettings.model, 'anthropic/claude-3');
        assert.strictEqual(ctx.window._currentSettings.systemMessage, '');
        assert.strictEqual(ctx.window._currentSettings.reasoning, '');
        assert.strictEqual(ctx.window._currentSettings.temperature, '');
    });
});
