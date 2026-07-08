// ======================================================
// chat-quote.js — D5: Quote from chat (text selection → insert quoted block)
// ======================================================

var quotePopup = null;

function quoteMessage(index) {
  var msg = chatMessages[index];
  if (!msg) return;

  var quotedText = '> ' + msg.content.split('\n').join('\n> ') + '\n\n';
  insertAtCursor(quotedText);
}

// Insert text at cursor position in chat input
function insertAtCursor(text) {
  var input = document.getElementById('chat-input');
  if (!input) return;

  var start = input.selectionStart;
  var end = input.selectionEnd;
  var currentValue = input.value;
  input.value = currentValue.substring(0, start) + text + currentValue.substring(end);
  input.selectionStart = input.selectionEnd = start + text.length;
  input.focus();
  autoResizeChatInput();
}

// Text selection listener on message content
document.addEventListener('mouseup', function(e) {
  var selection = window.getSelection();
  var selectedText = selection.toString().trim();

  if (quotePopup) {
    quotePopup.remove();
    quotePopup = null;
  }

  if (!selectedText || selectedText.length < 3) return;

  var range = selection.getRangeAt(0);
  var container = range.commonAncestorContainer;

  // Check if selection is within a chat message
  var bubble = container.closest ? container.closest('.chat-message') : null;
  if (!bubble) {
    // Walk up manually for older browsers without closest()
    var el = container;
    while (el && el !== document.body) {
      if (el.classList && el.classList.contains('chat-message')) {
        bubble = el;
        break;
      }
      el = el.parentNode;
    }
  }
  if (!bubble) return;

  // Show floating quote button near selection
  quotePopup = document.createElement('div');
  quotePopup.className = 'quote-popup';
  quotePopup.style.cssText = 'position:fixed;z-index:9999;background:var(--bs-primary);color:white;padding:4px 10px;border-radius:0.5rem;font-size:0.8rem;cursor:pointer;box-shadow:0 2px 8px rgba(0,0,0,0.2);';
  quotePopup.textContent = '💬 Quote';

  var rect = range.getBoundingClientRect();
  quotePopup.style.left = rect.left + 'px';
  quotePopup.style.top = (rect.bottom + 4) + 'px';

  quotePopup.addEventListener('mousedown', function(evt) {
    evt.preventDefault();
    evt.stopPropagation();
    var quoted = '> ' + selectedText.split('\n').join('\n> ') + '\n\n';
    insertAtCursor(quoted);
    selection.removeAllRanges();
    quotePopup.remove();
    quotePopup = null;
  });

  document.body.appendChild(quotePopup);
});

// Hide quote popup on click elsewhere
document.addEventListener('mousedown', function(e) {
  if (quotePopup && e.target !== quotePopup && !quotePopup.contains(e.target)) {
    quotePopup.remove();
    quotePopup = null;
  }
});