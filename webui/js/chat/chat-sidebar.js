// ======================================================
// chat-sidebar.js — Thread list sidebar, trash, thread map
// Matches mock's folder/chat-item/trash structure
// ======================================================

var sidebarOpen = false;
// Map of threadId → { title, folder } — populated by loadThreadList, the single source of truth
var _threadMeta = {};
// Array of { id, name } — available folders, populated by loadThreadList
var _folders = [];

function toggleSidebar() {
  if (sidebarOpen) closeSidebar();
  else openSidebar();
}

function openSidebar() {
  sidebarOpen = true;
  window.chrome.webview.postMessage(JSON.stringify({ action: 'sidebarAction', subAction: 'loadThreadList' }));
  window.chrome.webview.postMessage(JSON.stringify({ action: 'sidebarAction', subAction: 'loadTrashList' }));
}

function closeSidebar() { sidebarOpen = false; }

// -----------------------------------------------------------
// Topbar title — one sync point, always reads _threadMeta
// -----------------------------------------------------------

// Called by loadThread, loadThreadList, newChat, threadForked.
// Also called by main.js default handler when AHK sends "updateTopbarTitle" target.
function updateTopbarTitle(data) {
  // External update (from AHK via main.js): store in _threadMeta
  if (data && data.text !== undefined && activeThreadId) {
    if (!_threadMeta[activeThreadId]) _threadMeta[activeThreadId] = {};
    _threadMeta[activeThreadId].title = data.text;
    if (data.folder !== undefined) _threadMeta[activeThreadId].folder = data.folder;
  }

  // Read from _threadMeta for the active thread
  var meta = activeThreadId ? _threadMeta[activeThreadId] : null;
  var title = (meta && meta.title) ? meta.title : 'New Chat';
  var folder = (meta && meta.folder) ? meta.folder : 'Unfiled';

  var titleEl = document.querySelector('.title-text');
  if (titleEl) titleEl.textContent = title;
  var foldEl = document.querySelector('.fold');
  if (foldEl) { foldEl.textContent = folder; foldEl.style.display = ''; }
}

// Format relative date like mock: "Today, 09:53", "Yesterday, 14:20", "Mon, 11:05"
function formatRelativeDate(dateStr) {
  if (!dateStr) return '';
  var d = new Date(dateStr + (dateStr.indexOf('Z') < 0 ? 'Z' : ''));
  if (isNaN(d.getTime())) return dateStr.substring(0, 16);
  var now = new Date();
  var today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  var msgDay = new Date(d.getFullYear(), d.getMonth(), d.getDate());
  var diff = Math.floor((today - msgDay) / 86400000);
  var time = d.toLocaleString(undefined, {hour:'2-digit',minute:'2-digit',hour12:false});
  if (diff === 0) return 'Today, ' + time;
  if (diff === 1) return 'Yesterday, ' + time;
  var days = ['Sun','Mon','Tue','Wed','Thu','Fri','Sat'];
  return days[d.getDay()] + ', ' + time;
}

// Provider-specific colored badge for chat items
function _providerIconHtml(model) {
  var iconFile = '../icons/openrouter.ico';
  if (model) {
    var m = model.toLowerCase();
    if (m.indexOf('deepseek') >= 0) iconFile = '../icons/deepseek.ico';
    else if (m.indexOf('gpt') >= 0 || m.indexOf('o1') >= 0 || m.indexOf('o3') >= 0 || m.indexOf('openai') >= 0) iconFile = '../icons/openai.ico';
    else if (m.indexOf('claude') >= 0 || m.indexOf('anthropic') >= 0) iconFile = '../icons/anthropic.ico';
    else if (m.indexOf('gemini') >= 0 || m.indexOf('google') >= 0) iconFile = '../icons/google.ico';
    else if (m.indexOf('perplexity') >= 0) iconFile = '../icons/perplexity.ico';
  }
  return '<img src="' + iconFile + '" style="width:20px;height:20px;flex-shrink:0;mix-blend-mode:multiply;" alt="">';
}

// -----------------------------------------------------------
// Thread list rendering
// -----------------------------------------------------------

