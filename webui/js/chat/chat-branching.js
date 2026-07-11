// ======================================================
// chat-branching.js — D1 Edit, D2 Delete, D3 Branch Nav, D4 Tree Viz
// ======================================================

// D1: Edit message — opens inline textarea, two save modes
var _editingMessageId = null;
var _removedAttachmentIds = [];

function editMessage(index) {
  var msg = chatMessages[index];
  // Track editing state for deferred attachment removal
  _editingMessageId = msg.id;
  _removedAttachmentIds = [];
  if (!msg || isLoading) return;

  var container = document.getElementById('chat-messages');
  var bubble = container.querySelectorAll('.chat-message')[index];
  if (!bubble) return;

  // Get raw content (strip markdown — just use plain text)
  var contentDiv = bubble.querySelector('.message-content');
  var rawText = msg.content;

  // Replace content with textarea
  contentDiv.innerHTML = '';
  var textarea = document.createElement('textarea');
  textarea.className = 'edit-textarea';
  textarea.value = rawText;
  textarea.style.cssText = 'width:100%;min-height:100px;font-family:inherit;font-size:0.95rem;padding:0.5rem;border-radius:0.5rem;border:1px solid var(--bs-border-color);background:var(--bs-tertiary-bg);color:var(--bs-body-color);';
  contentDiv.appendChild(textarea);

  // Action buttons
  var actions = bubble.querySelector('.message-actions');
  if (actions) actions.style.display = 'none';

  var editActions = document.createElement('div');
  editActions.className = 'edit-actions';
  editActions.style.cssText = 'display:flex;gap:0.5rem;margin-top:0.5rem;';

  var saveBtn = document.createElement('button');
  saveBtn.textContent = '💾 Save (Overwrite)';
  saveBtn.style.cssText = 'padding:4px 12px;border-radius:0.25rem;border:1px solid var(--bs-border-color);cursor:pointer;background:var(--bs-primary);color:white;font-size:0.8rem;';
  saveBtn.addEventListener('click', function() {
    var newContent = textarea.value.trim();
    if (!newContent) return;
    // If nothing changed and no new attachments, just close the edit window (same as Cancel)
    if (newContent === msg.content && _editAttachments.length === 0 && _removedAttachmentIds.length === 0) {
      _editingMessageId = null;
      _removedAttachmentIds = [];
      contentDiv.innerHTML = md.render(msg.content);
      // Restore any attachments that were hidden during edit
      var bubble = container.querySelectorAll('.chat-message')[index];
      if (bubble) {
        var hidden = bubble.querySelectorAll('.msg-attachment-image[style*="display: none"], .msg-attachment-file[style*="display: none"]');
        for (var h = 0; h < hidden.length; h++) {
          hidden[h].style.display = '';
        }
      }
      if (actions) actions.style.display = 'flex';
      editActions.remove();
      return;
    }
    commitEdit(index, msg.id, newContent, 'overwrite');
  });

  var branchBtn = document.createElement('button');
  branchBtn.textContent = '⑂ Save as Branch';
  branchBtn.style.cssText = 'padding:4px 12px;border-radius:0.25rem;border:1px solid var(--bs-border-color);cursor:pointer;background:var(--bs-tertiary-bg);color:var(--bs-body-color);font-size:0.8rem;';
  branchBtn.addEventListener('click', function(e) {
    e.stopPropagation();
    var newContent = textarea.value.trim();
    if (!newContent) return;
    commitEdit(index, msg.id, newContent, 'branch');
  });

  var cancelBtn = document.createElement('button');
  cancelBtn.textContent = '✖ Cancel';
  cancelBtn.style.cssText = 'padding:4px 12px;border-radius:0.25rem;border:1px solid var(--bs-border-color);cursor:pointer;background:var(--bs-body-bg);color:var(--bs-secondary-color);font-size:0.8rem;';
  cancelBtn.addEventListener('click', function() {
    _editingMessageId = null;
    _removedAttachmentIds = [];
    contentDiv.innerHTML = md.render(msg.content);
    // Restore any attachments that were hidden during edit
    var bubble = container.querySelectorAll('.chat-message')[index];
    if (bubble) {
      var hidden = bubble.querySelectorAll('.msg-attachment-image[style*="display: none"], .msg-attachment-file[style*="display: none"]');
      for (var h = 0; h < hidden.length; h++) {
        hidden[h].style.display = '';
      }
    }
    if (actions) actions.style.display = 'flex';
    editActions.remove();
  });

  editActions.appendChild(saveBtn);
  editActions.appendChild(branchBtn);

  // Attach file button for editing — uses a dedicated file input
  var editFileInput = document.createElement('input');
  editFileInput.type = 'file';
  editFileInput.accept = 'image/*,.pdf,.docx,.txt,.md,.py,.js,.json,.xml,.csv,.ini,.cfg,.yaml,.yml,.log,.html,.css,.sql,.bat,.ps1,.sh,.java,.c,.cpp,.h,.rs,.go,.ts,.tsx,.jsx,.toml';
  editFileInput.multiple = true;
  editFileInput.style.display = 'none';
  contentDiv.appendChild(editFileInput);

  var attachBtn = document.createElement('button');
  attachBtn.textContent = '📎 Attach';
  attachBtn.style.cssText = 'padding:4px 12px;border-radius:0.25rem;border:1px solid var(--bs-border-color);cursor:pointer;background:var(--bs-tertiary-bg);color:var(--bs-body-color);font-size:0.8rem;';
  attachBtn.addEventListener('click', function() { editFileInput.click(); });
  editActions.appendChild(attachBtn);

  editActions.appendChild(cancelBtn);
  contentDiv.appendChild(editActions);

  // Track attachments and extraction promises
  _editAttachments = [];
  _editExtractPromises = [];
  var editAttBar = document.createElement('div');
  editAttBar.style.cssText = 'display:flex;flex-wrap:wrap;gap:0.25rem;margin-top:0.25rem;';
  contentDiv.insertBefore(editAttBar, editActions);

  // Helper to add file to edit attachments
  function addEditAttachment(file) {
    if (_editAttachments.length >= 10) { showErrorBanner('Max 10 attachments'); return; }
    if (file.size > MAX_FILE_SIZE) { showErrorBanner('File too large'); return; }
    var reader = new FileReader();
    reader.onload = (function(f, fname, fmime) {
      return function(e) {
        var arr = new Uint8Array(e.target.result);
        var bin = ''; for (var b = 0; b < arr.byteLength; b++) bin += String.fromCharCode(arr[b]);
        var b64 = btoa(bin);
        var attType = getAttachmentTypeFromMime(fmime, fname);
        var att = { type: attType, filename: fname, mimeType: fmime, base64: b64, size: f.size, extractedText: '', contentHash: '' };
        // Compute SHA-256 for content-addressable dedup (same as send flow)
        var hashPromise = crypto.subtle.digest('SHA-256', e.target.result.slice(0)).then(function(hashBuffer) {
          var hashArray = Array.from(new Uint8Array(hashBuffer));
          att.contentHash = hashArray.map(function(b) { return b.toString(16).padStart(2, '0'); }).join('');
        }).catch(function() { att.contentHash = ''; });
        _editHashPromises.push(hashPromise);
        // Extract text for PDF/DOCX
        if (attType === 'pdf' && typeof pdfjsLib !== 'undefined') {
            try {
                var p = pdfjsLib.getDocument({ data: e.target.result.slice(0) }).promise.then(function(pdf) {
                    var pages = []; for (var p = 1; p <= pdf.numPages; p++) pages.push(pdf.getPage(p).then(function(page) {
                        return page.getTextContent().then(function(tc) { return tc.items.map(function(it) { return it.str; }).join(' '); });
                    }));
                    return Promise.all(pages);
                }).then(function(texts) {
                    att.extractedText = texts.join('\n\n') || '(no text extracted)';
                    if (att.badge) att.badge.title = 'Extracted: ' + att.extractedText.substring(0, 100);
                }).catch(function() { att.extractedText = '(no text extracted)'; });
                _editExtractPromises.push(p);
            } catch(ex) { att.extractedText = '(no text extracted)'; }
        } else if (attType === 'docx' && typeof mammoth !== 'undefined') {
            try {
                var p = mammoth.extractRawText({ arrayBuffer: e.target.result }).then(function(r) {
                    att.extractedText = r.value || '(no text extracted)';
                    if (att.badge) att.badge.title = 'Extracted: ' + att.extractedText.substring(0, 100);
                }).catch(function() { att.extractedText = '(no text extracted)'; });
                _editExtractPromises.push(p);
            } catch(ex) { att.extractedText = '(no text extracted)'; }
        }
        _editAttachments.push(att);
        var badge = document.createElement('span');
        badge.style.cssText = 'display:inline-flex;align-items:center;gap:0.25rem;padding:0.15rem 0.4rem;border:1px solid var(--bs-border-color);border-radius:0.25rem;font-size:0.7rem;background:var(--bs-body-bg);cursor:pointer;';
        if (attType === 'image' && b64) {
            var thumb = document.createElement('img');
            thumb.src = 'data:' + fmime + ';base64,' + b64;
            thumb.style.cssText = 'width:32px;height:32px;object-fit:cover;border-radius:3px;';
            badge.appendChild(thumb);
        }
        var label = document.createElement('span');
        label.textContent = (attType === 'image' ? '' : '\uD83D\uDCCE ') + fname + ' \u00D7';
        badge.appendChild(label);
        badge.onclick = function() { var idx = _editAttachments.indexOf(att); if (idx >= 0) { _editAttachments.splice(idx, 1); badge.remove(); } };
        att.badge = badge;  // store ref for extraction callback
        editAttBar.appendChild(badge);
      };
    })(file, file.name, file.type);
    reader.readAsArrayBuffer(file);
  }

  // File input change
  editFileInput.addEventListener('change', function() {
    for (var f = 0; f < editFileInput.files.length; f++) addEditAttachment(editFileInput.files[f]);
    editFileInput.value = '';
  });

  // Drag-drop on edit area
  contentDiv.addEventListener('dragover', function(e) { e.preventDefault(); });
  contentDiv.addEventListener('drop', function(e) {
    e.preventDefault();
    var files = e.dataTransfer.files;
    for (var f = 0; f < files.length; f++) addEditAttachment(files[f]);
  });

  // Paste images into edit textarea
  textarea.addEventListener('paste', function(e) {
    var items = e.clipboardData && e.clipboardData.items;
    if (!items) return;
    for (var i = 0; i < items.length; i++) {
      if (items[i].type.indexOf('image') === 0) {
        e.preventDefault();
        addEditAttachment(items[i].getAsFile());
        return;
      }
    }
  });
}

