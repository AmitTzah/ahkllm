// ======================================================
// chat-render.js — Message bubble creation, DOM rendering, incremental updates
// ======================================================

// Persisted across renders so each message ID remembers its own state
// independently, even across branch switches.
var _persistedThinkingStates = {};

function _saveThinkingBlockStates() {
  var blocks = document.querySelectorAll('.thinking-block');
  for (var i = 0; i < blocks.length; i++) {
    var msgEl = blocks[i].closest('.msg');
    if (!msgEl) continue;
    var msgId = msgEl.getAttribute('data-msg-id');
    if (!msgId) continue;
    _persistedThinkingStates[msgId] = blocks[i].open;
  }
}

function _restoreThinkingBlockStates() {
  var container = document.getElementById('chat-messages');
  if (!container) return;
  // Scan visible thinking blocks (O(visible) instead of O(persisted)):
  // for a 1000-message tree, only ~10-50 are in the DOM at any time.
  var blocks = container.querySelectorAll('.thinking-block');
  for (var i = 0; i < blocks.length; i++) {
    var msgEl = blocks[i].closest('.msg');
    if (!msgEl) continue;
    var msgId = msgEl.getAttribute('data-msg-id');
    if (!msgId) continue;
    if (!_persistedThinkingStates.hasOwnProperty(msgId)) continue;
    if (_persistedThinkingStates[msgId]) {
      blocks[i].setAttribute('open', '');
    } else {
      blocks[i].removeAttribute('open');
    }
  }
}

function renderChatMessages(messages) {
  var container = document.getElementById('chat-messages');
  if (!container) return;
  _saveThinkingBlockStates();
  container.innerHTML = '';
  for (var i = 0; i < messages.length; i++) {
    container.appendChild(createMessageBubble(messages[i], i));
  }
  _restoreThinkingBlockStates();
  // Render Lucide icons now that bubbles are in the DOM
  if (typeof lucide !== 'undefined') lucide.createIcons();
  // Scroll the parent .thread element
  var scrollEl = document.getElementById('chat-scroll') || container.parentElement;
  if (scrollEl) scrollEl.scrollTop = scrollEl.scrollHeight;
}

function replaceMessagesAfter(startIndex, newMessages, startOffset) {
  var container = document.getElementById('chat-messages');
  if (!container) return;
  _saveThinkingBlockStates();
  startOffset = startOffset || 0;
  var existingBubbles = container.querySelectorAll('.msg');
  for (var i = startIndex; i < existingBubbles.length; i++) {
    existingBubbles[i].remove();
  }
  if (!newMessages || newMessages.length === 0) {
    _restoreThinkingBlockStates();
    return;
  }
  for (var j = startOffset; j < newMessages.length; j++) {
    var bubble = createMessageBubble(newMessages[j], startIndex + (j - startOffset));
    container.appendChild(bubble);
  }
  _restoreThinkingBlockStates();
}

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
  if (typeof renderNavList === 'function') renderNavList();
  if (prevScrollHeight > 0) {
    var scrollEl = document.getElementById('chat-scroll') || container.parentElement;
    if (scrollEl) scrollEl.scrollTop = Math.round(scrollEl.scrollHeight * (prevScrollTop / (scrollEl.scrollHeight || 1)));
  }
}


