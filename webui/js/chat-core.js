// ======================================================
// chat-core.js — Core chat state, rendering, and messaging
// ======================================================

// Chat state
var chatMessages = [];
var isChatMode = false;
var isLoading = false;
var activeThreadId = "";

// Initialize chat mode — called by AHK when a thread loads
function initChatMode(messages) {
  isChatMode = true;
  chatMessages = messages || [];

  // Show chat layout, hide the old content fallback
  var chatLayout = document.getElementById('chat-layout');
  if (chatLayout) chatLayout.style.display = 'flex';
  var content = document.getElementById('content');
  if (content) content.style.display = 'none';

  renderChatMessages(chatMessages);
  showTokenUsageBar();
  updateBranchBadges();

  // Only show loading if a request is already in-flight AND last message isn't assistant
  if (isLoading && chatMessages.length > 0 && chatMessages[chatMessages.length - 1].role !== 'assistant') {
    showLoadingIndicator();
  } else {
    isLoading = false;
    hideLoadingIndicator();
  }

  sessionStorage.setItem('chatMessages', JSON.stringify(chatMessages));
}

// Render all chat messages as bubbles
function renderChatMessages(messages) {
  var container = document.getElementById('chat-messages');
  if (!container) return;
  container.innerHTML = '';

  for (var i = 0; i < messages.length; i++) {
    var bubble = createMessageBubble(messages[i], i);
    container.appendChild(bubble);
  }

  container.scrollTop = container.scrollHeight;
}

// Create a single message bubble element
function createMessageBubble(msg, index) {
  var div = document.createElement('div');
  div.className = 'chat-message ' + msg.role;
  div.dataset.index = index;
  if (msg.id) div.dataset.msgId = msg.id;

  // Role label
  var label = document.createElement('div');
  label.className = 'message-label';
  switch (msg.role) {
    case 'user':
      label.textContent = 'You';
      break;
    case 'assistant':
      label.textContent = msg.model || 'Assistant';
      break;
    case 'system':
      label.textContent = 'System Prompt';
      break;
  }
  div.appendChild(label);

  // Reasoning/thinking block (rendered before content if present)
  if (msg.reasoning) {
    var thinkingDetails = document.createElement('details');
    thinkingDetails.className = 'thinking-block';
    thinkingDetails.open = true;  // Expanded by default, matching streaming behavior

    var summary = document.createElement('summary');
    summary.textContent = '🧠 Thought (' + msg.reasoning.length + ' chars)';
    thinkingDetails.appendChild(summary);

    var thinkingContent = document.createElement('div');
    thinkingContent.className = 'thinking-content';
    thinkingContent.textContent = msg.reasoning;
    thinkingDetails.appendChild(thinkingContent);

    div.appendChild(thinkingDetails);
  }

  // Content (rendered markdown)
  var contentDiv = document.createElement('div');
  contentDiv.className = 'message-content';
  contentDiv.innerHTML = md.render(msg.content || '');
  div.appendChild(contentDiv);

  // Branch badge (D3) — placed below content
  if (msg.siblingInfo && msg.siblingInfo.total > 1) {
    var badge = createBranchBadge(msg);
    div.appendChild(badge);
  }

  // Action buttons
  if (msg.role !== 'system') {
    var actions = document.createElement('div');
    actions.className = 'message-actions';

    // Quote button (D5)
    var quoteBtn = document.createElement('button');
    quoteBtn.className = 'quote-msg-btn';
    quoteBtn.textContent = '💬 Quote';
    quoteBtn.title = 'Quote this message';
    quoteBtn.addEventListener('click', function(e) {
      e.stopPropagation();
      quoteMessage(index);
    });
    actions.appendChild(quoteBtn);

    // Copy button
    var copyBtn = document.createElement('button');
    copyBtn.className = 'copy-msg-btn';
    copyBtn.textContent = '📋 Copy';
    copyBtn.title = 'Copy this message';
    copyBtn.addEventListener('click', function(e) {
      e.stopPropagation();
      copySingleMessage(index);
    });
    actions.appendChild(copyBtn);

    // Edit button (D1)
    var editBtn = document.createElement('button');
    editBtn.className = 'edit-msg-btn';
    editBtn.textContent = '✏️ Edit';
    editBtn.title = 'Edit this message';
    editBtn.addEventListener('click', function(e) {
      e.stopPropagation();
      editMessage(index);
    });
    actions.appendChild(editBtn);

    // Delete button (D2)
    var deleteBtn = document.createElement('button');
    deleteBtn.className = 'delete-msg-btn';
    deleteBtn.textContent = '🗑️ Delete';
    deleteBtn.title = 'Delete this message';
    deleteBtn.addEventListener('click', function(e) {
      e.stopPropagation();
      deleteMessage(index);
    });
    actions.appendChild(deleteBtn);

    // Fork button (D7)
    var forkBtn = document.createElement('button');
    forkBtn.className = 'fork-msg-btn';
    forkBtn.textContent = '⑂ Fork';
    forkBtn.title = 'Fork chat from here';
    forkBtn.addEventListener('click', function(e) {
      e.stopPropagation();
      forkChat(index);
    });
    actions.appendChild(forkBtn);

    // Retry button (assistant messages only)
    if (msg.role === 'assistant') {
      var retryBtn = document.createElement('button');
      retryBtn.className = 'retry-msg-btn';
      retryBtn.textContent = '🔄 Retry';
      retryBtn.title = 'Retry this response';
      retryBtn.addEventListener('click', function(e) {
        e.stopPropagation();
        retryLastAssistantMessage();
      });
      actions.appendChild(retryBtn);

      // Feedback buttons (D8)
      if (typeof addFeedbackButtons === 'function') {
        addFeedbackButtons(actions, msg, index);
      }
    }

    div.appendChild(actions);
  }

  return div;
}

