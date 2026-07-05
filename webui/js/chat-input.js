// ======================================================
// chat-input.js — Send, loading indicator, keyboard, retry
// ======================================================

function onChatSend() {
  var input = document.getElementById('chat-input');
  if (!input) return;

  var message = input.value.trim();
  if (!message || isLoading) return;

  input.value = '';
  input.style.height = 'auto';
  isLoading = true;

  showLoadingIndicator();

  var sendBtn = document.getElementById('chat-send-btn');
  if (sendBtn) sendBtn.disabled = true;
  input.disabled = true;

  window.chrome.webview.postMessage(JSON.stringify({ action: 'chatSend', message: message }));
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

// Enable/disable chat input buttons
function setChatButtonsEnabled(enabled) {
  isLoading = !enabled;
  var sendBtn = document.getElementById('chat-send-btn');
  var input = document.getElementById('chat-input');
  if (sendBtn) sendBtn.disabled = !enabled;
  if (input) input.disabled = !enabled;
  if (enabled && input) input.focus();
}

// Retry an assistant message. If messageId is provided, retry that specific
// assistant (removing it and all subsequent messages). Otherwise, retry the
// last assistant (legacy behavior).
function retryLastAssistantMessage(messageId) {
  if (isLoading) return;

  if (messageId) {
    // Find the target assistant and remove it + everything after it
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
