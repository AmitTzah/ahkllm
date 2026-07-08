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

  // Track user scroll intent for streaming
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

function onAssistantSelect() {
  var selector = document.getElementById('assistant-selector');
  if (!selector) return;
  var val = selector.value;
  // Always post — even empty value (Default Model) must clear assistant state in AHK
  window.chrome.webview.postMessage(JSON.stringify({
    action: 'switchAssistant',
    assistantId: val
  }));
}

function populateAssistantDropdown(assistants) {
  var selector = document.getElementById('assistant-selector');
  if (!selector || !assistants) return;

  // Keep the first "Custom Model..." option, remove the rest
  while (selector.options.length > 1) selector.remove(1);

  for (var i = 0; i < assistants.length; i++) {
    var opt = document.createElement('option');
    opt.value = assistants[i].id;
    opt.textContent = assistants[i].name;
    selector.appendChild(opt);
  }
}

// =====================================================
// Model Settings Modal
// =====================================================

function openModelSettings() {
  var modal = document.getElementById('model-settings-modal');
  if (!modal) return;

  // Request current settings from AHK to pre-populate fields
  window.chrome.webview.postMessage(JSON.stringify({ action: 'requestCurrentSettings' }));

  // Populate provider dropdown from modelList
  var providerSelect = document.getElementById('settings-provider');
  if (providerSelect && window.modelList) {
    while (providerSelect.options.length > 1) providerSelect.remove(1);
    for (var key in window.modelList) {
      var opt = document.createElement('option');
      opt.value = key;
      opt.textContent = key.charAt(0).toUpperCase() + key.slice(1);
      providerSelect.appendChild(opt);
    }
  }

  modal.style.display = 'block';
}

function populateCurrentSettings(settings) {
  if (!settings) return;
  var model = settings.model || '';
  var systemPrompt = settings.systemPrompt || '';
  var reasoning = settings.reasoning || '';
  var temperature = settings.temperature || '';
  var readOnly = settings.readOnly || false;

  // Set model: extract provider prefix to select correct dropdowns
  if (model && window.modelList) {
    var slashPos = model.indexOf('/');
    if (slashPos > 0) {
      var providerKey = model.substring(0, slashPos);
      var providerSelect = document.getElementById('settings-provider');
      if (providerSelect) {
        providerSelect.value = providerKey;
        providerSelect.disabled = readOnly;
        onSettingsProviderChange();
        var modelSelect = document.getElementById('settings-model');
        if (modelSelect) {
          modelSelect.value = model;
          modelSelect.disabled = readOnly;
        }
      }
    }
  }

  var sysPromptEl = document.getElementById('settings-system-prompt');
  var reasoningEl = document.getElementById('settings-reasoning');
  var tempEl = document.getElementById('settings-temperature');
  var saveBtn = document.querySelector('#model-settings-modal button[onclick="saveModelSettings()"]');

  if (sysPromptEl) { sysPromptEl.value = systemPrompt; sysPromptEl.disabled = readOnly; }
  if (reasoningEl) { reasoningEl.value = reasoning; reasoningEl.disabled = readOnly; }
  if (tempEl) { tempEl.value = temperature; tempEl.disabled = readOnly; }

  // Hide Save button and show read-only banner when assistant profile is active
  if (saveBtn) saveBtn.style.display = readOnly ? 'none' : '';

  // Update modal title to show read-only state
  var title = document.querySelector('#model-settings-modal h3');
  if (title) title.textContent = readOnly ? 'Model Settings (Read-Only)' : 'Model Settings';

  var modalContent = document.querySelector('#model-settings-modal > div');
  var bannerEl = document.getElementById('settings-readonly-banner');
  if (readOnly) {
    if (modalContent) modalContent.style.opacity = '0.7';
    if (!bannerEl) {
      bannerEl = document.createElement('div');
      bannerEl.id = 'settings-readonly-banner';
      bannerEl.style.cssText = 'background:var(--bs-warning-bg-subtle,#fff3cd);color:var(--bs-warning-text,#664d03);padding:8px 12px;border-radius:4px;font-size:0.8rem;margin-bottom:0.75rem;border:1px solid var(--bs-warning-border-subtle,#ffecb5);';
      bannerEl.textContent = 'ⓘ This is an assistant profile. Edit it in UserConfig.ahk.';
      if (modalContent) modalContent.insertBefore(bannerEl, modalContent.children[1]);
    }
  } else {
    if (modalContent) modalContent.style.opacity = '1';
    if (bannerEl) bannerEl.remove();
  }
}

function updateDropdownLabel(data) {
  var selector = document.getElementById('assistant-selector');
  if (!selector || !data) return;
  // Update the first option (Default Model) text to show current state
  if (data.text && !data.isAssistant) {
    selector.options[0].textContent = data.text;
  }
  // If assistant, select it in the dropdown
  if (data.isAssistant && data.text) {
    for (var i = 1; i < selector.options.length; i++) {
      if (selector.options[i].textContent === data.text) {
        selector.value = selector.options[i].value;
        return;
      }
    }
  } else if (!data.isAssistant) {
    selector.value = '';
  }
}

function closeModelSettings() {
  var modal = document.getElementById('model-settings-modal');
  if (modal) modal.style.display = 'none';
}

function onSettingsProviderChange() {
  var provider = document.getElementById('settings-provider').value;
  var modelSelect = document.getElementById('settings-model');
  if (!modelSelect) return;

  while (modelSelect.options.length > 1) modelSelect.remove(1);

  if (!provider || !window.modelList || !window.modelList[provider]) return;

  var models = window.modelList[provider];
  for (var i = 0; i < models.length; i++) {
    var opt = document.createElement('option');
    opt.value = models[i].fullId;
    opt.textContent = models[i].id;
    modelSelect.appendChild(opt);
  }
}

function showError(data) {
  // data is { message: string }
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

function saveModelSettings() {
  var model = document.getElementById('settings-model')?.value || '';
  var systemPrompt = document.getElementById('settings-system-prompt')?.value || '';
  var reasoning = document.getElementById('settings-reasoning')?.value || '';
  var temperature = document.getElementById('settings-temperature')?.value || '';

  window.chrome.webview.postMessage(JSON.stringify({
    action: 'updateModelSettings',
    model: model,
    systemPrompt: systemPrompt,
    reasoning: reasoning,
    temperature: temperature
  }));

  closeModelSettings();
}