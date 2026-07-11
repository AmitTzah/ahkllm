// chat-attachments.test.js — Unit tests for chat-attachments.js utility functions
// Uses Node.js built-in test runner (node:test). Zero dependencies.
// Run: node --test tests/js/unit/

const { describe, it } = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

// Load the chat-attachments.js source in a sandbox with mock browser globals
function loadModule(relativePath) {
    const src = fs.readFileSync(path.resolve(__dirname, '..', '..', '..', 'webui', 'js', relativePath), 'utf-8');
    const sandbox = {
        document: {
            getElementById: () => null,
            createElement: () => ({ style: {}, appendChild: () => {} }),
            querySelectorAll: () => [],
        },
        window: {
            chrome: { webview: { postMessage: () => {} } },
            addEventListener: () => {},
        },
        console: console,
        crypto: {
            subtle: {
                digest: async () => new Uint8Array(32).buffer,
            },
        },
        btoa: (s) => Buffer.from(s, 'binary').toString('base64'),
        atob: (s) => Buffer.from(s, 'base64').toString('binary'),
        TextDecoder: TextDecoder,
        Uint8Array: Uint8Array,
        FileReader: class {
            readAsArrayBuffer() {}
        },
        Blob: class {},
        File: class {},
        HTMLCanvasElement: class {
            getContext() { return { drawImage: () => {} }; }
            toDataURL() { return 'data:image/png;base64,'; }
        },
        setTimeout: setTimeout,
        clearTimeout: clearTimeout,
        ArrayBuffer: ArrayBuffer,
        Promise: Promise,
        // Module-level variables that the scripts expect
        attachmentState: [],
        _attachmentIdCounter: 0,
        MAX_FILE_SIZE: 50 * 1024 * 1024,
        getAttachmentTypeFromMime: undefined,
        isAllowedFile: undefined,
        getAttachmentIcon: undefined,
        ALLOWED_EXTENSIONS: undefined,
    };
    sandbox.global = sandbox;
    const ctx = vm.createContext(sandbox);
    vm.runInContext(src, ctx);
    return ctx;
}

const ctx = loadModule('chat/attachments/chat-attachments.js');

describe('getAttachmentTypeFromMime', () => {
    it('identifies images from MIME type', () => {
        assert.strictEqual(ctx.getAttachmentTypeFromMime('image/png', 'photo.png'), 'image');
        assert.strictEqual(ctx.getAttachmentTypeFromMime('image/jpeg', 'photo.jpg'), 'image');
        assert.strictEqual(ctx.getAttachmentTypeFromMime('image/webp', 'img.webp'), 'image');
    });

    it('identifies PDF from MIME type', () => {
        assert.strictEqual(ctx.getAttachmentTypeFromMime('application/pdf', 'doc.pdf'), 'pdf');
    });

    it('identifies office formats from MIME', () => {
        assert.strictEqual(ctx.getAttachmentTypeFromMime('application/vnd.openxmlformats-officedocument.wordprocessingml.document', 'file.docx'), 'docx');
        assert.strictEqual(ctx.getAttachmentTypeFromMime('application/vnd.openxmlformats-officedocument.presentationml.presentation', 'slides.pptx'), 'pptx');
        assert.strictEqual(ctx.getAttachmentTypeFromMime('application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', 'data.xlsx'), 'xlsx');
    });

    it('falls back to extension for formats with generic MIME', () => {
        assert.strictEqual(ctx.getAttachmentTypeFromMime('application/octet-stream', 'notes.odt'), 'odt');
        assert.strictEqual(ctx.getAttachmentTypeFromMime('application/octet-stream', 'slides.odp'), 'odp');
        assert.strictEqual(ctx.getAttachmentTypeFromMime('application/octet-stream', 'sheet.ods'), 'ods');
        assert.strictEqual(ctx.getAttachmentTypeFromMime('application/octet-stream', 'doc.rtf'), 'rtf');
    });

    it('returns text_file for unknown types', () => {
        assert.strictEqual(ctx.getAttachmentTypeFromMime('text/plain', 'readme.txt'), 'text_file');
        assert.strictEqual(ctx.getAttachmentTypeFromMime('application/octet-stream', 'script.py'), 'text_file');
    });
});

describe('isAllowedFile', () => {
    it('allows common image extensions', () => {
        assert.ok(ctx.isAllowedFile('photo.png'));
        assert.ok(ctx.isAllowedFile('photo.jpg'));
        assert.ok(ctx.isAllowedFile('photo.jpeg'));
        assert.ok(ctx.isAllowedFile('photo.gif'));
        assert.ok(ctx.isAllowedFile('photo.webp'));
        assert.ok(ctx.isAllowedFile('photo.bmp'));
    });

    it('allows document extensions', () => {
        assert.ok(ctx.isAllowedFile('doc.pdf'));
        assert.ok(ctx.isAllowedFile('doc.docx'));
        assert.ok(ctx.isAllowedFile('slides.pptx'));
        assert.ok(ctx.isAllowedFile('data.xlsx'));
        assert.ok(ctx.isAllowedFile('notes.odt'));
        assert.ok(ctx.isAllowedFile('notes.odp'));
        assert.ok(ctx.isAllowedFile('notes.ods'));
        assert.ok(ctx.isAllowedFile('notes.rtf'));
    });

    it('allows text/code extensions', () => {
        assert.ok(ctx.isAllowedFile('readme.txt'));
        assert.ok(ctx.isAllowedFile('readme.md'));
        assert.ok(ctx.isAllowedFile('script.py'));
        assert.ok(ctx.isAllowedFile('script.js'));
        assert.ok(ctx.isAllowedFile('script.ahk'));
        assert.ok(ctx.isAllowedFile('config.json'));
        assert.ok(ctx.isAllowedFile('data.xml'));
        assert.ok(ctx.isAllowedFile('data.csv'));
        assert.ok(ctx.isAllowedFile('config.ini'));
        assert.ok(ctx.isAllowedFile('config.yaml'));
        assert.ok(ctx.isAllowedFile('config.yml'));
        assert.ok(ctx.isAllowedFile('config.toml'));
    });

    it('rejects executables', () => {
        assert.ok(!ctx.isAllowedFile('virus.exe'));
        assert.ok(!ctx.isAllowedFile('script.dll'));
        assert.ok(!ctx.isAllowedFile('installer.msi'));
    });

    it('is case insensitive', () => {
        assert.ok(ctx.isAllowedFile('PHOTO.PNG'));
        assert.ok(ctx.isAllowedFile('Photo.Jpg'));
    });
});

describe('MAX_FILE_SIZE constant', () => {
    it('is 50MB', () => {
        assert.strictEqual(ctx.MAX_FILE_SIZE, 50 * 1024 * 1024);
    });
});
