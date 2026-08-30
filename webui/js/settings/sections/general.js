// ======================================================
// general.js — General settings section (Thread Titles, API Logs, Trash, Backups)
// ======================================================

(function() {
  var sectionName = 'general';
  var S = window.SettingsShared;

  // Populate the "New Chats Start With" dropdown: App Default first, then the
  // configured assistants ("asst:<id>"), then every available model. A saved
  // value that no longer exists (e.g. a removed model) is appended so the user
  // can see and change it.
  function fillNewChatDefault(sel, modelKeys, assistants, current) {
    sel.innerHTML = '';
    var values = [];
    function addOption(o) { values.push(o.value); sel.appendChild(o); }
    var opt = document.createElement('option');
    opt.value = '';
    // App Default is the application's configured default model. Assistants
    // are selected explicitly below, so this label has no hidden fallback.


    opt.textContent = 'App Default (deepseek/deepseek-v4-flash)';
    addOption(opt);
    if (assistants && assistants.length) {
      var og = document.createElement('optgroup');
      og.label = 'Assistants';
      assistants.forEach(function(a) {
        var o = document.createElement('option');
        o.value = 'asst:' + (a.id || '');
        o.textContent = a.name || '(unnamed assistant)';
        og.appendChild(o);
        values.push(o.value);
      });
      sel.appendChild(og);
    }
    var mg = document.createElement('optgroup');
    mg.label = 'Models';
    (modelKeys || []).forEach(function(m) {
      var o = document.createElement('option');
      o.value = m;
      o.textContent = m;
      addOption(o);
    });
    sel.appendChild(mg);
    if (current && values.indexOf(current) < 0) {
      var extra = document.createElement('option');
      extra.value = current;
      extra.textContent = current + ' (removed)';
      addOption(extra);
    }
    if (current) sel.value = current;
  }

  function load(data) {
    // New Chats Start With
    if (data && data.models) {
      var ncs = document.getElementById('newChatStartsWith');
      if (ncs) {
        fillNewChatDefault(ncs, Object.keys(data.models).sort(), (data && data.assistants) || [], data.newChatStartsWith || '');
      }
    }
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
      if (modelSel && data.models) S.fillSelect(modelSel, Object.keys(data.models).sort(), tt.model);
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
    // Web Search (Tavily key; DeepSeek models search natively)
    if (data && data.tavilyApiKey !== undefined) {
      var tk = document.getElementById('tavilyApiKey');
      if (tk) tk.value = data.tavilyApiKey || '';
    }
    if (data && data.backup) {
      var backup = data.backup;
      var enabled = document.getElementById('backupEnabledToggle');
      var folder = document.getElementById('backupFolder');
      if (enabled) enabled.classList.toggle('on', !!backup.enabled);
      if (folder) folder.value = backup.folder || '';
    }
    if (data && data.backupStatus) onBackupStatus(data.backupStatus);
  }

  function save() {
    var data = {};
    // Thread Titles
    var toggle = document.getElementById('titleGenToggle');
    data.threadTitles = {
      enabled: toggle ? toggle.classList.contains('on') : true,
      model: (document.getElementById('titleGenModel') || {}).value || 'deepseek/deepseek-v4-flash',
      prompt: (document.getElementById('titleGenPrompt') || {}).value || '',
      maxTokens: S.num((document.getElementById('titleGenMaxTokens') || {}).value, 50)
    };
    // API Logs
    data.apiLogs = {
      maxEntries: S.num((document.getElementById('apiLogMaxEntries') || {}).value, 20)
    };
    // Trash
    data.trash = {
      retentionDays: S.num((document.getElementById('trashRetentionDays') || {}).value, 30)
    };
    // Chat Shortcut
    data.chatShortcut = (document.getElementById('chatShortcut') || {}).value || '';
    // Web Search (Tavily key)
    data.tavilyApiKey = (document.getElementById('tavilyApiKey') || {}).value || '';
    // New Chats Start With
    data.newChatStartsWith = (document.getElementById('newChatStartsWith') || {}).value || '';
    var backupToggle = document.getElementById('backupEnabledToggle');
    data.backup = {
      enabled: backupToggle ? backupToggle.classList.contains('on') : false,
      folder: (document.getElementById('backupFolder') || {}).value || ''
    };
    return data;
  }

  function onFolderSelected(folder) {
    var input = document.getElementById('backupFolder');
    if (!input) return;
    input.value = folder || '';
    S.markDirty();
  }

  function onBackupStatus(status) {
    var el = document.getElementById('backupStatus');
    if (el && status) el.textContent = status.text || 'No backup has been created yet';
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
      S.markDirty();
    });
  }

  function wireBackupControls() {
    var toggle = document.getElementById('backupEnabledToggle');
    if (toggle) toggle.addEventListener('click', function() {
      this.classList.toggle('on');
      S.markDirty();
    });
    var browse = document.getElementById('backupBrowseBtn');
    if (browse) browse.addEventListener('click', function() {
      var folder = (document.getElementById('backupFolder') || {}).value || '';
      Ipc.postToHost('browseBackupFolder', { folder: folder });
    });
    var now = document.getElementById('backupNowBtn');
    if (now) now.addEventListener('click', function() {
      onBackupStatus({ text: 'Backup pending' });
      var current = save().backup;
      Ipc.request('backupNow', { backup: current }).catch(function(err) {
        onBackupStatus({ text: 'Backup failed: ' + ((err && err.message) || 'request failed') });
      });
    });
  }

  // Initialize
  if (typeof document !== 'undefined' && document.addEventListener) {
    document.addEventListener('DOMContentLoaded', function() {
      wireToggle();
      wireBackupControls();
      S.wireDirty('sec-general', S.markDirty);
    });
  }

  window.SettingsGeneral = { onFolderSelected: onFolderSelected, onBackupStatus: onBackupStatus };
  S.registerSection(sectionName, { load: load, save: save });
})();
