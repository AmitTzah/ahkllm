// chat-format.test.js — Unit tests for chat-format.js: getMessageText, formatCompact, formatNumber
const { describe, it } = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const ctx = (() => {
    const src = fs.readFileSync(path.resolve(__dirname, '..', '..', 'webui', 'js', 'chat', 'chat-format.js'), 'utf-8');
    const sandbox = {
        document: { getElementById: () => null, querySelectorAll: () => [] },
        navigator: { clipboard: { writeText: async () => {} } },
        console: console,
        setTimeout: setTimeout,
        chatMessages: [],
        Number: Number, String: String,
        formatNumber: undefined, formatCompact: undefined, getMessageText: undefined,
    };
    sandbox.global = sandbox;
    vm.runInContext(src, vm.createContext(sandbox));
    return sandbox;
})();

describe('getMessageText', () => {
    it('formats user message', () => {
        const text = ctx.getMessageText({ role: 'user', content: 'Hello world' });
        assert.ok(text.includes('You:'));
        assert.ok(text.includes('Hello world'));
    });

    it('formats assistant message with model', () => {
        const text = ctx.getMessageText({ role: 'assistant', content: 'Hi!', model: 'gpt-4o' });
        assert.ok(text.includes('gpt-4o'));
        assert.ok(text.includes('Hi!'));
    });

    it('formats assistant message without model as "Assistant"', () => {
        const text = ctx.getMessageText({ role: 'assistant', content: 'Hi!' });
        assert.ok(text.includes('Assistant'));
    });

    it('formats system message', () => {
        const text = ctx.getMessageText({ role: 'system', content: 'You are helpful' });
        assert.ok(text.includes('System Prompt'));
    });

    it('includes PDF attachment extracted text', () => {
        const msg = {
            role: 'user', content: 'Analyze this',
            attachments: [{ attachment_type: 'pdf', original_filename: 'report.pdf', extracted_text: 'PDF content here' }]
        };
        const text = ctx.getMessageText(msg);
        assert.ok(text.includes('[Attached PDF: report.pdf]'));
        assert.ok(text.includes('PDF content here'));
    });

    it('includes DOCX attachment extracted text', () => {
        const msg = {
            role: 'user', content: 'Read',
            attachments: [{ attachment_type: 'docx', original_filename: 'notes.docx', extracted_text: 'Chapter 1' }]
        };
        const text = ctx.getMessageText(msg);
        assert.ok(text.includes('[Attached DOCX: notes.docx]'));
    });

    it('skips __SCANNED_PDF__ extracted text', () => {
        const msg = {
            role: 'user', content: 'x',
            attachments: [{ attachment_type: 'pdf', original_filename: 'scan.pdf', extracted_text: '__SCANNED_PDF__' }]
        };
        const text = ctx.getMessageText(msg);
        assert.ok(!text.includes('__SCANNED_PDF__'));
    });

    it('skips __LIBRARY_UNAVAILABLE__ extracted text', () => {
        const msg = {
            role: 'user', content: 'x',
            attachments: [{ attachment_type: 'pdf', original_filename: 'doc.pdf', extracted_text: '__LIBRARY_UNAVAILABLE__' }]
        };
        const text = ctx.getMessageText(msg);
        assert.ok(!text.includes('__LIBRARY_UNAVAILABLE__'));
    });

    it('skips (no text extracted) placeholder', () => {
        const msg = {
            role: 'user', content: 'x',
            attachments: [{ attachment_type: 'pdf', original_filename: 'empty.pdf', extracted_text: '(no text extracted)' }]
        };
        const text = ctx.getMessageText(msg);
        assert.ok(!text.includes('(no text extracted)'));
    });

    it('handles message with no attachments', () => {
        const text = ctx.getMessageText({ role: 'user', content: 'Hello' });
        assert.ok(text.includes('Hello'));
        assert.ok(!text.includes('[Attached'));
    });

    it('handles empty attachments array', () => {
        const text = ctx.getMessageText({ role: 'user', content: 'Hello', attachments: [] });
        assert.ok(!text.includes('[Attached'));
    });

    it('labels unknown attachment types as "File"', () => {
        const msg = {
            role: 'user', content: 'x',
            attachments: [{ attachment_type: 'image', original_filename: 'photo.jpg', extracted_text: 'binary' }]
        };
        const text = ctx.getMessageText(msg);
        assert.ok(text.includes('[Attached File: photo.jpg]'));
    });
});

