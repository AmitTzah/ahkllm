// ======================================================
// icons.js — Icons settings section (tray icons)
// ======================================================

(function() {
  var sectionName = 'icons';

  function load(data) {
    if (data && data.icons) {
      var iconOnEl = document.getElementById('iconOnPath');
      var iconOffEl = document.getElementById('iconOffPath');
      if (iconOnEl) iconOnEl.value = data.icons.iconOn || '';
      if (iconOffEl) iconOffEl.value = data.icons.iconOff || '';
    }
  }

  function save() {
    return {
      icons: {
        iconOn: (document.getElementById('iconOnPath') || {}).value || '',
        iconOff: (document.getElementById('iconOffPath') || {}).value || ''
      }
    };
  }

  // Wire dirty tracking
  function wireDirty() {
    var container = document.getElementById('sec-icons');
    if (!container) return;
    container.querySelectorAll('input').forEach(function(el) {
      el.addEventListener('change', function() {
        if (window.SettingsPanel) window.SettingsPanel.markDirty();
      });
      el.addEventListener('input', function() {
        if (window.SettingsPanel) window.SettingsPanel.markDirty();
      });
    });
  }

  if (typeof document !== 'undefined' && document.addEventListener) {
    document.addEventListener('DOMContentLoaded', function() {
      wireDirty();
      // Wire Browse buttons
      var container = document.getElementById('sec-icons');
      if (container) {
        container.querySelectorAll('button[data-icon-field]').forEach(function(btn) {
          btn.addEventListener('click', function() {
            var field = this.getAttribute('data-icon-field');
            window.chrome.webview.postMessage(JSON.stringify({action:'browseIcon', field: field}));
          });
        });
      }
    });
  }

  // Register with settings panel
  if (typeof window !== 'undefined' && window.SettingsPanel) {
    window.SettingsPanel.registerSection(sectionName, { load: load, save: save });
  } else {
    window.addEventListener('load', function() {
      if (window.SettingsPanel) {
        window.SettingsPanel.registerSection(sectionName, { load: load, save: save });
      }
    });
  }

  // Expose handler for icon file selection from AHK
  window.SettingsIcons = {
    onFileSelected: function(field, path) {
      var targetId = field === 'iconOn' ? 'iconOnPath' : 'iconOffPath';
      var el = document.getElementById(targetId);
      if (el) {
        el.value = path;
        if (window.SettingsPanel) window.SettingsPanel.markDirty();
      }
    }
  };
})();
