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
function onStreamDone(modelName) {
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

    // Only add if not already in chatMessages (avoid duplicates)
    var found = false;
    for (var i = chatMessages.length - 1; i >= 0; i--) {
      if (chatMessages[i].role === 'assistant' && chatMessages[i].content === streamState.contentBuffer) {
        found = true;
        break;
      }
    }
    if (!found) {
      chatMessages.push(streamingMessage);
      sessionStorage.setItem('chatMessages', JSON.stringify(chatMessages));
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

// Create a thinking/details block for reasoning content
function createThinkingBlock() {
  var details = document.createElement('details');
  details.className = 'thinking-block';

  var summary = document.createElement('summary');
  summary.innerHTML = '🧠 Thinking (0 chars) <span class="thinking-pulse">⏳</span>';
  details.appendChild(summary);

  var content = document.createElement('div');
  content.className = 'thinking-content';
  details.appendChild(content);

  // Insert before the streaming bubble
  if (streamState.bubble && streamState.bubble.parentNode) {
    streamState.bubble.parentNode.insertBefore(details, streamState.bubble);
  } else {
    var container = document.getElementById('chat-messages');
    container.appendChild(details);
  }

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