describe('formatCompact', () => {
    it('returns string for numbers under 1000', () => {
        assert.strictEqual(ctx.formatCompact(0), '0');
        assert.strictEqual(ctx.formatCompact(500), '500');
        assert.strictEqual(ctx.formatCompact(999), '999');
    });

    it('formats thousands with k', () => {
        assert.strictEqual(ctx.formatCompact(1000), '1k');
        assert.strictEqual(ctx.formatCompact(1500), '1.5k');
        assert.strictEqual(ctx.formatCompact(999999), '1000k');
    });

    it('formats millions with m', () => {
        assert.strictEqual(ctx.formatCompact(1000000), '1m');
        assert.strictEqual(ctx.formatCompact(2500000), '2.5m');
        assert.strictEqual(ctx.formatCompact(10000000), '10m');
    });

    it('strips trailing .0', () => {
        assert.strictEqual(ctx.formatCompact(2000), '2k');
        assert.strictEqual(ctx.formatCompact(3000000), '3m');
    });
});

describe('updateTokenUsage', () => {
    it('no-ops when token-usage-bar is missing', () => {
        assert.doesNotThrow(() => ctx.updateTokenUsage({ activePathTokens: 100, contextWindow: 1000 }));
    });

    it('no-ops when token-usage-content is missing', () => {
        const origGetEl = ctx.document.getElementById;
        ctx.document.getElementById = (id) => id === 'token-usage-bar' ? { style: {} } : null;
        assert.doesNotThrow(() => ctx.updateTokenUsage({ activePathTokens: 0, contextWindow: 0 }));
        ctx.document.getElementById = origGetEl;
    });

    it('tooltip label says Cumulative (bug #66)', () => {
        const src = fs.readFileSync(path.resolve(__dirname, '..', '..', 'webui', 'js', 'chat', 'chat-format.js'), 'utf-8');
        assert.ok(!src.includes('Culminative'), 'tooltip must not contain the misspelling Culminative');
        assert.ok(src.includes('Cumulative Input/output token usage'), 'tooltip should read Cumulative...');
    });
});

describe('showTokenUsageBar', () => {
    it('no-ops when token-usage-bar is missing', () => {
        assert.doesNotThrow(() => ctx.showTokenUsageBar());
    });
});

describe('formatNumber', () => {
    it('adds commas', () => {
        assert.strictEqual(ctx.formatNumber(1000), '1,000');
        assert.strictEqual(ctx.formatNumber(1000000), '1,000,000');
        assert.strictEqual(ctx.formatNumber(123456789), '123,456,789');
    });

    it('handles small numbers without commas', () => {
        assert.strictEqual(ctx.formatNumber(0), '0');
        assert.strictEqual(ctx.formatNumber(42), '42');
        assert.strictEqual(ctx.formatNumber(999), '999');
    });
});