// Build message HTML by copying the mock's structure EXACTLY, substituting only dynamic values
function createMessageBubble(msg, index) {
  var roleClass = msg.role === 'user' ? 'you' : (msg.role === 'assistant' ? 'bot' : 'system');
  var authorName = msg.role === 'user' ? 'You' : (msg.role === 'system' ? 'System Prompt' : (msg.model || 'Assistant'));
  var msgId = msg.id || '';
  var metaText = _buildMetaText(msg);
  var contentHtml = md.render(msg.content || '');
  var reasoningHtml = _buildReasoningHtml(msg);
  var attachmentHtml = _buildAttachmentHtml(msg);
  var editUiHtml = _buildEditUiHtml(msg);

  var html = '';
  if (msg.role === 'user') {
    html = '        <div class="msg you"' + (msgId ? ' data-msg-id="' + msgId + '"' : '') + '>\n' +
      '          <div class="msg-body">\n' +
      '            <div class="msg-head">\n' +
      '              <span class="msg-author">' + escHtml(authorName) + '</span>\n' +
      '              <span class="msg-meta">' + metaText + '</span>\n' +
      '            </div>\n' +
      attachmentHtml +
      '            <div class="msg-content">' + contentHtml + '</div>\n' +
      '\n' + editUiHtml + '\n' +
      '            <div class="msg-actions"></div>\n' +
      '          </div>\n' +
      '        </div>';
  } else if (msg.role === 'assistant') {
    html = '        <div class="msg bot"' + (msgId ? ' data-msg-id="' + msgId + '"' : '') + '>\n' +
      '          <div class="msg-body">\n' +
      '            <div class="msg-head">\n' +
      '              <span class="msg-author">' + escHtml(authorName) + '</span>\n' +
      '              <span class="msg-meta">' + metaText + '</span>\n' +
      '            </div>\n' +
      reasoningHtml + '\n' +
      '            <div class="msg-content">' + contentHtml + '</div>\n' +
      '\n' + editUiHtml + '\n' +
      '            <div class="msg-actions"></div>\n' +
      '          </div>\n' +
      '        </div>';
  } else {
    html = '        <div class="msg system"' + (msgId ? ' data-msg-id="' + msgId + '"' : '') + '>\n' +
      '          <div class="msg-body">\n' +
      '            <div class="msg-head">\n' +
      '              <span class="msg-author">' + escHtml(authorName) + '</span>\n' +
      '              <span class="msg-meta">' + metaText + '</span>\n' +
      '            </div>\n' +
      '            <div class="msg-content">' + contentHtml + '</div>\n' +
      '          </div>\n' +
      '        </div>';
  }

  var template = document.createElement('div');
  template.innerHTML = html;
  var bubble = template.firstElementChild;

  if (msg.role !== 'system') {
    var actionsDiv = bubble.querySelector('.msg-actions');
    if (actionsDiv) addMessageActions(actionsDiv, msg, index);
  }

  return bubble;
}

function _buildMetaText(msg) {
  if (!msg.createdAt) return '';
  var d = new Date(msg.createdAt + 'Z');
  if (isNaN(d.getTime())) return '';
  var timeStr = d.toLocaleString(undefined, {hour:'2-digit',minute:'2-digit',hour12:false});
  if (msg.role === 'assistant') return escHtml(msg.model || '') + ' · ' + timeStr;
  if (msg.role === 'user') return '· ' + timeStr;
  return timeStr;
}

function _buildReasoningHtml(msg) {
  if (!msg.reasoning) return '';
  return '\n            <details class="thinking-block" open>\n' +
    '              <summary><i data-lucide="brain" style="width:16px;height:16px;"></i> Thought Process</summary>\n' +
    '              <div class="thinking-content">' + escHtml(msg.reasoning) + '</div>\n' +
    '            </details>';
}

function _buildAttachmentHtml(msg) {
  if (!msg.attachments || !msg.attachments.length || msg.role !== 'user') return '';
  var html = '';
  for (var a = 0; a < msg.attachments.length; a++) {
    var att = msg.attachments[a];
    if (att.attachment_type === 'image' && att.base64) {
      html += '\n            <div class="msg-attachment-image">\n' +
        '              <img src="data:' + (att.mime_type || 'image/png') + ';base64,' + att.base64 + '" alt="' + escHtml(att.original_filename || 'image') + '">\n' +
        '            </div>';
    } else {
      html += '\n            <div class="msg-attachment-file">\n' +
        '              <span class="file-icon">' + (att.attachment_type === 'pdf' ? '📕' : '📎') + '</span>\n' +
        '              <span class="file-name">' + escHtml(att.original_filename || 'file') + '</span>\n' +
        '            </div>';
    }
  }
  return html;
}

function _buildEditUiHtml(msg) {
  return '            <div class="msg-edit-ui">\n' +
    '              <textarea class="msg-edit-textarea">' + escHtml(msg.content || '') + '</textarea>\n' +
    '              <div class="msg-edit-actions">\n' +
    '                <button class="ghost-btn cancel-edit">Cancel</button>\n' +
    '                <div style="display:flex; gap:12px;">\n' +
    '                  <button class="ghost-btn save-branch"><i data-lucide="git-branch" style="width:16px;height:16px;"></i> Save as Branch</button>\n' +
    '                  <button class="btn-primary save-overwrite">Overwrite</button>\n' +
    '                </div>\n' +
    '              </div>\n' +
    '            </div>';
}

function appendChatMessage(message) {
  chatMessages.push(message);
  var container = document.getElementById('chat-messages');
  if (!container) return;
  container.appendChild(createMessageBubble(message, chatMessages.length - 1));
  if (typeof lucide !== 'undefined') lucide.createIcons();
  var scrollEl = document.getElementById('chat-scroll');
  if (scrollEl) scrollEl.scrollTop = scrollEl.scrollHeight;
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
