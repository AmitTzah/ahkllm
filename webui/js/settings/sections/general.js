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
      if (modelSel) modelSel.value = tt.model || 'deepseek/deepseek-v4-flash';
      var promptTa = document.getElementById('titleGenPrompt');
      if (promptTa) promptTa.value = tt.prompt || '';
      var maxTok = document.getElementById('titleGenMaxTokens');
      if (maxTok) maxTok.value = tt.maxTokens || 50;
    }
    // API Logs
    if (data && data.apiLogs) {
      var logEntries = document.getElementById('apiLogMaxEntries');
      if (logEntries) logEntries.value = data.apiLogs.maxEntries || 20;
    }
    // Trash
    if (data && data.trash) {
      var trashDays = document.getElementById('trashRetentionDays');
      if (trashDays) trashDays.value = data.trash.retentionDays || 30;
    }
  }

  function save() {
    var data = {};
    // Thread Titles
    var toggle = document.getElementById('titleGenToggle');
    data.threadTitles = {
      enabled: toggle ? toggle.classList.contains('on') : true,
      model: (document.getElementById('titleGenModel') || {}).value || 'deepseek/deepseek-v4-flash',
      prompt: (document.getElementById('titleGenPrompt') || {}).value || '',
      maxTokens: parseInt((document.getElementById('titleGenMaxTokens') || {}).value) || 50
    };
    // API Logs
    data.apiLogs = {
      maxEntries: parseInt((document.getElementById('apiLogMaxEntries') || {}).value) || 20
    };
    // Trash
    data.trash = {
      retentionDays: parseInt((document.getElementById('trashRetentionDays') || {}).value) || 30
    };
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
