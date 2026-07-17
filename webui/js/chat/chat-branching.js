// ======================================================
// chat-branching.js — D1 Edit, D2 Delete, D3 Branch Nav
// ======================================================

// D1: Edit message — opens inline textarea, two save modes
var _editingMessageId = null;
var _removedAttachmentIds = [];

function editMessage(index) {
  var msg = chatMessages[index];
  _editingMessageId = msg.id;
  _removedAttachmentIds = [];
  if (!msg || isLoading) return;

  var bubble = document.querySelectorAll('.msg')[index];
  if (!bubble) return;

  // Use mock's pre-rendered .msg-edit-ui — just add .editing class
  bubble.classList.add('editing');
  var textarea = bubble.querySelector('.msg-edit-textarea');
  if (textarea) { textarea.value = msg.content || ''; textarea.focus(); }

  // Wire buttons (use onclick to replace any previous handler)
  var cancelBtn = bubble.querySelector('.cancel-edit');
  if (cancelBtn) cancelBtn.onclick = function() { bubble.classList.remove('editing'); };

  var overwriteBtn = bubble.querySelector('.save-overwrite');
  if (overwriteBtn) overwriteBtn.onclick = function() {
    var v = textarea.value.trim(); if (!v) return;
    commitEdit(index, msg.id, v, 'overwrite');
    bubble.classList.remove('editing');
  };

  var branchBtn = bubble.querySelector('.save-branch');
  if (branchBtn) branchBtn.onclick = function() {
    var v = textarea.value.trim(); if (!v) return;
    commitEdit(index, msg.id, v, 'branch');
    bubble.classList.remove('editing');
  };

}

// Module-level variables for edit attachments (kept for commitEdit compatibility)
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

  _showConfirm('Delete this message? This removes it from the current view but data is preserved.', function() {
    // Record undo state before deleting
    recordUndo('delete', msg.id, { content: msg.content, role: msg.role });
    window.chrome.webview.postMessage(JSON.stringify({ action: 'deleteMessage', id: msg.id }));
  });
}

// D3: Switch branch
function switchBranch(msgId, direction) {
  window.chrome.webview.postMessage(JSON.stringify({
    action: 'switchBranch',
    id: msgId,
    direction: direction
  }));
}

