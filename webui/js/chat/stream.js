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

  // Remove the loading indicator since we're now showing live content
  hideLoadingIndicator();
}

// Called when streaming content arrives (token by token)
function onStreamContent(text, threadId) {
  // Bug #195: a stream that belongs to another thread/branch must never paint
  // into the currently-visible conversation.
  if (threadId && activeThreadId && threadId !== activeThreadId) return;
  if (!streamState.active) {
    // Late chunk after finalize (Stop raced the final SSE event): append it
    // to the last assistant bubble instead of opening a DUPLICATE bubble.
    var container = document.getElementById('chat-messages');
    if (!container) return;
    var bubbles = container.querySelectorAll('.msg.bot');
    if (!bubbles.length) return;
    var contentDiv = bubbles[bubbles.length - 1].querySelector('.msg-content');
    if (!contentDiv) return;
    var full = contentDiv.textContent + text;
    contentDiv.innerHTML = md.render(full);
    var last = chatMessages[chatMessages.length - 1];
    if (last && last.role === 'assistant') last.content = full;
    scrollToBottom();
    return;
  }

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
function onStreamReasoning(data, threadId) {
  if (threadId && activeThreadId && threadId !== activeThreadId) return;
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
  }
}

// Bug #195: a streamed response may only be persisted into the CURRENT UI
// array when that array is actually the request's own path. The DB row is the
// source of truth; the completion/cancel message carries the sending
// thread id and the persisted message's parent id.
function _streamBelongsToCurrentPath(dbMsg) {
  if (!dbMsg) return false;
  // Legacy/unit-test payloads without a parent id are treated as current;
  // production dbMsg always carries parentId (bug #195).
  if (dbMsg.parentId === undefined) return true;
  if (!dbMsg.parentId) {
    // Root retry (or a response with no parent): only valid when the UI path
    // was emptied for the retry (or is the same root).
    var last0 = chatMessages.length ? chatMessages[chatMessages.length - 1] : null;
    return chatMessages.length === 0 || (last0 && last0.id === dbMsg.id);
  }
  var last = chatMessages.length ? chatMessages[chatMessages.length - 1] : null;
  return !!last && last.id === dbMsg.parentId;
}

// Called when streaming is complete
function onStreamDone(data) {
  var modelName = typeof data === 'string' ? data : (data && data.model ? data.model : '');
  var displayName = (data && data.displayName) ? data.displayName : modelName;
  var dbMsg = (data && data.dbMsg) ? data.dbMsg : null;
  // Legacy payloads without a dbMsg are treated as current (they carry no
  // thread/parent scoping info); production payloads always carry dbMsg +
  // threadId, so a non-current stream can be scoped away (bugs #195/#221).
  var isCurrent = (!dbMsg || _streamBelongsToCurrentPath(dbMsg)) &&
    (!data.threadId || !activeThreadId || data.threadId === activeThreadId);

  streamState.userScrolledUp = false;
  var container = document.getElementById('chat-messages');
  if (container) container.scrollTop = container.scrollHeight;
  streamState.modelName = displayName;

  if (isCurrent) {
    _finalizeStreamBubble(displayName, modelName, dbMsg);
    _finalizeThinkingBlock();
    _finalizeStreamContent();
  }

  // Persist and add action buttons even when the final content is empty but
  // reasoning was streamed (reasoning-only responses) - otherwise the message
  // never lands in chatMessages and the bubble has no Copy/Retry/etc until reload.
  if (isCurrent && (streamState.contentBuffer || streamState.thinkingBuffer)) {
    _persistStreamedMessage(streamState.contentBuffer, modelName, dbMsg);
    if (streamState.bubble) addStreamingActions(streamState.bubble, chatMessages.length - 1);
  } else if (isCurrent && dbMsg && dbMsg.role === 'assistant') {
    // Bug #229: a NON-STREAMING (single-shot) chat response never streams any
    // content/reasoning chunks, so the buffers are empty and the branch above
    // is skipped - AHK persisted the assistant row and posted streamDone with
    // dbMsg, but the bubble never appeared until the thread was reloaded
    // (e.g. chat-mode commands with "Stream Response" OFF, like the default
    // Summarize command). Render the persisted DB message directly.
    _persistStreamedMessage(dbMsg.content || '', modelName, dbMsg);
    if (typeof renderChatMessages === 'function') renderChatMessages(chatMessages);
  }

  if (isCurrent) _updateUserTokenCount(data);

  // The retry succeeded - the streamed response replaced the removed
  // messages, so never restore them on a later error.
  if (typeof _retryRemovedMessages !== 'undefined') _retryRemovedMessages = null;
  if (typeof _retryThreadId !== 'undefined') _retryThreadId = null;
  if (typeof _retryAnchorId !== 'undefined') _retryAnchorId = null;

  // Bug #221: a NON-current stream's completion must not clear the global
  // stream state - the CURRENT thread may still have its own stream in flight
  // (two chat-mode commands can stream at once). AHK posts
  // setChatButtonsEnabled(true) only once NO request remains, and that
  // (handled in setChatButtonsEnabled) is the signal to reset the composer.
  if (!isCurrent) return;

  streamState.active = false;
  streamState.contentBuffer = '';
  streamState.thinkingBuffer = '';
  streamState.bubble = null;
  streamState.thinkingDetails = null;
  streamState.contentDiv = null;

  // Refresh thread map (right panel nav)
  if (typeof renderNavList === 'function') renderNavList();
}