function loadThreadList(threads, folders) {
  var list = document.getElementById('thread-list');
  if (!list) return;
  list.innerHTML = '';

  folders = folders || [];
  threads = threads || [];
  _folders = folders; // Store for move-to-folder dropdown

  // Populate _threadMeta from incoming data (single source of truth)
  for (var i = 0; i < threads.length; i++) {
    var t = threads[i];
    if (!_threadMeta[t.id]) _threadMeta[t.id] = {};
    _threadMeta[t.id].title = t.title;
    _threadMeta[t.id].folder = t.folder_name || '';
  }

  if (threads.length === 0 && folders.length === 0) {
    list.innerHTML = '<div style="padding:1rem;color:var(--text-tertiary);font-size:0.85rem;">No chats yet.</div>';
    updateTopbarTitle();
    return;
  }

  for (var fi = 0; fi < folders.length; fi++) {
    list.appendChild(_buildFolderSection(folders[fi], threads));
  }

  // Unfiled chats
  var unfiled = threads.filter(function(t) { return !t.folder_id; });
  if (unfiled.length > 0 || folders.length === 0) {
    var unfiledLabel = document.createElement('div');
    unfiledLabel.className = 'unfiled-label';
    unfiledLabel.textContent = 'Unfiled';
    list.appendChild(unfiledLabel);

    for (var ui = 0; ui < unfiled.length; ui++) {
      list.appendChild(createChatItem(unfiled[ui]));
    }
  }

  // Sync topbar for active thread (handles title-gen and chat-switch updates)
  updateTopbarTitle();

  if (typeof lucide !== 'undefined') lucide.createIcons();
}

function createChatItem(t) {
  var item = document.createElement('div');
  item.className = 'chat-item';
  if (t.id === activeThreadId) item.classList.add('active');
  item.setAttribute('data-chat', t.id);

  var dateStr = formatRelativeDate(t.updated_at || t.created_at);

  item.innerHTML =
    '<div class="chat-icon">' + _providerIconHtml(t.model) + '</div>' +
    '<div class="chat-meta">' +
      '<div class="chat-name">' + escHtml(t.title || 'New Chat') + '</div>' +
      '<div class="chat-item-bottom">' +
        '<div class="chat-date">' + dateStr + '</div>' +
        '<div class="chat-actions">' +
          '<button class="chat-action-btn" title="Rename"><i data-lucide="edit-2"></i></button>' +
          '<button class="chat-action-btn" title="Move to folder"><i data-lucide="folder"></i></button>' +
          '<button class="chat-action-btn danger" title="Delete"><i data-lucide="trash-2"></i></button>' +
        '</div>' +
      '</div>' +
    '</div>';

  item.addEventListener('click', function(e) {
    if (e.target.closest('.chat-action-btn')) return;
    loadThread(t.id);
  });

  _wireRenameHandler(item, t);
  _wireMoveToFolderHandler(item, t);

  // Delete
  item.querySelector('.chat-action-btn.danger').addEventListener('click', function(e) {
    e.stopPropagation();
    _showConfirm('Delete this chat?', function() {
      window.chrome.webview.postMessage(JSON.stringify({ action: 'sidebarAction', subAction: 'deleteThread', threadId: t.id }));
    });
  });

  return item;
}

// -----------------------------------------------------------
// Trash
// -----------------------------------------------------------

function _wireRenameHandler(item, t) {
  item.querySelector('.chat-action-btn[title="Rename"]').addEventListener('click', function(e) {
    e.stopPropagation();
    var nameEl = item.querySelector('.chat-name');
    if (!nameEl || nameEl.querySelector('input')) return;
    var currentTitle = nameEl.textContent;
    var input = document.createElement('input');
    input.type = 'text'; input.value = currentTitle;
    input.style.cssText = 'font:inherit;color:inherit;background:var(--bg-hover);border:1px solid var(--border-main);border-radius:4px;padding:0 4px;width:100%;outline:none;font-size:0.85rem;';
    nameEl.textContent = ''; nameEl.appendChild(input); input.focus(); input.select();
    var save = function() {
      var newTitle = input.value.trim();
      nameEl.textContent = newTitle || currentTitle;
      if (newTitle && newTitle !== currentTitle) {
        window.chrome.webview.postMessage(JSON.stringify({ action: 'sidebarAction', subAction: 'renameThread', threadId: t.id, title: newTitle }));
      }
    };
    input.addEventListener('blur', save);
    input.addEventListener('keydown', function(ev) { if (ev.key === 'Enter') { input.blur(); } if (ev.key === 'Escape') { nameEl.textContent = currentTitle; } });
  });
}

