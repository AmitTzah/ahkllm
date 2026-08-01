// main.test.js — Unit tests for main.js: handleWebMessage routing
const { describe, it } = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

function loadMainModule() {
    const src = fs.readFileSync(path.resolve(__dirname, '..', '..', 'webui', 'js', 'main.js'), 'utf-8');
    let receivedCalls = {};
    const sandbox = {
        document: {
            getElementById: () => null,
            querySelectorAll: () => [],
            addEventListener: () => {},
            createElement: () => ({ style: {}, appendChild: () => {}, querySelector: () => null, querySelectorAll: () => [] }),
            documentElement: { setAttribute: () => {}, getAttribute: () => null }
        },
        window: {
            chrome: { webview: { addEventListener: () => {} } },
            addEventListener: () => {},
            markdownit: function() { return { use: function() { return this; }, render: (c) => '<p>' + c + '</p>' }; },
            texmath: {},
            katex: {},
            hljs: { getLanguage: () => null, highlight: () => ({ value: '' }) },
            _showChat: function() { receivedCalls._showChat = true; },
            _hideSettings: function() { receivedCalls._hideSettings = true; },
            SettingsPanel: { onSettingsReceived: function(data) { receivedCalls.onSettingsReceived = data; } },
        },
        console: console,
        md: { render: (c) => '<p>' + c + '</p>' },
        sessionStorage: { getItem: () => null, setItem: () => {} },
        navigator: { clipboard: { writeText: async () => {} } },
        setTimeout: setTimeout, clearTimeout: clearTimeout,
        // Mock all feature module functions
        setFontFace: function(family) { receivedCalls.setFontFace = family; },
        initChatMode: function(data) { receivedCalls.initChatMode = data; },
        appendChatMessage: function(data) { receivedCalls.appendChatMessage = data; },
        removeLastAssistantMessage: function() { receivedCalls.removeLastAssistantMessage = true; },
        renderMarkdown: function(data) { receivedCalls.renderMarkdown = data; },
        setChatButtonsEnabled: function(data) { receivedCalls.setChatButtonsEnabled = data; },
        updateTokenUsage: function(data) { receivedCalls.updateTokenUsage = data; },
        updateChatView: function(data) { receivedCalls.updateChatView = data; },
        updateChatMessages: function(data) { receivedCalls.updateChatMessages = data; },
        updateBranchInfo: function(data) { receivedCalls.updateBranchInfo = data; },
        renderChatTree: function(data) { receivedCalls.renderChatTree = data; },
        loadThreadList: function(data) { receivedCalls.loadThreadList = data; },
        loadTrashList: function(data) { receivedCalls.loadTrashList = data; },
        loadThread: function(data) { receivedCalls.loadThread = data; },
        threadForked: function(data) { receivedCalls.threadForked = data; },
        populateAssistantDropdown: function(data) { receivedCalls.populateAssistantDropdown = data; },
        populateCurrentSettings: function(data) { receivedCalls.populateCurrentSettings = data; },
        updateDropdownLabel: function(data) { receivedCalls.updateDropdownLabel = data; },
        showError: function(data) { receivedCalls.showError = data; },
        showErrorBanner: function(data) { receivedCalls.showErrorBanner = data; },
        hideLoadingIndicator: function() {},
        renderNavList: function() { receivedCalls.renderNavList = true; },
        copyEntireChat: function() { receivedCalls.copyEntireChat = true; },
        toggleSidebar: function() { receivedCalls.toggleSidebar = true; },
        toggleTreeModal: function() { receivedCalls.toggleTreeModal = true; },
        toggleNavBar: function() { receivedCalls.toggleNavBar = true; },
        newChat: function() { receivedCalls.newChat = true; },
        handleStreamMessage: function(target, data) { receivedCalls.handleStreamMessage = { target, data }; },
        handleChatInputKeydown: function() {},
        autoResizeChatInput: function() {}
    };
    sandbox.global = sandbox;
    sandbox._receivedCalls = receivedCalls;
    vm.runInContext(src, vm.createContext(sandbox));
    return sandbox;
}

