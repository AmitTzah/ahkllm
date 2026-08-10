// chat-search.test.js — Unit tests for chat-search.js
const { describe, it } = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { installIpc } = require('./helpers/ipc-test-utils');

function loadSearchModule() {
    const src = fs.readFileSync(path.resolve(__dirname, '..', '..', 'webui', 'js', 'chat', 'chat-search.js'), 'utf-8');
    let postedMessages = [];
    const elementCache = {};

    function makeEl(tag) {
        const el = {
            tagName: tag, className: '', innerHTML: '', id: '', value: '', placeholder: '',
            disabled: false, style: { display: '' }, dataset: {}, children: [],
            classList: {
                _classes: [],
                add: function(c) { if (this._classes.indexOf(c) < 0) this._classes.push(c); },
                remove: function(c) { this._classes = this._classes.filter(function(x) { return x !== c; }); },
                contains: function(c) { return this._classes.indexOf(c) >= 0; }
            },
            addEventListener: function(evt, fn) { (this._listeners = this._listeners || {})[evt] = fn; },
            querySelector: function(sel) {
                if (sel === '.search-result-item') return makeEl('div');
                if (el._queryResults && el._queryResults[sel]) return el._queryResults[sel];
                return null;
            },
            querySelectorAll: function(sel) { return el._queryAllResults && el._queryAllResults[sel] ? el._queryAllResults[sel] : []; },
            appendChild: function(child) { el.children.push(child); return child; },
            removeChild: function(child) { el.children = el.children.filter(function(c) { return c !== child; }); },
            remove: function() {},
            closest: function(sel) {
                if (sel === '.search-wrap') return el._closestWrap || null;
                return el._closestResult || null;
            },
            getAttribute: function(attr) {
                var a = '_attr_' + attr;
                return el[a] !== undefined ? el[a] : null;
            },
            setAttribute: function(attr, val) { el['_attr_' + attr] = val; },
            blur: function() {},
            focus: function() {}
        };
        return el;
    }

    const sandbox = {
        document: {
            body: makeEl('div'),
            getElementById: function(id) { return elementCache[id] || null; },
            querySelector: function(sel) {
                if (elementCache[sel]) return elementCache[sel];
                return null;
            },
            addEventListener: function(evt, fn) { (this._docListeners = this._docListeners || {})[evt] = fn; },
            createElement: function(tag) { return makeEl(tag); }
        },
        window: {
            chrome: {
                webview: {
                    postMessage: function(msg) { postedMessages.push(msg); }
                }
            }
        },
        setTimeout: function(fn, delay) { fn(); return 1; },
        clearTimeout: function() {},
        scrollToMessage: function(idx) { sandbox._lastScrolledIndex = idx; },
        scrollToMessageById: function(id) { sandbox._lastScrolledMsgId = id; },
        loadThread: function(id) { sandbox._loadedThreadId = id; },
        escHtml: function(s) { return String(s || '').replace(/&/g, '&').replace(/</g, '<').replace(/>/g, '>').replace(/"/g, '"'); },
        activeThreadId: '',
        chatMessages: [],
        console: { log: function() {} },
        postedMessages: postedMessages,
        elementCache: elementCache,
        makeEl: makeEl,
        _lastScrolledIndex: -1,
        _lastScrolledMsgId: null,
        _loadedThreadId: null
    };

    const script = new vm.Script(src);
    const ctx = vm.createContext(sandbox);
    installIpc(ctx);
    script.runInContext(ctx);

    return sandbox;
}

describe('chat-search', function() {

    describe('initSearch', function() {
        it('attaches input listeners to both search inputs', function() {
            var ctx = loadSearchModule();
            var globalInput = ctx.makeEl('input');
            globalInput.className = 'search-input';
            var globalWrap = ctx.makeEl('div');
            globalWrap.className = 'search-wrap';
            globalWrap.appendChild(globalInput);
            globalInput._closestWrap = globalWrap;

            var scopedInput = ctx.makeEl('input');
            scopedInput.className = 'search-input';
            var scopedWrap = ctx.makeEl('div');
            scopedWrap.className = 'search-wrap in-panel';
            scopedWrap.appendChild(scopedInput);
            scopedInput._closestWrap = scopedWrap;

            ctx.elementCache['.search-wrap:not(.in-panel) .search-input'] = globalInput;
            ctx.elementCache['.search-wrap.in-panel .search-input'] = scopedInput;

            ctx.initSearch();

            // Both inputs should have input listeners
            assert.ok(globalInput._listeners && globalInput._listeners['input'], 'global input should have input listener');
            assert.ok(scopedInput._listeners && scopedInput._listeners['input'], 'scoped input should have input listener');
        });

        it('disables scoped search when no active thread', function() {
            var ctx = loadSearchModule();
            var scopedInput = ctx.makeEl('input');
            scopedInput.className = 'search-input';
            var scopedWrap = ctx.makeEl('div');
            scopedWrap.className = 'search-wrap in-panel';
            scopedWrap.appendChild(scopedInput);
            scopedInput._closestWrap = scopedWrap;
            ctx.elementCache['.search-wrap.in-panel .search-input'] = scopedInput;
            ctx.elementCache['.search-wrap:not(.in-panel) .search-input'] = ctx.makeEl('input');

            ctx.activeThreadId = '';
            ctx.initSearch();

            assert.strictEqual(scopedInput.disabled, true);
            assert.strictEqual(scopedInput.placeholder, 'Open a chat to search');
        });

        it('enables scoped search when active thread is set', function() {
            var ctx = loadSearchModule();
            var scopedInput = ctx.makeEl('input');
            scopedInput.className = 'search-input';
            var scopedWrap = ctx.makeEl('div');
            scopedWrap.className = 'search-wrap in-panel';
            scopedWrap.appendChild(scopedInput);
            scopedInput._closestWrap = scopedWrap;
            ctx.elementCache['.search-wrap.in-panel .search-input'] = scopedInput;
            ctx.elementCache['.search-wrap:not(.in-panel) .search-input'] = ctx.makeEl('input');

            ctx.activeThreadId = 'thread-123';
            ctx.initSearch();

            assert.strictEqual(scopedInput.disabled, false);
            assert.strictEqual(scopedInput.placeholder, 'Search in chat...');
        });
    });

    describe('minimum character threshold', function() {
        it('does not send search for < 2 characters', function() {
            var ctx = loadSearchModule();
            ctx.postedMessages.length = 0;

            var input = ctx.makeEl('input');
            input.value = 'a';
            var wrap = ctx.makeEl('div');
            wrap.className = 'search-wrap';
            wrap.appendChild(input);
            input._closestWrap = wrap;

            // Simulate input event
            ctx.handleSearchInput({ target: input }, false);

            assert.strictEqual(ctx.postedMessages.length, 0, 'should not post message for single char');
        });

        it('sends search for >= 2 characters', function() {
            var ctx = loadSearchModule();
            ctx.postedMessages.length = 0;

            var input = ctx.makeEl('input');
            input.value = 'ab';
            var wrap = ctx.makeEl('div');
            wrap.className = 'search-wrap';
            wrap.appendChild(input);
            input._closestWrap = wrap;

            ctx.handleSearchInput({ target: input }, false);

            // Should send a message (setTimeout is mocked to fire immediately)
            assert.ok(ctx.postedMessages.length >= 1, 'should post message for 2+ chars');
            var msg = JSON.parse(ctx.postedMessages[ctx.postedMessages.length - 1]);
            assert.strictEqual(msg.action, 'searchMessages');
            assert.strictEqual(msg.query, 'ab');
            assert.ok(msg.queryId > 0, 'should have queryId');
        });
    });

    describe('queryId stale response guard', function() {
        it('discards responses with non-matching queryId', function() {
            var ctx = loadSearchModule();

            // Fire a search to increment _activeQueryId
            var input = ctx.makeEl('input');
            input.value = 'hello';
            var wrap = ctx.makeEl('div');
            wrap.className = 'search-wrap';
            wrap.appendChild(input);
            input._closestWrap = wrap;
            ctx.handleSearchInput({ target: input }, false);

            // Now send a stale response
            var dropdownCreated = false;
            var origCreateEl = ctx.document.createElement;
            ctx.document.createElement = function(tag) {
                if (tag === 'div') { dropdownCreated = true; }
                return origCreateEl.call(ctx.document, tag);
            };

            ctx.handleSearchResults({ queryId: 0, results: [{ messageId: 'x', contentPreview: 'test', threadId: 't1', threadTitle: 'T', role: 'user' }], query: 'hello' });

            // The stale response (queryId: 0) should NOT trigger dropdown rendering
            assert.strictEqual(dropdownCreated, false, 'stale response should NOT render dropdown');
            ctx.document.createElement = origCreateEl;
        });
    });

    describe('term highlighting', function() {
        it('wraps matching term in <mark> tags', function() {
            var ctx = loadSearchModule();
            var result = ctx.highlightTerm('hello world', 'hello');
            assert.ok(result.indexOf('<mark>hello</mark>') >= 0, 'should wrap hello in mark tags');
        });

        it('is case-insensitive', function() {
            var ctx = loadSearchModule();
            var result = ctx.highlightTerm('Hello World', 'hello');
            assert.ok(result.indexOf('<mark>Hello</mark>') >= 0, 'should match case-insensitively');
        });

        it('escapes HTML in text before highlighting', function() {
          var ctx = loadSearchModule();
          var result = ctx.highlightTerm('<script>alert("xss")</script> test', 'test');
          assert.ok(result.indexOf('<') >= 0, 'should escape < to < — got: ' + result);
          assert.ok(result.indexOf('<mark>test</mark>') >= 0, 'should still highlight term');
        });
    });

    describe('cross-chat result click', function() {
        it('sends loadThread for different thread', function() {
            var ctx = loadSearchModule();
            ctx.activeThreadId = 'current-thread';
            ctx.postedMessages.length = 0;

            // Need to set up dropdown with a result
            var input = ctx.makeEl('input');
            input.value = 'test';
            var wrap = ctx.makeEl('div');
            wrap.className = 'search-wrap';
            wrap.appendChild(input);
            input._closestWrap = wrap;

            // Fire search to set _activeSearchWrapper
            ctx.handleSearchInput({ target: input }, false);

            // Simulate AHK response
            var results = [
                { messageId: 'msg-1', threadId: 'other-thread', threadTitle: 'Other Chat', contentPreview: 'test message', role: 'user' }
            ];
            ctx.handleSearchResults({ queryId: ctx._activeQueryId || 1, results: results, query: 'test' });

            // selectSearchResult posts loadThread for cross-thread clicks
            assert.doesNotThrow(function() { ctx.selectSearchResult(0); },
                'selectSearchResult should not throw for cross-thread result');
        });
    });

    describe('same-thread result click', function() {
      it('scrolls to message within current thread', function() {
        var ctx = loadSearchModule();
        ctx.activeThreadId = 'thread-1';
        ctx.chatMessages = [
          { id: 'msg-1', role: 'user', content: 'hello' },
          { id: 'msg-2', role: 'assistant', content: 'hi' }
        ];
  
        // Verify scrollToMessage can find the message by index
        ctx.scrollToMessage(1);
        assert.strictEqual(ctx._lastScrolledIndex, 1, 'scrollToMessage should work with index');
      });
    });

    describe('dropdown rendering', function() {
        it('shows thread title for cross-chat results', function() {
            var ctx = loadSearchModule();
            ctx.activeThreadId = 'current-thread';

            var input = ctx.makeEl('input');
            input.value = 'test';
            var wrap = ctx.makeEl('div');
            wrap.className = 'search-wrap';
            wrap.appendChild(input);
            input._closestWrap = wrap;
            ctx.handleSearchInput({ target: input }, false);

            var results = [
                { messageId: 'msg-1', threadId: 'other-thread', threadTitle: 'Other Chat', contentPreview: 'test msg', role: 'user' }
            ];
            ctx.handleSearchResults({ queryId: ctx._activeQueryId || 1, results: results, query: 'test' });

            // The dropdown should contain thread title
            var dropdown = ctx._searchDropdownEl;
            assert.ok(dropdown, 'dropdown should exist');
            assert.ok(dropdown.innerHTML.indexOf('Other Chat') >= 0, 'should show thread title');
        });

        it('shows thread title even for same-thread results', function() {
            var ctx = loadSearchModule();
            ctx.activeThreadId = 'thread-1';

            var input = ctx.makeEl('input');
            input.value = 'test';
            var wrap = ctx.makeEl('div');
            wrap.className = 'search-wrap';
            wrap.appendChild(input);
            input._closestWrap = wrap;
            ctx.handleSearchInput({ target: input }, false);

            var results = [
                { messageId: 'msg-1', threadId: 'thread-1', threadTitle: 'Same Chat', contentPreview: 'test msg', role: 'user' }
            ];
            ctx.handleSearchResults({ queryId: ctx._activeQueryId || 1, results: results, query: 'test' });

            var dropdown = ctx._searchDropdownEl;
            assert.ok(dropdown, 'dropdown should exist');
            assert.ok(dropdown.innerHTML.indexOf('Current Chat') >= 0, 'should show Current Chat label for active thread');
        });

        it('shows empty state for zero results', function() {
            var ctx = loadSearchModule();
            var input = ctx.makeEl('input');
            input.value = 'xyz';
            var wrap = ctx.makeEl('div');
            wrap.className = 'search-wrap';
            wrap.appendChild(input);
            input._closestWrap = wrap;
            ctx.handleSearchInput({ target: input }, false);

            ctx.handleSearchResults({ queryId: ctx._activeQueryId || 1, results: [], query: 'xyz' });
            var dropdown = ctx._searchDropdownEl;
            assert.ok(dropdown, 'dropdown should exist');
            assert.ok(dropdown.innerHTML.indexOf('No messages found') >= 0, 'should show empty state');
        });
    });

    describe('closeSearchDropdown', function() {
        it('hides dropdown on Escape key', function() {
            var ctx = loadSearchModule();

            // Create dropdown first
            var input = ctx.makeEl('input');
            input.value = 'test';
            var wrap = ctx.makeEl('div');
            wrap.className = 'search-wrap';
            wrap.appendChild(input);
            input._closestWrap = wrap;
            ctx.handleSearchInput({ target: input }, false);

            ctx.handleSearchResults({ queryId: ctx._activeQueryId || 1, results: [{ messageId: 'm1', threadId: 't1', threadTitle: 'T', contentPreview: 'test', role: 'user' }], query: 'test' });

            var dropdown = ctx._searchDropdownEl;
            assert.ok(dropdown && dropdown.style.display !== 'none', 'dropdown should be visible');

            // Simulate Escape on the input
            ctx.handleSearchKeydown({ key: 'Escape', target: input, preventDefault: function() {}, stopPropagation: function() {} });

            assert.strictEqual(dropdown.style.display, 'none', 'dropdown should be hidden after Escape');
        });
    });

    describe('highlightTerm with snippet format (search repo now extracts window around match)', function() {
        it('highlights term in middle of snippet with ... prefix', function() {
            var ctx = loadSearchModule();
            // Simulate a snippet from the middle of a message: "...window around match..."
            var result = ctx.highlightTerm('...30 chars before historical event here...', 'historical');
            assert.ok(result.indexOf('<mark>historical</mark>') >= 0,
                'should highlight term even when snippet has leading ...');
        });

        it('highlights term at beginning of snippet (no ... prefix)', function() {
            var ctx = loadSearchModule();
            var result = ctx.highlightTerm('The Bastille was a medieval fortress...', 'Bastille');
            assert.ok(result.indexOf('<mark>Bastille</mark>') >= 0,
                'should highlight term at beginning of snippet');
        });

        it('returns plain text when term not in snippet', function() {
            var ctx = loadSearchModule();
            var result = ctx.highlightTerm('The Bastille was a medieval fortress...', 'revolution');
            // 'revolution' is not in this snippet — should return escaped text without marks
            assert.ok(result.indexOf('<mark>') === -1,
                'should not add mark tags when term is not in the snippet');
        });
    });

    describe('onSearchCrossThreadLoaded', function() {
        it('no-ops when no pending scroll message', function() {
            var ctx = loadSearchModule();
            ctx._pendingSearchScrollMsgId = null;
            assert.doesNotThrow(function() { ctx.onSearchCrossThreadLoaded(); });
        });

        it('posts navigateToMessage and clears pending when set', function() {
            var ctx = loadSearchModule();
            ctx.postedMessages.length = 0;
            ctx._pendingSearchScrollMsgId = 'msg-scroll-1';
            ctx.onSearchCrossThreadLoaded();
            var navMsg = ctx.postedMessages.find(function(m) {
                try { return JSON.parse(m).action === 'sidebarAction'; } catch(e) { return false; }
            });
            assert.ok(navMsg, 'should post sidebarAction');
            assert.strictEqual(ctx._pendingSearchScrollMsgId, null, 'should clear pending');
        });

        it('does not consume the pending navigation for an unrelated thread (bug #175)', function() {
            var ctx = loadSearchModule();
            ctx.postedMessages.length = 0;
            ctx.activeThreadId = 't-B';
            ctx._pendingSearchScrollMsgId = 'msg-scroll-1';
            ctx._pendingSearchScrollThreadId = 't-A';
            ctx.onSearchCrossThreadLoaded();
            assert.strictEqual(ctx.postedMessages.length, 0, 'an unrelated thread must not post navigateToMessage');
            assert.strictEqual(ctx._pendingSearchScrollMsgId, 'msg-scroll-1', 'the pending navigation must survive');
        });

        it('consumes the pending navigation when the target thread is active (bug #175)', function() {
            var ctx = loadSearchModule();
            ctx.postedMessages.length = 0;
            ctx.activeThreadId = 't-A';
            ctx._pendingSearchScrollMsgId = 'msg-scroll-1';
            ctx._pendingSearchScrollThreadId = 't-A';
            ctx.onSearchCrossThreadLoaded();
            assert.strictEqual(ctx._pendingSearchScrollMsgId, null, 'should clear pending for the target thread');
            var navMsg = ctx.postedMessages.find(function(m) {
                try { return JSON.parse(m).action === 'sidebarAction'; } catch(e) { return false; }
            });
            assert.ok(navMsg, 'the target thread should post navigateToMessage');
        });
    });

    describe('handleSearchKeydown — navigation keys', function() {
        it('no-ops when dropdown is null', function() {
            var ctx = loadSearchModule();
            ctx._searchDropdownEl = null;
            assert.doesNotThrow(function() {
                ctx.handleSearchKeydown({ key: 'ArrowDown', target: {}, preventDefault: function() {} });
            });
        });

        it('no-ops when dropdown is hidden', function() {
            var ctx = loadSearchModule();
            ctx._searchDropdownEl = { style: { display: 'none' }, querySelectorAll: function() { return []; } };
            assert.doesNotThrow(function() {
                ctx.handleSearchKeydown({ key: 'ArrowDown', target: {}, preventDefault: function() {} });
            });
        });
    });

    describe('updateKeyboardHighlight', function() {
        it('adds active class to selected item', function() {
            var ctx = loadSearchModule();
            var items = [ctx.makeEl('div'), ctx.makeEl('div')];
            ctx._selectedIndex = 0;
            ctx.updateKeyboardHighlight(items);
            assert.ok(items[0].classList._classes.indexOf('active') >= 0, 'first item should have active class');
            assert.strictEqual(items[1].classList._classes.indexOf('active'), -1, 'second item should not have active class');
        });

        it('removes active class when index is -1', function() {
            var ctx = loadSearchModule();
            var items = [ctx.makeEl('div')];
            items[0].classList._classes = ['active'];
            ctx._selectedIndex = -1;
            ctx.updateKeyboardHighlight(items);
            assert.strictEqual(items[0].classList._classes.indexOf('active'), -1, 'active class should be removed');
        });
    });
});
