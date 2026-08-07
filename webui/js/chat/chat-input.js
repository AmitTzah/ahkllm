// ======================================================
// chat-input.js — Send, loading indicator, keyboard, retry
// ======================================================

function onChatSend() {
  var input = document.getElementById('chat-input');
  if (!input) return;

  // If streaming, treat click as "Stop"
  if (isLoading) {
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
  if (enabled && input) input.focus();
}

// Cancel streaming — sends cancel message to AHK
function onStopStreaming() {
  Ipc.postToHost('cancelStream');
}

// Retry an assistant message
function retryLastAssistantMessage(messageId) {
  if (isLoading) return;

  if (messageId) {
    for (var i = 0; i < chatMessages.length; i++) {
      if (chatMessages[i].id === messageId && chatMessages[i].role === 'assistant') {
        chatMessages.splice(i);
        break;
      }
    }
    renderChatMessages(chatMessages);
  } else {
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