// Module-level variables for edit attachments
var _editAttachments = [];
var _editExtractPromises = [];
var _editHashPromises = [];

function commitEdit(index, msgId, newContent, mode) {
  // Wait for any pending PDF/DOCX extractions AND SHA-256 hash computations to complete
  var allPromises = _editExtractPromises.concat(_editHashPromises);
  var doCommit = function() {
    var msg = chatMessages[index];
    if (msg && mode === 'overwrite') {
      recordUndo('edit', msgId, { content: msg.content }, { content: newContent });
    }
    var payload = { action: 'editMessage', id: msgId, content: newContent, mode: mode };
    if (_removedAttachmentIds.length > 0) {
      payload.removedAttachmentIds = _removedAttachmentIds.slice();
    }
    if (_editAttachments.length > 0) {
      // Include contentHash for content-addressable dedup
      payload.attachments = _editAttachments.map(function(a) {
        return { type: a.type, filename: a.filename, mimeType: a.mimeType, base64: a.base64, size: a.size, extractedText: a.extractedText || '', contentHash: a.contentHash || '' };
      });
      _editAttachments = [];
    }
    _editExtractPromises = [];
    _editHashPromises = [];
    _editingMessageId = null;
    _removedAttachmentIds = [];
    window.chrome.webview.postMessage(JSON.stringify(payload));
  };

  if (allPromises.length > 0) {
    Promise.all(allPromises).then(function() { doCommit(); }).catch(function() { doCommit(); });
  } else {
    doCommit();
  }
}

