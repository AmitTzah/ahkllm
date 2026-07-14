// ======================================================
// chat-settings-modal.js — Model settings modal functions
// Extracted from main.js for single-responsibility.
// ======================================================

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
  var systemPrompt = settings.systemMessage || '';
  var reasoning = settings.reasoning || '';
  var temperature = settings.temperature || '';

  // Set model: extract provider prefix to select correct dropdowns
  if (model && window.modelList) {
    var slashPos = model.indexOf('/');
    if (slashPos > 0) {
      var providerKey = model.substring(0, slashPos);
      var providerSelect = document.getElementById('settings-provider');
      if (providerSelect) {
        providerSelect.value = providerKey;
        onSettingsProviderChange();
        var modelSelect = document.getElementById('settings-model');
        if (modelSelect) {
          modelSelect.value = model;
        }
      }
    }
  }

  var sysPromptEl = document.getElementById('settings-system-prompt');
  var reasoningEl = document.getElementById('settings-reasoning');
  var tempEl = document.getElementById('settings-temperature');

  if (sysPromptEl) sysPromptEl.value = systemPrompt;
  if (reasoningEl) reasoningEl.value = reasoning;
  if (tempEl) tempEl.value = temperature;

  // Remove any leftover read-only banner
  var bannerEl = document.getElementById('settings-readonly-banner');
  if (bannerEl) bannerEl.remove();
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

function saveModelSettings() {
  var model = document.getElementById('settings-model')?.value || '';
  var systemPrompt = document.getElementById('settings-system-prompt')?.value || '';
  var reasoning = document.getElementById('settings-reasoning')?.value || '';
  var temperature = document.getElementById('settings-temperature')?.value || '';

  window.chrome.webview.postMessage(JSON.stringify({
    action: 'updateModelSettings',
    model: model,
    systemMessage: systemPrompt,
    reasoning: reasoning,
    temperature: temperature
  }));

  closeModelSettings();
}
