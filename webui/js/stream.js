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

  var container = document.getElementById('chat-messages');
  if (!container) return;

  container.scrollTop = container.scrollHeight;
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
  summary.innerHTML = '🧠 Thinking (' + streamState.thinkingBuffer.length + ' chars)' +
    ' <span class="thinking-pulse">⏳</span>';

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
    if (dbMsg.feedback) msg.feedback = dbMsg.feedback;
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
}

function _finalizeStreamBubble(modelName, dbMsg) {
  if (!streamState.bubble) return;
  var label = streamState.bubble.querySelector('.message-label');
  if (label) label.textContent = modelName || 'Assistant';

  // Add timestamp if available from DB message
  if (dbMsg && dbMsg.createdAt) {
    var existingTs = streamState.bubble.querySelector('.message-timestamp');
    if (!existingTs) {
      var d2 = new Date(dbMsg.createdAt + 'Z');
      if (!isNaN(d2.getTime())) {
        var ts = document.createElement('span');
        ts.className = 'message-timestamp';
        ts.style.cssText = 'margin-left:auto;font-size:0.68rem;color:var(--bs-text-muted,#9ca3af);white-space:nowrap;';
        ts.textContent = d2.toLocaleString(undefined, {month:'short',day:'numeric',hour:'2-digit',minute:'2-digit'});
        var labelRow = label.parentNode;
        if (labelRow) labelRow.appendChild(ts);
      }
    }
  }
}

function _finalizeThinkingBlock() {
  if (!streamState.thinkingDetails) return;
  var summary = streamState.thinkingDetails.querySelector('summary');
  summary.textContent = streamState.thinkingBuffer.length > 0
    ? '🧠 Thought (' + streamState.thinkingBuffer.length + ' chars)'
    : '🧠 Thinking';
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

  var bubble = document.createElement('div');
  bubble.className = 'chat-message assistant';
  bubble.id = 'streaming-bubble';

  // Label row — same structure as createMessageBubble for timestamp support
  var labelRow = document.createElement('div');
  labelRow.style.cssText = 'display:flex;align-items:baseline;';
  var label = document.createElement('span');
  label.className = 'message-label';
  label.textContent = 'Streaming...';
  labelRow.appendChild(label);
  bubble.appendChild(labelRow);

  streamState.contentDiv = document.createElement('div');
  streamState.contentDiv.className = 'message-content';
  bubble.appendChild(streamState.contentDiv);

  container.appendChild(bubble);
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
  summary.innerHTML = '🧠 Thinking (0 chars) <span class="thinking-pulse">⏳</span>';
  details.appendChild(summary);

  var content = document.createElement('div');
  content.className = 'thinking-content';
  details.appendChild(content);

  // Insert inside the bubble, between the label and the message-content div
  streamState.bubble.insertBefore(details, streamState.contentDiv);

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
  // Avoid adding twice
  if (bubble.querySelector('.message-actions')) return;

  var msg = chatMessages[index];
  if (!msg) return;

  var actions = document.createElement('div');
  actions.className = 'message-actions';
  addMessageActions(actions, msg, index);
  bubble.appendChild(actions);
}
