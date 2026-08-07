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

  // Use the pre-rendered .msg-edit-ui — just add the .editing class
  bubble.classList.add('editing');
  var textarea = bubble.querySelector('.msg-edit-textarea');
  if (textarea) { textarea.value = msg.content || ''; textarea.focus(); }

  // Wire buttons (use onclick to replace any previous handler)
  var cancelBtn = bubble.querySelector('.cancel-edit');
  if (cancelBtn) cancelBtn.onclick = function() {
    // Bug #49: canceling an edit must roll back deferred attachment removals
    // and clear the edit state - otherwise attachments stay hidden in the UI
    // while their DB rows survive (and get sent anyway), and later attachment
    // delete clicks keep deferring instead of deleting.
    bubble.classList.remove('editing');
    _removedAttachmentIds.forEach(function(attId) {
      var delBtn = bubble.querySelector('[data-attachment-id="' + attId + '"]');
      if (delBtn) {
        var wrapper = delBtn.closest('.msg-attachment-image, .msg-attachment-file');
        if (wrapper) wrapper.style.display = '';
      }
    });
    _removedAttachmentIds = [];
    _editingMessageId = null;
  };

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

function commitEdit(index, msgId, newContent, mode) {
  var payload = { id: msgId, content: newContent, mode: mode };
  if (_removedAttachmentIds.length > 0) {
    payload.removedAttachmentIds = _removedAttachmentIds.slice();
  }
  _editingMessageId = null;
  _removedAttachmentIds = [];
  Ipc.postToHost('editMessage', payload);
}

// Fork chat at a specific message — creates a copy thread up to that point
function forkChat(index) {
  var msg = chatMessages[index];
  if (!msg || isLoading) return;
  Ipc.postToHost('forkChat', { id: msg.id });
}

// D2: Delete message
function deleteMessage(index) {
  var msg = chatMessages[index];
  if (!msg || isLoading) return;

  _showChatConfirm('Delete this message? This permanently deletes the message and cannot be undone.', function() {
    Ipc.postToHost('deleteMessage', { id: msg.id });
  });
}

// D3: Switch branch
function switchBranch(msgId, direction) {
  Ipc.postToHost('switchBranch', { id: msgId, direction: direction });
}