// Branch badge (D3)
function createBranchBadge(msg) {
  var badge = document.createElement('div');
  badge.className = 'branch-badge';
  badge.dataset.msgId = msg.id;

  var prevBtn = document.createElement('button');
  prevBtn.className = 'branch-arrow branch-arrow-prev';
  prevBtn.textContent = '◀';
  prevBtn.title = 'Previous branch';
  prevBtn.addEventListener('click', function(e) {
    e.stopPropagation();
    switchBranch(msg.id, -1);
  });

  var label = document.createElement('span');
  label.className = 'branch-label';
  label.textContent = msg.siblingInfo.index + '/' + msg.siblingInfo.total;

  var nextBtn = document.createElement('button');
  nextBtn.className = 'branch-arrow branch-arrow-next';
  nextBtn.textContent = '▶';
  nextBtn.title = 'Next branch';
  nextBtn.addEventListener('click', function(e) {
    e.stopPropagation();
    switchBranch(msg.id, 1);
  });

  badge.appendChild(prevBtn);
  badge.appendChild(label);
  badge.appendChild(nextBtn);
  return badge;
}

// Update branch badges after message changes
function updateBranchBadges() {
  // No-op, badges are embedded during createMessageBubble
}

// Append a single message to the chat
function appendChatMessage(message) {
  chatMessages.push(message);

  var container = document.getElementById('chat-messages');
  if (!container) return;
  var bubble = createMessageBubble(message, chatMessages.length - 1);
  container.appendChild(bubble);
  container.scrollTop = container.scrollHeight;

  sessionStorage.setItem('chatMessages', JSON.stringify(chatMessages));
  hideLoadingIndicator();
}

// Remove the last assistant message (for retry)
function removeLastAssistantMessage() {
  for (var i = chatMessages.length - 1; i >= 0; i--) {
    if (chatMessages[i].role === 'assistant') {
      chatMessages.splice(i, 1);
      break;
    }
  }
  renderChatMessages(chatMessages);
  sessionStorage.setItem('chatMessages', JSON.stringify(chatMessages));
}

// Copy a single message's content to clipboard
function copySingleMessage(index) {
  var msg = chatMessages[index];
  if (!msg) return;

  var text = '';
  switch (msg.role) {
    case 'user': text = 'You:\n' + msg.content; break;
    case 'assistant': text = (msg.model || 'Assistant') + ':\n' + msg.content; break;
    case 'system': text = 'System Prompt:\n' + msg.content; break;
  }

  navigator.clipboard.writeText(text).then(function() {
    showCopiedFeedback(index);
  }).catch(function(err) {
    console.error('Failed to copy: ', err);
  });
}

// Copy entire chat to clipboard
function copyEntireChat() {
  var parts = [];
  for (var i = 0; i < chatMessages.length; i++) {
    var msg = chatMessages[i];
    switch (msg.role) {
      case 'user': parts.push('You:\n' + msg.content); break;
      case 'assistant': parts.push((msg.model || 'Assistant') + ':\n' + msg.content); break;
      case 'system': parts.push('System Prompt:\n' + msg.content); break;
    }
  }

  var fullText = parts.join('\n\n---\n\n');

  navigator.clipboard.writeText(fullText).then(function() {
    var btn = document.getElementById('copy-entire-chat-btn');
    if (!btn) return;
    var originalText = btn.innerHTML;
    btn.innerHTML = '✅ Copied!';
    btn.disabled = true;
    setTimeout(function() {
      btn.innerHTML = originalText;
      btn.disabled = false;
    }, 2000);
  }).catch(function(err) {
    console.error('Failed to copy chat: ', err);
  });
}

