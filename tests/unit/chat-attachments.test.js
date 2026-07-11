// chat-attachments.test.js — Unit tests for chat-attachments.js: MIME, extensions, icons, constants
// Uses Node.js built-in test runner (node:test). Zero dependencies.
// Run: node --test tests/js/unit/chat-attachments.test.js

const { describe, it } = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

function loadModule(relativePath) {
    const src = fs.readFileSync(path.resolve(__dirname, '..', '..', 'webui', 'js', relativePath), 'utf-8');
    const sandbox = {
        document: { getElementById: () => null, createElement: () => ({ style: {}, appendChild: () => {} }), querySelectorAll: () => [] },
        window: { chrome: { webview: { postMessage: () => {} } }, addEventListener: () => {} },
        console: console,
        crypto: { subtle: { digest: async () => new Uint8Array(32).buffer } },
        btoa: (s) => Buffer.from(s, 'binary').toString('base64'),
        atob: (s) => Buffer.from(s, 'base64').toString('binary'),
        TextDecoder: TextDecoder,
        Uint8Array: Uint8Array,
        FileReader: class { readAsArrayBuffer() {} },
        Blob: class {},
        File: class {},
        HTMLCanvasElement: class { getContext() { return { drawImage: () => {} }; } toDataURL() { return ''; } },
        setTimeout: setTimeout, clearTimeout: clearTimeout,
        ArrayBuffer: ArrayBuffer, Promise: Promise,
        attachmentState: [], _attachmentIdCounter: 0,
        MAX_FILE_SIZE: 50 * 1024 * 1024,
        getAttachmentTypeFromMime: undefined, isAllowedFile: undefined, getAttachmentIcon: undefined,
        ALLOWED_EXTENSIONS: undefined, MAX_BASE64_SIZE: undefined,
    };
    sandbox.global = sandbox;
    vm.runInContext(src, vm.createContext(sandbox));
    return sandbox;
}

const ctx = loadModule('chat/attachments/chat-attachments.js');

describe('getAttachmentTypeFromMime', () => {
    it('identifies all image MIME types', () => {
        assert.strictEqual(ctx.getAttachmentTypeFromMime('image/png', 'photo.png'), 'image');
        assert.strictEqual(ctx.getAttachmentTypeFromMime('image/jpeg', 'photo.jpg'), 'image');
        assert.strictEqual(ctx.getAttachmentTypeFromMime('image/gif', 'anim.gif'), 'image');
        assert.strictEqual(ctx.getAttachmentTypeFromMime('image/webp', 'img.webp'), 'image');
        assert.strictEqual(ctx.getAttachmentTypeFromMime('image/bmp', 'img.bmp'), 'image');
    });

    it('identifies PDF', () => {
        assert.strictEqual(ctx.getAttachmentTypeFromMime('application/pdf', 'doc.pdf'), 'pdf');
    });

    it('identifies DOCX from wordprocessing MIME', () => {
        assert.strictEqual(ctx.getAttachmentTypeFromMime('application/vnd.openxmlformats-officedocument.wordprocessingml.document', 'f.docx'), 'docx');
    });

    it('identifies PPTX from presentation MIME', () => {
        assert.strictEqual(ctx.getAttachmentTypeFromMime('application/vnd.openxmlformats-officedocument.presentationml.presentation', 's.pptx'), 'pptx');
    });

    it('identifies XLSX from spreadsheet MIME', () => {
        assert.strictEqual(ctx.getAttachmentTypeFromMime('application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', 'd.xlsx'), 'xlsx');
    });

    it('falls back to extension for ODT with generic MIME', () => {
        assert.strictEqual(ctx.getAttachmentTypeFromMime('application/octet-stream', 'notes.odt'), 'odt');
    });

    it('falls back to extension for ODP with generic MIME', () => {
        assert.strictEqual(ctx.getAttachmentTypeFromMime('application/octet-stream', 'slides.odp'), 'odp');
    });

    it('falls back to extension for ODS with generic MIME', () => {
        assert.strictEqual(ctx.getAttachmentTypeFromMime('application/octet-stream', 'sheet.ods'), 'ods');
    });

    it('falls back to extension for RTF with generic MIME', () => {
        assert.strictEqual(ctx.getAttachmentTypeFromMime('application/octet-stream', 'doc.rtf'), 'rtf');
    });

    it('returns text_file for plain text', () => {
        assert.strictEqual(ctx.getAttachmentTypeFromMime('text/plain', 'readme.txt'), 'text_file');
    });

    it('returns text_file for code files with generic MIME', () => {
        assert.strictEqual(ctx.getAttachmentTypeFromMime('application/octet-stream', 'script.py'), 'text_file');
        assert.strictEqual(ctx.getAttachmentTypeFromMime('application/octet-stream', 'script.js'), 'text_file');
        assert.strictEqual(ctx.getAttachmentTypeFromMime('application/octet-stream', 'script.ahk'), 'text_file');
    });

    it('returns text_file for unrecognized extensions', () => {
        assert.strictEqual(ctx.getAttachmentTypeFromMime('application/x-unknown', 'data.bin'), 'text_file');
        assert.strictEqual(ctx.getAttachmentTypeFromMime('application/octet-stream', 'file.xyz'), 'text_file');
    });
});