// Fork chat at a specific message — creates a copy thread up to that point
function forkChat(index) {
  var msg = chatMessages[index];
  if (!msg || isLoading) return;
  window.chrome.webview.postMessage(JSON.stringify({ action: 'forkChat', id: msg.id }));
}

// D2: Delete message
function deleteMessage(index) {
  var msg = chatMessages[index];
  if (!msg || isLoading) return;

  if (!confirm('Delete this message? This removes it from the current view but data is preserved.')) return;

  // Record undo state before deleting
  recordUndo('delete', msg.id, { content: msg.content, role: msg.role });

  window.chrome.webview.postMessage(JSON.stringify({ action: 'deleteMessage', id: msg.id }));
}

// D3: Switch branch
function switchBranch(msgId, direction) {
  window.chrome.webview.postMessage(JSON.stringify({
    action: 'switchBranch',
    id: msgId,
    direction: direction
  }));
}

// D4: Chat tree visualization (modal)
var treeModalOpen = false;

function toggleTreeModal() {
  if (treeModalOpen) {
    closeTreeModal();
  } else {
    openTreeModal();
  }
}

function openTreeModal() {
  var existing = document.getElementById('tree-modal');
  if (existing) existing.remove();

  var modal = document.createElement('div');
  modal.id = 'tree-modal';
  modal.className = 'tree-modal';
  modal.innerHTML = '<div class="tree-modal-content"><h4>🌳 Chat Tree</h4><div id="tree-container"></div><button id="tree-close-btn">Close</button></div>';
  document.body.appendChild(modal);

  document.getElementById('tree-close-btn').addEventListener('click', closeTreeModal);
  modal.addEventListener('click', function(e) {
    if (e.target === modal) closeTreeModal();
  });

  treeModalOpen = true;
}

