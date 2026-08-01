// ======================================================
// chat-settings-modal.js — Right panel config + system prompt modal
// ======================================================

function openModelSettings() {
  // Settings are always visible in right panel — no modal to open
  // Request current settings from AHK
  window.chrome.webview.postMessage(JSON.stringify({ action: 'requestCurrentSettings' }));
}

function populateCurrentSettings(settings) {
  if (!settings) return;

  // Store all values (keep empty as empty — don't default to 1.0)
  window._currentSettings = {
    model: settings.model || '',
    systemMessage: settings.systemMessage || '',
    reasoning: settings.reasoning || '',
    temperature: settings.temperature || '',
    fontSize: settings.fontSize || '17',
    assistantName: settings.assistantName || '',
    assistantBaseModel: settings.assistantBaseModel || '',
    assistantDescription: settings.assistantDescription || ''
  };

  // Apply per-chat font size
  if (settings.fontSize) {
    document.documentElement.style.setProperty('--chat-font-size', settings.fontSize + 'px');
    var fontDisp = document.getElementById('font-size-display');
    if (fontDisp) fontDisp.textContent = settings.fontSize + 'px';
  }

  // Update model card
  _updateModelCard();

  // System prompt mini textarea
  var mini = document.getElementById('sysMsgMini');
  if (mini) mini.value = settings.systemMessage || '';

  // Temperature slider
  var tempSlider = document.getElementById('tempSlider');
  var tempVal = document.getElementById('tempVal');
  var tempReset = document.getElementById('tempReset');
  if (tempSlider) {
    var hasTemp = settings.temperature && settings.temperature !== '';
    if (hasTemp) {
      tempSlider.value = settings.temperature;
      tempSlider.classList.remove('temp-default');
      if (tempVal) tempVal.textContent = parseFloat(tempSlider.value).toFixed(1);
      if (tempReset) tempReset.style.display = '';
    } else {
      tempSlider.value = '1.0';
      tempSlider.classList.add('temp-default');
      if (tempVal) tempVal.textContent = 'Default';
      if (tempReset) tempReset.style.display = 'none';
    }
  }

  // Thinking dropdown — the backend sends raw level values; the shared
  // ReasoningLevels helper labels and sorts them (Model Default + levels).
  var thinkingDropdown = document.getElementById('reasoningDropdown');
  if (thinkingDropdown) {
    var levels = settings.thinkingLevels || [];
    var currentValue = settings.reasoning || '';
    var rl = (typeof window !== 'undefined') ? window.ReasoningLevels : null;

    thinkingDropdown.innerHTML = rl
      ? rl.buildOptionsHtmlForValues(levels)
      : '<option value="">Model Default</option>' + levels.map(function(lv) {
          return '<option value="' + lv + '">' + lv + '</option>';
        }).join('');

    // Restore current value if still valid
    var valueExists = false;
    for (var i = 0; i < thinkingDropdown.options.length; i++) {
      if (thinkingDropdown.options[i].value === currentValue) {
        valueExists = true;
        break;
      }
    }
    thinkingDropdown.value = valueExists ? currentValue : '';
  }
}

// Called by main.js when dropdownLabel arrives
function updateDropdownLabel(data) {
  if (!data || !window._currentSettings) return;
  if (!data.isAssistant && data.text) {
    // Only update model if not already set (avoids overwriting full model ID)
    if (!window._currentSettings.model || window._currentSettings.model.indexOf(data.text) < 0) {
      window._currentSettings.model = data.text;
    }
    window._currentSettings.assistantName = '';
    _updateModelCard();
  }
  if (data.isAssistant && data.text) {
    window._currentSettings.assistantName = data.text;
    // Find assistant in list to get base model and description
    if (window._assistantList) {
      for (var i = 0; i < window._assistantList.length; i++) {
        if (window._assistantList[i].name === data.text) {
          window._currentSettings.assistantBaseModel = window._assistantList[i].baseModel || '';
          window._currentSettings.assistantDescription = window._assistantList[i].description || '';
          break;
        }
      }
    }
    _updateModelCard();
  }
}

