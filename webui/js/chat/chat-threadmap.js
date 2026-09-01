// ======================================================
// chat-threadmap.js — Right-panel thread map navigation
// ======================================================

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

    // Model names are user-controlled; escape the label and snippet before HTML insertion.
    item.innerHTML = '<span class="who">' + escHtml(who) + '</span><span class="snippet">' + escHtml(snippet) + '</span>';

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
    bubbles[index].scrollIntoView({ behavior: 'smooth', block: 'start' });
    bubbles[index].classList.remove('flash');
    void bubbles[index].offsetWidth; // Force reflow to re-trigger CSS animation
    bubbles[index].classList.add('flash');
  }
}

// Shared helper: find message by ID and scroll with flash.
// Used by tree modal, search dropdown, and thread map fallback.
function scrollToMessageById(messageId) {
  for (var i = 0; i < chatMessages.length; i++) {
    if (chatMessages[i].id === messageId) {
      scrollToMessage(i);
      return true;
    }
  }
  return false;
}
