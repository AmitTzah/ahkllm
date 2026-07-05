// ======================================================
// chat-branching.js — D1 Edit, D2 Delete, D3 Branch Nav, D4 Tree Viz
// ======================================================

// D1: Edit message — opens inline textarea, two save modes
function editMessage(index) {
  var msg = chatMessages[index];
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
    contentDiv.innerHTML = md.render(msg.content);
    contentDiv.removeChild(textarea);
    if (actions) actions.style.display = 'flex';
    editActions.remove();
  });

  editActions.appendChild(saveBtn);
  editActions.appendChild(branchBtn);
  editActions.appendChild(cancelBtn);
  contentDiv.appendChild(editActions);
}

function commitEdit(index, msgId, newContent, mode) {
  // Record undo state before sending
  var msg = chatMessages[index];
  if (msg && mode === 'overwrite') {
    recordUndo('edit', msgId, { content: msg.content }, { content: newContent });
  }

  window.chrome.webview.postMessage(JSON.stringify({
    action: 'editMessage',
    id: msgId,
    content: newContent,
    mode: mode
  }));
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

// Update branch info badge after branch switch
function updateBranchInfo(data) {
  var container = document.getElementById('chat-messages');
  if (!container) return;
  var badge = container.querySelector('.branch-badge[data-msg-id="' + data.msgId + '"]');
  if (badge) {
    var label = badge.querySelector('.branch-label');
    if (label) label.textContent = data.siblingInfo.index + '/' + data.siblingInfo.total;
  }
}