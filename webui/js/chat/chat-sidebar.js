// ======================================================
// chat-sidebar.js — D6: Chat navigation bar + thread list sidebar
// ======================================================

var sidebarOpen = false;

function toggleSidebar() {
  if (sidebarOpen) {
    closeSidebar();
  } else {
    openSidebar();
  }
}

function openSidebar() {
  var sidebar = document.getElementById('chat-sidebar');
  if (!sidebar) return;
  sidebar.style.display = 'flex';
  sidebarOpen = true;

  // Load thread list and trash
  window.chrome.webview.postMessage(JSON.stringify({ action: 'sidebarAction', subAction: 'loadThreadList' }));
  window.chrome.webview.postMessage(JSON.stringify({ action: 'sidebarAction', subAction: 'loadTrashList' }));
}

function modelEmoji(model) {
  if (!model) return '🤖';
  var m = model.toLowerCase();
  if (m.indexOf('deepseek') !== -1) return '🐋';
  if (m.indexOf('gpt') !== -1 || m.indexOf('o1') !== -1 || m.indexOf('o3') !== -1) return '🧠';
  if (m.indexOf('claude') !== -1) return '🎭';
  if (m.indexOf('gemini') !== -1) return '💎';
  return '🤖';
}

function closeSidebar() {
  var sidebar = document.getElementById('chat-sidebar');
  if (!sidebar) return;
  sidebar.style.display = 'none';
  sidebarOpen = false;
}

// Attach inline rename via double-click to a thread title span.
function _attachInlineRename(titleSpan, titleDiv, thread) {
  titleSpan.addEventListener('dblclick', function(e) {
    e.stopPropagation();
    var input = document.createElement('input');
    input.type = 'text';
    input.value = thread.title || '';
    input.style.cssText = 'width:140px;font-size:0.85rem;background:var(--bs-body-bg);color:var(--bs-body-color);border:1px solid var(--bs-primary);border-radius:3px;padding:1px 4px;';

    var finishRename = function() {
      var newTitle = input.value.trim();
      if (newTitle && newTitle !== (thread.title || '')) {
        window.chrome.webview.postMessage(JSON.stringify({
          action: 'sidebarAction',
          subAction: 'renameThread',
          threadId: thread.id,
          title: newTitle
        }));
      }
      titleSpan.style.display = '';
      input.remove();
    };

    input.addEventListener('blur', finishRename);
    input.addEventListener('keydown', function(ev) {
      if (ev.key === 'Enter') { finishRename(); }
      if (ev.key === 'Escape') { input.remove(); titleSpan.style.display = ''; }
    });

    titleSpan.style.display = 'none';
    titleDiv.insertBefore(input, titleSpan);
    input.focus();
    input.select();
  });
}

// Called by AHK with thread list data
function loadThreadList(threads) {
  var list = document.getElementById('thread-list');
  if (!list) return;

  list.innerHTML = '';

  if (!threads || threads.length === 0) {
    list.innerHTML = '<div style="padding:1rem;color:var(--bs-secondary-color);font-size:0.85rem;">No chats yet.</div>';
    return;
  }

  for (var i = 0; i < threads.length; i++) {
    (function(t) {
      var item = document.createElement('div');
      item.className = 'thread-item';
      if (t.id === activeThreadId) item.classList.add('active');
      item.style.cssText = 'padding:0.75rem;margin:0.25rem 0.5rem;border-radius:0.5rem;cursor:pointer;font-size:0.85rem;border:1px solid transparent;';

      var date = t.updated_at || t.created_at || '';
      if (date.length > 16) date = date.substring(0, 16);

      // Title with inline editing
      var titleDiv = document.createElement('div');
      titleDiv.style.cssText = 'font-weight:600;display:flex;align-items:center;gap:4px;';
      
      var titleSpan = document.createElement('span');
      var displayTitle = t.title || 'New Chat';
      if (displayTitle.length > 30) displayTitle = displayTitle.substring(0, 30) + '...';
      var modelIcon = modelEmoji(t.model);
      titleSpan.textContent = modelIcon + ' ' + displayTitle;
      titleSpan.style.cssText = 'cursor:text;';
      
      // Inline rename: double-click title to edit
      _attachInlineRename(titleSpan, titleDiv, t);
      
      titleDiv.appendChild(titleSpan);

      // Date
      var dateDiv = document.createElement('div');
      dateDiv.style.cssText = 'font-size:0.7rem;color:var(--bs-secondary-color);';
      dateDiv.textContent = date;

      item.appendChild(titleDiv);
      item.appendChild(dateDiv);

      item.addEventListener('click', function() {
        loadThread(t.id);
      });

      // Rename button
      var renameBtn = document.createElement('button');
      renameBtn.textContent = '✏️';
      renameBtn.style.cssText = 'float:right;background:none;border:none;cursor:pointer;font-size:0.7rem;opacity:0.5;margin-left:0;';
      renameBtn.title = 'Rename';
      renameBtn.addEventListener('click', function(e) {
        e.stopPropagation();
        titleSpan.dispatchEvent(new MouseEvent('dblclick'));
      });
      item.appendChild(renameBtn);
  
      // Delete button
      var delBtn = document.createElement('button');
      delBtn.textContent = '🗑';
      delBtn.style.cssText = 'float:right;background:none;border:none;cursor:pointer;font-size:0.7rem;opacity:0.5;';
      delBtn.title = 'Delete thread';
      delBtn.addEventListener('click', function(e) {
        e.stopPropagation();
        if (confirm('Delete this chat permanently?')) {
          window.chrome.webview.postMessage(JSON.stringify({
            action: 'sidebarAction',
            subAction: 'deleteThread',
            threadId: t.id
          }));
        }
      });
      item.appendChild(delBtn);

      list.appendChild(item);
    })(threads[i]);
  }
}

