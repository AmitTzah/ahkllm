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

  // Load thread list
  window.chrome.webview.postMessage(JSON.stringify({ action: 'sidebarAction', subAction: 'loadThreadList' }));
}

function closeSidebar() {
  var sidebar = document.getElementById('chat-sidebar');
  if (!sidebar) return;
  sidebar.style.display = 'none';
  sidebarOpen = false;
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
    var t = threads[i];
    var item = document.createElement('div');
    item.className = 'thread-item';
    if (t.id === activeThreadId) item.classList.add('active');
    item.style.cssText = 'padding:0.75rem;margin:0.25rem 0.5rem;border-radius:0.5rem;cursor:pointer;font-size:0.85rem;border:1px solid transparent;';

    var title = t.title || 'New Chat';
    if (title.length > 30) title = title.substring(0, 30) + '...';

    var date = t.updated_at || t.created_at || '';
    if (date.length > 16) date = date.substring(0, 16);

    item.innerHTML = '<div style="font-weight:600;">📝 ' + title + '</div><div style="font-size:0.7rem;color:var(--bs-secondary-color);">' + date + '</div>';

    item.addEventListener('click', function(threadId) {
      return function() {
        loadThread(threadId);
      };
    }(t.id));

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
  }
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