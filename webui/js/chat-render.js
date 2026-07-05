// ======================================================
// chat-render.js — Message bubble creation, DOM rendering, incremental updates
// ======================================================

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

// Incrementally update chat messages — replaces DOM elements from startIndex onward,
// preserving existing elements before that point. Only newly appended bubbles get
// the msgFadeIn animation. Maintains scroll position proportionally.
// The newMessages parameter is the FULL array (use startOffset to determine where
// to start iterating) to avoid unnecessary slice allocations.
function replaceMessagesAfter(startIndex, newMessages, startOffset) {
  var container = document.getElementById('chat-messages');
  if (!container) return;

  startOffset = startOffset || 0;

  // Remove all existing DOM bubbles at or after startIndex
  var existingBubbles = container.querySelectorAll('.chat-message');
  for (var i = startIndex; i < existingBubbles.length; i++) {
    existingBubbles[i].remove();
  }

  // If no new messages to add, we're done (old ones already removed)
  if (!newMessages || newMessages.length === 0) return;

  // Append new bubbles — add msg-new class for targeted fade-in animation
  for (var j = startOffset; j < newMessages.length; j++) {
    var bubble = createMessageBubble(newMessages[j], startIndex + (j - startOffset));
    bubble.classList.add('msg-new');
    container.appendChild(bubble);
  }
}

// Compare current chatMessages with a new array by message `id`.
// Find the first index where they diverge, then incrementally replace
// everything from that point onward using replaceMessagesAfter().
// Preserves scroll position: if user was near bottom, scroll to new bottom.
// Otherwise, maintain proportional position.
function updateChatMessages(newMessages) {
  if (!newMessages) return;

  var container = document.getElementById('chat-messages');
  if (!container) return;

  // Find divergence point — first index where id OR content differs
  // This detects overwrite edits (same id, different content) as well
  // as structural changes (different id, e.g. branch switch or delete).
  var divIdx = 0;
  while (divIdx < chatMessages.length && divIdx < newMessages.length) {
    var oldMsg = chatMessages[divIdx];
    var newMsg = newMessages[divIdx];
    if (oldMsg.id !== newMsg.id || oldMsg.content !== newMsg.content) break;
    divIdx++;
  }

  // Save scroll position proportionally so the view stays static
  // (the same content stays at the same visual position on screen).
  var prevScrollTop = container.scrollTop;
  var prevScrollHeight = container.scrollHeight;

  // Replace everything from divergence point
  replaceMessagesAfter(divIdx, newMessages, divIdx);

  // Update in-memory message array and persist
  chatMessages = newMessages;
  sessionStorage.setItem('chatMessages', JSON.stringify(chatMessages));

  // Restore proportional scroll position synchronously (no rAF needed —
  // the new content is already in the DOM so scrollHeight is current).
  if (prevScrollHeight > 0) {
    container.scrollTop = Math.round(container.scrollHeight * (prevScrollTop / prevScrollHeight));
  }
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

  // Action buttons (branch arrows are inside the action bar via addMessageActions)
  if (msg.role !== 'system') {
    var actions = document.createElement('div');
    actions.className = 'message-actions';
    addMessageActions(actions, msg, index);
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

// ======================================================
// Shared action button creation — used by both createMessageBubble and addStreamingActions
// ======================================================

function addMessageActions(actionsContainer, msg, index) {
  // Branch arrows (D3) — first in the action bar, before Quote
  if (msg.siblingInfo && msg.siblingInfo.total > 1) {
    var prevBtn = document.createElement('button');
    prevBtn.textContent = '◀';
    prevBtn.title = 'Previous branch';
    prevBtn.style.cssText = 'padding:2px 6px;font-size:0.75rem;';
    prevBtn.addEventListener('click', function(e) {
      e.stopPropagation();
      switchBranch(msg.id, -1);
    });
    actionsContainer.appendChild(prevBtn);

    var label = document.createElement('span');
    label.className = 'branch-label-inline';
    label.textContent = msg.siblingInfo.index + '/' + msg.siblingInfo.total;
    label.style.cssText = 'font-weight:600;font-size:0.75rem;min-width:2.5em;text-align:center;color:var(--bs-secondary-color);';
    actionsContainer.appendChild(label);

    var nextBtn = document.createElement('button');
    nextBtn.textContent = '▶';
    nextBtn.title = 'Next branch';
    nextBtn.style.cssText = 'padding:2px 6px;font-size:0.75rem;';
    nextBtn.addEventListener('click', function(e) {
      e.stopPropagation();
      switchBranch(msg.id, 1);
    });
    actionsContainer.appendChild(nextBtn);
  }

  // Quote button (D5)
  var quoteBtn = document.createElement('button');
  quoteBtn.className = 'quote-msg-btn';
  quoteBtn.textContent = '💬 Quote';
  quoteBtn.title = 'Quote this message';
  quoteBtn.addEventListener('click', function(e) {
    e.stopPropagation();
    quoteMessage(index);
  });
  actionsContainer.appendChild(quoteBtn);

  // Copy button
  var copyBtn = document.createElement('button');
  copyBtn.className = 'copy-msg-btn';
  copyBtn.textContent = '📋 Copy';
  copyBtn.title = 'Copy this message';
  copyBtn.addEventListener('click', function(e) {
    e.stopPropagation();
    copySingleMessage(index);
  });
  actionsContainer.appendChild(copyBtn);

  // Edit button (D1)
  var editBtn = document.createElement('button');
  editBtn.className = 'edit-msg-btn';
  editBtn.textContent = '✏️ Edit';
  editBtn.title = 'Edit this message';
  editBtn.addEventListener('click', function(e) {
    e.stopPropagation();
    editMessage(index);
  });
  actionsContainer.appendChild(editBtn);

  // Delete button (D2)
  var deleteBtn = document.createElement('button');
  deleteBtn.className = 'delete-msg-btn';
  deleteBtn.textContent = '🗑️ Delete';
  deleteBtn.title = 'Delete this message';
  deleteBtn.addEventListener('click', function(e) {
    e.stopPropagation();
    deleteMessage(index);
  });
  actionsContainer.appendChild(deleteBtn);

  // Fork button (D7)
  var forkBtn = document.createElement('button');
  forkBtn.className = 'fork-msg-btn';
  forkBtn.textContent = '↪ Fork';
  forkBtn.title = 'Fork chat from here';
  forkBtn.addEventListener('click', function(e) {
    e.stopPropagation();
    forkChat(index);
  });
  actionsContainer.appendChild(forkBtn);

  // Retry button (assistant messages only)
  if (msg.role === 'assistant') {
    var retryBtn = document.createElement('button');
    retryBtn.className = 'retry-msg-btn';
    retryBtn.textContent = '🔄 Retry';
    retryBtn.title = 'Retry this response';
    retryBtn.addEventListener('click', function(e) {
      e.stopPropagation();
      retryLastAssistantMessage(msg.id);
    });
    actionsContainer.appendChild(retryBtn);

    // Feedback buttons (D8)
    if (typeof addFeedbackButtons === 'function') {
      addFeedbackButtons(actionsContainer, msg, index);
    }
  }
}