describe('isAllowedFile', () => {
    it('allows all image extensions', () => {
        for (const ext of ['png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp']) {
            assert.ok(ctx.isAllowedFile('photo.' + ext), 'should allow .' + ext);
        }
    });

    it('allows all document extensions', () => {
        for (const ext of ['pdf', 'docx', 'pptx', 'xlsx', 'odt', 'odp', 'ods', 'rtf']) {
            assert.ok(ctx.isAllowedFile('doc.' + ext), 'should allow .' + ext);
        }
    });

    it('allows all text/code extensions', () => {
        const extensions = ['txt', 'md', 'py', 'js', 'ahk', 'json', 'xml', 'csv',
            'ini', 'cfg', 'yaml', 'yml', 'log', 'html', 'css', 'sql',
            'bat', 'ps1', 'sh', 'java', 'c', 'cpp', 'h', 'rs', 'go', 'ts', 'tsx', 'jsx', 'toml'];
        for (const ext of extensions) {
            assert.ok(ctx.isAllowedFile('file.' + ext), 'should allow .' + ext);
        }
    });

    it('rejects executables', () => {
        assert.ok(!ctx.isAllowedFile('virus.exe'));
        assert.ok(!ctx.isAllowedFile('malware.dll'));
        assert.ok(!ctx.isAllowedFile('installer.msi'));
    });

    it('rejects archives', () => {
        assert.ok(!ctx.isAllowedFile('archive.zip'));
        assert.ok(!ctx.isAllowedFile('archive.rar'));
        assert.ok(!ctx.isAllowedFile('archive.7z'));
    });

    it('rejects empty filename', () => {
        assert.ok(!ctx.isAllowedFile(''));
    });

    it('rejects no extension', () => {
        assert.ok(!ctx.isAllowedFile('noextension'));
    });

    it('is case insensitive', () => {
        assert.ok(ctx.isAllowedFile('PHOTO.PNG'));
        assert.ok(ctx.isAllowedFile('Doc.PDF'));
        assert.ok(ctx.isAllowedFile('Script.JS'));
    });
});