describe('_langToExtension', () => {
    it('maps javascript to js', () => {
        assert.strictEqual(ctx._langToExtension('javascript'), 'js');
        assert.strictEqual(ctx._langToExtension('js'), 'js');
    });

    it('maps python to py', () => {
        assert.strictEqual(ctx._langToExtension('python'), 'py');
        assert.strictEqual(ctx._langToExtension('py'), 'py');
    });

    it('maps typescript to ts', () => {
        assert.strictEqual(ctx._langToExtension('typescript'), 'ts');
        assert.strictEqual(ctx._langToExtension('ts'), 'ts');
    });

    it('maps c++ to cpp', () => {
        assert.strictEqual(ctx._langToExtension('c++'), 'cpp');
        assert.strictEqual(ctx._langToExtension('cpp'), 'cpp');
    });

    it('maps bash/shell to sh', () => {
        assert.strictEqual(ctx._langToExtension('bash'), 'sh');
        assert.strictEqual(ctx._langToExtension('shell'), 'sh');
        assert.strictEqual(ctx._langToExtension('sh'), 'sh');
    });

    it('maps yaml to yml', () => {
        assert.strictEqual(ctx._langToExtension('yaml'), 'yml');
        assert.strictEqual(ctx._langToExtension('yml'), 'yml');
    });

    it('maps markdown to md', () => {
        assert.strictEqual(ctx._langToExtension('markdown'), 'md');
        assert.strictEqual(ctx._langToExtension('md'), 'md');
    });

    it('maps ahk/autohotkey to ahk', () => {
        assert.strictEqual(ctx._langToExtension('ahk'), 'ahk');
        assert.strictEqual(ctx._langToExtension('autohotkey'), 'ahk');
    });

    it('maps powershell to ps1', () => {
        assert.strictEqual(ctx._langToExtension('powershell'), 'ps1');
        assert.strictEqual(ctx._langToExtension('ps1'), 'ps1');
    });

    it('returns txt for unknown languages', () => {
        assert.strictEqual(ctx._langToExtension(''), 'txt');
        assert.strictEqual(ctx._langToExtension('unknownLang'), 'txt');
    });

    it('is case-insensitive', () => {
        assert.strictEqual(ctx._langToExtension('JavaScript'), 'js');
        assert.strictEqual(ctx._langToExtension('PYTHON'), 'py');
        assert.strictEqual(ctx._langToExtension('JaVa'), 'java');
    });

    it('handles leading/trailing whitespace', () => {
        assert.strictEqual(ctx._langToExtension('  python  '), 'py');
    });

    it('maps vb.net to vb', () => {
        assert.strictEqual(ctx._langToExtension('vb.net'), 'vb');
    });

    it('maps f# to fs', () => {
        assert.strictEqual(ctx._langToExtension('f#'), 'fs');
    });

    it('maps haskell to hs', () => {
        assert.strictEqual(ctx._langToExtension('haskell'), 'hs');
    });

    it('maps docker/dockerfile to dockerfile', () => {
        assert.strictEqual(ctx._langToExtension('docker'), 'dockerfile');
        assert.strictEqual(ctx._langToExtension('dockerfile'), 'dockerfile');
    });

    it('maps latex/tex to tex', () => {
        assert.strictEqual(ctx._langToExtension('latex'), 'tex');
        assert.strictEqual(ctx._langToExtension('tex'), 'tex');
    });

    it('strips special characters before lookup', () => {
        assert.strictEqual(ctx._langToExtension('c++'), 'cpp');
        assert.strictEqual(ctx._langToExtension('f#'), 'fs');
    });

    it('throws for non-string input (null/undefined)', () => {
        assert.throws(() => ctx._langToExtension(null));
        assert.throws(() => ctx._langToExtension(undefined));
    });
});

describe('copySingleMessage', () => {
    it('no-ops when message index is out of bounds', () => {
        ctx.chatMessages = [];
        assert.doesNotThrow(() => ctx.copySingleMessage(0));
    });

    it('calls getMessageText and navigator.clipboard.writeText for valid message', async () => {
        let copiedText = null;
        const origWriteText = ctx.navigator.clipboard.writeText;
        ctx.navigator.clipboard.writeText = async (text) => { copiedText = text; };
        ctx.chatMessages = [{ role: 'user', content: 'Hello', id: 'm1' }];
        ctx.copySingleMessage(0);
        // Allow microtask to flush
        await new Promise(r => setTimeout(r, 10));
        assert.ok(copiedText !== null, 'clipboard.writeText should have been called');
        assert.ok(copiedText.includes('Hello'), 'copied text should contain message content');
        ctx.navigator.clipboard.writeText = origWriteText;
    });
});