function closeModelSettings() {
  // No-op in new UI
}

// Wire right panel controls
if (typeof document !== 'undefined' && document.addEventListener) {
document.addEventListener('DOMContentLoaded', function() {
  window._currentSettings = { model: '', systemMessage: '', reasoning: '', temperature: '' };

  // Temperature slider — auto-enable on interaction, reset to default
  var tempSlider = document.getElementById('tempSlider');
  var tempVal = document.getElementById('tempVal');
  var tempReset = document.getElementById('tempReset');
  if (tempSlider) {
    tempSlider.addEventListener('input', function() {
      // Auto-enable on first interaction
      if (tempSlider.classList.contains('temp-default')) {
        tempSlider.classList.remove('temp-default');
        if (tempReset) tempReset.style.display = '';
      }
      if (tempVal) tempVal.textContent = parseFloat(tempSlider.value).toFixed(1);
    });
    tempSlider.addEventListener('change', function() {
      window._currentSettings.temperature = tempSlider.value;
      _sendAllSettings();
    });
  }
  if (tempReset) {
    tempReset.addEventListener('click', function() {
      tempSlider.value = '1.0';
      tempSlider.classList.add('temp-default');
      if (tempVal) tempVal.textContent = 'Default';
      tempReset.style.display = 'none';
      window._currentSettings.temperature = '';
      _sendAllSettings();
    });
  }

  // System prompt expand modal
  var expandBtn = document.getElementById('expandSysMsg');
  if (expandBtn) expandBtn.addEventListener('click', function() {
    var overlay = document.getElementById('sysMsgOverlay');
    var mini = document.getElementById('sysMsgMini');
    var full = document.getElementById('sysMsgFull');
    if (overlay && mini && full) {
      full.value = mini.value;
      overlay.classList.add('open');
    }
  });

  // System prompt save
  var sysMsgSave = document.getElementById('sysMsgSave');
  if (sysMsgSave) sysMsgSave.addEventListener('click', function() {
    var full = document.getElementById('sysMsgFull');
    var mini = document.getElementById('sysMsgMini');
    var overlay = document.getElementById('sysMsgOverlay');
    if (full && mini) {
      mini.value = full.value;
      window._currentSettings.systemMessage = full.value;
      _sendAllSettings();
    }
    if (overlay) overlay.classList.remove('open');
  });

  // System prompt close/cancel
  var sysMsgClose = document.getElementById('sysMsgClose');
  var sysMsgCancel = document.getElementById('sysMsgCancel');
  if (sysMsgClose) sysMsgClose.addEventListener('click', function() {
    document.getElementById('sysMsgOverlay').classList.remove('open');
  });
  if (sysMsgCancel) sysMsgCancel.addEventListener('click', function() {
    document.getElementById('sysMsgOverlay').classList.remove('open');
  });
  // Overlay background click
  var sysMsgOverlay = document.getElementById('sysMsgOverlay');
  if (sysMsgOverlay) sysMsgOverlay.addEventListener('click', function(e) {
    if (e.target === sysMsgOverlay) sysMsgOverlay.classList.remove('open');
  });

  // Thinking level dropdown
  var thinkingDropdown = document.getElementById('reasoningDropdown');
  if (thinkingDropdown) thinkingDropdown.addEventListener('change', function() {
    window._currentSettings.reasoning = thinkingDropdown.value;
    _sendAllSettings();
  });

  // Advanced toggle
  var advToggle = document.getElementById('advancedToggle');
  var advWrap = document.getElementById('advancedWrap');
  if (advToggle && advWrap) advToggle.addEventListener('click', function() {
    advWrap.classList.toggle('open');
  });

  // Toggle switches (right rail only — avoid double-handling settings panel switches)
  document.querySelectorAll('#railRight .toggle-row .switch').forEach(function(sw) {
    sw.addEventListener('click', function() {
      sw.classList.toggle('on');
      _sendAllSettings();
    });
  });

  // Model card click — handled by chat-settings.js
});

} // end DOMContentLoaded guard