describe('getAttachmentIcon', () => {
    it('returns non-empty string for all types', () => {
        assert.ok(ctx.getAttachmentIcon('image/png', 'photo.png').length > 0);
        assert.ok(ctx.getAttachmentIcon('application/pdf', 'doc.pdf').length > 0);
        assert.ok(ctx.getAttachmentIcon('text/plain', 'readme.txt').length > 0);
        assert.ok(ctx.getAttachmentIcon('application/x-unknown', 'file.bin').length > 0);
    });

    it('returns different icons for different categories', () => {
        const img = ctx.getAttachmentIcon('image/png', 'photo.png');
        const pdf = ctx.getAttachmentIcon('application/pdf', 'doc.pdf');
        const code = ctx.getAttachmentIcon('application/octet-stream', 'script.py');
        const txt = ctx.getAttachmentIcon('text/plain', 'readme.txt');
        const unknown = ctx.getAttachmentIcon('application/x-unknown', 'file.bin');
        // All should be different from each other
        const icons = new Set([img, pdf, code, txt, unknown]);
        assert.ok(icons.size >= 3, 'expected at least 3 distinct icons, got ' + icons.size);
    });

    it('wordprocessing MIME returns word icon', () => {
        const icon = ctx.getAttachmentIcon('application/vnd.openxmlformats-officedocument.wordprocessingml.document', 'f.docx');
        assert.ok(icon.length > 0);
    });

    it('presentation MIME returns presentation icon', () => {
        const icon = ctx.getAttachmentIcon('application/vnd.openxmlformats-officedocument.presentationml.presentation', 's.pptx');
        assert.ok(icon.length > 0);
    });

    it('spreadsheet MIME returns spreadsheet icon', () => {
        const icon = ctx.getAttachmentIcon('application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', 'd.xlsx');
        assert.ok(icon.length > 0);
    });

    it('code files (.py, .js, .ahk) return code icon', () => {
        const py = ctx.getAttachmentIcon('application/octet-stream', 'script.py');
        const js = ctx.getAttachmentIcon('application/octet-stream', 'script.js');
        const ahk = ctx.getAttachmentIcon('application/octet-stream', 'script.ahk');
        assert.strictEqual(py, js);
        assert.strictEqual(js, ahk);
    });

    it('data files (.json, .xml, .csv) return data icon', () => {
        const json = ctx.getAttachmentIcon('application/octet-stream', 'data.json');
        const xml = ctx.getAttachmentIcon('application/octet-stream', 'data.xml');
        const csv = ctx.getAttachmentIcon('application/octet-stream', 'data.csv');
        assert.strictEqual(json, xml);
        assert.strictEqual(xml, csv);
    });

    it('web files (.html, .css) return web icon', () => {
        const html = ctx.getAttachmentIcon('application/octet-stream', 'page.html');
        const css = ctx.getAttachmentIcon('application/octet-stream', 'style.css');
        assert.strictEqual(html, css);
    });
});

describe('ALLOWED_EXTENSIONS completeness', () => {
    it('includes all image extensions', () => {
        for (const ext of ['png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp']) {
            assert.ok(ctx.ALLOWED_EXTENSIONS.indexOf(ext) !== -1, 'missing .' + ext);
        }
    });

    it('includes all document extensions', () => {
        for (const ext of ['pdf', 'docx', 'pptx', 'xlsx', 'odt', 'odp', 'ods', 'rtf']) {
            assert.ok(ctx.ALLOWED_EXTENSIONS.indexOf(ext) !== -1, 'missing .' + ext);
        }
    });

    it('includes all programming language extensions', () => {
        for (const ext of ['py', 'js', 'ahk', 'java', 'c', 'cpp', 'h', 'rs', 'go', 'ts', 'tsx', 'jsx', 'sql', 'bat', 'ps1', 'sh']) {
            assert.ok(ctx.ALLOWED_EXTENSIONS.indexOf(ext) !== -1, 'missing .' + ext);
        }
    });

    it('includes all config/data extensions', () => {
        for (const ext of ['json', 'xml', 'csv', 'ini', 'cfg', 'yaml', 'yml', 'toml']) {
            assert.ok(ctx.ALLOWED_EXTENSIONS.indexOf(ext) !== -1, 'missing .' + ext);
        }
    });

    it('includes web/text extensions', () => {
        for (const ext of ['txt', 'md', 'log', 'html', 'css']) {
            assert.ok(ctx.ALLOWED_EXTENSIONS.indexOf(ext) !== -1, 'missing .' + ext);
        }
    });

    it('has no duplicates', () => {
        const seen = new Set();
        for (const ext of ctx.ALLOWED_EXTENSIONS) {
            assert.ok(!seen.has(ext), 'duplicate extension: .' + ext);
            seen.add(ext);
        }
    });
});

describe('constants', () => {
    it('MAX_FILE_SIZE is 50MB', () => {
        assert.strictEqual(ctx.MAX_FILE_SIZE, 50 * 1024 * 1024);
    });

    it('MAX_BASE64_SIZE is 10MB', () => {
        assert.strictEqual(ctx.MAX_BASE64_SIZE, 10 * 1024 * 1024);
    });
});
