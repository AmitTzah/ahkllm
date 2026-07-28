// ======================================================
// settings-panel.js — Settings panel tab switching, IPC, dirty tracking
// ======================================================

window.SettingsPanel = (function() {
  var _dirty = false;
  var _initialized = false;
  var _defaultSettings = null;
  var _currentSettings = null;
  var _sectionModules = {};
  var _navItems = [];
  var _allSections = [];

  function init() {
    if (_initialized) return; // listeners are wired once — re-entry would duplicate them
    _initialized = true;
    _navItems = document.querySelectorAll('.settings-nav .nav-item[data-section]');
    _allSections = document.querySelectorAll('.section-card[id^="sec-"]');

    // Wire nav clicks
    _navItems.forEach(function(item) {
      item.addEventListener('click', function() {
        showSection(this.getAttribute('data-section'));
      });
    });

    // Wire Save button
    var saveBtn = document.querySelector('.nav-footer .btn-primary');
    if (saveBtn) {
      saveBtn.addEventListener('click', function() {
        saveSettings();
      });
    }

    // Wire Reset button — opens confirmation modal
    var resetBtn = document.querySelector('.nav-footer .btn-ghost');
    if (resetBtn) {
      resetBtn.addEventListener('click', function() {
        resetToDefaults();
      });
    }

    // Show general by default
    showSection('general');
  }

  function showSection(sectionName) {
    _allSections.forEach(function(s) { s.style.display = 'none'; });
    var target = document.getElementById('sec-' + sectionName);
    if (target) target.style.display = '';
    _navItems.forEach(function(n) { n.classList.remove('active'); });
    var activeNav = document.querySelector('.settings-nav .nav-item[data-section="' + sectionName + '"]');
    if (activeNav) activeNav.classList.add('active');
    var content = document.querySelector('.settings-content');
    if (content) content.scrollTop = 0;
  }

  function markDirty() {
    if (_dirty) return;
    _dirty = true;
    var saveBtn = document.querySelector('.nav-footer .btn-primary');
    if (saveBtn) saveBtn.disabled = false;
  }

  function clearDirty() {
    _dirty = false;
    var saveBtn = document.querySelector('.nav-footer .btn-primary');
    if (saveBtn) saveBtn.disabled = true;
  }

  function isDirty() {
    return _dirty;
  }

  function loadSettings(settings) {
    _defaultSettings = JSON.parse(JSON.stringify(settings)); // deep clone
    _currentSettings = settings;
    clearDirty();
  }

  function saveSettings() {
    if (!_currentSettings) return;
    // Collect data from all registered section modules
    var data = {};
    for (var key in _sectionModules) {
      if (_sectionModules[key] && typeof _sectionModules[key].save === 'function') {
        var sectionData = _sectionModules[key].save();
        if (sectionData) {
          for (var k in sectionData) {
            data[k] = sectionData[k];
          }
        }
      }
    }
    window.chrome.webview.postMessage(JSON.stringify({
      action: 'saveSettings',
      data: data
    }));
  }

  function resetToDefaults() {
    window._showConfirm('Reset to Defaults', 'Reset all settings to their default values? This cannot be undone.', 'Reset', function() {
      window.chrome.webview.postMessage(JSON.stringify({ action: 'requestDefaultSettings' }));
    });
  }

  function reloadWithDefaults(defaults) {
    if (!defaults) return;
    _defaultSettings = JSON.parse(JSON.stringify(defaults));
    for (var key in _sectionModules) {
      if (_sectionModules[key] && typeof _sectionModules[key].load === 'function') {
        _sectionModules[key].load(defaults);
      }
    }
    markDirty();
  }

  function handleSettingsSaved(response) {
    if (response && response.success) {
      clearDirty();
      console.log('[Settings] Saved successfully');
    } else {
      console.error('[Settings] Save failed:', response ? response.error : 'unknown');
    }
  }

  function registerSection(name, module) {
    _sectionModules[name] = module;
  }

  // Called by main.js when settings data arrives from AHK
  function onSettingsReceived(data) {
    loadSettings(data);
    for (var key in _sectionModules) {
      if (_sectionModules[key] && typeof _sectionModules[key].load === 'function') {
        _sectionModules[key].load(data);
      }
    }
  }

  return {
    init: init,
    showSection: showSection,
    markDirty: markDirty,
    clearDirty: clearDirty,
    isDirty: isDirty,
    saveSettings: saveSettings,
    resetToDefaults: resetToDefaults,
    handleSettingsSaved: handleSettingsSaved,
    registerSection: registerSection,
    onSettingsReceived: onSettingsReceived,
    reloadWithDefaults: reloadWithDefaults
  };
})();