describe('exportChat', () => {
    function loadExportCtx() {
        const src = fs.readFileSync(path.resolve(__dirname, '..', '..', 'webui', 'js', 'chat', 'chat-format.js'), 'utf-8');
        let downloadedName = null;
        let clicked = false;
        const anchor = {
            set href(v) { this._href = v; },
            get href() { return this._href; },
            set download(v) { downloadedName = v; this._download = v; },
            get download() { return this._download; },
            click() { clicked = true; }
        };
        const body = { appendChild() {}, removeChild() {} };
        const sandbox = {
            document: {
                getElementById: () => null,
                createElement: () => anchor,
                body: body
            },
            navigator: { clipboard: { writeText: async () => {} } },
            console: console,
            setTimeout: setTimeout,
            chatMessages: [
                { role: 'user', content: 'Hello' },
                { role: 'assistant', content: 'Hi there', model: 'gpt-4o' }
            ],
            URL: { createObjectURL: () => 'blob:test', revokeObjectURL: () => {} },
            Blob: function() {},
            _threadMeta: { 't1': { title: 'My Chat' } },
            activeThreadId: 't1',
            lucide: undefined,
            Number: Number, String: String
        };
        sandbox.global = sandbox;
        vm.runInContext(src, vm.createContext(sandbox));
        return { ctx: sandbox, anchor, getDownloadedName: () => downloadedName, wasClicked: () => clicked };
    }

    it('downloads the conversation as a titled .txt file', () => {
        const { ctx, getDownloadedName, wasClicked } = loadExportCtx();
        ctx.exportChat();
        assert.ok(wasClicked(), 'download anchor click should fire');
        assert.strictEqual(getDownloadedName(), 'My_Chat.txt');
    });

    it('falls back to a generic name without a thread title', () => {
        const { ctx, getDownloadedName } = loadExportCtx();
        ctx.activeThreadId = '';
        ctx.exportChat();
        assert.strictEqual(getDownloadedName(), 'chat.txt');
    });
});

describe('copyEntireChat', () => {
    it('joins all messages with separator and writes to clipboard', async () => {
        let copiedText = null;
        const origWriteText = ctx.navigator.clipboard.writeText;
        ctx.navigator.clipboard.writeText = async (text) => { copiedText = text; };
        ctx.chatMessages = [
            { role: 'user', content: 'Q1' },
            { role: 'assistant', content: 'A1', model: 'gpt-4o' }
        ];
        ctx.copyEntireChat();
        await new Promise(r => setTimeout(r, 10));
        assert.ok(copiedText !== null, 'clipboard.writeText should have been called');
        assert.ok(copiedText.includes('---'), 'should have separator between messages');
        assert.ok(copiedText.includes('Q1'), 'should include first message');
        assert.ok(copiedText.includes('A1'), 'should include second message');
        ctx.navigator.clipboard.writeText = origWriteText;
    });

    it('handles empty chatMessages', async () => {
        let copiedText = null;
        const origWriteText = ctx.navigator.clipboard.writeText;
        ctx.navigator.clipboard.writeText = async (text) => { copiedText = text; };
        ctx.chatMessages = [];
        ctx.copyEntireChat();
        await new Promise(r => setTimeout(r, 10));
        assert.strictEqual(copiedText, '');
        ctx.navigator.clipboard.writeText = origWriteText;
    });
});

describe('showCopiedFeedback', () => {
    it('no-ops when chat-messages container is missing', () => {
        const origGetEl = ctx.document.getElementById;
        ctx.document.getElementById = () => null;
        assert.doesNotThrow(() => ctx.showCopiedFeedback(0));
        ctx.document.getElementById = origGetEl;
    });
});

