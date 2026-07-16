// ======================================================
// chat-actions.js — Message action button creation
// Extracted from chat-render.js. Used by createMessageBubble
// and addStreamingActions (stream.js).
// ======================================================

// Create a minimal icon-only action button
function _iconBtn(icon, title, onClick) {
  var btn = document.createElement('button');
  btn.className = 'msg-action-btn';
  btn.innerHTML = icon;
  btn.title = title;
  btn.addEventListener('click', function(e) {
    e.stopPropagation();
    onClick();
  });
  return btn;
}

// Create the "More" dropdown menu
// Add branch nav when multiple branches exist
function _addBranchNav(container, msg) {
  var totalBranches = msg.siblingInfo ? msg.siblingInfo.total : 1;
  if (totalBranches <= 1) return;

  container.appendChild(_iconBtn('\u25C0', 'Previous branch', function() {
    switchBranch(msg.id, -1);
  }));

  var label = document.createElement('span');
  label.className = 'branch-label-inline';
  label.textContent = (msg.siblingInfo ? msg.siblingInfo.index : 1) + '/' + totalBranches;
  container.appendChild(label);

  container.appendChild(_iconBtn('\u25B6', 'Next branch', function() {
    switchBranch(msg.id, 1);
  }));
}

// Main entry point — called by createMessageBubble (chat-render.js)
// and addStreamingActions (stream.js)
function addMessageActions(actionsContainer, msg, index) {
  // --- USER: branch-nav | copy | edit | quote | fork | delete | token ---
  if (msg.role === 'user') {
    _addBranchNav(actionsContainer, msg);

    actionsContainer.appendChild(_iconBtn('<i data-lucide="copy"></i>', 'Copy', function() { copySingleMessage(index); }));
    actionsContainer.appendChild(_iconBtn('<i data-lucide="edit-2"></i>', 'Edit', function() { editMessage(index); }));
    actionsContainer.appendChild(_iconBtn('<i data-lucide="message-square-quote"></i>', 'Quote', function() { quoteMessage(index); }));
    actionsContainer.appendChild(_iconBtn('<i data-lucide="git-branch"></i>', 'Fork', function() { forkChat(index); }));
    actionsContainer.appendChild(_iconBtn('<i data-lucide="trash-2"></i>', 'Delete', function() { deleteMessage(index); }));

    var tokenIcon = createTokenInfoIcon(msg, index);
    if (tokenIcon) actionsContainer.appendChild(tokenIcon);
    return;
  }

  // --- ASSISTANT: branch-nav | copy | retry | edit | quote | fork | delete | token ---
  _addBranchNav(actionsContainer, msg);

  actionsContainer.appendChild(_iconBtn('<i data-lucide="copy"></i>', 'Copy', function() { copySingleMessage(index); }));
  actionsContainer.appendChild(_iconBtn('<i data-lucide="refresh-cw"></i>', 'Retry', function() { retryLastAssistantMessage(msg.id); }));
  actionsContainer.appendChild(_iconBtn('<i data-lucide="edit-2"></i>', 'Edit', function() { editMessage(index); }));
  actionsContainer.appendChild(_iconBtn('<i data-lucide="message-square-quote"></i>', 'Quote', function() { quoteMessage(index); }));
  actionsContainer.appendChild(_iconBtn('<i data-lucide="git-branch"></i>', 'Fork', function() { forkChat(index); }));
  actionsContainer.appendChild(_iconBtn('<i data-lucide="trash-2"></i>', 'Delete', function() { deleteMessage(index); }));

  var tokenIcon = createTokenInfoIcon(msg, index);
  if (tokenIcon) actionsContainer.appendChild(tokenIcon);
}
