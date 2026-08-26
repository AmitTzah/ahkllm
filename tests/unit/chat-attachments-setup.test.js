// chat-attachments-setup.test.js — Unit tests for chat-attachments-setup.js
// Regression (bug #217): deleting another message's attachment while editing
// must never be deferred into the edit commit (which hard-deletes the wrong
// attachment row). The delegated X handler may only defer attachments that
// belong to the message being edited; other bubbles are untouched while the
// editor is open and delete immediately when no editor is open.
const { describe, it } = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { installIpc } = require('./helpers/ipc-test-utils');

function loadSetupModule() {
    const src = fs.readFileSync(path.resolve(__dirname, '..', '..', 'webui', 'js', 'chat', 'attachments', 'chat-attachments-setup.js'), 'utf-8');
    let postedMessages = [];
    let clickHandler = null;
    const chatMessagesEl = {
        addEventListener: (evt, fn) => { if (evt === 'click') clickHandler = fn; }
    };
    const sandbox = {
        document: {
            getElementById: (id) => (id === 'chat-messages' ? chatMessagesEl : null),
            createElement: () => ({ style: {}, appendChild: () => {}, addEventListener: () => {} }),
            addEventListener: () => {},
            querySelectorAll: () => [],
        },
        window: { chrome: { webview: { postMessage: (m) => { postedMessages.push(JSON.parse(m)); } } }, addEventListener: () => {} },
        console: console,
        _editingMessageId: null,
        _removedAttachmentIds: [],
        attachmentState: [],
        showErrorBanner: () => {},
        removeAttachment: () => {},
        addAttachment: () => {},
    };
    sandbox.global = sandbox;
    const ctx = vm.createContext(sandbox);
    installIpc(ctx);
    vm.runInContext(src, ctx);
    // The module wires the delegated handler on DOMContentLoaded; invoke it
    // directly since the sandbox's document does not fire lifecycle events.
    sandbox.setupMessageAttachmentDeleteDelegation();
    return { ctx: sandbox, click: (evt) => clickHandler(evt), postedMessages };
}

function deleteBtn(attId, msgId) {
    const btn = {
        getAttribute: (name) => (name === 'data-attachment-id' ? attId : null),
        closest: (sel) => {
            if (sel === '.msg') return { getAttribute: (name) => (name === 'data-msg-id' ? msgId : null) };
            if (sel === '.msg-attachment-image, .msg-attachment-file') return { style: { display: 'block' } };
            return null;
        }
    };
    return { target: { closest: (sel) => (sel === '.msg-attachment-delete' ? btn : null) }, stopPropagation: () => {} };
}

describe('setupMessageAttachmentDeleteDelegation ownership (bug #217)', () => {
    it('does not defer another message\'s attachment while editing (no delete, no defer)', () => {
        const { ctx, click, postedMessages } = loadSetupModule();
        ctx._editingMessageId = 'msg-1';
        click(deleteBtn('att-2', 'msg-2'));
        assert.strictEqual(ctx._removedAttachmentIds.length, 0,
            'another message\'s attachment must not be deferred into this edit');
        assert.strictEqual(postedMessages.length, 0,
            'another message\'s attachment must not be deleted while an editor is open');
    });

    it('defers the edited message\'s own attachment to the edit commit', () => {
        const { ctx, click } = loadSetupModule();
        ctx._editingMessageId = 'msg-1';
        click(deleteBtn('att-1', 'msg-1'));
        assert.deepStrictEqual(ctx._removedAttachmentIds, ['att-1'],
            'the edited message\'s own attachment must still defer to the edit commit');
    });

    it('defers into the owning editor when multiple editors are open (bug #317)', () => {
        const { ctx, click } = loadSetupModule();
        ctx._editStatesByMessageId = {
            'msg-1': { removedAttachmentIds: [] },
            'msg-2': { removedAttachmentIds: [] }
        };
        ctx._editingMessageId = 'msg-2';
        ctx._removedAttachmentIds = ctx._editStatesByMessageId['msg-2'].removedAttachmentIds;
        click(deleteBtn('att-1', 'msg-1'));
        assert.deepStrictEqual(ctx._editStatesByMessageId['msg-1'].removedAttachmentIds, ['att-1']);
        assert.deepStrictEqual(ctx._editStatesByMessageId['msg-2'].removedAttachmentIds, []);
        assert.strictEqual(ctx._removedAttachmentIds, ctx._editStatesByMessageId['msg-1'].removedAttachmentIds,
            'the compatibility mirror follows the editor that received the click');
    });

    it('deletes immediately when no editor is open', () => {
        const { ctx, click, postedMessages } = loadSetupModule();
        ctx._editingMessageId = null;
        click(deleteBtn('att-3', 'msg-3'));
        assert.strictEqual(ctx._removedAttachmentIds.length, 0);
        assert.strictEqual(postedMessages.length, 1);
        assert.strictEqual(postedMessages[0].action, 'deleteAttachment');
        assert.strictEqual(postedMessages[0].id, 'att-3');
    });
});
