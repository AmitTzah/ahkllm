// ======================================================
// chat-input.js — Send, loading indicator, keyboard, retry
// ======================================================

// Bug #169: the messages removed when a retry starts (the retried assistant
// and everything after it). If the retry FAILS, they are restored so the
// original response stays visible instead of being lost until reload.
var _retryRemovedMessages = null;

function onChatSend() {
  var input = document.getElementById('chat-input');
  if (!input) return;

  // If streaming, treat click as "Stop". streamState.active is checked in
  // addition to isLoading so a mismatched composer (bugs #214/#218: input
  // re-enabled / isLoading reset while the first stream is still in flight)
  // can never fire a second send that clobbers the first stream.
  if (isLoading || (typeof streamState !== 'undefined' && streamState.active)) {
    onStopStreaming();
    return;
  }

  var message = input.value.trim();
  var attachments = typeof getAttachmentsForSend === 'function' ? getAttachmentsForSend() : [];

  // Check if any attachment is still loading
  if (typeof attachmentState !== 'undefined') {
    var anyLoading = false;
    for (var a = 0; a < attachmentState.length; a++) {
      if (attachmentState[a].loading) { anyLoading = true; }
    }
    if (anyLoading) {
      showErrorBanner('Please wait — file processing in progress');
      return;
    }
  }

  if (message || attachments.length > 0) {
    // Normal send with typed text and/or attachments
    input.value = '';
    input.style.height = 'auto';
    isLoading = true;
    showLoadingIndicator();
    var sendBtn = document.getElementById('chat-send-btn');
    if (sendBtn) sendBtn.disabled = true;
    input.disabled = true;
    var payload = { message: message || 'Describe the attached content.' };
    if (attachments.length > 0) payload.attachments = attachments;
    Ipc.postToHost('chatSend', payload);
    if (typeof clearAttachments === 'function') clearAttachments();
    return;
  }

  // Bug #77: an empty Send (no text, no attachments) must be a no-op - the
  // old fall-through retried the last assistant/user message, so an
  // accidental click/Enter duplicated a request and burned tokens/cost.
  return;
}

// Show the loading dots indicator
function showLoadingIndicator() {
  var container = document.getElementById('chat-messages');
  if (!container) return;
  var indicator = document.createElement('div');
  indicator.className = 'loading-indicator';
  indicator.id = 'chat-loading';
  indicator.innerHTML = '<span class="dot"></span><span class="dot"></span><span class="dot"></span>';
  container.appendChild(indicator);
  container.scrollTop = container.scrollHeight;
}

// Hide the loading dots indicator
function hideLoadingIndicator() {
  var indicator = document.getElementById('chat-loading');
  if (indicator) indicator.remove();
}

// Enable/disable chat input. During streaming, button shows "Stop" to cancel.
function setChatButtonsEnabled(enabled) {
  isLoading = !enabled;
  var sendBtn = document.getElementById('chat-send-btn');
  var input = document.getElementById('chat-input');
  if (sendBtn) {
    if (enabled) {
      sendBtn.innerHTML = '<i data-lucide="send"></i>';
      sendBtn.disabled = false;
      sendBtn.onclick = onChatSend;
    } else {
      sendBtn.innerHTML = '<i data-lucide="square"></i>';
      sendBtn.disabled = false;
      sendBtn.onclick = onStopStreaming;
    }
    if (typeof lucide !== 'undefined') lucide.createIcons();
  }
  if (input) input.disabled = !enabled;
  if (enabled) {
    // Bug #215: enabling the composer means no request is in flight, so any
    // visible loading dots must clear. This matters when a stream completes
    // (or fails/cancels) while a DIFFERENT thread is visible: onStreamDone is
    // scoped away for the non-current thread and never reaches the indicator
    // through the normal render path, leaving the dots stuck forever.
    hideLoadingIndicator();
    if (input) input.focus();
  }
}

// Cancel streaming — sends cancel message to AHK
function onStopStreaming() {
  Ipc.postToHost('cancelStream');
}

// Retry an assistant message
function retryLastAssistantMessage(messageId) {
  if (isLoading) return;

  _retryRemovedMessages = null;
  if (messageId) {
    for (var i = 0; i < chatMessages.length; i++) {
      if (chatMessages[i].id === messageId && chatMessages[i].role === 'assistant') {
        _retryRemovedMessages = chatMessages.slice(i);
        chatMessages.splice(i);
        break;
      }
    }
    renderChatMessages(chatMessages);
  } else {
    var lastAssistantIdx = -1;
    for (var j = chatMessages.length - 1; j >= 0; j--) {
      if (chatMessages[j].role === 'assistant') { lastAssistantIdx = j; break; }
    }
    if (lastAssistantIdx >= 0) _retryRemovedMessages = chatMessages.slice(lastAssistantIdx);
    removeLastAssistantMessage();
  }

  isLoading = true;
  showLoadingIndicator();
  var sendBtn = document.getElementById('chat-send-btn');
  var input = document.getElementById('chat-input');
  if (sendBtn) sendBtn.disabled = true;
  if (input) input.disabled = true;

  var payload = {};
  if (messageId) payload.messageId = messageId;
  Ipc.postToHost('retry', payload);
}

// Restore the retry-removed messages after a failed retry (called from the
// global showError path). The DB row was never touched - only the UI was
// truncated - so this brings the conversation back exactly as it was.
function restoreRetryMessagesOnError() {
  if (!_retryRemovedMessages || _retryRemovedMessages.length === 0) return;
  var restored = _retryRemovedMessages;
  _retryRemovedMessages = null;
  for (var i = 0; i < restored.length; i++) chatMessages.push(restored[i]);
  renderChatMessages(chatMessages);
}

// Keyboard handlers
function handleChatInputKeydown(e) {
  if (e.key === 'Enter' && !e.shiftKey) {
    e.preventDefault();
    onChatSend();
  }
}

function autoResizeChatInput() {
  var input = document.getElementById('chat-input');
  if (!input) return;
  input.style.height = 'auto';
  input.style.height = Math.min(input.scrollHeight, 200) + 'px';
}
