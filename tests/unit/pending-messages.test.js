const { describe, it } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

function loadPendingChat(threadId = 'A') {
  const frames = [], timers = [], posts = [], bubbles = [];
  const input = { value: 'Send this image', style: {}, disabled: false, focus() {} };
  const button = { disabled: false, setAttribute() {} };
  const thumbnail = { cachedImage: true };
  const attachment = { _id: 1, type: 'image', filename: 'cover.png', mimeType: 'image/png', size: 32 * 1024 * 1024, base64: 'fixture-image', loading: false };
  const container = {
    appendChild(bubble) { bubbles.push(bubble); },
    querySelector(selector) { return bubbles.find(b => selector.includes('"' + b.message?.id + '"')) || null; }
  };
  const root = {
    activeThreadId: threadId, chatMessages: threadId ? [{ id: 'anchor', role: 'assistant', content: 'Prior answer' }] : [],
    attachmentState: [attachment], streamState: { active: false }, isLoading: false,
    document: {
      getElementById(id) { return ({ 'chat-input': input, 'chat-send-btn': button, 'chat-messages': container })[id] || null; },
      querySelectorAll(selector) { return selector.includes('attachment-thumb') ? [thumbnail] : []; },
      createElement() { return { style: {}, remove() {} }; }
    },
    console: { info() {}, error() {} }, sessionStorage: { setItem() {}, getItem() {} },
    requestAnimationFrame(callback) { frames.push(callback); }, setTimeout(callback) { timers.push(callback); },
    Ipc: { request(action, payload) { posts.push({ action, payload }); return Promise.resolve(); } },
    getAttachmentsForSend() { return this.attachmentState.slice(); },
    clearAttachments() { root.attachmentState = []; }, renderAttachmentBar() {},
    createMessageBubble(message) {
      return { message, replaceWith(next) { bubbles[bubbles.indexOf(this)] = next; },
        remove() { bubbles.splice(bubbles.indexOf(this), 1); } };
    },
    appendChatMessage(message) {
      root.chatMessages.push(message);
      container.appendChild(root.createMessageBubble(message));
    }
  };
  // Browser globals, including attachmentState, all live on the same window.
  root.getAttachmentsForSend = () => root.attachmentState.slice();
  root.window = root;
  vm.createContext(root);
  for (const file of ['pending-messages.js', 'chat-input.js'])
    vm.runInContext(fs.readFileSync(path.join(__dirname, '../../webui/js/chat', file), 'utf8'), root);
  return { root, input, attachment, thumbnail, posts, bubbles,
    flushPaint() { frames.splice(0).forEach(callback => callback()); timers.splice(0).forEach(callback => callback()); } };
}