// Show "Copied!" feedback on a message button
function showCopiedFeedback(index) {
  var container = document.getElementById('chat-messages');
  if (!container) return;
  var bubbles = container.querySelectorAll('.chat-message');
  if (bubbles[index]) {
    var copyBtn = bubbles[index].querySelector('.copy-msg-btn');
    if (copyBtn) {
      var originalText = copyBtn.textContent;
      copyBtn.textContent = '✅ Copied!';
      setTimeout(function() { copyBtn.textContent = originalText; }, 2000);
    }
  }
}

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

// Retry the last assistant message
function retryLastAssistantMessage() {
  if (isLoading) return;

  removeLastAssistantMessage();
  isLoading = true;
  showLoadingIndicator();
  var sendBtn = document.getElementById('chat-send-btn');
  var input = document.getElementById('chat-input');
  if (sendBtn) sendBtn.disabled = true;
  if (input) input.disabled = true;

  window.chrome.webview.postMessage(JSON.stringify({ action: 'retry' }));
}

// Markdown rendering for non-chat modes (FIM fallback)
function renderMarkdown(content) {
  var contentToRender = content || 'There is no content available.';
  sessionStorage.setItem('preMarkdownText', contentToRender);

  var result = md.render(contentToRender);
  var contentElement = document.getElementById('content');
  if (contentElement) contentElement.innerHTML = result;

  if (!isChatMode) {
    var chatLayout = document.getElementById('chat-layout');
    var contentEl = document.getElementById('content');
    if (chatLayout) chatLayout.style.display = 'none';
    if (contentEl) contentEl.style.display = 'block';
  }
}

// Format helpers
function formatNumber(n) {
  return n.toString().replace(/\B(?=(\d{3})+(?!\d))/g, ",");
}

function formatCost(cost) {
  if (cost === "" || cost === null || cost === undefined) return "";
  var num = Number(cost);
  if (num === 0) return "$0.00";
  var s = num.toFixed(6);
  s = s.replace(/\.?0+$/, "");
  if (s.indexOf(".") === -1) s += ".00";
  var parts = s.split(".");
  if (parts.length < 2 || parts[1].length < 2) s = num.toFixed(2);
  return "$" + s;
}

// Token usage bar
function showTokenUsageBar() {
  var bar = document.getElementById('token-usage-bar');
  var content = document.getElementById('token-usage-content');
  if (!bar || !content) return;

  var html = '<div class="tu-row"><span><span class="tu-label">🔢 Token Usage:</span> — / —</span></div>';
  html += '<div class="tu-row">';
  html += '<span><span class="tu-label">Input:</span> —</span>';
  html += '<span><span class="tu-label">Output:</span> —</span>';
  html += '<span><span class="tu-label">Total:</span> —</span>';
  html += '</div>';
  content.innerHTML = html;
  bar.style.display = 'block';
}

function updateTokenUsage(data) {
  var bar = document.getElementById('token-usage-bar');
  var content = document.getElementById('token-usage-content');
  if (!bar || !content) return;

  var html = '<div class="tu-row">';
  html += '<span><span class="tu-label">🔢 Token Usage:</span> ' +
    formatNumber(data.totalTokens) +
    (data.contextWindow ? ' / ' + formatNumber(data.contextWindow) : '') +
    '</span></div>';

  html += '<div class="tu-row">';
  html += '<span><span class="tu-label">Input:</span> ' + formatNumber(data.promptTokens);
  if (data.cachedTokens && data.cachedTokens > 0)
    html += ' (' + formatNumber(data.cachedTokens) + ' cached)';
  html += '</span>';
  html += '<span><span class="tu-label">Output:</span> ' + formatNumber(data.completionTokens) + '</span>';
  html += '<span><span class="tu-label">Total:</span> ' + formatNumber(data.totalTokens) + '</span>';
  html += '</div>';

  if (data.inputCost !== "" || data.outputCost !== "" || data.totalCost !== "") {
    html += '<div class="tu-row tu-cost">';
    html += '<span><span class="tu-label">💲 Cost Est.<sup class="tu-asterisk">*</sup></span>';
    if (data.inputCost !== "") html += ' Input: ' + formatCost(data.inputCost);
    if (data.outputCost !== "") html += '  |  Output: ' + formatCost(data.outputCost);
    if (data.totalCost !== "") html += '  |  Total: ' + formatCost(data.totalCost);
    html += '</span></div>';
  }

  content.innerHTML = html;
  bar.style.display = 'block';
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