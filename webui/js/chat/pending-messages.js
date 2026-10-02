// Local previews exist before attachment persistence; saved IDs replace them.
(function(root) {
  var entries = Object.create(null);
  var navigationEpoch = 0;

  function visible(entry) {
    return entry.threadId ? entry.threadId === String(root.activeThreadId || '')
      : !root.activeThreadId && entry.epoch === navigationEpoch;
  }

  function repaint(entry, replacement) {
    if (!visible(entry)) return;
    var index = root.chatMessages.findIndex(function(message) { return message.id === entry.message.id; });
    if (index < 0) return;
    var container = root.document.getElementById('chat-messages');
    var oldBubble = container && container.querySelector('[data-msg-id="' + entry.message.id + '"]');
    root.chatMessages[index] = replacement;
    if (oldBubble) oldBubble.replaceWith(root.createMessageBubble(replacement, index));
  }

  function begin(id, text, attachments, draftText) {
    var states = typeof root.attachmentState !== 'undefined' ? root.attachmentState.slice() : attachments;
    Object.keys(entries).forEach(function(previousId) {
      var previous = entries[previousId];
      if (!visible(previous) || previous.message.sendState !== 'failed' || previous.draftText !== draftText) return;
      if (previous.attachments.length !== states.length || !states.every(function(state, index) {
        var old = previous.attachments[index];
        return state.filename === old.filename && state.size === old.size && state.contentHash === old.contentHash;
      })) return;
      var container = root.document.getElementById('chat-messages');
      var bubble = container && container.querySelector('[data-msg-id="' + previous.message.id + '"]');
      if (bubble) bubble.remove();
      root.chatMessages = root.chatMessages.filter(function(message) { return message.id !== previous.message.id; });
      delete entries[previousId];
    });
    var previews = root.document.querySelectorAll('#attachment-bar .attachment-thumb');
    var imageIndex = 0;
    var renderedAttachments = attachments.map(function(attachment) {
      var preview = attachment.type === 'image' ? previews[imageIndex++] : null;
      return {
        attachment_type: attachment.type, original_filename: attachment.filename,
        mime_type: attachment.mimeType, file_size: attachment.size,
        extracted_text: attachment.extractedText || '',
        previewElement: preview || null, base64: preview ? '' : attachment.base64
      };
    });
    var message = { id: 'pending-' + id, clientMessageId: id, role: 'user', content: text,
      attachments: renderedAttachments, pending: true, sendState: 'pending' };
    var entry = { id: id, threadId: String(root.activeThreadId || ''), epoch: navigationEpoch,
      message: message, draftText: draftText, attachments: states, savedId: '',
      anchorId: root.chatMessages.length ? root.chatMessages[root.chatMessages.length - 1].id : '' };
    entries[id] = entry;
    root.appendChatMessage(message);
    return entry;
  }

  function bindThread(entry, threadId) {
    var wasVisible = visible(entry);
    entry.threadId = threadId;
    if (wasVisible) {
      root.activeThreadId = threadId;
      root.isChatMode = true;
      if (root.sessionStorage) root.sessionStorage.setItem('isChatMode', 'true');
      if (typeof root._setThreadRequestInFlight === 'function') root._setThreadRequestInFlight(threadId, true);
      if (typeof root.updateTopbarTitle === 'function') root.updateTopbarTitle();
      if (typeof root.renderNavList === 'function') root.renderNavList();
      if (typeof root.showTokenUsageBar === 'function') root.showTokenUsageBar();
    }
  }

  function saved(data) {
    var entry = data && entries[data.clientMessageId];
    if (!entry) return;
    entry.savedId = data.messageId;
    entry.message.saved = true;
    bindThread(entry, data.threadId);
    repaint(entry, entry.message);
  }

  function saveFailed(data) {
    var entry = data && entries[data.clientMessageId];
    if (!entry) return;
    if (!entry.threadId && data.threadId) bindThread(entry, data.threadId);
    failed(entry.id, data.message);
  }

  function confirm(message) {
    var entry = message && entries[message.clientMessageId];
    if (!entry) return false;
    // Keep the existing decoded thumbnail while replacing temporary IDs/actions.
    var displayed = Object.assign({}, message);
    displayed.attachments = (message.attachments || []).map(function(attachment, index) {
      var preview = entry.message.attachments[index];
      return Object.assign({}, attachment, { previewElement: preview && preview.previewElement });
    });
    repaint(entry, displayed);
    delete entries[entry.id];
    return true;
  }

  function failed(id, error) {
    var entry = entries[id];
    if (!entry || entry.savedId || entry.message.sendState === 'failed') return;
    entry.message.sendState = 'failed';
    entry.message.sendError = error || 'Message could not be saved.';
    repaint(entry, entry.message);
    if (typeof root._setThreadRequestInFlight === 'function') root._setThreadRequestInFlight(entry.threadId, false);
    if (visible(entry)) {
      var input = root.document.getElementById('chat-input');
      if (input && !input.value && !(root.attachmentState || []).length) {
        input.value = entry.draftText || '';
        root.attachmentState = entry.attachments;
        if (typeof root.renderAttachmentBar === 'function') root.renderAttachmentBar();
      }
      if (typeof root.syncChatButtonsForActiveThread === 'function') root.syncChatButtonsForActiveThread();
    }
  }

  function post(entry, payload) {
    function dispatch() {
      if (entry.posted || entry.message.sendState !== 'pending') return;
      if (entry.epoch !== navigationEpoch || !visible(entry)) {
        failed(entry.id, 'Chat changed before the message could be sent.');
        return;
      }
      entry.posted = true;
      try {
        root.Ipc.request('chatSend', payload, 60000).catch(function(error) { failed(entry.id, error.message); });
        if (typeof root._latencyMark === 'function') root._latencyMark('web.chatSend.posted');
      } catch (error) { failed(entry.id, error.message); }
    }
    entry.dispatch = dispatch;
    // Paint the already-rendered message before serializing a large IPC payload.
    if (typeof root.requestAnimationFrame === 'function')
      root.requestAnimationFrame(function() { root.setTimeout(dispatch, 0); });
    else dispatch();
  }

  function forThread(messages, threadId) {
    var result = messages.slice();
    Object.keys(entries).forEach(function(id) {
      var entry = entries[id];
      if (entry.threadId !== String(threadId || '')) return;
      if (!entry.threadId && entry.epoch !== navigationEpoch) return;
      if (entry.savedId && result.some(function(message) { return message.id === entry.savedId; }))
        delete entries[id];
      else if ((result.length ? result[result.length - 1].id : '') === entry.anchorId)
        result.push(entry.message);
    });
    return result;
  }

  function flush() {
    Object.keys(entries).forEach(function(id) {
      var entry = entries[id];
      if (!entry.posted && entry.dispatch && visible(entry)) entry.dispatch();
    });
  }

  root.PendingChatMessages = {
    begin: begin, post: post, saved: saved, saveFailed: saveFailed, confirm: confirm, failed: failed,
    forThread: forThread, flush: flush,
    navigated: function() { flush(); navigationEpoch++; }
  };
})(window);
