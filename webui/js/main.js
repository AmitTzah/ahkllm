window.chrome.webview.addEventListener('message', handleWebMessage);

// Set Bootstrap theme based on darkMode config
function setTheme(isDark) {
  document.documentElement.setAttribute("data-bs-theme", isDark ? "dark" : "light");
}

// Apply font face to the document body (from user config)
function setFontFace(fontFamily) {
  document.body.style.fontFamily = fontFamily;
}

// Initialize markdown-it with options
var md = window.markdownit({
  html: true,         // Enable HTML tags in source
  linkify: true,      // Autoconvert URL-like text to links
  typographer: true,  // Enable smartypants and other sweet transforms
  highlight: function (str, lang) {
    if (lang && hljs.getLanguage(lang)) {
      try {
        return '<pre class="hljs"><code>' +
          hljs.highlight(str, { language: lang, ignoreIllegals: true }).value +
          '</code></pre>';
      } catch (__) { }
    }
    return '<pre class="hljs"><code>' + md.utils.escapeHtml(str) + '</code></pre>';
  }
})
  .use(window.texmath, {  // Use texmath plugin for mathematical expressions
    engine: window.katex,
    delimiters: 'dollars',
    katexOptions: { macros: { "\\RR": "\\mathbb{R}" } }
  });

// Chat state
var chatMessages = [];
var isChatMode = false;
var isLoading = false;

// Initialize chat mode — called by AHK when a chat-based Response Window opens
function initChatMode(messages) {
  isChatMode = true;
  chatMessages = messages || [];

  // Show chat layout, hide the old content fallback
  document.getElementById('chat-layout').style.display = 'flex';
  document.getElementById('content').style.display = 'none';

  // Hide old action buttons
  var actionButtons = document.getElementById('action-buttons');
  if (actionButtons) actionButtons.style.display = 'none';

  renderChatMessages(chatMessages);

  // Show token usage bar immediately (with empty placeholder state)
  // It will be updated with real data when the LLM responds
  showTokenUsageBar();

  // If the last message is not from "assistant", we're still waiting for the LLM
  // (this happens when the window is shown before the first cURL response arrives)
  if (chatMessages.length > 0 && chatMessages[chatMessages.length - 1].role !== 'assistant') {
    isLoading = true;
    showLoadingIndicator();
  }

  // Save to sessionStorage for reload persistence within the same window session
  sessionStorage.setItem('chatMessages', JSON.stringify(chatMessages));
  sessionStorage.setItem('isChatMode', 'true');
}

// Show token usage bar immediately with an empty placeholder state
function showTokenUsageBar() {
  var bar = document.getElementById('token-usage-bar');
  var content = document.getElementById('token-usage-content');
  if (!bar || !content) return;

  var html = '';
  // First row: placeholder overview
  html += '<div class="tu-row">';
  html += '<span><span class="tu-label">🔢 Token Usage:</span> — / —</span>';
  html += '</div>';
  // Second row: breakdown with dashes
  html += '<div class="tu-row">';
  html += '<span><span class="tu-label">Input:</span> —</span>';
  html += '<span><span class="tu-label">Output:</span> —</span>';
  html += '<span><span class="tu-label">Total:</span> —</span>';
  html += '</div>';

  content.innerHTML = html;
  bar.style.display = 'block';
}

