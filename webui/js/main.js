// ======================================================
// main.js — Main message handler and initialization
// Orchestrates communication between AHK and all feature modules.
// ======================================================

window.chrome.webview.addEventListener('message', handleWebMessage);

// Set Bootstrap theme based on darkMode config
function setTheme(isDark) {
  document.documentElement.setAttribute("data-bs-theme", isDark ? "dark" : "light");
}

// Apply font face to the document body (from user config)
function setFontFace(fontFamily) {
  document.body.style.fontFamily = fontFamily;
}

// Initialize markdown-it with options
var md = window.markdownit({
  html: true,
  linkify: true,
  typographer: true,
  highlight: function (str, lang) {
    if (lang && hljs.getLanguage(lang)) {
      try {
        return '<pre class="hljs"><code>' +
          hljs.highlight(str, { language: lang, ignoreIllegals: true }).value +
          '</code></pre>';
      } catch (__) { }
    }
    return '<pre class="hljs"><code>' + md.utils.escapeHtml(str) + '</code></pre>';
  }
})
  .use(window.texmath, {
    engine: window.katex,
    delimiters: 'dollars',
    katexOptions: { macros: { "\\RR": "\\mathbb{R}" } }
  });

// Main message handler from AHK
function handleWebMessage(event) {
  try {
    var message = event.data;

    // Handle JSON string messages from AHK
    if (typeof message === 'string') {
      try {
        message = JSON.parse(message);
      } catch (e) {
        // Not JSON — pass through
      }
    }

    var target = message.target;
    var data = message.data;

    switch (target) {
      case 'setTheme':
        setTheme(Array.isArray(data) ? data[0] : data);
        break;

      case 'setFontFace':
        setFontFace(Array.isArray(data) ? data[0] : data);
        break;

      case 'initChatMode':
        initChatMode(data);
        renderNavList();
        break;

      case 'appendChatMessage':
        appendChatMessage(data);
        break;

      case 'removeLastAssistantMessage':
        removeLastAssistantMessage();
        break;

      case 'renderMarkdown':
        renderMarkdown(Array.isArray(data) ? data[0] : data);
        break;

      case 'setChatButtonsEnabled':
        setChatButtonsEnabled(data);
        break;

      case 'updateTokenUsage':
        updateTokenUsage(data);
        break;

      case 'updateChatView':
        updateChatMessages(data);
        break;

      case 'updateBranchInfo':
        updateBranchInfo(data);
        break;

      case 'undeleteMessage':
        // Handled by AHK via message passing — no JS action needed
        break;

      case 'renderChatTree':
        // Only render tree content — don't auto-open modal on thread switch
        var treeContainer = document.getElementById('tree-container');
        if (treeContainer) {
          renderChatTree(data);
        }
        break;

      case 'threadList':
        loadThreadList(data);
        break;

      case 'trashList':
        if (typeof loadTrashList === 'function') loadTrashList(data);
        break;

      case 'loadThread':
        loadThread(data);
        break;

      case 'threadForked':
        threadForked(data);
        break;

      case 'streamContent':
      case 'streamReasoning':
      case 'streamDone':
      case 'streamCancelled':
        handleStreamMessage(target, data);
        break;

      case 'assistantList':
        populateAssistantDropdown(data);
        break;

      case 'modelList':
        window.modelList = data;
        break;

      case 'showError':
        showError(data);
        break;

      case 'currentSettings':
        populateCurrentSettings(data);
        break;

      case 'dropdownLabel':
        updateDropdownLabel(data);
        break;

      default:
        // Try calling as a function name for backward compatibility
        if (typeof window[target] === 'function') {
          if (Array.isArray(data)) {
            window[target](...data);
          } else {
            window[target](data);
          }
        } else {
          console.log('Unknown message target:', target);
        }
    }
  } catch (error) {
    console.error('Error handling incoming message:', error);
  }
}

