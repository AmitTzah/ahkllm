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

  // Update the content div with rendered markdown + blinking cursor
  var rendered = md.render(streamState.contentBuffer);
  streamState.contentDiv.innerHTML = rendered + '<span class="streaming-cursor">▊</span>';
  scrollToBottom();
}

// Called when reasoning/thinking content arrives
function onStreamReasoning(text) {
  if (!streamState.active) startStreaming();

  streamState.thinkingBuffer += text;

  // Create the thinking details block if it doesn't exist
  if (!streamState.thinkingDetails) {
    streamState.thinkingDetails = createThinkingBlock();
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

// Called when streaming is complete
function onStreamDone(data) {
  // Support both legacy (string modelName) and new ({ model, dbMsg }) formats
  var modelName = typeof data === 'string' ? data : (data && data.model ? data.model : '');
  var dbMsg = (data && data.dbMsg) ? data.dbMsg : null;

  // Always scroll to bottom on completion and reset the flag
  streamState.userScrolledUp = false;
  var container = document.getElementById('chat-messages');
  if (container) {
    container.scrollTop = container.scrollHeight;
  }

  streamState.modelName = modelName;

  // Update the bubble's label to the model name
  if (streamState.bubble) {
    var label = streamState.bubble.querySelector('.message-label');
    if (label) {
      label.textContent = modelName || 'Assistant';
    }
  }

  // Update thinking block to show it's done
  if (streamState.thinkingDetails) {
    var summary = streamState.thinkingDetails.querySelector('summary');
    var charCount = streamState.thinkingBuffer.length;
    summary.textContent = charCount > 0
      ? '🧠 Thought (' + charCount + ' chars)'
      : '🧠 Thinking';

    // Remove the pulse animation
    var pulse = streamState.thinkingDetails.querySelector('.thinking-pulse');
    if (pulse) pulse.remove();
  }

  // Remove the streaming cursor from content
  if (streamState.contentDiv) {
    // Re-render final content without cursor
    streamState.contentDiv.innerHTML = md.render(streamState.contentBuffer);
  }

  // Add the streaming message to chat history for persistence
  if (streamState.contentBuffer) {
    var streamingMessage = { role: 'assistant', content: streamState.contentBuffer };
    if (modelName) streamingMessage.model = modelName;
    // Apply DB fields (id, siblingInfo, reasoning, feedback) if available
    if (dbMsg) {
      if (dbMsg.id) streamingMessage.id = dbMsg.id;
      if (dbMsg.siblingInfo) streamingMessage.siblingInfo = dbMsg.siblingInfo;
      if (dbMsg.reasoning) streamingMessage.reasoning = dbMsg.reasoning;
      if (dbMsg.feedback) streamingMessage.feedback = dbMsg.feedback;
      // Update the bubble's dataset with the DB id
      if (streamState.bubble && dbMsg.id) {
        streamState.bubble.dataset.msgId = dbMsg.id;
      }
    }

    // Only add if not already in chatMessages (avoid duplicates — use id if available)
    var found = false;
    if (dbMsg && dbMsg.id) {
      for (var i = chatMessages.length - 1; i >= 0; i--) {
        if (chatMessages[i].id === dbMsg.id) {
          found = true;
          break;
        }
      }
    } else {
      // Fallback: content-based dedup (no id available from DB)
      for (var i = chatMessages.length - 1; i >= 0; i--) {
        if (chatMessages[i].role === 'assistant' && chatMessages[i].content === streamState.contentBuffer) {
          found = true;
          break;
        }
      }
    }
    if (!found) {
      chatMessages.push(streamingMessage);
      sessionStorage.setItem('chatMessages', JSON.stringify(chatMessages));
    }
    // Add action buttons now that the message is in chatMessages
    if (streamState.bubble) {
      addStreamingActions(streamState.bubble, chatMessages.length - 1);
      // Branch arrows are handled inside addMessageActions — no separate badge needed
    }
  }

  // Enable the chat input
  setChatButtonsEnabled(true);
  streamState.active = false;
}

// Create a streaming assistant bubble (empty, with cursor)
function createStreamingBubble() {
  var container = document.getElementById('chat-messages');

  var bubble = document.createElement('div');
  bubble.className = 'chat-message assistant';
  bubble.id = 'streaming-bubble';

  var label = document.createElement('div');
  label.className = 'message-label';
  label.textContent = 'Streaming...';
  bubble.appendChild(label);

  streamState.contentDiv = document.createElement('div');
  streamState.contentDiv.className = 'message-content';
  streamState.contentDiv.innerHTML = '<span class="streaming-cursor">▊</span>';
  bubble.appendChild(streamState.contentDiv);

  container.appendChild(bubble);
  scrollToBottom();
  return bubble;
}

// Create a thinking/details block for reasoning content.
// Nests the block INSIDE the streaming bubble (between label and content),
// matching how createMessageBubble renders it. This ensures the thinking
// block is removed when the bubble is removed — no orphaned DOM elements.
function createThinkingBlock() {
  // Reasoning may arrive before the first content token. If no bubble
  // exists yet, create one so we have a parent to nest inside.
  if (!streamState.bubble) {
    streamState.bubble = createStreamingBubble();
  }

  var details = document.createElement('details');
  details.className = 'thinking-block';
  details.open = true;  // Expanded by default

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
  }
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