function _finalizeStreamBubble(displayName, modelName, dbMsg) {
  if (!streamState.bubble) return;
  var author = streamState.bubble.querySelector('.msg-author');
  if (author) author.textContent = displayName || 'Assistant';

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
  // Bug #150: a 0 contribution is a real value (e.g. a branch copy whose
  // context already exceeds the new prompt) - it must still overwrite the
  // stale UI token count, so only skip when the value is absent.
  if (!(data && data.userTokenCount !== undefined && data.userTokenCount >= 0)) return;
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

  // Build the assistant message bubble HTML
  var displayName = streamState.modelName || 'Assistant';
  var html = '<div class="msg bot" id="streaming-bubble">';
  html += '<div class="msg-body">';
  html += '<div class="msg-head">';
  // Bug #208: displayName comes from the AHK streamModelName post (assistant
  // name or sanitized model name) and is user-controlled - escape it like
  // createMessageBubble does, or markup in the name is parsed as HTML and
  // inline handlers execute inside the WebView.
  html += '<span class="msg-author">' + escHtml(displayName) + '</span>';
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
      onStreamContent(typeof data === 'string' ? data : (data && data.text ? data.text : data), data && data.threadId);
      break;
    case 'streamReasoning':
      onStreamReasoning(data, data && data.threadId);
      break;
    case 'streamModelName':
      onStreamModelName(typeof data === 'string' ? data : (data && data.name ? data.name : data), data && data.threadId);
      break;
    case 'streamDone':
      onStreamDone(data);
      break;
    case 'streamCancelled':
      cancelStreaming(data);
      break;
  }
}

// Update the streaming bubble's author to the actual model name as soon as it's known
function onStreamModelName(modelName, threadId) {
  if (threadId && activeThreadId && threadId !== activeThreadId) return;
  if (!modelName) return;
  streamState.modelName = modelName;

  if (!streamState.bubble) return;
  var author = streamState.bubble.querySelector('.msg-author');
  if (author) author.textContent = modelName;
}

// Clean up after user cancellation (Esc or Stop button).
// data may be {dbMsg: {...}} with DB message info for action buttons.
function cancelStreaming(data) {
  if (!streamState.active) return;
  // A cancelled retry keeps its partial response; the removed messages must
  // not be restored afterwards.
  if (typeof _retryRemovedMessages !== 'undefined') _retryRemovedMessages = null;
  if (typeof _retryThreadId !== 'undefined') _retryThreadId = null;
  if (typeof _retryAnchorId !== 'undefined') _retryAnchorId = null;

  var dbMsg = (data && data.dbMsg) ? data.dbMsg : null;
  var isCurrent = (!dbMsg || _streamBelongsToCurrentPath(dbMsg)) &&
    (!data.threadId || !activeThreadId || data.threadId === activeThreadId);
  // Bug #221: a NON-current stream's cancel/error must not clear the current
  // view's streaming state - the current thread may still be streaming its
  // own response (two chat-mode commands can stream at once).
  if (!isCurrent) return;

  streamState.active = false;

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

  // Bug #221: the composer re-enable is AHK's job (it posts
  // setChatButtonsEnabled(true) only when NO other request is still in
  // flight) - calling it here would un-wedge the composer while another
  // concurrent command stream is still running.
  streamState.contentBuffer = '';
  streamState.thinkingBuffer = '';
  streamState.bubble = null;
  streamState.thinkingDetails = null;
  streamState.contentDiv = null;
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
