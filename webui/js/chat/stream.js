// Streaming response state
var streamState = {
  active: false,
  bubble: null,
  contentDiv: null,
  thinkingDetails: null,
  thinkingBuffer: '',
  contentBuffer: '',
  modelName: '',
  userScrolledUp: false   // Tracks whether user has manually scrolled up during streaming
};

// Scroll the chat messages container to the bottom,
// but only if the user hasn't manually scrolled up.
// Once the user scrolls up, auto-scroll stops until they scroll back to bottom
// or streaming completes.
function scrollToBottom() {
  if (streamState.userScrolledUp) return;

  var scrollEl = document.getElementById('chat-scroll');
  if (!scrollEl) return;

  scrollEl.scrollTop = scrollEl.scrollHeight;
}

// Start streaming - called automatically when first stream content/reasoning arrives
function startStreaming() {
  streamState.active = true;
  streamState.contentBuffer = '';
  streamState.thinkingBuffer = '';
  streamState.thinkingDetails = null;
  streamState.bubble = null;       // Reset bubble so a fresh one is created each session
  streamState.modelName = '';

  // Remove the loading indicator since we're now showing live content
  hideLoadingIndicator();
}

// Called when streaming content arrives (token by token)
function onStreamContent(text) {
  if (!streamState.active) startStreaming();

  streamState.contentBuffer += text;

  // Find or create the streaming assistant bubble
  if (!streamState.bubble) {
    streamState.bubble = createStreamingBubble();
  }

  // Update the content div with rendered markdown
  var rendered = md.render(streamState.contentBuffer);
  streamState.contentDiv.innerHTML = rendered;
  scrollToBottom();
}

// Called when reasoning/thinking content arrives.
// Accepts either a string (legacy) or {content, collapsed} object.
function onStreamReasoning(data) {
  if (!streamState.active) startStreaming();

  var text = typeof data === 'string' ? data : (data.content || '');
  var collapsed = (typeof data === 'object' && data.collapsed) || false;

  streamState.thinkingBuffer += text;

  // Create the thinking details block if it doesn't exist
  if (!streamState.thinkingDetails) {
    streamState.thinkingDetails = createThinkingBlock(collapsed);
  }

  // Update the thinking content
  var thinkingContent = streamState.thinkingDetails.querySelector('.thinking-content');
  thinkingContent.textContent = streamState.thinkingBuffer;

  // Update the summary label with character count
  var summary = streamState.thinkingDetails.querySelector('summary');
  summary.innerHTML = '<i data-lucide="brain" style="width:16px;height:16px;"></i> Thought Process <span class="thinking-pulse">⏳</span>';
  if (typeof lucide !== 'undefined') lucide.createIcons();

  scrollToBottom();
}

// Persist a streamed message to chatMessages with dedup check.
// Used by both onStreamDone() and cancelStreaming().
function _persistStreamedMessage(content, modelName, dbMsg) {
  var msg = { role: 'assistant', content: content };
  if (modelName) msg.model = modelName;

  // Apply DB fields
  if (dbMsg) {
    if (dbMsg.id) msg.id = dbMsg.id;
    if (dbMsg.siblingInfo) msg.siblingInfo = dbMsg.siblingInfo;
    if (dbMsg.reasoning) msg.reasoning = dbMsg.reasoning;
    if (dbMsg.tokenCount !== undefined) msg.tokenCount = dbMsg.tokenCount;
    if (dbMsg.thinkingTokens !== undefined) msg.thinkingTokens = dbMsg.thinkingTokens;
    if (dbMsg.cachedTokens !== undefined) msg.cachedTokens = dbMsg.cachedTokens;
    if (dbMsg.responseTimeMs !== undefined) msg.responseTimeMs = dbMsg.responseTimeMs;
    if (dbMsg.ttftMs !== undefined) msg.ttftMs = dbMsg.ttftMs;
    if (streamState.bubble && dbMsg.id) {
      streamState.bubble.dataset.msgId = dbMsg.id;
    }
  }

  // Dedup by id (preferred) or content (fallback)
  var found = false;
  if (dbMsg && dbMsg.id) {
    for (var i = chatMessages.length - 1; i >= 0; i--) {
      if (chatMessages[i].id === dbMsg.id) { found = true; break; }
    }
  } else {
    for (var i = chatMessages.length - 1; i >= 0; i--) {
      if (chatMessages[i].role === 'assistant' && chatMessages[i].content === content) {
        found = true; break;
      }
    }
  }
  if (!found) {
    chatMessages.push(msg);
    sessionStorage.setItem('chatMessages', JSON.stringify(chatMessages));
  }
}

