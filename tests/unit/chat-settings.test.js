// chat-settings.test.js — Unit tests for model-picker.js: populateAssistantDropdown, model card, popover
const { describe, it } = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { installIpc } = require('./helpers/ipc-test-utils');

function loadSettingsModule() {
    const src = fs.readFileSync(path.resolve(__dirname, '..', '..', 'webui', 'js', 'chat', 'model-picker', 'model-picker.js'), 'utf-8');
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
    const ctx = vm.createContext(sandbox);
    installIpc(ctx);
    vm.runInContext(src, ctx);
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

describe('_makeModelClickHandler — keeps reasoning, clears assistant overrides', () => {
    it('keeps reasoning but clears systemMessage/temperature when switching from assistant to model', () => {
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
        assert.strictEqual(ctx.window._currentSettings.reasoning, 'high', 'the selected reasoning level must survive a model change');
        assert.strictEqual(ctx.window._currentSettings.temperature, '');
    });

    it('keeps reasoning when switching model-to-model (no assistant was active)', () => {
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

        // Assistant-owned overrides are still cleared, but the user's
        // reasoning selection is preserved on model-to-model switch.
        assert.strictEqual(ctx.window._currentSettings.model, 'anthropic/claude-3');
        assert.strictEqual(ctx.window._currentSettings.systemMessage, '');
        assert.strictEqual(ctx.window._currentSettings.reasoning, 'medium', 'the selected reasoning level must survive a model-to-model switch');
        assert.strictEqual(ctx.window._currentSettings.temperature, '');
    });
});

describe('_sendAllSettings', () => {
    it('includes the right-rail Web Search flag in the payload (code execution removed)', () => {
        const ctx = loadSettingsModule();
        const posted = [];
        ctx.window.chrome.webview.postMessage = (m) => posted.push(m);
        ctx.window._currentSettings = {
            model: 'deepseek/deepseek-v4-flash', systemMessage: '', reasoning: '', temperature: '',
            webSearch: true
        };
        ctx._sendAllSettings();
        assert.strictEqual(posted.length, 1);
        const payload = JSON.parse(posted[0]);
        assert.strictEqual(payload.action, 'updateModelSettings');
        assert.strictEqual(payload.codeExecution, undefined, 'codeExecution stub was removed');
        assert.strictEqual(payload.webSearch, true);
    });

    it('includes explicit empty override flags in the payload', () => {
        const ctx = loadSettingsModule();
        const posted = [];
        ctx.window.chrome.webview.postMessage = (m) => posted.push(m);
        ctx.window._currentSettings = {
            model: '', systemMessage: '', systemOverrideSet: true, reasoning: '', temperature: '', assistantName: 'Defaults',
            reasoningOverrideSet: true, temperatureOverrideSet: true
        };
        ctx._sendAllSettings();
        const payload = JSON.parse(posted[0]);
        assert.strictEqual(payload.systemOverrideSet, true);
        assert.strictEqual(payload.reasoningOverrideSet, true);
        assert.strictEqual(payload.temperatureOverrideSet, true);
    });

    it('keeps a temperature override of 0 in the payload (bug #193)', () => {
        const ctx = loadSettingsModule();
        const posted = [];
        ctx.window.chrome.webview.postMessage = (m) => posted.push(m);
        ctx.window._currentSettings = {
            model: '', systemMessage: '', reasoning: '', temperature: 0,
            webSearch: false, assistantName: ''
        };
        ctx._sendAllSettings();
        assert.strictEqual(posted.length, 1);
        const payload = JSON.parse(posted[0]);
        assert.strictEqual(payload.action, 'updateModelSettings');
        assert.strictEqual(payload.temperature, 0, 'a numeric 0 temperature must survive the send (0 is falsy in JS)');

        // A truly empty temperature must still serialize as "".
        ctx.window._currentSettings.temperature = '';
        posted.length = 0;
        ctx._sendAllSettings();
        assert.strictEqual(posted.length, 1);
        assert.strictEqual(JSON.parse(posted[0]).temperature, '');
    });
});
