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
      console.log('[ATTACH-JS] send check: idx=' + a + ' loading=' + attachmentState[a].loading + ' type=' + attachmentState[a].type);
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
    var payload = { action: 'chatSend', message: message || 'Describe the attached content.' };
    if (attachments.length > 0) payload.attachments = attachments;
    console.log('[ATTACH-JS] Sending chatSend: msgLen=' + message.length + ' attCount=' + attachments.length + ' payloadLen=' + JSON.stringify(payload).length);
    window.chrome.webview.postMessage(JSON.stringify(payload));
    if (typeof clearAttachments === 'function') clearAttachments();
    return;
  }

  // No input typed — try to act on existing chat context
  if (chatMessages && chatMessages.length > 0) {
    var lastMsg = chatMessages[chatMessages.length - 1];
    if (lastMsg.role === 'assistant' && lastMsg.id) {
      // Regenerate the last assistant response
      retryLastAssistantMessage(lastMsg.id);
      return;
    }
    if (lastMsg.role === 'user') {
      // Chat ends with user (assistant was deleted) — resend current chat
      // without inserting a duplicate message. Goes through retry which
      // just builds the request from the current path.
      isLoading = true;
      showLoadingIndicator();
      var btn = document.getElementById('chat-send-btn');
      if (btn) btn.disabled = true;
      input.disabled = true;
      window.chrome.webview.postMessage(JSON.stringify({ action: 'retry' }));
      return;
    }
  }
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
      sendBtn.textContent = 'Send';
      sendBtn.disabled = false;
      sendBtn.onclick = onChatSend;
    } else {
      sendBtn.textContent = 'Stop';
      sendBtn.disabled = false;
      sendBtn.onclick = onStopStreaming;
    }
  }
  if (input) input.disabled = !enabled;
  if (enabled && input) input.focus();
}

// Cancel streaming — sends cancel message to AHK
function onStopStreaming() {
  window.chrome.webview.postMessage(JSON.stringify({ action: 'cancelStream' }));
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
    sessionStorage.setItem('chatMessages', JSON.stringify(chatMessages));
  } else {
    removeLastAssistantMessage();
  }

  isLoading = true;
  showLoadingIndicator();
  var sendBtn = document.getElementById('chat-send-btn');
  var input = document.getElementById('chat-input');
  if (sendBtn) sendBtn.disabled = true;
  if (input) input.disabled = true;

  var payload = { action: 'retry' };
  if (messageId) payload.messageId = messageId;
  window.chrome.webview.postMessage(JSON.stringify(payload));
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