// Called by AHK with trashed thread list
function loadTrashList(threads) {
  var list = document.getElementById('thread-list');
  if (!list) return;

  // Remove any existing trash section
  var existingTrash = document.getElementById('trash-section');
  if (existingTrash) existingTrash.remove();

  if (!threads || threads.length === 0) return;

  var trashSection = document.createElement('div');
  trashSection.id = 'trash-section';
  trashSection.style.cssText = 'border-top:1px solid var(--bs-border-color);margin-top:0.5rem;padding-top:0.25rem;';

  // Collapsible header
  var trashHeader = document.createElement('div');
  trashHeader.style.cssText = 'padding:0.5rem 0.75rem;font-size:0.8rem;font-weight:600;cursor:pointer;display:flex;justify-content:space-between;align-items:center;';
  trashHeader.innerHTML = '<span>🗑 Trash (' + threads.length + ')</span><span id="trash-toggle" style="font-size:0.7rem;">▼</span>';
  trashHeader.title = 'Click to toggle trash visibility';

  var trashBody = document.createElement('div');
  trashBody.style.cssText = 'display:none;max-height:200px;overflow-y:auto;';

  // Toggle collapse
  trashHeader.addEventListener('click', function() {
    var isHidden = trashBody.style.display === 'none';
    trashBody.style.display = isHidden ? 'block' : 'none';
    document.getElementById('trash-toggle').textContent = isHidden ? '▲' : '▼';
  });

  // Empty trash button
  var emptyBtn = document.createElement('button');
  emptyBtn.textContent = '🗑 Empty Trash';
  emptyBtn.style.cssText = 'width:calc(100% - 1rem);margin:0.25rem 0.5rem;padding:3px 8px;font-size:0.75rem;background:none;border:1px solid var(--bs-border-color);border-radius:4px;cursor:pointer;color:var(--bs-danger, #dc3545);';
  emptyBtn.addEventListener('click', function(e) {
    e.stopPropagation();
    if (confirm('Permanently delete ALL trashed chats?')) {
      window.chrome.webview.postMessage(JSON.stringify({ action: 'sidebarAction', subAction: 'emptyTrash' }));
    }
  });

  for (var i = 0; i < threads.length; i++) {
    (function(t) {
      var item = document.createElement('div');
      item.style.cssText = 'padding:0.4rem 0.5rem;margin:0.1rem 0.5rem;border-radius:0.4rem;font-size:0.8rem;opacity:0.6;cursor:pointer;';

      var displayTitle = t.title || 'New Chat';
      if (displayTitle.length > 25) displayTitle = displayTitle.substring(0, 25) + '...';
      
      var date = t.updated_at || t.created_at || '';
      if (date.length > 16) date = date.substring(0, 16);

      // Click to open in read-only mode
      item.addEventListener('click', function() {
        loadThread(t.id);
        // Disable chat input since thread is trashed
        var chatInput = document.getElementById('chat-input');
        if (chatInput) chatInput.disabled = true;
        var sendBtn = document.getElementById('chat-send-btn');
        if (sendBtn) sendBtn.disabled = true;
      });

      // Restore button
      var restoreBtn = document.createElement('button');
      restoreBtn.textContent = '♻';
      restoreBtn.style.cssText = 'float:right;background:none;border:none;cursor:pointer;font-size:0.7rem;margin-left:4px;opacity:0.7;';
      restoreBtn.title = 'Restore';
      restoreBtn.addEventListener('click', function(e) {
        e.stopPropagation();
        window.chrome.webview.postMessage(JSON.stringify({
          action: 'sidebarAction',
          subAction: 'restoreThread',
          threadId: t.id
        }));
      });

      // Delete forever button
      var delForeverBtn = document.createElement('button');
      delForeverBtn.textContent = '✕';
      delForeverBtn.style.cssText = 'float:right;background:none;border:none;cursor:pointer;font-size:0.7rem;opacity:0.5;';
      delForeverBtn.title = 'Delete forever';
      delForeverBtn.addEventListener('click', function(e) {
        e.stopPropagation();
        if (confirm('Permanently delete this chat?')) {
          window.chrome.webview.postMessage(JSON.stringify({
            action: 'sidebarAction',
            subAction: 'deleteThreadForever',
            threadId: t.id
          }));
        }
      });

      // Read-only: no click to load, just display
      item.innerHTML = '<div style="text-decoration:line-through;color:var(--bs-secondary-color);">📝 ' + displayTitle + '</div><div style="font-size:0.65rem;color:var(--bs-secondary-color);">' + date + '</div>';
      item.appendChild(restoreBtn);
      item.appendChild(delForeverBtn);
      trashBody.appendChild(item);
    })(threads[i]);
  }

  trashSection.appendChild(trashHeader);
  trashSection.appendChild(emptyBtn);
  trashSection.appendChild(trashBody);
  list.appendChild(trashSection);

  // Auto-expand if items exist
  setTimeout(function() {
    if (threads.length > 0) {
      trashBody.style.display = 'block';
      document.getElementById('trash-toggle').textContent = '▲';
    }
  }, 100);
}

