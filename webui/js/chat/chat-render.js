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
  // Preserve error banners across re-render (e.g. vision gate error on first send)
  // so they survive initChatMode when loadThread triggers _LoadThreadAndRefreshUI.
  var errorBanners = container.querySelectorAll('.error-banner');
  container.innerHTML = '';
  for (var i = 0; i < messages.length; i++) {
    container.appendChild(createMessageBubble(messages[i], i));
  }
  for (var i = 0; i < errorBanners.length; i++) {
    container.appendChild(errorBanners[i]);
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
  var reasoningHtml = _buildReasoningHtml(msg);
  var attachmentHtml = _buildAttachmentHtml(msg);
  var editUiHtml = _buildEditUiHtml(msg);

  var html = '';
  if (msg.role === 'user') {
    var content = (msg.content || '').replace(/\r\n/g, '\n').replace(/\r/g, '\n');
    content = content.replace(/\n{3,}/g, '\n\n<br>\n\n');
    var contentHtml = md.render(content);
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
    var contentHtml = md.render(msg.content || '');
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
    var contentHtml = md.render(msg.content || '');
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

  // Render Lucide icons in the new bubble (attachment icons, action buttons)
  if (typeof lucide !== 'undefined') lucide.createIcons();

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

function _formatFileSize(bytes) {
  if (!bytes || bytes === 0) return '0B';
  if (bytes < 1024) return bytes + 'B';
  if (bytes < 1048576) return (bytes / 1024).toFixed(1) + 'KB';
  return (bytes / 1048576).toFixed(1) + 'MB';
}

function _buildAttachmentHtml(msg) {
  if (!msg.attachments || !msg.attachments.length || msg.role !== 'user') return '';
  var html = '';
  var hasScannedPDF = false;

  // Pre-scan for scanned PDF banner (show once per message)
  for (var a = 0; a < msg.attachments.length; a++) {
    if (msg.attachments[a].extracted_text === '__SCANNED_PDF__') {
      hasScannedPDF = true;
      break;
    }
  }
  if (hasScannedPDF) {
    html += '\n            <div class="scan-banner">\n' +
      '              <span>\u26A0\uFE0F No extractable text (scanned PDF) \u2014 attached as image(s)</span>\n' +
      '              <button onclick="this.parentElement.remove()">\u00D7</button>\n' +
      '            </div>';
  }

  for (var a = 0; a < msg.attachments.length; a++) {
    var att = msg.attachments[a];
    var attId = att.id || '';

    if (att.attachment_type === 'image' && att.base64) {
      var imgSrc = 'data:' + (att.mime_type || 'image/png') + ';base64,' + att.base64;
      html += '\n            <div class="msg-attachment-image">\n' +
        '              <img src="' + imgSrc + '" alt="' + escHtml(att.original_filename || 'image') + '" onclick="(function(){var o=document.createElement(\'div\');o.className=\'image-overlay\';o.style.display=\'flex\';var i=document.createElement(\'img\');i.src=this.src;o.appendChild(i);o.addEventListener(\'click\',function(){this.remove()});document.body.appendChild(o);}).call(this)">\n' +
        '              <div class="msg-attachment-info">\n' +
        '                <i data-lucide="image" class="file-icon"></i>\n' +
        '                <span class="file-name">' + escHtml(att.original_filename || 'image') + '</span>\n' +
        '                <span class="file-size">' + _formatFileSize(att.file_size) + '</span>\n' +
        (attId ? '                <button class="msg-attachment-delete" data-attachment-id="' + attId + '" title="Remove attachment">\u00D7</button>\n' : '') +
        '              </div>\n' +
        '            </div>';
    } else {
      var iconName = typeof getAttachmentIcon === 'function' ? getAttachmentIcon(att.mime_type || '', att.original_filename || '') : 'file-text';
      var iconHtml;
      if (iconName.indexOf('icons/') === 0) {
        iconHtml = '<img src="' + iconName + '" class="file-icon">';
      } else {
        iconHtml = '<i data-lucide="' + iconName + '" class="file-icon"></i>';
      }
      html += '\n            <div class="msg-attachment-file">\n' +
        '              ' + iconHtml + '\n' +
        '              <span class="file-name">' + escHtml(att.original_filename || 'file') + '</span>\n' +
        '              <span class="file-size">' + _formatFileSize(att.file_size) + '</span>\n' +
        (attId ? '              <button class="msg-attachment-delete" data-attachment-id="' + attId + '" title="Remove attachment">\u00D7</button>\n' : '') +
        '            </div>';
      // Extraction failure banner (visible warning, not collapsible)
      if (att.extracted_text && att.extracted_text.indexOf('(extraction failed') === 0) {
        html += '\n            <div class="scan-banner">\n' +
          '              <span>\u26A0\uFE0F ' + escHtml(att.extracted_text) + '</span>\n' +
          '            </div>';
      // Extracted text preview
      } else if (att.extracted_text && att.extracted_text !== '__SCANNED_PDF__' && att.extracted_text !== '__LIBRARY_UNAVAILABLE__' && att.extracted_text !== '(no text extracted)') {
        var extractedEscaped = escHtml(att.extracted_text);
        html += '\n            <details class="msg-attachment-text-preview">\n' +
          '              <summary>\uD83D\uDCCB Extracted text' +
          '                <button class="copy-extract-btn" title="Copy extracted text" onclick="var p=this.parentElement.parentElement.querySelector(\'pre\');if(p){navigator.clipboard.writeText(p.textContent).then(function(){var b=this;b.innerHTML=\'<i data-lucide=check style=width:13px;height:13px></i>\';lucide.createIcons();setTimeout(function(){b.innerHTML=\'<i data-lucide=copy style=width:13px;height:13px></i>\';lucide.createIcons();},2000)}.bind(this))}" style="background:none;border:none;cursor:pointer;color:var(--text-tertiary);padding:0 2px;margin-left:6px;vertical-align:-2px;"><i data-lucide="copy" style="width:13px;height:13px;"></i></button>' +
          '              </summary>\n' +
          '              <pre>' + extractedEscaped + '</pre>\n' +
          '            </details>';
      } else if (att.extracted_text === '__SCANNED_PDF__' && !hasScannedPDF) {
        html += '\n            <div class="scan-banner">\n' +
          '              <span>\u26A0\uFE0F No extractable text (scanned PDF) \u2014 attached as image(s)</span>\n' +
          '              <button onclick="this.parentElement.remove()">\u00D7</button>\n' +
          '            </div>';
      }
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
}