// Called when streaming is complete
function onStreamDone(data) {
  var modelName = typeof data === 'string' ? data : (data && data.model ? data.model : '');
  var dbMsg = (data && data.dbMsg) ? data.dbMsg : null;

  streamState.userScrolledUp = false;
  var container = document.getElementById('chat-messages');
  if (container) container.scrollTop = container.scrollHeight;
  streamState.modelName = modelName;

  _finalizeStreamBubble(modelName, dbMsg);
  _finalizeThinkingBlock();
  _finalizeStreamContent();

  if (streamState.contentBuffer) {
    _persistStreamedMessage(streamState.contentBuffer, modelName, dbMsg);
    if (streamState.bubble) addStreamingActions(streamState.bubble, chatMessages.length - 1);
  }

  _updateUserTokenCount(data);

  setChatButtonsEnabled(true);
  streamState.active = false;

  // Refresh thread map (right panel nav)
  if (typeof renderNavList === 'function') renderNavList();
}

function _finalizeStreamBubble(modelName, dbMsg) {
  if (!streamState.bubble) return;
  var author = streamState.bubble.querySelector('.msg-author');
  if (author) author.textContent = modelName || 'Assistant';

  var meta = streamState.bubble.querySelector('.msg-meta');
  if (meta) {
    var timeStr = '';
    if (dbMsg && dbMsg.createdAt) {
      var d2 = new Date(dbMsg.createdAt + 'Z');
      if (!isNaN(d2.getTime())) {
        timeStr = d2.toLocaleString(undefined, {hour:'2-digit',minute:'2-digit',hour12:false});
      }
    }
    meta.textContent = (modelName || '') + (timeStr ? ' · ' + timeStr : '');
  }
}

function _finalizeThinkingBlock() {
  if (!streamState.thinkingDetails) return;
  var summary = streamState.thinkingDetails.querySelector('summary');
  summary.innerHTML = streamState.thinkingBuffer.length > 0
    ? '<i data-lucide="brain" style="width:16px;height:16px;"></i> Thought (' + streamState.thinkingBuffer.length + ' chars)'
    : '<i data-lucide="brain" style="width:16px;height:16px;"></i> Thought Process';
  if (typeof lucide !== 'undefined') lucide.createIcons();
  var pulse = streamState.thinkingDetails.querySelector('.thinking-pulse');
  if (pulse) pulse.remove();
}

function _finalizeStreamContent() {
  if (!streamState.contentDiv) return;
  streamState.contentDiv.innerHTML = md.render(streamState.contentBuffer);
}

function _updateUserTokenCount(data) {
  if (!(data && data.userTokenCount > 0)) return;
  for (var i = chatMessages.length - 1; i >= 0; i--) {
    if (chatMessages[i].role === 'user') {
      chatMessages[i].tokenCount = data.userTokenCount;
      break;
    }
  }
}

// Create a streaming assistant bubble (empty, with cursor)
function createStreamingBubble() {
  var container = document.getElementById('chat-messages');

  // Build HTML matching mock assistant message structure exactly
  var html = '<div class="msg bot" id="streaming-bubble">';
  html += '<div class="msg-body">';
  html += '<div class="msg-head">';
  html += '<span class="msg-author">Assistant</span>';
  html += '<span class="msg-meta"></span>';
  html += '</div>';
  html += '<div class="msg-content"></div>';
  html += '<div class="msg-edit-ui">';
  html += '<textarea class="msg-edit-textarea"></textarea>';
  html += '<div class="msg-edit-actions">';
  html += '<button class="ghost-btn cancel-edit">Cancel</button>';
  html += '<div style="display:flex; gap:12px;">';
  html += '<button class="ghost-btn save-branch"><i data-lucide="git-branch" style="width:16px;height:16px;"></i> Save as Branch</button>';
  html += '<button class="btn-primary save-overwrite">Overwrite</button>';
  html += '</div></div></div>';
  html += '<div class="msg-actions"></div>';
  html += '</div></div>';

  var template = document.createElement('div');
  template.innerHTML = html;
  var bubble = template.firstElementChild;
  container.appendChild(bubble);

  streamState.contentDiv = bubble.querySelector('.msg-content');
  scrollToBottom();
  return bubble;
}