function _wireMoveToFolderHandler(item, t) {
  item.querySelector('.chat-action-btn[title="Move to folder"]').addEventListener('click', function(e) {
    e.stopPropagation();
    var btn = this;
    var existing = document.querySelector('.folder-pick-dropdown');
    if (existing) existing.remove();
    if (existing && existing._btn === btn) return;

    var dd = document.createElement('div');
    dd.className = 'folder-pick-dropdown';
    dd.style.cssText = 'position:fixed;z-index:100;background:var(--bg-panel);border:1px solid var(--border-main);border-radius:8px;box-shadow:var(--shadow-modal);padding:4px;min-width:150px;';
    dd._btn = btn;
    var rect = btn.getBoundingClientRect();
    dd.style.left = rect.left + 'px'; dd.style.top = (rect.bottom + 2) + 'px';

    var unfiledItem = document.createElement('div');
    unfiledItem.textContent = 'Unfiled (no folder)';
    unfiledItem.style.cssText = 'padding:8px 12px;cursor:pointer;border-radius:4px;font-size:0.85rem;color:var(--text-secondary);';
    unfiledItem.addEventListener('mouseenter', function() { this.style.background = 'var(--bg-hover)'; });
    unfiledItem.addEventListener('mouseleave', function() { this.style.background = ''; });
    unfiledItem.addEventListener('click', function(ev) {
      ev.stopPropagation();
      window.chrome.webview.postMessage(JSON.stringify({ action: 'sidebarAction', subAction: 'moveToFolder', threadId: t.id, folderId: '__none__' }));
      dd.remove();
    });
    dd.appendChild(unfiledItem);

    for (var fi = 0; fi < _folders.length; fi++) {
      var folder = _folders[fi];
      var folderItem = document.createElement('div');
      folderItem.textContent = folder.name;
      folderItem.style.cssText = 'padding:8px 12px;cursor:pointer;border-radius:4px;font-size:0.85rem;';
      folderItem.addEventListener('mouseenter', function() { this.style.background = 'var(--bg-hover)'; });
      folderItem.addEventListener('mouseleave', function() { this.style.background = ''; });
      folderItem.addEventListener('click', function(folderId) {
        return function(ev) {
          ev.stopPropagation();
          window.chrome.webview.postMessage(JSON.stringify({ action: 'sidebarAction', subAction: 'moveToFolder', threadId: t.id, folderId: folderId }));
          dd.remove();
        };
      }(folder.id));
      dd.appendChild(folderItem);
    }
    document.body.appendChild(dd);
    setTimeout(function() {
      document.addEventListener('click', function closeDd(ev2) {
        if (!dd.contains(ev2.target) && ev2.target !== btn) { dd.remove(); document.removeEventListener('click', closeDd); }
      });
    }, 0);
  });
}