function loadThread(threadId) {
  activeThreadId = threadId;
  window.chrome.webview.postMessage(JSON.stringify({
    action: 'sidebarAction',
    subAction: 'loadThread',
    threadId: threadId
  }));
}

function newChat() {
  window.chrome.webview.postMessage(JSON.stringify({ action: 'sidebarAction', subAction: 'newChat' }));
}

// Thread forked callback
function threadForked(data) {
  loadThread(data.newThreadId);
  if (typeof loadThreadList === 'function') {
    window.chrome.webview.postMessage(JSON.stringify({ action: 'sidebarAction', subAction: 'loadThreadList' }));
  }
}

// D6: Chat navigation bar (scrollable message list)
function scrollToMessage(index) {
  var container = document.getElementById('chat-messages');
  if (!container) return;
  var bubbles = container.querySelectorAll('.chat-message');
  if (bubbles[index]) {
    bubbles[index].scrollIntoView({ behavior: 'smooth', block: 'center' });
    bubbles[index].style.outline = '2px solid var(--bs-primary)';
    setTimeout(function() { bubbles[index].style.outline = ''; }, 1500);
  }
}

function renderNavList() {
  var navList = document.getElementById('nav-message-list');
  if (!navList) return;

  navList.innerHTML = '';
  for (var i = 0; i < chatMessages.length; i++) {
    var msg = chatMessages[i];
    var item = document.createElement('div');
    item.className = 'nav-item';
    var preview = msg.content || '';
    if (preview.length > 40) preview = preview.substring(0, 40) + '...';
    var icon = msg.role === 'user' ? '👤' : msg.role === 'assistant' ? '🤖' : '⚙️';
    item.innerHTML = '<span style="font-size:0.7rem;">' + icon + ' ' + preview + '</span>';
    item.style.cssText = 'padding:0.35rem 0.5rem;cursor:pointer;font-size:0.75rem;border-bottom:1px solid var(--bs-border-color);';
    item.addEventListener('click', function(index) {
      return function() { scrollToMessage(index); };
    }(i));
    navList.appendChild(item);
  }
}