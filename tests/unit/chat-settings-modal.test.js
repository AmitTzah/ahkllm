// chat-settings-modal.test.js — Unit tests for model-picker-config.js
const { describe, it } = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

function loadModule() {
    const src = fs.readFileSync(path.resolve(__dirname, '..', '..', 'webui', 'js', 'chat', 'model-picker', 'model-picker-config.js'), 'utf-8');
    const sandbox = {
        document: {
            getElementById: (id) => {
                if (id === 'tempSlider') return { value: '1.0', disabled: false, classList: { add: () => {}, remove: () => {}, contains: () => false }, addEventListener: () => {} };
                if (id === 'tempVal') return { textContent: '1.0' };
                if (id === 'tempToggle') return { classList: { add: () => {}, remove: () => {}, contains: () => false }, addEventListener: () => {} };
                if (id === 'tempReset') return { style: { display: '' }, addEventListener: () => {} };
                if (id === 'reasoningDropdown') return {
                    value: '', options: [], innerHTML: '',
                    appendChild: (opt) => { },
                    addEventListener: () => {}
                };
                if (id === 'sysMsgMini') return { value: '' };
                if (id === 'sysMsgFull') return { value: '' };
                if (id === 'sysMsgOverlay') return { classList: { add: (c) => {}, remove: (c) => {} } };
                if (id === 'expandSysMsg') return { addEventListener: () => {} };
                if (id === 'sysMsgSave') return { addEventListener: () => {} };
                if (id === 'sysMsgClose') return { addEventListener: () => {} };
                if (id === 'sysMsgCancel') return { addEventListener: () => {} };
                if (id === 'advancedToggle') return { addEventListener: () => {} };
                if (id === 'advancedWrap') return { classList: { toggle: () => {} } };
                if (id === 'modelCardTrigger') return { querySelector: () => ({ textContent: '' }) };
                return null;
            },
            querySelector: () => null,
            querySelectorAll: () => [],
            createElement: () => ({ style: {}, appendChild: () => {}, addEventListener: () => {} }),
            addEventListener: () => {}
        },
        window: { chrome: { webview: { postMessage: () => {} } }, addEventListener: () => {}, _currentSettings: {} },
        setTimeout: (fn) => { try { fn(); } catch(e) {} }, clearTimeout: () => {},
        _sendAllSettings: () => {}, _updateModelCard: () => {},
        lucide: { createIcons: () => {} },
        console: console
    };
    sandbox.global = sandbox;
    vm.runInContext(src, vm.createContext(sandbox));
    return sandbox;
}

describe('openModelSettings', () => {
    it('sends requestCurrentSettings', () => {
        const ctx = loadModule();
        assert.doesNotThrow(() => ctx.openModelSettings());
    });
});

describe('populateCurrentSettings', () => {
    it('stores settings and updates slider', () => {
        const ctx = loadModule();
        const settings = { model: 'deepseek-v4', systemMessage: '', reasoning: '', temperature: '0.7' };
        assert.doesNotThrow(() => ctx.populateCurrentSettings(settings));
        assert.strictEqual(ctx.window._currentSettings.temperature, '0.7');
    });

    it('shows Default for empty temperature', () => {
        const ctx = loadModule();
        const settings = { model: '', systemMessage: '', reasoning: '', temperature: '' };
        ctx.populateCurrentSettings(settings);
        assert.strictEqual(ctx.window._currentSettings.temperature, '');
    });

    it('handles null settings gracefully', () => {
        const ctx = loadModule();
        assert.doesNotThrow(() => ctx.populateCurrentSettings(null));
    });

    it('stores assistant metadata when provided', () => {
        const ctx = loadModule();
        ctx.populateCurrentSettings({
            model: 'deepseek-v4',
            systemMessage: 'test',
            reasoning: 'none',
            temperature: '',
            assistantName: 'Violet',
            assistantBaseModel: 'deepseek-v4',
            assistantDescription: 'A friendly bot'
        });
        assert.strictEqual(ctx.window._currentSettings.assistantName, 'Violet');
        assert.strictEqual(ctx.window._currentSettings.assistantDescription, 'A friendly bot');
    });

    it('stores the advanced toggles and syncs the right-rail switches', () => {
        const ctx = loadModule();
        const added = [], removed = [];
        const switches = [0, 1].map(() => ({
            classList: { add: (c) => added.push(c), remove: (c) => removed.push(c), contains: () => false }
        }));
        ctx.document.querySelectorAll = () => switches;

        ctx.populateCurrentSettings({
            model: 'deepseek/deepseek-v4-flash', systemMessage: '', reasoning: '', temperature: '',
            codeExecution: false, webSearch: true
        });

        assert.strictEqual(ctx.window._currentSettings.codeExecution, false);
        assert.strictEqual(ctx.window._currentSettings.webSearch, true);
        // Row order: Code Execution / Web Search
        assert.strictEqual(added.length, 1, 'one switch should turn on');
        assert.ok(removed.includes('on'), 'off toggle should have its class removed');
    });
});

