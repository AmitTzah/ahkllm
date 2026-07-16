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