function _buildFolderSection(folder, threads) {
  var folderThreads = threads.filter(function(t) { return t.folder_id === folder.id; });
  var folderDiv = document.createElement('div');
  folderDiv.className = 'folder';
  folderDiv.setAttribute('data-folder', folder.id);

  var head = document.createElement('div');
  head.className = 'folder-head';
  head.innerHTML = '<div style="display:flex; align-items:center; gap:8px; flex:1;">' +
    '<i data-lucide="chevron-down" class="folder-chevron"></i>' +
    '<span class="folder-name">' + escHtml(folder.name) + '</span>' +
    '<span class="folder-count">' + folderThreads.length + '</span></div>' +
    '<div class="folder-actions">' +
      '<button class="folder-action-btn" title="Rename Folder"><i data-lucide="edit-2" style="width:16px;height:16px;"></i></button>' +
      '<button class="folder-action-btn danger folder-delete-btn" title="Delete Folder"><i data-lucide="trash-2" style="width:16px;height:16px;"></i></button></div>';

  head.addEventListener('click', function(e) {
    if (e.target.closest('.folder-action-btn')) return;
    this.closest('.folder').classList.toggle('collapsed');
  });
  head.querySelector('.folder-action-btn:not(.danger)').addEventListener('click', function(e) {
    e.stopPropagation();
    var nameSpan = this.closest('.folder-head').querySelector('.folder-name');
    if (!nameSpan || nameSpan.querySelector('input')) return;
    var currentName = nameSpan.textContent;
    var input = document.createElement('input');
    input.type = 'text'; input.value = currentName;
    input.style.cssText = 'font:inherit;color:inherit;background:var(--bg-hover);border:1px solid var(--border-main);border-radius:4px;padding:0 4px;width:120px;outline:none;font-size:0.85rem;';
    nameSpan.textContent = ''; nameSpan.appendChild(input); input.focus(); input.select();
    var save = function() {
      var newName = input.value.trim();
      nameSpan.textContent = newName || currentName;
      if (newName && newName !== currentName) {
        window.chrome.webview.postMessage(JSON.stringify({ action: 'sidebarAction', subAction: 'renameFolder', folderId: folder.id, name: newName }));
      }
    };
    input.addEventListener('blur', save);
    input.addEventListener('keydown', function(ev) { if (ev.key === 'Enter') { input.blur(); } if (ev.key === 'Escape') { nameSpan.textContent = currentName; } });
  });
  head.querySelector('.folder-delete-btn').addEventListener('click', function(e) {
    e.stopPropagation();
    _showConfirm('Delete folder "' + escHtml(folder.name) + '"? Chats will become unfiled.', function() {
      window.chrome.webview.postMessage(JSON.stringify({ action: 'sidebarAction', subAction: 'deleteFolder', folderId: folder.id }));
    });
  });
  folderDiv.appendChild(head);

  var chatsDiv = document.createElement('div');
  chatsDiv.className = 'folder-chats';
  for (var ci = 0; ci < folderThreads.length; ci++) {
    chatsDiv.appendChild(createChatItem(folderThreads[ci]));
  }
  folderDiv.appendChild(chatsDiv);
  return folderDiv;
}

function loadTrashList(threads) {
  var trashItems = document.querySelector('.trash-items');
  if (!trashItems) return;
  trashItems.innerHTML = '';

  if (!threads || threads.length === 0) {
    // Re-collapse trash when empty so chevron rotates back
    var trashWrap2 = document.getElementById('trashWrap');
    if (trashWrap2) trashWrap2.classList.add('collapsed');
    return;
  }

  for (var i = 0; i < threads.length; i++) {
    var t = threads[i];
    var item = document.createElement('div');
    item.className = 'trash-item';
    item.innerHTML =
      '<div class="chat-name">' + escHtml(t.title || 'New Chat') + '</div>' +
      '<div class="trash-item-acts">' +
        '<button title="Restore"><i data-lucide="rotate-ccw" style="width:16px;height:16px;"></i></button>' +
        '<button class="danger" title="Delete forever"><i data-lucide="x" style="width:16px;height:16px;"></i></button>' +
      '</div>';

    item.querySelector('button[title="Restore"]').addEventListener('click', function() {
      window.chrome.webview.postMessage(JSON.stringify({ action: 'sidebarAction', subAction: 'restoreThread', threadId: t.id }));
    });
    item.querySelector('button.danger').addEventListener('click', function() {
      _showConfirm('Permanently delete?', function() {
        window.chrome.webview.postMessage(JSON.stringify({ action: 'sidebarAction', subAction: 'deleteThreadForever', threadId: t.id }));
      });
    });

    trashItems.appendChild(item);
  }

  var trashWrap = document.getElementById('trashWrap');
  if (trashWrap) trashWrap.classList.remove('collapsed');
  if (typeof lucide !== 'undefined') lucide.createIcons();
}

// -----------------------------------------------------------
// Thread map (right panel nav)
// -----------------------------------------------------------

function renderNavList() {
  var navList = document.getElementById('nav-message-list');
  if (!navList) return;
  navList.innerHTML = '';

  for (var i = 0; i < chatMessages.length; i++) {
    var msg = chatMessages[i];
    var item = document.createElement('div');
    var role = msg.role === 'user' ? 'you-row' : (msg.role === 'assistant' ? 'bot-row' : '');
    item.className = 'thread-item ' + role;
    item.setAttribute('data-target', 'msg-' + i);

    var who = msg.role === 'user' ? 'You' : (msg.model || 'Assistant');
    var snippet = (msg.content || '').substring(0, 60).replace(/\n/g, ' ');

    item.innerHTML = '<span class="who">' + who + '</span><span class="snippet">' + escHtml(snippet) + '</span>';

    item.addEventListener('click', function(targetIdx) {
      return function() {
        scrollToMessage(targetIdx);
      };
    }(i));

    navList.appendChild(item);
  }
}