describe('copyCodeBlock', () => {
    it('no-ops when btn has no .code-block-wrapper ancestor', () => {
        const btn = { closest: () => null };
        assert.doesNotThrow(() => ctx.copyCodeBlock(btn));
    });

    it('no-ops when wrapper has no code element', () => {
        const btn = { closest: () => ({ querySelector: () => null }) };
        assert.doesNotThrow(() => ctx.copyCodeBlock(btn));
    });

    it('copies code textContent to clipboard', async () => {
        let copiedText = null;
        const origWriteText = ctx.navigator.clipboard.writeText;
        ctx.navigator.clipboard.writeText = async (text) => { copiedText = text; };
        const codeEl = { textContent: 'console.log("hi");' };
        const btn = {
            innerHTML: '<i data-lucide="copy"></i>',
            classList: { add: () => {}, remove: () => {} },
            closest: (sel) => sel === '.code-block-wrapper' ? { querySelector: (s) => s === 'code' ? codeEl : null } : null
        };
        ctx.copyCodeBlock(btn);
        await new Promise(r => setTimeout(r, 10));
        assert.strictEqual(copiedText, 'console.log("hi");');
        ctx.navigator.clipboard.writeText = origWriteText;
    });
});

describe('downloadCodeBlock', () => {
    it('no-ops when btn has no .code-block-wrapper ancestor', () => {
        const btn = { closest: () => null };
        assert.doesNotThrow(() => ctx.downloadCodeBlock(btn));
    });

    it('no-ops when wrapper has no code element', () => {
        const btn = { closest: () => ({ querySelector: () => null }) };
        assert.doesNotThrow(() => ctx.downloadCodeBlock(btn));
    });
});

describe('updateTokenUsage with data', () => {
    it('populates tokenBar innerHTML with token stats', () => {
        let barHTML = '';
        const bar = {
            get innerHTML() { return barHTML; },
            set innerHTML(v) { barHTML = v; }
        };
        const origGetEl = ctx.document.getElementById;
        ctx.document.getElementById = (id) => id === 'tokenBar' ? bar : null;
        ctx.updateTokenUsage({
            activePathTokens: 5000,
            contextWindow: 128000,
            cumulativeInputTokens: 15000,
            cumulativeOutputTokens: 3000,
            cumulativeCachedTokens: 7000,
            cumulativeCost: 0.05,
            cumulativeInputCost: 0.02,
            cumulativeCachedInputCost: 0.005,
            cumulativeOutputCost: 0.025
        });
        assert.ok(barHTML.includes('5k'), 'should show formatted active path tokens');
        assert.ok(barHTML.includes('128k'), 'should show formatted context window');
        assert.ok(barHTML.includes('15k'), 'should show formatted input tokens');
        assert.ok(barHTML.includes('3k'), 'should show formatted output tokens');
        assert.ok(barHTML.includes('7k'), 'should show formatted cached tokens');
        ctx.document.getElementById = origGetEl;
    });

    it('renders without contextWindow when zero', () => {
        let barHTML = '';
        const bar = {
            get innerHTML() { return barHTML; },
            set innerHTML(v) { barHTML = v; }
        };
        const origGetEl = ctx.document.getElementById;
        ctx.document.getElementById = (id) => id === 'tokenBar' ? bar : null;
        ctx.updateTokenUsage({
            activePathTokens: 100,
            contextWindow: 0,
            cumulativeInputTokens: 200,
            cumulativeOutputTokens: 50,
            cumulativeCachedTokens: 0,
            cumulativeCost: 0,
            cumulativeInputCost: 0,
            cumulativeCachedInputCost: 0,
            cumulativeOutputCost: 0
        });
        // Should NOT include " / " since contextWindow is 0
        assert.ok(barHTML.indexOf(' / ') === -1, 'should not show divider when contextWindow is 0/absent');
        ctx.document.getElementById = origGetEl;
    });
});
