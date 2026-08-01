// ======================================================
// icons.js — Icons settings section (tray icons)
// ======================================================

(function() {
  var sectionName = 'icons';
  var S = window.SettingsShared;

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

  if (typeof document !== 'undefined' && document.addEventListener) {
    document.addEventListener('DOMContentLoaded', function() {
      S.wireDirty('sec-icons', S.markDirty);
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

  S.registerSection(sectionName, { load: load, save: save });

  // Expose handler for icon file selection from AHK
  window.SettingsIcons = {
    onFileSelected: function(field, path) {
      var targetId = field === 'iconOn' ? 'iconOnPath' : 'iconOffPath';
      var el = document.getElementById(targetId);
      if (el) {
        el.value = path;
        S.markDirty();
      }
    }
  };
})();