function scrollToMessage(index) {
  var container = document.getElementById('chat-messages');
  if (!container) return;
  var bubbles = container.querySelectorAll('.msg');
  if (bubbles[index]) {
    bubbles[index].scrollIntoView({ behavior: 'smooth', block: 'center' });
    bubbles[index].classList.remove('flash');
    void bubbles[index].offsetWidth;
    bubbles[index].classList.add('flash');
  }
}

// -----------------------------------------------------------
// Thread switching
// -----------------------------------------------------------

function loadThread(threadId) {
  // Switch to chat view if currently showing dashboard
  if (typeof window._showChat === 'function') window._showChat();
  activeThreadId = threadId;
  // Title is read from _threadMeta (populated by loadThreadList).
  // If not yet loaded, it will be "New Chat" until threadList arrives.
  updateTopbarTitle();

  // Update active highlight immediately (sidebar may not re-render)
  var allItems = document.querySelectorAll('.chat-item');
  for (var i = 0; i < allItems.length; i++) {
    var chatId = allItems[i].getAttribute('data-chat');
    if (chatId === threadId) {
      allItems[i].classList.add('active');
    } else {
      allItems[i].classList.remove('active');
    }
  }

  window.chrome.webview.postMessage(JSON.stringify({ action: 'sidebarAction', subAction: 'loadThread', threadId: threadId }));
}

function newChat() {
  activeThreadId = '';
  updateTopbarTitle();
  // Clear active highlight
  var allItems = document.querySelectorAll('.chat-item');
  for (var i = 0; i < allItems.length; i++) {
    allItems[i].classList.remove('active');
  }
  window.chrome.webview.postMessage(JSON.stringify({ action: 'sidebarAction', subAction: 'newChat' }));
}

function threadForked(data) {
  loadThread(data.newThreadId);
  window.chrome.webview.postMessage(JSON.stringify({ action: 'sidebarAction', subAction: 'loadThreadList' }));
}

// -----------------------------------------------------------
// Trash toggle
// -----------------------------------------------------------

if (typeof document !== 'undefined' && document.addEventListener) {
  document.addEventListener('DOMContentLoaded', function() {
    var trashToggle = document.getElementById('trashToggle');
    if (trashToggle) {
      trashToggle.addEventListener('click', function() {
        document.getElementById('trashWrap').classList.toggle('collapsed');
      });
    }
  });
}


// Shared custom confirmation dialog — no browser prompt()
var _confirmCallback = null;
function _showConfirm(message, onYes) {
  // Remove any existing confirm
  var existing = document.getElementById('customConfirmOverlay');
  if (existing) existing.remove();

  _confirmCallback = onYes;
  var overlay = document.createElement('div');
  overlay.id = 'customConfirmOverlay';
  overlay.style.cssText = 'position:fixed;inset:0;background:rgba(17,24,39,0.4);backdrop-filter:blur(2px);display:flex;align-items:center;justify-content:center;z-index:200;';
  overlay.innerHTML =
    '<div style="background:var(--bg-panel);border:1px solid var(--border-main);border-radius:12px;padding:24px;max-width:360px;box-shadow:var(--shadow-modal);">' +
      '<div style="font-size:15px;color:var(--text-primary);margin-bottom:16px;line-height:1.5;">' + escHtml(message) + '</div>' +
      '<div style="display:flex;justify-content:flex-end;gap:8px;">' +
        '<button class="cancel-confirm-btn" style="padding:8px 16px;border:1px solid var(--border-main);border-radius:6px;background:transparent;color:var(--text-secondary);cursor:pointer;">Cancel</button>' +
        '<button class="yes-confirm-btn" style="padding:8px 16px;border:none;border-radius:6px;background:var(--danger);color:#fff;cursor:pointer;">Delete</button>' +
      '</div>' +
    '</div>';
  document.body.appendChild(overlay);

  overlay.querySelector('.cancel-confirm-btn').addEventListener('click', function() { overlay.remove(); _confirmCallback = null; });
  overlay.querySelector('.yes-confirm-btn').addEventListener('click', function() {
    overlay.remove();
    var cb = _confirmCallback;
    _confirmCallback = null;
    if (cb) cb();
  });
  overlay.addEventListener('click', function(e) { if (e.target === overlay) { overlay.remove(); _confirmCallback = null; } });
}
