// ======================================================
// general.js — General settings section (Thread Titles, API Logs, Trash)
// ======================================================

(function() {
  var sectionName = 'general';

  function load(data) {
    // Thread Titles
    if (data && data.threadTitles) {
      var tt = data.threadTitles;
      var toggle = document.getElementById('titleGenToggle');
      var fields = document.getElementById('titleGenFields');
      if (toggle) {
        if (tt.enabled) {
          toggle.classList.add('on');
          if (fields) fields.classList.remove('fields-disabled');
        } else {
          toggle.classList.remove('on');
          if (fields) fields.classList.add('fields-disabled');
        }
      }
      var modelSel = document.getElementById('titleGenModel');
      if (modelSel && data.models) fillSelect(modelSel, Object.keys(data.models).sort(), tt.model);
      var promptTa = document.getElementById('titleGenPrompt');
      if (promptTa) promptTa.value = tt.prompt || '';
      var maxTok = document.getElementById('titleGenMaxTokens');
      if (maxTok) maxTok.value = tt.maxTokens || 50;
    }
    // API Logs
    if (data && data.apiLogs) {
      var logEntries = document.getElementById('apiLogMaxEntries');
      if (logEntries && data.apiLogs.maxEntries !== undefined) logEntries.value = data.apiLogs.maxEntries;
    }
    // Trash
    if (data && data.trash) {
      var trashDays = document.getElementById('trashRetentionDays');
      if (trashDays && data.trash.retentionDays !== undefined) trashDays.value = data.trash.retentionDays;
    }
    // Chat Shortcut
    if (data && data.chatShortcut !== undefined) {
      var cs = document.getElementById('chatShortcut');
      if (cs) cs.value = data.chatShortcut || '';
    }
  }

  function num(v, dflt) { var n = parseInt(v, 10); return isNaN(n) ? dflt : n; }

  function save() {
    var data = {};
    // Thread Titles
    var toggle = document.getElementById('titleGenToggle');
    data.threadTitles = {
      enabled: toggle ? toggle.classList.contains('on') : true,
      model: (document.getElementById('titleGenModel') || {}).value || 'deepseek/deepseek-v4-flash',
      prompt: (document.getElementById('titleGenPrompt') || {}).value || '',
      maxTokens: num((document.getElementById('titleGenMaxTokens') || {}).value, 50)
    };
    // API Logs
    data.apiLogs = {
      maxEntries: num((document.getElementById('apiLogMaxEntries') || {}).value, 20)
    };
    // Trash
    data.trash = {
      retentionDays: num((document.getElementById('trashRetentionDays') || {}).value, 30)
    };
    // Chat Shortcut
    data.chatShortcut = (document.getElementById('chatShortcut') || {}).value || '';
    return data;
  }

  // Wire toggle
  function wireToggle() {
    var toggle = document.getElementById('titleGenToggle');
    var fields = document.getElementById('titleGenFields');
    if (!toggle || !fields) return;
    toggle.addEventListener('click', function() {
      this.classList.toggle('on');
      if (this.classList.contains('on')) {
        fields.classList.remove('fields-disabled');
      } else {
        fields.classList.add('fields-disabled');
      }
      if (window.SettingsPanel) window.SettingsPanel.markDirty();
    });
  }

  // Wire all fields for dirty tracking
  function wireDirty() {
    var container = document.getElementById('sec-general');
    if (!container) return;
    container.querySelectorAll('input, select, textarea').forEach(function(el) {
      el.addEventListener('change', function() {
        if (window.SettingsPanel) window.SettingsPanel.markDirty();
      });
      el.addEventListener('input', function() {
        if (window.SettingsPanel) window.SettingsPanel.markDirty();
      });
    });
  }

  function fillSelect(sel, keys, current) {
    if (!sel) return;
    sel.innerHTML = '';
    if (current != null && keys.indexOf(current) < 0) keys.unshift(current);
    keys.forEach(function(k) { var o = document.createElement('option'); o.value = k; o.textContent = k; sel.appendChild(o); });
    if (current != null) sel.value = current;
  }

  // Initialize
  if (typeof document !== 'undefined' && document.addEventListener) {
    document.addEventListener('DOMContentLoaded', function() {
      wireToggle();
      wireDirty();
    });
  }

  // Register with settings panel
  if (typeof window !== 'undefined' && window.SettingsPanel) {
    window.SettingsPanel.registerSection(sectionName, { load: load, save: save });
  } else {
    // Defer registration
    window.addEventListener('load', function() {
      if (window.SettingsPanel) {
        window.SettingsPanel.registerSection(sectionName, { load: load, save: save });
      }
    });
  }
})();
