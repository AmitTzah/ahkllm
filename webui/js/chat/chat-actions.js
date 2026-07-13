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
function _createMoreDropdown(items) {
  var wrapper = document.createElement('span');
  wrapper.className = 'more-dropdown';

  var toggleBtn = _iconBtn('\u22EF', 'More actions', function() {});
  toggleBtn.classList.add('more-toggle');

  // Toggle menu on click
  toggleBtn.addEventListener('click', function(e) {
    e.stopPropagation();
    var menu = wrapper.querySelector('.more-menu');
    var isOpen = menu.style.display === 'block';
    // Close all other open menus first
    document.querySelectorAll('.more-menu').forEach(function(m) {
      m.style.display = 'none';
    });
    menu.style.display = isOpen ? 'none' : 'block';
  });

  var menu = document.createElement('div');
  menu.className = 'more-menu';
  menu.style.display = 'none';

  items.forEach(function(item) {
    var itemBtn = document.createElement('button');
    itemBtn.className = 'more-menu-item';
    itemBtn.textContent = item.label;
    itemBtn.addEventListener('click', function(e) {
      e.stopPropagation();
      item.action();
      menu.style.display = 'none';
    });
    menu.appendChild(itemBtn);
  });

  wrapper.appendChild(toggleBtn);
  wrapper.appendChild(menu);
  return wrapper;
}

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
  // --- USER MESSAGE ACTIONS ---
  if (msg.role === 'user') {
    var copyBtn = _iconBtn('\uD83D\uDCCB', 'Copy', function() {
      copySingleMessage(index);
    });
    copyBtn.dataset.action = 'copy';
    actionsContainer.appendChild(copyBtn);

    actionsContainer.appendChild(_iconBtn('\u270F\uFE0F', 'Edit', function() {
      editMessage(index);
    }));

    _addBranchNav(actionsContainer, msg);

    var tokenIcon = createTokenInfoIcon(msg);
    if (tokenIcon) actionsContainer.appendChild(tokenIcon);

    // Hidden actions: Quote, Fork, Delete
    var moreItems = [
      { label: '\uD83D\uDCAC Quote', action: function() { quoteMessage(index); } },
      { label: '\u21AA Fork',  action: function() { forkChat(index); } },
      { label: '\uD83D\uDDD1\uFE0F Delete', action: function() { deleteMessage(index); } }
    ];
    actionsContainer.appendChild(_createMoreDropdown(moreItems));
    return;
  }

  // --- ASSISTANT MESSAGE ACTIONS ---
  var copyBtn = _iconBtn('\uD83D\uDCCB', 'Copy', function() {
    copySingleMessage(index);
  });
  copyBtn.dataset.action = 'copy';
  actionsContainer.appendChild(copyBtn);

  actionsContainer.appendChild(_iconBtn('\uD83D\uDD04', 'Retry', function() {
    retryLastAssistantMessage(msg.id);
  }));

  actionsContainer.appendChild(_iconBtn('\u270F\uFE0F', 'Edit', function() {
    editMessage(index);
  }));

  // Feedback buttons
  var upBtn = _iconBtn('\uD83D\uDC4D', 'Thumbs up', function() {
    var rating = msg.feedback === 1 ? 0 : 1;
    setFeedback(msg.id, rating, upBtn, downBtn, msg);
  });
  if (msg.feedback === 1) upBtn.classList.add('feedback-active-up');

  var downBtn = _iconBtn('\uD83D\uDC4E', 'Thumbs down', function() {
    var rating = msg.feedback === -1 ? 0 : -1;
    setFeedback(msg.id, rating, upBtn, downBtn, msg);
  });
  if (msg.feedback === -1) downBtn.classList.add('feedback-active-down');

  actionsContainer.appendChild(upBtn);
  actionsContainer.appendChild(downBtn);

  _addBranchNav(actionsContainer, msg);

  var tokenIcon = createTokenInfoIcon(msg);
  if (tokenIcon) actionsContainer.appendChild(tokenIcon);

  // Hidden actions: Quote, Fork, Delete
  var moreItems = [
    { label: '\uD83D\uDCAC Quote', action: function() { quoteMessage(index); } },
    { label: '\u21AA Fork',  action: function() { forkChat(index); } },
    { label: '\uD83D\uDDD1\uFE0F Delete', action: function() { deleteMessage(index); } }
  ];
  actionsContainer.appendChild(_createMoreDropdown(moreItems));
}