function closeTreeModal() {
  var modal = document.getElementById('tree-modal');
  if (modal) modal.remove();
  treeModalOpen = false;
}

// Called by AHK with tree data
function renderChatTree(tree) {
  var container = document.getElementById('tree-container');
  if (!container) return;

  if (!tree || tree.length === 0) {
    container.innerHTML = '<p style="color:var(--bs-secondary-color);">No messages yet.</p>';
    return;
  }

  container.innerHTML = '';
  for (var i = 0; i < tree.length; i++) {
    container.appendChild(renderTreeNode(tree[i], 0));
  }
}

function renderTreeNode(node, depth) {
  var div = document.createElement('div');
  div.className = 'tree-node';
  div.style.cssText = 'margin-left:' + (depth * 20) + 'px;padding:6px 10px;margin-bottom:4px;border-radius:0.5rem;cursor:pointer;border:1px solid var(--bs-border-color);';

  var roleIcon = { user: '👤', assistant: '🤖', system: '⚙️' };
  var preview = node.content_preview || '(empty)';
  if (preview.length > 60) preview = preview.substring(0, 60) + '...';

  div.innerHTML = '<span style="font-size:0.8rem;">' + (roleIcon[node.role] || '') + ' <strong>' + node.role + '</strong></span><br><span style="font-size:0.75rem;color:var(--bs-secondary-color);">' + preview + '</span>';

  if (node.sibling_group) {
    div.innerHTML += ' <span style="font-size:0.65rem;background:var(--bs-primary);color:white;padding:1px 6px;border-radius:1rem;">' + (node.sibling_index + 1) + '</span>';
  }

  div.addEventListener('click', function(e) {
    e.stopPropagation();
    // Navigate to this specific message (set as active leaf)
    window.chrome.webview.postMessage(JSON.stringify({
      action: 'sidebarAction',
      subAction: 'navigateToMessage',
      messageId: node.id
    }));
    closeTreeModal();
  });

  // Render children
  for (var i = 0; i < node.children.length; i++) {
    div.appendChild(renderTreeNode(node.children[i], depth + 1));
  }

  return div;
}

// Update branch info label after branch switch
function updateBranchInfo(data) {
  var container = document.getElementById('chat-messages');
  if (!container) return;
  // Find the message bubble and its inline branch label
  var bubble = container.querySelector('.chat-message[data-msg-id="' + data.msgId + '"]');
  if (bubble) {
    var label = bubble.querySelector('.branch-label-inline');
    if (label) label.textContent = data.siblingInfo.index + '/' + data.siblingInfo.total;
  }
}