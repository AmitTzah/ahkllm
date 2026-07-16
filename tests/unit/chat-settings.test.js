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
        lucide: { createIcons: () => {} }
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
