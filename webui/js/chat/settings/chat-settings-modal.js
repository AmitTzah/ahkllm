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
    if (!bannerEl) {
      bannerEl = document.createElement('div');
      bannerEl.id = 'settings-readonly-banner';
      bannerEl.style.cssText = 'background:var(--bs-warning-bg-subtle,#fff3cd);color:var(--bs-warning-text,#664d03);padding:8px 12px;border-radius:4px;font-size:0.8rem;margin-bottom:0.75rem;border:1px solid var(--bs-warning-border-subtle,#ffecb5);';
      bannerEl.textContent = 'ⓘ This is an assistant profile. Edit it in UserConfig.ahk.';
      if (modalContent) modalContent.insertBefore(bannerEl, modalContent.children[1]);
    }
  } else {
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