// Create a thinking/details block for reasoning content.
// Nests the block INSIDE the streaming bubble (between label and content),
// matching how createMessageBubble renders it. This ensures the thinking
// block is removed when the bubble is removed — no orphaned DOM elements.
function createThinkingBlock(collapsed) {
  // Reasoning may arrive before the first content token. If no bubble
  // exists yet, create one so we have a parent to nest inside.
  if (!streamState.bubble) {
    streamState.bubble = createStreamingBubble();
  }

  var details = document.createElement('details');
  details.className = 'thinking-block';
  details.open = !collapsed;  // Collapsed by default for OpenAI/Gemini (useless summaries), expanded for DeepSeek

  var summary = document.createElement('summary');
  summary.innerHTML = '<i data-lucide="brain" style="width:16px;height:16px;"></i> Thought Process <span class="thinking-pulse">⏳</span>';
  details.appendChild(summary);

  var content = document.createElement('div');
  content.className = 'thinking-content';
  details.appendChild(content);

  // Insert inside the bubble, between the label and the message-content div
  var bodyEl = streamState.bubble.querySelector('.msg-body');
  if (bodyEl) bodyEl.insertBefore(details, streamState.contentDiv);
  else streamState.bubble.insertBefore(details, streamState.contentDiv);

  scrollToBottom();
  return details;
}

// Handle incoming streaming messages from AHK
function handleStreamMessage(target, data) {
  switch (target) {
    case 'streamContent':
      onStreamContent(data);
      break;
    case 'streamReasoning':
      onStreamReasoning(data);
      break;
    case 'streamDone':
      onStreamDone(data);
      break;
    case 'streamCancelled':
      cancelStreaming(data);
      break;
  }
}

// Clean up after user cancellation (Esc or Stop button).
// data may be {dbMsg: {...}} with DB message info for action buttons.
function cancelStreaming(data) {
  if (!streamState.active) return;
  streamState.active = false;

  var dbMsg = (data && data.dbMsg) ? data.dbMsg : null;

  // Remove blinking cursor from partial content
  if (streamState.contentDiv) {
    streamState.contentDiv.innerHTML = md.render(streamState.contentBuffer || '');
  }

  // Update thinking block to show it was cancelled
  if (streamState.thinkingDetails) {
    var summary = streamState.thinkingDetails.querySelector('summary');
    var pulse = streamState.thinkingDetails.querySelector('.thinking-pulse');
    if (pulse) pulse.remove();
    if (summary && streamState.thinkingBuffer) {
      summary.textContent = '🧠 Thought (' + streamState.thinkingBuffer.length + ' chars) — cancelled';
    }
  }

  // Update bubble label to model name if we have it
  if (streamState.bubble && streamState.modelName) {
    var label = streamState.bubble.querySelector('.message-label');
    if (label) label.textContent = streamState.modelName;
  }

  // Add to chatMessages and render action buttons if we have DB data.
  // Must also render when only thinking content exists (no text yet) —
  // otherwise Stop during reasoning leaves no action bar.
  if (dbMsg && (streamState.contentBuffer || streamState.thinkingBuffer)) {
    _persistStreamedMessage(streamState.contentBuffer, streamState.modelName, dbMsg);
    if (streamState.bubble) {
      addStreamingActions(streamState.bubble, chatMessages.length - 1);
    }
  }

  setChatButtonsEnabled(true);
}

// Add action buttons to a streaming bubble after completion
function addStreamingActions(bubble, index) {
  var msg = chatMessages[index];
  if (!msg) return;

  var existing = bubble.querySelector('.msg-actions');
  if (!existing) return;

  // Clear any existing content and re-add
  existing.innerHTML = '';
  addMessageActions(existing, msg, index);
}
