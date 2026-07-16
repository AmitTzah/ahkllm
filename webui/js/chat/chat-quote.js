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

// Text selection quote popup removed — quote action available in message action bar