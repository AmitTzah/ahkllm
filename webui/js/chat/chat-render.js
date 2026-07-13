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

// Incrementally update chat messages
function replaceMessagesAfter(startIndex, newMessages, startOffset) {
  var container = document.getElementById('chat-messages');
  if (!container) return;
  startOffset = startOffset || 0;
  var existingBubbles = container.querySelectorAll('.chat-message');
  for (var i = startIndex; i < existingBubbles.length; i++) {
    existingBubbles[i].remove();
  }
  if (!newMessages || newMessages.length === 0) return;
  for (var j = startOffset; j < newMessages.length; j++) {
    var bubble = createMessageBubble(newMessages[j], startIndex + (j - startOffset));
    bubble.classList.add('msg-new');
    container.appendChild(bubble);
  }
}

// Compare attachment arrays for divergence detection
function attachmentsEqual(a, b) {
  if (!a && !b) return true;
  if (!a || !b) return false;
  if (a.length !== b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i].id !== b[i].id) return false;
  }
  return true;
}

function updateChatMessages(newMessages) {
  if (!newMessages) return;
  var container = document.getElementById('chat-messages');
  if (!container) return;
  var divIdx = 0;
  while (divIdx < chatMessages.length && divIdx < newMessages.length) {
    var oldMsg = chatMessages[divIdx];
    var newMsg = newMessages[divIdx];
    if (oldMsg.id !== newMsg.id || oldMsg.content !== newMsg.content || !attachmentsEqual(oldMsg.attachments, newMsg.attachments)) break;
    divIdx++;
  }
  var prevScrollTop = container.scrollTop;
  var prevScrollHeight = container.scrollHeight;
  replaceMessagesAfter(divIdx, newMessages, divIdx);
  chatMessages = newMessages;
  sessionStorage.setItem('chatMessages', JSON.stringify(chatMessages));
  setChatButtonsEnabled(true);
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

  var bubbleContent = div;

  // Role label + timestamp on same line
  var labelRow = document.createElement('div');
  labelRow.style.cssText = 'display:flex;align-items:baseline;';
  var label = document.createElement('span');
  label.className = 'message-label';
  switch (msg.role) {
    case 'user': label.textContent = 'You'; break;
    case 'assistant': label.textContent = msg.model || 'Assistant'; break;
    case 'system': label.textContent = 'System Prompt'; break;
  }
  labelRow.appendChild(label);

  // Timestamp — right-aligned on same line as label
  if (msg.createdAt) {
    var d2 = new Date(msg.createdAt + 'Z');
    if (!isNaN(d2.getTime())) {
      var ts = document.createElement('span');
      ts.className = 'message-timestamp';
      ts.style.cssText = 'margin-left:auto;font-size:0.68rem;color:var(--bs-text-muted,#9ca3af);white-space:nowrap;';
      ts.textContent = d2.toLocaleString(undefined, {month:'short',day:'numeric',hour:'2-digit',minute:'2-digit'});
      labelRow.appendChild(ts);
    }
  }
  bubbleContent.appendChild(labelRow);

  // Attachment previews (user messages only)
  if (msg.attachments && msg.attachments.length > 0 && msg.role === 'user') {
    // Show scanned PDF banner once, above all images
    for (var a = 0; a < msg.attachments.length; a++) {
      if (msg.attachments[a].extracted_text === '__SCANNED_PDF__') {
        var scanBanner = document.createElement('div');
        scanBanner.style.cssText = 'background:var(--bs-warning-bg-subtle);color:var(--bs-warning-text-emphasis);padding:6px 12px;margin:4px 0;border-radius:6px;font-size:0.8rem;border:1px solid var(--bs-warning-border-subtle);display:flex;align-items:center;justify-content:space-between;';
        scanBanner.innerHTML = '<span>⚠️ No extractable text (scanned PDF) — attached as image(s)</span>';
        var dismissBtn = document.createElement('button');
        dismissBtn.textContent = '\u00D7';
        dismissBtn.title = 'Dismiss';
        dismissBtn.style.cssText = 'background:none;border:none;font-size:1rem;cursor:pointer;color:var(--bs-warning-text-emphasis);padding:0 4px;line-height:1;';
        dismissBtn.addEventListener('click', function() { scanBanner.remove(); });
        scanBanner.appendChild(dismissBtn);
        bubbleContent.appendChild(scanBanner);
        break;
      }
    }
    for (var a = 0; a < msg.attachments.length; a++) {
      var att = msg.attachments[a];
      if (att.attachment_type === 'image') {
        var imgWrapper = document.createElement('div');
        imgWrapper.className = 'msg-attachment-image';
        var img = document.createElement('img');
        img.alt = att.original_filename || 'image';
        img.title = (att.original_filename || 'image') + ' (' + (att.file_size ? Math.round(att.file_size / 1024) + 'KB' : '') + ')';
        img.src = 'data:' + (att.mime_type || 'image/png') + ';base64,' + (att.base64 || '');
        if (att.base64) {
            img.addEventListener('click', function() {
                var overlay = document.createElement('div');
                overlay.className = 'image-overlay';
                overlay.style.display = 'flex';
                var fullImg = document.createElement('img');
                fullImg.src = this.src;
                overlay.appendChild(fullImg);
                overlay.addEventListener('click', function() { this.remove(); });
                document.body.appendChild(overlay);
            });
        }
        imgWrapper.appendChild(img);
        var infoBar = document.createElement('div');
        infoBar.style.cssText = 'display:flex;align-items:center;gap:0.5rem;font-size:0.75rem;margin-top:0.2rem;';
        var nameSpan = document.createElement('span');
        nameSpan.textContent = '\uD83D\uDDBC' + ' ' + (att.original_filename || 'image');
        nameSpan.style.cssText = 'color:var(--bs-secondary-color);';
        infoBar.appendChild(nameSpan);
        if (att.id) {
          var delBtn = document.createElement('button');
          delBtn.className = 'msg-attachment-delete';
          delBtn.textContent = '\u00D7';
          delBtn.title = 'Remove attachment';
          delBtn.setAttribute('data-attachment-id', att.id);
          infoBar.appendChild(delBtn);
        }
        imgWrapper.appendChild(infoBar);
        bubbleContent.appendChild(imgWrapper);
      } else {
        var fileDiv = document.createElement('div');
        fileDiv.className = 'msg-attachment-file';
        var icon = '\uD83D\uDCCE';
        if (att.attachment_type === 'pdf') icon = '\uD83D\uDCD5';
        else if (att.attachment_type === 'docx') icon = '\uD83D\uDCC4';
        else if (att.attachment_type === 'text_file') icon = '\uD83D\uDCDD';
        var iconSpan = document.createElement('span');
        iconSpan.className = 'file-icon';
        iconSpan.textContent = icon;
        fileDiv.appendChild(iconSpan);
        var nameSpan = document.createElement('span');
        nameSpan.className = 'file-name';
        nameSpan.textContent = att.original_filename || 'file';
        fileDiv.appendChild(nameSpan);
        var sizeSpan = document.createElement('span');
        sizeSpan.className = 'file-size';
        sizeSpan.textContent = att.file_size ? Math.round(att.file_size / 1024) + 'KB' : '';
        fileDiv.appendChild(sizeSpan);
        if (att.id) {
          var delBtn2 = document.createElement('button');
          delBtn2.className = 'msg-attachment-delete';
          delBtn2.textContent = '\u00D7';
          delBtn2.title = 'Remove attachment';
          delBtn2.setAttribute('data-attachment-id', att.id);
          fileDiv.appendChild(delBtn2);
        }
        bubbleContent.appendChild(fileDiv);
        if (att.extracted_text === '__SCANNED_PDF__') {
          var scanBanner = document.createElement('div');
          scanBanner.style.cssText = 'background:var(--bs-warning-bg-subtle);color:var(--bs-warning-text-emphasis);padding:6px 12px;margin:4px 0;border-radius:6px;font-size:0.8rem;border:1px solid var(--bs-warning-border-subtle);';
          scanBanner.innerHTML = '<span>⚠️ No extractable text (scanned PDF) — attached as image(s)</span>';
          bubbleContent.appendChild(scanBanner);
        } else if (att.extracted_text && att.extracted_text !== '(no text extracted)' && att.extracted_text !== '__LIBRARY_UNAVAILABLE__') {
          var preview = document.createElement('details');
          preview.className = 'msg-attachment-text-preview';
          var previewSummary = document.createElement('summary');
          previewSummary.style.cssText = 'cursor:pointer;font-size:0.75rem;color:var(--bs-secondary-color);';
          previewSummary.textContent = '\uD83D\uDCCB Extracted text';
          preview.appendChild(previewSummary);
          var preBlock = document.createElement('pre');
          preBlock.textContent = att.extracted_text;
          preview.appendChild(preBlock);
          bubbleContent.appendChild(preview);
        }
      }
    }
  }

  // Reasoning/thinking block
  if (msg.reasoning) {
    var thinkingDetails = document.createElement('details');
    thinkingDetails.className = 'thinking-block';
    thinkingDetails.open = true;
    var summary = document.createElement('summary');
    summary.textContent = '\uD83E\uDDE0 Thought (' + msg.reasoning.length + ' chars)';
    thinkingDetails.appendChild(summary);
    var thinkingContent = document.createElement('div');
    thinkingContent.className = 'thinking-content';
    thinkingContent.textContent = msg.reasoning;
    thinkingDetails.appendChild(thinkingContent);
    bubbleContent.appendChild(thinkingDetails);
  }

  // Content (rendered markdown)
  var contentDiv = document.createElement('div');
  contentDiv.className = 'message-content';
  contentDiv.innerHTML = md.render(msg.content || '');
  bubbleContent.appendChild(contentDiv);

  // Action buttons
  if (msg.role !== 'system') {
    var actions = document.createElement('div');
    actions.className = 'message-actions';
    addMessageActions(actions, msg, index);
    div.appendChild(actions);
  }

  return div;
}

// Branch badge
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