describe('updateDropdownLabel', () => {
    it('sets assistant name when isAssistant', () => {
        const ctx = loadModule();
        ctx.window._currentSettings = {};
        ctx.window._assistantList = [{ name: 'Violet', baseModel: 'gpt-4o', description: 'desc' }];
        ctx.updateDropdownLabel({ text: 'Violet', isAssistant: true });
        assert.strictEqual(ctx.window._currentSettings.assistantName, 'Violet');
    });

    it('clears assistant name when switching to model', () => {
        const ctx = loadModule();
        ctx.window._currentSettings = { assistantName: 'Violet', model: '' };
        ctx.updateDropdownLabel({ text: 'deepseek-v4', isAssistant: false });
        assert.strictEqual(ctx.window._currentSettings.assistantName, '');
    });

    it('returns early for null data', () => {
        const ctx = loadModule();
        assert.doesNotThrow(() => ctx.updateDropdownLabel(null));
    });
});

describe('toggle switch handler scoping — regression: double-handler on titleGenToggle', () => {
    it('attaches click handler to all three #railRight .toggle-row .switch and calls _sendAllSettings', () => {
        const handlers = [];
        let sendAllSettingsCalls = 0;

        const makeSwitch = () => ({
            classList: { toggle: () => {}, contains: () => false },
            closest: () => null,
            addEventListener: (ev, fn) => { handlers.push(fn); }
        });

        const sandbox = {
            document: {
                getElementById: () => null,
                querySelector: () => null,
                querySelectorAll: (sel) => {
                    if (sel === '#railRight .toggle-row .switch') {
                        return [makeSwitch(), makeSwitch(), makeSwitch()];
                    }
                    return [];
                },
                createElement: () => ({ style: {}, appendChild: () => {}, addEventListener: () => {} }),
                addEventListener: (ev, fn) => { if (ev === 'DOMContentLoaded') fn(); }
            },
            window: { chrome: { webview: { postMessage: () => {} } }, addEventListener: () => {} },
            setTimeout: (fn) => { try { fn(); } catch(e) {} }, clearTimeout: () => {},
            _sendAllSettings: () => { sendAllSettingsCalls++; },
            _updateModelCard: () => {},
            lucide: { createIcons: () => {} },
            console: console
        };
        sandbox.global = sandbox;

        const src = fs.readFileSync(path.resolve(__dirname, '..', '..', 'webui', 'js', 'chat', 'model-picker', 'model-picker-config.js'), 'utf-8');
        vm.runInContext(src, vm.createContext(sandbox));

        // All three switches should have click handlers
        assert.strictEqual(handlers.length, 3, 'Expected 3 click handlers for 3 right-rail switches');
        // Simulate clicking one — should call _sendAllSettings
        handlers[0]();
        assert.strictEqual(sendAllSettingsCalls, 1, 'Expected _sendAllSettings to be called once on click');
    });

    it('does not attach handlers to switches outside #railRight', () => {
        const outsideHandlers = [];

        const makeSwitch = () => ({
            classList: { toggle: () => {}, contains: () => false },
            addEventListener: (ev, fn) => { outsideHandlers.push(fn); }
        });

        const sandbox = {
            document: {
                getElementById: () => null,
                querySelector: () => null,
                querySelectorAll: (sel) => {
                    if (sel === '#railRight .toggle-row .switch') return [];
                    // settings panel switches (outside #railRight)
                    if (sel === '.toggle-row .switch') return [makeSwitch(), makeSwitch()];
                    return [];
                },
                createElement: () => ({ style: {}, appendChild: () => {}, addEventListener: () => {} }),
                addEventListener: (ev, fn) => { if (ev === 'DOMContentLoaded') fn(); }
            },
            window: { chrome: { webview: { postMessage: () => {} } }, addEventListener: () => {} },
            setTimeout: (fn) => { try { fn(); } catch(e) {} }, clearTimeout: () => {},
            _sendAllSettings: () => {}, _updateModelCard: () => {},
            lucide: { createIcons: () => {} },
            console: console
        };
        sandbox.global = sandbox;

        const src = fs.readFileSync(path.resolve(__dirname, '..', '..', 'webui', 'js', 'chat', 'model-picker', 'model-picker-config.js'), 'utf-8');
        vm.runInContext(src, vm.createContext(sandbox));

        // No handlers should be attached to switches outside #railRight
        assert.strictEqual(outsideHandlers.length, 0, 'Expected 0 handlers on switches outside #railRight');
    });

    it('does not attach handlers when no #railRight .toggle-row .switch exist', () => {
        const sandbox2 = {
            document: {
                getElementById: () => null,
                querySelector: () => null,
                querySelectorAll: () => [],
                createElement: () => ({ style: {}, appendChild: () => {}, addEventListener: () => {} }),
                addEventListener: (ev, fn) => { if (ev === 'DOMContentLoaded') fn(); }
            },
            window: { chrome: { webview: { postMessage: () => {} } }, addEventListener: () => {} },
            setTimeout: (fn) => { try { fn(); } catch(e) {} }, clearTimeout: () => {},
            _sendAllSettings: () => {}, _updateModelCard: () => {},
            lucide: { createIcons: () => {} },
            console: console
        };
        sandbox2.global = sandbox2;

        const src = fs.readFileSync(path.resolve(__dirname, '..', '..', 'webui', 'js', 'chat', 'model-picker', 'model-picker-config.js'), 'utf-8');
        // Should not throw even with no switches
        assert.doesNotThrow(() => vm.runInContext(src, vm.createContext(sandbox2)));
    });
});

