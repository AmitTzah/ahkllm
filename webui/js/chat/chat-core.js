// ======================================================
// chat-core.js — Core chat state and initialization
// ======================================================

// Chat state
var chatMessages = [];
var isChatMode = false;
var isLoading = false;
var activeThreadId = "";

// Close all dropdown menus when clicking outside
document.addEventListener('click', function() {
  var menus = document.querySelectorAll('.more-menu');
  for (var i = 0; i < menus.length; i++) {
    menus[i].style.display = 'none';
  }
});

// Initialize chat mode — called by AHK when a thread loads
function initChatMode(messages) {
  isChatMode = true;
  chatMessages = messages || [];

  var fimNotice = document.getElementById('fim-notice');
  if (fimNotice) fimNotice.style.display = 'none';

  renderChatMessages(chatMessages);
  showTokenUsageBar();
  // Re-enable chat input in case it was disabled from trash view
  var chatInput = document.getElementById('chat-input');
  if (chatInput) chatInput.disabled = false;
  var sendBtn = document.getElementById('chat-send-btn');
  if (sendBtn) sendBtn.disabled = false;

  // Only show loading if a request is already in-flight AND last message isn't assistant
  if (isLoading && chatMessages.length > 0 && chatMessages[chatMessages.length - 1].role !== 'assistant') {
    showLoadingIndicator();
  } else {
    isLoading = false;
    hideLoadingIndicator();
  }

  sessionStorage.setItem('isChatMode', 'true');
  sessionStorage.setItem('chatMessages', JSON.stringify(chatMessages));

  // Clear undo stack when switching threads (new context = clean undo history)
  if (typeof clearUndoStack === 'function') {
    clearUndoStack();
  }
}

// Markdown rendering for non-chat modes (FIM fallback)
function renderMarkdown(content) {
  var contentToRender = content || 'There is no content available.';
  sessionStorage.setItem('preMarkdownText', contentToRender);
  var result = md.render(contentToRender);
  var contentElement = document.getElementById('content');
  if (contentElement) contentElement.innerHTML = result;
  if (!isChatMode) {
    var fimNotice = document.getElementById('fim-notice');
    if (fimNotice) fimNotice.style.display = 'block';
    var chatMessagesEl = document.getElementById('chat-messages');
    if (chatMessagesEl) chatMessagesEl.style.display = 'none';
    if (contentElement) contentElement.style.display = 'block';
  } else {
    var chatMessagesEl2 = document.getElementById('chat-messages');
    if (chatMessagesEl2) chatMessagesEl2.style.display = '';
    var contentEl2 = document.getElementById('content');
    if (contentEl2) contentEl2.style.display = 'none';
  }
}

// Shared HTML escape utility (used by multiple chat modules)
function escHtml(s) {
  if (!s) return '';
  return String(s).replace(/&/g,'&').replace(/</g,'<').replace(/>/g,'>').replace(/"/g,'"');
}
