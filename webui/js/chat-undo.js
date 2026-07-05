// ======================================================
// chat-undo.js — D9: Undo/Redo message edits (Ctrl+Z/Ctrl+Y)
// Per-chat stack, persists until chat closed.
// ======================================================

var MAX_UNDO_STACK = 50;
var undoStack = [];
var redoStack = [];

// Record an action for undo
function recordUndo(action, messageId, beforeState) {
  undoStack.push({
    action: action,          // 'edit' | 'delete' | 'branch'
    messageId: messageId,
    beforeState: beforeState, // snapshot before the change
    timestamp: Date.now()
  });

  if (undoStack.length > MAX_UNDO_STACK) {
    undoStack.shift();
  }

  // Clear redo stack on new action
  redoStack = [];
}

// Undo last action
function undo() {
  if (undoStack.length === 0) {
    showUndoNotification('Nothing to undo');
    return;
  }

  var action = undoStack.pop();
  redoStack.push(action);

  switch (action.action) {
    case 'edit':
      undoEdit(action);
      break;
    case 'delete':
      undoDelete(action);
      break;
    default:
      showUndoNotification('Undo not supported for this action');
  }
}

// Redo last undone action
function redo() {
  if (redoStack.length === 0) {
    showUndoNotification('Nothing to redo');
    return;
  }

  var action = redoStack.pop();
  undoStack.push(action);

  switch (action.action) {
    case 'edit':
      redoEdit(action);
      break;
    case 'delete':
      redoDelete(action);
      break;
    default:
      showUndoNotification('Redo not supported for this action');
  }
}

function undoEdit(action) {
  // Restore original content
  if (action.beforeState && action.beforeState.content) {
    window.chrome.webview.postMessage(JSON.stringify({
      action: 'editMessage',
      id: action.messageId,
      content: action.beforeState.content,
      mode: 'overwrite'
    }));
  }
}

function redoEdit(action) {
  // Re-apply the edit (the action itself is the redo)
  if (action.afterState && action.afterState.content) {
    window.chrome.webview.postMessage(JSON.stringify({
      action: 'editMessage',
      id: action.messageId,
      content: action.afterState.content,
      mode: 'overwrite'
    }));
  }
}

function undoDelete(action) {
  // Can't truly undo a soft delete from JS side — would need AHK support
  showUndoNotification('Undo delete not available for soft-deleted messages');
}

function redoDelete(action) {
  showUndoNotification('Redo delete not available');
}

// Show a brief notification
var undoNotificationTimeout = null;

function showUndoNotification(message) {
  var existing = document.getElementById('undo-notification');
  if (existing) existing.remove();
  if (undoNotificationTimeout) clearTimeout(undoNotificationTimeout);

  var notif = document.createElement('div');
  notif.id = 'undo-notification';
  notif.textContent = message;
  notif.style.cssText = 'position:fixed;bottom:80px;right:20px;background:var(--bs-tertiary-bg);color:var(--bs-body-color);padding:8px 16px;border-radius:0.5rem;font-size:0.8rem;border:1px solid var(--bs-border-color);z-index:9999;opacity:0.95;';
  document.body.appendChild(notif);

  undoNotificationTimeout = setTimeout(function() {
    notif.remove();
  }, 2000);
}

// Keyboard listener for Ctrl+Z / Ctrl+Y
document.addEventListener('keydown', function(e) {
  if (e.ctrlKey && !e.shiftKey && e.key === 'z') {
    e.preventDefault();
    undo();
  } else if (e.ctrlKey && e.key === 'y') {
    e.preventDefault();
    redo();
  }
});

// Clear undo stack when switching threads
function clearUndoStack() {
  undoStack = [];
  redoStack = [];
}