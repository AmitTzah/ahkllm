// ======================================================
// chat-core.js — Core chat state and initialization
// ======================================================

// Chat state
var chatMessages = [];
var isChatMode = false;
var isLoading = false;
var activeThreadId = "";

// Initialize chat mode — called by AHK when a thread loads
function initChatMode(messages) {
  isChatMode = true;
  chatMessages = messages || [];

  // Show chat layout, hide the old content fallback
  var chatLayout = document.getElementById('chat-layout');
  if (chatLayout) chatLayout.style.display = 'flex';
  var content = document.getElementById('content');
  if (content) content.style.display = 'none';

  renderChatMessages(chatMessages);
  showTokenUsageBar();
  // Re-enable chat input in case it was disabled from trash view
  var chatInput = document.getElementById('chat-input');
  if (chatInput) chatInput.disabled = false;
  var sendBtn = document.getElementById('chat-send-btn');
  if (sendBtn) sendBtn.disabled = false;

  updateBranchBadges();
  updateBranchBadges();

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
    var chatLayout = document.getElementById('chat-layout');
    var contentEl = document.getElementById('content');
    if (chatLayout) chatLayout.style.display = 'none';
    if (contentEl) contentEl.style.display = 'block';
  }
}
