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
  // Bug #214: a branch switch (or any updateChatView rebuild) while a request
  // is in flight must NOT re-enable the composer - a second send would
  // overwrite the shared requestParams["_stream*"] state, orphaning the first
  // billed response. Keep the composer in Stop mode for the whole in-flight
  // window (isLoading covers the pre-stream phase, streamState.active the
  // streaming phase); only re-enable when idle.
  var requestInFlight = isLoading || (typeof streamState !== 'undefined' && streamState.active);
  setChatButtonsEnabled(!requestInFlight);
  if (typeof renderNavList === 'function') renderNavList();
  if (prevScrollHeight > 0) {
    var scrollEl = document.getElementById('chat-scroll') || container.parentElement;
    if (scrollEl) scrollEl.scrollTop = Math.round(scrollEl.scrollHeight * (prevScrollTop / (scrollEl.scrollHeight || 1)));
  }
}


// Normalize message line endings before markdown rendering. Bugs #222/#224:
// the old code only converted runs of 3+ newlines to a literal <br> tag -
// which html:false markdown-it ESCAPES into "&lt;br&gt;" - and left single
// newlines as markdown soft breaks that the .msg-content CSS collapsed to
// spaces, so single-newline paragraph breaks rendered as one block. markdown-it
// is now configured with breaks:true (soft break -> <br>), so the only
// normalization needed here is CRLF/CR -> LF.
function _prepUserContent(content) {
  return (content || '').replace(/\r\n/g, '\n').replace(/\r/g, '\n');
}

function _buildMsgBubble(roleClass, msgId, authorName, metaText, contentHtml, middleHtml, editUiHtml) {
  return '        <div class="msg ' + roleClass + '"' + (msgId ? ' data-msg-id="' + msgId + '"' : '') + '>\n' +
    '          <div class="msg-body">\n' +
    '            <div class="msg-head">\n' +
    '              <span class="msg-author">' + escHtml(authorName) + '</span>\n' +
    '              <span class="msg-meta">' + metaText + '</span>\n' +
    '            </div>\n' +
    middleHtml +
    '            <div class="msg-content">' + contentHtml + '</div>\n' +
    (editUiHtml ? '\n' + editUiHtml + '\n' : '') +
    '            <div class="msg-actions"></div>\n' +
    '          </div>\n' +
    '        </div>';
}

function createMessageBubble(msg, index) {
  var msgId = msg.id || '';
  var metaText = _buildMetaText(msg);
  var role = msg.role;

  var roleClass, authorName, contentHtml, middleHtml, editUiHtml, isSearchContext = false;
  if (role === 'user') {
    // Web-search context messages (persisted as plain user-role text so API
    // history round-trips without schema changes) render as a muted,
    // collapsible card: the query in the header, the results hidden until
    // the user expands them.
    isSearchContext = typeof msg.content === 'string' && msg.content.indexOf('[Web search:') === 0;
    roleClass = isSearchContext ? 'you search-context' : 'you';
    authorName = isSearchContext ? 'Web Search' : 'You';
    contentHtml = isSearchContext
      ? _buildSearchContextHtml(_parseSearchContext(msg.content))
      : md.render(_prepUserContent(msg.content));
    middleHtml = _buildAttachmentHtml(msg);
    editUiHtml = _buildEditUiHtml(msg);
  } else if (role === 'assistant') {
    roleClass = 'bot';
    authorName = msg.model || 'Assistant';
    // Bug #222: assistant content must get the same line-ending normalization
    // as user content - markdown-it's breaks:true then keeps single-newline
    // paragraph breaks visible instead of collapsing them into one block.
    contentHtml = md.render(_prepUserContent(msg.content));
    middleHtml = _buildReasoningHtml(msg);
    editUiHtml = _buildEditUiHtml(msg);
  } else {
    roleClass = 'system';
    authorName = 'System Prompt';
    contentHtml = md.render(msg.content || '');
    middleHtml = '';
    editUiHtml = '';
  }

  var template = document.createElement('div');
  template.innerHTML = _buildMsgBubble(roleClass, msgId, authorName, metaText, contentHtml, middleHtml, editUiHtml);
  var bubble = template.firstElementChild;

  if (isSearchContext) _wireSearchCardToggle(bubble);

  if (role !== 'system') {
    var actionsDiv = bubble.querySelector('.msg-actions');
    if (actionsDiv) addMessageActions(actionsDiv, msg, index);
  }

  if (typeof lucide !== 'undefined') lucide.createIcons();
  return bubble;
}

// Split a persisted "[Web search: <query>]" message into its query and
// results body (the marker line is replaced by the card header).
function _parseSearchContext(content) {
  var text = String(content || '');
  var query = '';
  var results = text;
  var m = /^\[Web search: ([^\]]*)\](?:\r?\n)*/.exec(text);
  if (m) {
    query = m[1];
    results = text.slice(m[0].length);
  }
  return { query: query, results: results };
}

// Collapsible search-result card: header shows the query, the results body
// is hidden by default and revealed by the toggle.
function _buildSearchContextHtml(sc) {
  var q = escHtml(sc.query || '');
  var body = md.render(_prepUserContent(sc.results || ''));
  return '<div class="search-card">' +
    '<button type="button" class="search-card-toggle" aria-expanded="false" title="Show or hide the search results">' +
    '<i data-lucide="search" style="width:14px;height:14px;flex-shrink:0;"></i>' +
    '<span class="search-card-title">Searched the web for: <strong>' + q + '</strong></span>' +
    '<i data-lucide="chevron-down" class="search-card-caret" style="width:14px;height:14px;flex-shrink:0;"></i>' +
    '</button>' +
    '<div class="search-card-results" hidden>' + body + '</div>' +
    '</div>';
}

// Toggle the card's results on click and keep aria-expanded in sync.
function _wireSearchCardToggle(bubble) {
  var toggle = bubble.querySelector('.search-card-toggle');
  if (!toggle) return;
  toggle.addEventListener('click', function() {
    var card = toggle.closest('.search-card');
    var results = card ? card.querySelector('.search-card-results') : null;
    var expanded = toggle.getAttribute('aria-expanded') === 'true';
    toggle.setAttribute('aria-expanded', String(!expanded));
    if (results) results.hidden = expanded;
  });
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
