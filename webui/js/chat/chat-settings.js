// ======================================================
// chat-settings.js — Assistant selector dropdown
//
// Handles assistant selection and dropdown population.
// Model settings modal functions moved to chat-settings-modal.js.
// ======================================================

function onAssistantSelect() {
  var selector = document.getElementById('assistant-selector');
  if (!selector) return;
  var val = selector.value;
  window.chrome.webview.postMessage(JSON.stringify({
    action: 'switchAssistant',
    assistantId: val
  }));
}

function populateAssistantDropdown(assistants) {
  var selector = document.getElementById('assistant-selector');
  if (!selector || !assistants) return;
  while (selector.options.length > 1) selector.remove(1);
  for (var i = 0; i < assistants.length; i++) {
    var opt = document.createElement('option');
    opt.value = assistants[i].id;
    opt.textContent = assistants[i].name;
    selector.appendChild(opt);
  }
}