// Attach event listeners when DOM is ready
document.addEventListener('DOMContentLoaded', function () {
  // Show token usage bar immediately (zero state, updated by postThreadStats)
  showTokenUsageBar();

  // Chat send button
  // NOTE: Do NOT add a click listener here. setChatButtonsEnabled() manages
  // the button's onclick handler dynamically (onChatSend vs onStopStreaming).
  // A second listener would cause onChatSend to fire twice on mouse clicks,
  // with the second call seeing isLoading=true and cancelling the request.

  // Chat input
  var chatInput = document.getElementById('chat-input');
  if (chatInput) {
    chatInput.addEventListener('keydown', handleChatInputKeydown);
    chatInput.addEventListener('input', autoResizeChatInput);
  }

  // Scroll tracking for streaming auto-scroll
  var chatMessagesEl = document.getElementById('chat-messages');
  if (chatMessagesEl) {
    chatMessagesEl.addEventListener('scroll', function () {
      var distanceFromBottom = chatMessagesEl.scrollHeight - chatMessagesEl.scrollTop - chatMessagesEl.clientHeight;
      if (typeof streamState !== 'undefined') {
        streamState.userScrolledUp = distanceFromBottom > 5;
      }
    });
  }

  // Copy entire chat button
  var copyAllBtn = document.getElementById('copy-entire-chat-btn');
  if (copyAllBtn) copyAllBtn.addEventListener('click', copyEntireChat);

  // Sidebar toggle
  var sidebarToggle = document.getElementById('sidebar-toggle');
  if (sidebarToggle) sidebarToggle.addEventListener('click', toggleSidebar);

  // New chat button in sidebar
  var newChatBtn = document.getElementById('new-chat-btn');
  if (newChatBtn) newChatBtn.addEventListener('click', newChat);

  // Tree view button
  var treeBtn = document.getElementById('tree-view-btn');
  if (treeBtn) treeBtn.addEventListener('click', toggleTreeModal);

  // Nav bar toggle
  var navToggle = document.getElementById('nav-toggle');
  if (navToggle) navToggle.addEventListener('click', toggleNavBar);

  // Restore chat state from sessionStorage if available (reload persistence)
  var storedIsChatMode = sessionStorage.getItem('isChatMode');
  var storedMessages = sessionStorage.getItem('chatMessages');
  if (storedIsChatMode === 'true' && storedMessages) {
    try {
      var messages = JSON.parse(storedMessages);
      if (messages.length > 0) {
        initChatMode(messages);
      }
    } catch (e) {
      console.error('Failed to restore chat state:', e);
    }
  }

  // Restore fallback markdown content
  var storedContent = sessionStorage.getItem('preMarkdownText');
  if (storedContent && !isChatMode) {
    renderMarkdown(storedContent);
  }
});

// D6: Nav bar toggle
var navBarOpen = false;

function toggleNavBar() {
  var navBar = document.getElementById('chat-nav-bar');
  if (!navBar) return;

  if (navBarOpen) {
    navBar.style.display = 'none';
    navBarOpen = false;
  } else {
    navBar.style.display = 'flex';
    navBarOpen = true;
    renderNavList();
  }
}

function showError(data) {
  // data is { message: string }
  hideLoadingIndicator();
  var msg = (typeof data === 'string') ? data : (data && data.message ? data.message : 'An error occurred');
  var chatMessages = document.getElementById('chat-messages');
  if (!chatMessages) return;
  var el = document.createElement('div');
  el.className = 'error-banner';
  el.style.cssText = 'background:var(--bs-danger);color:var(--bs-light);padding:8px 16px;margin:8px;border-radius:6px;font-size:0.85rem;display:flex;justify-content:space-between;align-items:center;';
  el.innerHTML = '<span>' + msg.replace(/</g, '<').replace(/>/g, '>') + '</span><button onclick="this.parentElement.remove()" style="background:none;border:none;color:inherit;font-size:1.2rem;cursor:pointer;">&times;</button>';
  chatMessages.appendChild(el);
  chatMessages.scrollTop = chatMessages.scrollHeight;
}