// Append a single message to the chat (used for new responses)
function appendChatMessage(message) {
  chatMessages.push(message);

  // Append just the new bubble instead of re-rendering everything,
  // so ephemeral elements (thinking blocks, streaming bubbles) are preserved.
  var container = document.getElementById('chat-messages');
  var bubble = createMessageBubble(message, chatMessages.length - 1);
  container.appendChild(bubble);
  container.scrollTop = container.scrollHeight;

  // Save to sessionStorage
  sessionStorage.setItem('chatMessages', JSON.stringify(chatMessages));

  // Hide loading indicator if present
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

// Render all chat messages as bubbles
function renderChatMessages(messages) {
  var container = document.getElementById('chat-messages');
  container.innerHTML = '';

  for (var i = 0; i < messages.length; i++) {
    var msg = messages[i];
    var bubble = createMessageBubble(msg, i);
    container.appendChild(bubble);
  }

  // Scroll to bottom
  container.scrollTop = container.scrollHeight;
}

// Create a single message bubble element
function createMessageBubble(msg, index) {
  var div = document.createElement('div');
  div.className = 'chat-message ' + msg.role;
  div.dataset.index = index;

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

  // Content (rendered markdown)
  var contentDiv = document.createElement('div');
  contentDiv.className = 'message-content';
  contentDiv.innerHTML = md.render(msg.content || '');
  div.appendChild(contentDiv);

  // Action buttons (copy + retry for assistant, copy only for user)
  if (msg.role !== 'system') {
    var actions = document.createElement('div');
    actions.className = 'message-actions';

    // Copy button
    var copyBtn = document.createElement('button');
    copyBtn.className = 'copy-msg-btn';
    copyBtn.textContent = '📋 Copy';
    copyBtn.title = 'Copy this message';
    copyBtn.addEventListener('click', function (e) {
      e.stopPropagation();
      copySingleMessage(index);
    });
    actions.appendChild(copyBtn);

    // Retry button (assistant messages only)
    if (msg.role === 'assistant') {
      var retryBtn = document.createElement('button');
      retryBtn.className = 'retry-msg-btn';
      retryBtn.textContent = '🔄 Retry';
      retryBtn.title = 'Retry this response';
      retryBtn.addEventListener('click', function (e) {
        e.stopPropagation();
        retryLastAssistantMessage();
      });
      actions.appendChild(retryBtn);
    }

    div.appendChild(actions);
  }

  return div;
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

  navigator.clipboard.writeText(text).then(function () {
    showCopiedFeedback(index);
  }).catch(function (err) {
    console.error('Failed to copy: ', err);
  });
}

// Copy entire chat to clipboard
function copyEntireChat() {
  var parts = [];
  for (var i = 0; i < chatMessages.length; i++) {
    var msg = chatMessages[i];
    switch (msg.role) {
      case 'user':
        parts.push('You:\n' + msg.content);
        break;
      case 'assistant':
        parts.push((msg.model || 'Assistant') + ':\n' + msg.content);
        break;
      case 'system':
        parts.push('System Prompt:\n' + msg.content);
        break;
    }
  }

  var fullText = parts.join('\n\n---\n\n');

  navigator.clipboard.writeText(fullText).then(function () {
    var btn = document.getElementById('copy-entire-chat-btn');
    var originalText = btn.innerHTML;
    btn.innerHTML = '✅ Copied!';
    btn.disabled = true;
    setTimeout(function () {
      btn.innerHTML = originalText;
      btn.disabled = false;
    }, 2000);
  }).catch(function (err) {
    console.error('Failed to copy chat: ', err);
  });
}

// Show "Copied!" feedback on a message button
function showCopiedFeedback(index) {
  var container = document.getElementById('chat-messages');
  var bubbles = container.querySelectorAll('.chat-message');
  if (bubbles[index]) {
    var copyBtn = bubbles[index].querySelector('.copy-msg-btn');
    if (copyBtn) {
      var originalText = copyBtn.textContent;
      copyBtn.textContent = '✅ Copied!';
      setTimeout(function () {
        copyBtn.textContent = originalText;
      }, 2000);
    }
  }
}

// Send a chat message to AHK
function onChatSend() {
  var input = document.getElementById('chat-input');
  var message = input.value.trim();
  if (!message || isLoading) return;

  input.value = '';
  input.style.height = 'auto';
  isLoading = true;

  // Add user message to chat immediately
  appendChatMessage({ role: 'user', content: message });

  // Show loading indicator
  showLoadingIndicator();

  // Disable send button
  document.getElementById('chat-send-btn').disabled = true;
  document.getElementById('chat-input').disabled = true;

  // Post to AHK via HostObject (WebViewToo uses .Func() suffix)
  window.chrome.webview.hostObjects.ChatSend.Func(message);
}

// Show the loading dots indicator
function showLoadingIndicator() {
  var container = document.getElementById('chat-messages');
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
  if (indicator) {
    indicator.remove();
  }
}

// Enable/disable chat input buttons
function setChatButtonsEnabled(enabled) {
  isLoading = !enabled;
  document.getElementById('chat-send-btn').disabled = !enabled;
  document.getElementById('chat-input').disabled = !enabled;

  if (enabled) {
    document.getElementById('chat-input').focus();
  }
}

// Retry the last assistant message
function retryLastAssistantMessage() {
  if (isLoading) return;

  // Remove last assistant message from local state
  removeLastAssistantMessage();

  // Show loading
  isLoading = true;
  showLoadingIndicator();
  document.getElementById('chat-send-btn').disabled = true;
  document.getElementById('chat-input').disabled = true;

  // Tell AHK to retry via HostObject (WebViewToo uses .Func() suffix)
  window.chrome.webview.hostObjects.RetryAction.Func();
}

// Markdown rendering for non-chat modes (FIM fallback)
function renderMarkdown(content) {
  var contentToRender = content || 'There is no content available.';
  sessionStorage.setItem('preMarkdownText', contentToRender);

  var result = md.render(contentToRender);
  var contentElement = document.getElementById('content');
  contentElement.innerHTML = result;
  contentElement.scrollTo(0, 0);

  // Show the fallback content area if in non-chat mode
  if (!isChatMode) {
    document.getElementById('chat-layout').style.display = 'none';
    document.getElementById('content').style.display = 'block';
  }
}

// Format a number with comma separators
function formatNumber(n) {
  return n.toString().replace(/\B(?=(\d{3})+(?!\d))/g, ",");
}

// Format cost to a reasonable number of decimal places
function formatCost(cost) {
  if (cost === "" || cost === null || cost === undefined) return "";
  var num = Number(cost);
  if (num === 0) return "$0.00";
  // Show up to 6 decimal places, but strip trailing zeros
  var s = num.toFixed(6);
  // Remove trailing zeros after decimal but keep at least 2 decimals
  s = s.replace(/\.?0+$/, "");
  if (s.indexOf(".") === -1) s += ".00";
  // Ensure at least 2 decimal places
  var parts = s.split(".");
  if (parts.length < 2 || parts[1].length < 2) {
    s = num.toFixed(2);
  }
  return "$" + s;
}

// Update the token usage bar at the top of the chat
function updateTokenUsage(data) {
  var bar = document.getElementById('token-usage-bar');
  var content = document.getElementById('token-usage-content');
  if (!bar || !content) return;

  var html = '';

  // First row: Token Usage overview
  html += '<div class="tu-row">';
  html += '<span><span class="tu-label">🔢 Token Usage:</span> ' +
    formatNumber(data.totalTokens) +
    (data.contextWindow ? ' / ' + formatNumber(data.contextWindow) : '') +
    '</span>';
  html += '</div>';

  // Second row: detailed breakdown
  html += '<div class="tu-row">';
  html += '<span><span class="tu-label">Input:</span> ' + formatNumber(data.promptTokens);
  if (data.cachedTokens && data.cachedTokens > 0) {
    html += ' (' + formatNumber(data.cachedTokens) + ' cached)';
  }
  html += '</span>';
  html += '<span><span class="tu-label">Output:</span> ' + formatNumber(data.completionTokens) + '</span>';
  html += '<span><span class="tu-label">Total:</span> ' + formatNumber(data.totalTokens) + '</span>';
  html += '</div>';

  // Third row: cost estimation (only if costs are available)
  if (data.inputCost !== "" || data.outputCost !== "" || data.totalCost !== "") {
    html += '<div class="tu-row tu-cost">';
    html += '<span><span class="tu-label">💲 Cost Est.<sup class="tu-asterisk">*</sup></span>';
    if (data.inputCost !== "") {
      html += ' Input: ' + formatCost(data.inputCost);
    }
    if (data.outputCost !== "") {
      html += '  |  Output: ' + formatCost(data.outputCost);
    }
    if (data.totalCost !== "") {
      html += '  |  Total: ' + formatCost(data.totalCost);
    }
    html += '</span>';
    html += '</div>';
  }

  content.innerHTML = html;
  bar.style.display = 'block';
}

// Main message handler from AHK
function handleWebMessage(event) {
  try {
    var message = event.data;

    // Handle JSON string messages from AHK
    if (typeof message === 'string') {
      try {
        message = JSON.parse(message);
      } catch (e) {
        // If it's not JSON, check if it's a target/data format
        // Some AHK versions send plain strings
      }
    }

    var target = message.target;
    var data = message.data;

    switch (target) {
      case 'setTheme':
        // The AHK code sends data wrapped in an array like [darkMode]
        if (Array.isArray(data)) {
          setTheme(data[0]);
        } else {
          setTheme(data);
        }
        break;

      case 'initChatMode':
        initChatMode(data);
        break;

      case 'appendChatMessage':
        appendChatMessage(data);
        break;

      case 'removeLastAssistantMessage':
        removeLastAssistantMessage();
        break;

      case 'renderMarkdown':
        // For non-chat mode fallback (e.g. FIM)
        renderMarkdown(Array.isArray(data) ? data[0] : data);
        break;

      case 'setFontFace':
        setFontFace(Array.isArray(data) ? data[0] : data);
        break;

      case 'setChatButtonsEnabled':
        setChatButtonsEnabled(data);
        break;

      case 'updateTokenUsage':
        updateTokenUsage(data);
        break;

      case 'streamContent':
      case 'streamReasoning':
      case 'streamDone':
        handleStreamMessage(target, data);
        break;

      default:
        // Try calling as a function name for backward compatibility
        if (typeof window[target] === 'function') {
          if (Array.isArray(data)) {
            window[target](...data);
          } else {
            window[target](data);
          }
        } else {
          console.log('Unknown message target:', target);
        }
    }
  } catch (error) {
    console.error('Error handling incoming message:', error);
  }
}

// Handle Enter key in chat input (Shift+Enter for newline)
function handleChatInputKeydown(e) {
  if (e.key === 'Enter' && !e.shiftKey) {
    e.preventDefault();
    onChatSend();
  }
}

// Auto-resize the chat input as user types
function autoResizeChatInput() {
  var input = document.getElementById('chat-input');
  input.style.height = 'auto';
  input.style.height = Math.min(input.scrollHeight, 200) + 'px';
}

// Attach event listeners when DOM is ready
document.addEventListener('DOMContentLoaded', function () {
  // Chat send button
  var sendBtn = document.getElementById('chat-send-btn');
  if (sendBtn) {
    sendBtn.addEventListener('click', onChatSend);
  }

  // Chat input
  var chatInput = document.getElementById('chat-input');
  if (chatInput) {
    chatInput.addEventListener('keydown', handleChatInputKeydown);
    chatInput.addEventListener('input', autoResizeChatInput);
  }

  // Track user scroll intent for streaming — a single scroll up stops auto-follow
  var chatMessagesEl = document.getElementById('chat-messages');
  if (chatMessagesEl) {
    chatMessagesEl.addEventListener('scroll', function () {
      var distanceFromBottom = chatMessagesEl.scrollHeight - chatMessagesEl.scrollTop - chatMessagesEl.clientHeight;
      if (typeof streamState !== 'undefined') {
        streamState.userScrolledUp = distanceFromBottom > 5;
      }
    });
  }

  // Copy entire chat button
  var copyAllBtn = document.getElementById('copy-entire-chat-btn');
  if (copyAllBtn) {
    copyAllBtn.addEventListener('click', copyEntireChat);
  }

  // Restore chat state from sessionStorage if available
  var storedIsChatMode = sessionStorage.getItem('isChatMode');
  var storedMessages = sessionStorage.getItem('chatMessages');
  if (storedIsChatMode === 'true' && storedMessages) {
    try {
      var messages = JSON.parse(storedMessages);
      if (messages.length > 0) {
        initChatMode(messages);
      }
    } catch (e) {
      console.error('Failed to restore chat state:', e);
    }
  }

  // Restore fallback markdown content
  var storedContent = sessionStorage.getItem('preMarkdownText');
  if (storedContent && !isChatMode) {
    renderMarkdown(storedContent);
  }
});