describe('Pending chat messages', () => {
  it('renders the text and cached image synchronously, before posting the attachment', () => {
    const ctx = loadPendingChat();
    ctx.root.onChatSend();
    const pending = ctx.root.chatMessages.at(-1);
    assert.equal(pending.content, 'Send this image');
    assert.equal(pending.pending, true);
    assert.equal(pending.attachments[0].previewElement, ctx.thumbnail);
    assert.equal(pending.attachments[0].base64, '');
    assert.equal(ctx.posts.length, 0);
    ctx.flushPaint();
    assert.equal(ctx.posts.length, 1);
    assert.equal(ctx.posts[0].payload.clientMessageId, pending.clientMessageId);
    assert.equal(ctx.posts[0].payload.attachments[0].base64, 'fixture-image');
    assert.equal(ctx.posts[0].payload.threadId, 'A');
  });

  it('replaces the pending bubble with the durable message and preserves its decoded preview', () => {
    const ctx = loadPendingChat();
    ctx.root.onChatSend();
    const id = ctx.root.chatMessages.at(-1).clientMessageId;
    ctx.root.PendingChatMessages.saved({ clientMessageId: id, threadId: 'A', messageId: 'saved' });
    ctx.root.PendingChatMessages.confirm({ clientMessageId: id, threadId: 'A', id: 'saved', role: 'user', content: 'Send this image', attachments: [{ id: 'attachment-saved', base64: 'fixture-image' }] });
    assert.equal(ctx.root.chatMessages.length, 2);
    assert.equal(ctx.root.chatMessages.at(-1).id, 'saved');
    assert.equal(ctx.root.chatMessages.at(-1).pending, undefined);
    assert.equal(ctx.root.chatMessages.at(-1).attachments[0].id, 'attachment-saved');
    assert.equal(ctx.root.chatMessages.at(-1).attachments[0].previewElement, ctx.thumbnail);
  });

  it('binds a fresh chat to its real thread ID without losing the provisional request state', () => {
    const ctx = loadPendingChat('');
    ctx.root.onChatSend();
    const id = ctx.root.chatMessages[0].clientMessageId;
    ctx.root.PendingChatMessages.saved({ clientMessageId: id, threadId: 'created', messageId: 'saved' });
    assert.equal(ctx.root.activeThreadId, 'created');
    assert.equal(ctx.root.isThreadRequestInFlight('created'), true);
    assert.equal(ctx.root.isThreadRequestInFlight(''), false);
  });

  it('keeps confirmations for a background chat out of the visible thread', () => {
    const ctx = loadPendingChat();
    ctx.root.onChatSend();
    const id = ctx.root.chatMessages.at(-1).clientMessageId;
    ctx.root.PendingChatMessages.navigated();
    ctx.root.activeThreadId = 'B';
    ctx.root.chatMessages = [{ id: 'b-message' }];
    ctx.root.PendingChatMessages.saved({ clientMessageId: id, threadId: 'A', messageId: 'saved' });
    ctx.root.PendingChatMessages.confirm({ clientMessageId: id, threadId: 'A', id: 'saved', attachments: [] });
    assert.equal(ctx.root.activeThreadId, 'B');
    assert.deepEqual(ctx.root.chatMessages.map(m => m.id), ['b-message']);
  });

  it('marks a failed save as not sent and restores the text and attachment draft', () => {
    const ctx = loadPendingChat();
    ctx.root.onChatSend();
    const id = ctx.root.chatMessages.at(-1).clientMessageId;
    ctx.root.PendingChatMessages.saveFailed({ clientMessageId: id, threadId: 'A', message: 'Attachment could not be saved.' });
    assert.equal(ctx.root.chatMessages.at(-1).sendState, 'failed');
    assert.equal(ctx.input.value, 'Send this image');
    assert.equal(ctx.root.attachmentState[0], ctx.attachment);
    assert.equal(ctx.root.isThreadRequestInFlight('A'), false);
  });

  it('does not mistake a generation/ack failure after persistence for a failed save', () => {
    const ctx = loadPendingChat();
    ctx.root.onChatSend();
    const id = ctx.root.chatMessages.at(-1).clientMessageId;
    ctx.root.PendingChatMessages.saved({ clientMessageId: id, threadId: 'A', messageId: 'saved' });
    ctx.root.PendingChatMessages.failed(id, 'Generation timed out');
    assert.equal(ctx.root.chatMessages.at(-1).sendState, 'pending');
    assert.equal(ctx.input.value, '');
  });

  it('replaces the failed attempt when the restored draft is retried', () => {
    const ctx = loadPendingChat();
    ctx.root.onChatSend();
    const previous = ctx.root.chatMessages.at(-1).clientMessageId;
    ctx.root.PendingChatMessages.saveFailed({ clientMessageId: previous, threadId: 'A', message: 'Save failed' });
    ctx.root.onChatSend();
    assert.equal(ctx.root.chatMessages.length, 2);
    assert.notEqual(ctx.root.chatMessages.at(-1).clientMessageId, previous);
    assert.equal(ctx.root.chatMessages.at(-1).sendState, 'pending');
  });

  it('posts a queued send to its originating chat before navigation and never posts it twice', () => {
    const ctx = loadPendingChat();
    ctx.root.onChatSend();
    ctx.root.PendingChatMessages.navigated();
    ctx.root.activeThreadId = 'B';
    ctx.root.chatMessages = [{ id: 'b-message' }];
    ctx.flushPaint();
    assert.equal(ctx.posts.length, 1);
    assert.equal(ctx.posts[0].payload.threadId, 'A');
    assert.deepEqual(ctx.root.chatMessages.map(m => m.id), ['b-message']);
    assert.equal(ctx.root.PendingChatMessages.forThread([{ id: 'anchor' }], 'A').at(-1).sendState, 'pending');
  });

  it('does not merge a pending message into a sibling branch or another fresh-chat view', () => {
    const ctx = loadPendingChat();
    ctx.root.onChatSend();
    assert.equal(ctx.root.PendingChatMessages.forThread([{ id: 'sibling' }], 'A').length, 1);
    const fresh = loadPendingChat('');
    fresh.root.onChatSend();
    fresh.root.PendingChatMessages.navigated();
    assert.equal(fresh.root.PendingChatMessages.forThread([], '').length, 0);
  });
});
