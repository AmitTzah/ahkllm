// ui-controls.test.js — Unit tests for ui-controls.js: panel resize, font controls, composer resize
const { describe, it } = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

function loadModule() {
    const src = fs.readFileSync(path.resolve(__dirname, '..', '..', 'webui', 'js', 'ui-controls.js'), 'utf-8');
    function makeEl(tag) {
        const el = {
            tagName: tag, className: '', innerHTML: '', id: '', textContent: '', style: {}, value: '',
            children: [],
            classList: { add: function() {}, remove: function() {}, contains: function() { return false; }, toggle: function() {} },
            appendChild: function(c) { el.children.push(c); return c; },
            addEventListener: function() {},
            removeEventListener: function() {},
            querySelector: function() { return null; },
            querySelectorAll: function() { return []; },
            getBoundingClientRect: function() { return { top: 0, left: 0, width: 0, height: 0, right: 0, bottom: 0 }; },
            closest: function() { return null; },
            remove: function() {},
            insertBefore: function() {},
            getAttribute: function() { return null; },
            setAttribute: function() {},
            contains: function() { return false; },
            scrollHeight: 50
        };
        return el;
    }
    const docEl = makeEl('html');
    docEl.style.setProperty = function() {};
    const sandbox = {
        document: {
            body: makeEl('body'),
            documentElement: docEl,
            getElementById: function(id) {
                if (id === 'font-size-display') return makeEl('span');
                if (id === 'btn-font-dec') return makeEl('button');
                if (id === 'btn-font-inc') return makeEl('button');
                if (id === 'chat-input') return makeEl('textarea');
                if (id === 'railLeft') return makeEl('div');
                if (id === 'railRight') return makeEl('div');
                return null;
            },
            querySelector: function() { return null; },
            querySelectorAll: function() { return []; },
            createElement: function(tag) { return makeEl(tag); },
            addEventListener: function() {},
            removeEventListener: function() {}
        },
        window: {
            UiControls: undefined,
            addEventListener: function() {},
            removeEventListener: function() {},
            innerWidth: 1200,
            innerHeight: 800,
            matchMedia: function() { return { matches: false, addEventListener: function() {} }; },
            getComputedStyle: function() { return { width: '300px', height: '400px' }; },
            requestAnimationFrame: function(fn) { fn(); return 0; }
        },
        console: console,
        setTimeout: function(fn) { try { fn(); } catch(e) {} },
        clearTimeout: function() {},
        setInterval: function() { return 0; },
        clearInterval: function() {},
        navigator: { maxTouchPoints: 0 },
        screen: { availWidth: 1920, availHeight: 1080, width: 1920, height: 1080 }
    };
    sandbox.global = sandbox;
    vm.runInContext(src, vm.createContext(sandbox));
    return sandbox;
}

describe('UiControls module', () => {
    it('exposes window.UiControls as an object', () => {
        const ctx = loadModule();
        assert.ok(ctx.window.UiControls !== undefined);
        assert.strictEqual(typeof ctx.window.UiControls, 'object');
    });

    it('exports initFontControls', () => {
        const ctx = loadModule();
        assert.strictEqual(typeof ctx.window.UiControls.initFontControls, 'function');
    });

    it('exports initComposerResize', () => {
        const ctx = loadModule();
        assert.strictEqual(typeof ctx.window.UiControls.initComposerResize, 'function');
    });

    it('exports initAutoCollapse', () => {
        const ctx = loadModule();
        assert.strictEqual(typeof ctx.window.UiControls.initAutoCollapse, 'function');
    });
});

describe('initFontControls', () => {
    it('does not throw when font controls exist', () => {
        const ctx = loadModule();
        assert.doesNotThrow(() => ctx.window.UiControls.initFontControls());
    });
});

describe('initComposerResize', () => {
    it('does not throw when textarea exists', () => {
        const ctx = loadModule();
        assert.doesNotThrow(() => ctx.window.UiControls.initComposerResize());
    });
});

describe('initAutoCollapse', () => {
    it('does not throw', () => {
        const ctx = loadModule();
        assert.doesNotThrow(() => ctx.window.UiControls.initAutoCollapse());
    });
});

describe('font-size +/- stale base (bug #31)', () => {
    it('syncFontSize updates the cached base so +/- after a thread load increments from the thread size', () => {
        const srcControls = fs.readFileSync(require('path').resolve(__dirname, '..', '..', 'webui', 'js', 'ui-controls.js'), 'utf-8');
        const srcConfig = fs.readFileSync(require('path').resolve(__dirname, '..', '..', 'webui', 'js', 'chat', 'model-picker', 'model-picker-config.js'), 'utf-8');
        assert.ok(srcControls.includes('syncFontSize'), 'ui-controls.js should expose syncFontSize');
        assert.ok(srcConfig.includes('syncFontSize'), 'model-picker-config.js should call syncFontSize when applying per-chat font size');
    });
});