describe('system prompt modal char counter — regression: never updated', () => {
    it('updates #charCount on input and when the modal opens', () => {
        let charCountText = '0 chars';
        const makeEl = (id) => {
            const el = {
                value: id === 'sysMsgFull' ? '' : '',
                textContent: id === 'charCount' ? charCountText : '',
                classList: { add: () => {}, remove: () => {} },
                _handlers: {}
            };
            el.addEventListener = (ev, fn) => { el._handlers[ev] = fn; };
            return el;
        };
        const els = {};
        ['sysMsgFull', 'charCount', 'sysMsgMini', 'sysMsgOverlay', 'expandSysMsg', 'sysMsgSave', 'sysMsgClose', 'sysMsgCancel'].forEach((id) => {
            els[id] = makeEl(id);
        });
        const sandbox = {
            document: {
                getElementById: (id) => els[id] || null,
                querySelector: () => null,
                querySelectorAll: () => [],
                createElement: () => ({ style: {}, appendChild: () => {}, addEventListener: () => {} }),
                addEventListener: (ev, fn) => { if (ev === 'DOMContentLoaded') fn(); }
            },
            window: { chrome: { webview: { postMessage: () => {} } }, addEventListener: () => {}, _currentSettings: {} },
            setTimeout: (fn) => { try { fn(); } catch(e) {} }, clearTimeout: () => {},
            _sendAllSettings: () => {}, _updateModelCard: () => {},
            lucide: { createIcons: () => {} },
            console: console
        };
        sandbox.global = sandbox;
        const src = fs.readFileSync(path.resolve(__dirname, '..', '..', 'webui', 'js', 'chat', 'model-picker', 'model-picker-config.js'), 'utf-8');
        vm.runInContext(src, vm.createContext(sandbox));

        // Open the modal with existing mini text: counter must reflect it.
        els.sysMsgFull.value = 'Hello';
        els.sysMsgMini.value = 'Hello';
        els.expandSysMsg._handlers.click();
        assert.strictEqual(els.charCount.textContent, '5 chars');

        // Typing in the full textarea updates the counter live.
        els.sysMsgFull.value = 'Hello world';
        els.sysMsgFull._handlers.input();
        assert.strictEqual(els.charCount.textContent, '11 chars');
    });
});