describe('handleWebMessage routing', () => {
    it('routes initChatMode', () => {
        const ctx = loadMainModule();
        const testData = [{ id: '1', role: 'user', content: 'hi' }];
        ctx.handleWebMessage({ data: JSON.stringify({ target: 'initChatMode', data: testData }) });
        assert.ok(ctx._receivedCalls.initChatMode !== undefined);
        assert.strictEqual(ctx._receivedCalls.initChatMode[0].id, '1');
        assert.strictEqual(ctx._receivedCalls.renderNavList, true);
        // Verify view switches from settings/dashboard to chat
        assert.strictEqual(ctx._receivedCalls._hideSettings, true);
        assert.strictEqual(ctx._receivedCalls._showChat, true);
    });

    it('routes appendChatMessage', () => {
        const ctx = loadMainModule();
        const msg = { id: '2', role: 'assistant', content: 'hello' };
        ctx.handleWebMessage({ data: JSON.stringify({ target: 'appendChatMessage', data: msg }) });
        assert.ok(ctx._receivedCalls.appendChatMessage !== undefined);
        assert.strictEqual(ctx._receivedCalls.appendChatMessage.id, '2');
    });

    it('routes streamContent', () => {
        const ctx = loadMainModule();
        ctx.handleWebMessage({ data: JSON.stringify({ target: 'streamContent', data: 'token' }) });
        assert.strictEqual(ctx._receivedCalls.handleStreamMessage.target, 'streamContent');
        assert.strictEqual(ctx._receivedCalls.handleStreamMessage.data, 'token');
    });

    it('routes streamDone', () => {
        const ctx = loadMainModule();
        ctx.handleWebMessage({ data: JSON.stringify({ target: 'streamDone', data: { model: 'gpt-4o' } }) });
        assert.strictEqual(ctx._receivedCalls.handleStreamMessage.target, 'streamDone');
    });

    it('routes streamCancelled', () => {
        const ctx = loadMainModule();
        ctx.handleWebMessage({ data: JSON.stringify({ target: 'streamCancelled', data: {} }) });
        assert.strictEqual(ctx._receivedCalls.handleStreamMessage.target, 'streamCancelled');
    });

    it('routes threadList', () => {
        const ctx = loadMainModule();
        const threads = [{ id: 't1', title: 'Chat 1' }];
        ctx.handleWebMessage({ data: JSON.stringify({ target: 'threadList', data: threads }) });
        assert.ok(ctx._receivedCalls.loadThreadList !== undefined);
        assert.strictEqual(ctx._receivedCalls.loadThreadList[0].id, 't1');
    });

    it('routes currentSettings with FULL settings to the settings panel', () => {
        const ctx = loadMainModule();
        const full = { commands: [{ commandName: 'C' }], assistants: [], models: {} };
        ctx.handleWebMessage({ data: JSON.stringify({ target: 'currentSettings', data: full }) });
        assert.ok(ctx._receivedCalls.populateCurrentSettings !== undefined, 'populateCurrentSettings should be called');
        assert.ok(ctx._receivedCalls.onSettingsReceived !== undefined, 'onSettingsReceived should be called for full settings (has commands)');
    });

    it('does NOT wipe the settings panel on chat-sidebar currentSettings (no commands)', () => {
        // Regression: the chat sidebar posts "currentSettings" with a partial
        // payload (model/reasoning/thinkingLevels, NO commands). Routing it into
        // SettingsPanel.onSettingsReceived reloaded every section with empty data
        // and blanked the Commands tab after saving settings.
        const ctx = loadMainModule();
        const chatPayload = { model: 'deepseek/deepseek-v4-flash', reasoning: '', temperature: '0.7', thinkingLevels: ['none', 'low'] };
        ctx.handleWebMessage({ data: JSON.stringify({ target: 'currentSettings', data: chatPayload }) });
        assert.ok(ctx._receivedCalls.populateCurrentSettings !== undefined, 'populateCurrentSettings should still be called for the chat payload');
        assert.strictEqual(ctx._receivedCalls.onSettingsReceived, undefined, 'onSettingsReceived must NOT be called for the chat-sidebar payload');
    });

    it('routes loadThread', () => {
        const ctx = loadMainModule();
        ctx.handleWebMessage({ data: JSON.stringify({ target: 'loadThread', data: 'thread-id-1' }) });
        assert.strictEqual(ctx._receivedCalls.loadThread, 'thread-id-1');
    });

    it('routes showError without throwing', () => {
        const ctx = loadMainModule();
        // showError tries to access #chat-messages which returns null, so it short-circuits
        assert.doesNotThrow(() => ctx.handleWebMessage({ data: JSON.stringify({ target: 'showError', data: { message: 'Oops' } }) }));
    });

    it('handles string message that is JSON', () => {
        const ctx = loadMainModule();
        ctx.handleWebMessage({ data: '{"target":"loadThread","data":"thread-123"}' });
        assert.strictEqual(ctx._receivedCalls.loadThread, 'thread-123');
    });

    it('does not throw for unknown target', () => {
        const ctx = loadMainModule();
        assert.doesNotThrow(() => ctx.handleWebMessage({ data: JSON.stringify({ target: 'unknownTarget', data: {} }) }));
    });
});
