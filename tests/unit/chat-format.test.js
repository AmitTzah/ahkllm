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
});
