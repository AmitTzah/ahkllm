// sysmsg-modal.js — shared system message edit modal (open + save)
(function() {
  var S = window.SettingsShared;

  function postAction(action) {
    if (typeof Ipc !== 'undefined' && Ipc && typeof Ipc.postToHost === 'function') Ipc.postToHost(action);
  }
  function requestSystemMessageFiles() { postAction('requestSystemMessageFiles'); }
  function optionHtml(value, label) { return '<option value="' + S.escHtml(value) + '">' + S.escHtml(label) + '</option>'; }

  function selectStoredFile(fileSelect, stored) {
    if (!fileSelect || !stored) return;
    fileSelect.value = stored;
    if (fileSelect.selectedIndex !== -1) return;
    var bareName = String(stored).replace(/^.*[\\/]/, '');
    if (fileSelect.options) {
      for (var i = 0; i < fileSelect.options.length; i++) {
        var optionValue = String(fileSelect.options[i].value || '');
        if (optionValue === bareName || optionValue.replace(/^.*[\\/]/, '') === bareName) {
          fileSelect.selectedIndex = i;
          return;
        }
      }
    }
    fileSelect.value = bareName;
  }

  function systemMessageSummary(filePath, inlineText) {
    if (filePath) return '\uD83D\uDCC4 ' + String(filePath);
    var normalized = String(inlineText || '').replace(/\s+/g, ' ').trim();
    if (!normalized) return '\uD83D\uDCC4 (none)';
    var preview = normalized.length > 96 ? normalized.slice(0, 93) + '...' : normalized;
    return '\uD83D\uDCC4 (inline) \u00B7 ' + preview;
  }

  window.updateSystemMessageFiles = function(data) {
    data = data || {};
    var defaultGroup = document.getElementById('smDefaultFiles');
    var userGroup = document.getElementById('smUserFiles');
    var folderPath = document.getElementById('smUserFolderPath');
    var fileSelect = document.getElementById('smFileSelect');
    var modal = document.getElementById('sysMsgEditModal');
    var defaultFiles = Array.isArray(data.defaultFiles) ? data.defaultFiles.slice().sort() : [];
    var userFiles = Array.isArray(data.userFiles) ? data.userFiles.slice().sort() : [];
    if (defaultGroup) defaultGroup.innerHTML = defaultFiles.map(function(name) { return optionHtml('default-settings/system-messages/' + name, name); }).join('');
    if (userGroup) userGroup.innerHTML = userFiles.length
      ? userFiles.map(function(name) { return optionHtml('system-messages/' + name, name); }).join('')
      : '<option value="" disabled>(no custom .txt files yet)</option>';
    if (folderPath) folderPath.textContent = data.userFolder || '%APPDATA%\\AhkLLM\\system-messages';
    if (fileSelect && modal && modal.dataset) selectStoredFile(fileSelect, modal.dataset.sysMsgFile || '');
  };

  window.populateSysMsgModal = function(opts) {
    opts = opts || {};
    var modal = document.getElementById('sysMsgEditModal');
    if (!modal) return;
    modal.dataset.sysMsgFile = opts.systemMessageFile || '';
    var fileRadio = modal.querySelector('input[name="sysMsgMode"][value="file"]');
    var inlineRadio = modal.querySelector('input[name="sysMsgMode"][value="inline"]');
    var fileSection = document.getElementById('smFileSection');
    var inlineSection = document.getElementById('smInlineSection');
    var fileSelect = document.getElementById('smFileSelect');
    var inlineText = document.getElementById('smInlineText');
    if (inlineText) inlineText.value = opts.systemMessage || '';
    if (fileSelect) selectStoredFile(fileSelect, opts.systemMessageFile || '');
    if (opts.systemMessageFile) {
      if (fileRadio) fileRadio.checked = true;
      if (inlineRadio) inlineRadio.checked = false;
      if (fileSection) fileSection.style.display = '';
      if (inlineSection) inlineSection.style.display = 'none';
    } else {
      if (inlineRadio) inlineRadio.checked = true;
      if (fileRadio) fileRadio.checked = false;
      if (inlineSection) inlineSection.style.display = '';
      if (fileSection) fileSection.style.display = 'none';
    }
    modal.classList.add('open');
    requestSystemMessageFiles();
  };

  if (typeof document !== 'undefined') {
    document.addEventListener('DOMContentLoaded', function() {
      var modal = document.getElementById('sysMsgEditModal');
      var fileRadio = modal ? modal.querySelector('input[name="sysMsgMode"][value="file"]') : null;
      var inlineRadio = modal ? modal.querySelector('input[name="sysMsgMode"][value="inline"]') : null;
      function syncSysMsgSections() {
        var isInline = !!(inlineRadio && inlineRadio.checked);
        var fileSection = document.getElementById('smFileSection');
        var inlineSection = document.getElementById('smInlineSection');
        var inlineText = document.getElementById('smInlineText');
        if (fileSection) fileSection.style.display = isInline ? 'none' : '';
        if (inlineSection) inlineSection.style.display = isInline ? '' : 'none';
        if (isInline && inlineText && typeof inlineText.focus === 'function') inlineText.focus();
        if (!isInline) requestSystemMessageFiles();
      }
      if (fileRadio) fileRadio.addEventListener('change', syncSysMsgSections);
      if (inlineRadio) inlineRadio.addEventListener('change', syncSysMsgSections);

      var openFolder = document.getElementById('smOpenFolder');
      if (openFolder) openFolder.addEventListener('click', function() { postAction('openSystemMessagesFolder'); });
      var refreshFiles = document.getElementById('smRefreshFiles');
      if (refreshFiles) refreshFiles.addEventListener('click', requestSystemMessageFiles);

      var saveBtn = document.getElementById('sysMsgEditSave');
      if (!saveBtn) return;
      saveBtn.addEventListener('click', function() {
        var t = window._sysMsgTarget;
        if (!t) return;
        var modal = document.getElementById('sysMsgEditModal');
        var inlineRadio = modal ? modal.querySelector('input[name="sysMsgMode"][value="inline"]') : null;
        var isInline = inlineRadio && inlineRadio.checked;
        var sysMsg = '', sysMsgFile = '';
        if (isInline) {
          var inlineText = document.getElementById('smInlineText');
          sysMsg = inlineText ? inlineText.value : '';
        } else {
          var fileSelect = document.getElementById('smFileSelect');
          sysMsgFile = fileSelect ? fileSelect.value : '';
          if (fileSelect && fileSelect.selectedIndex === -1 && modal && modal.dataset && modal.dataset.sysMsgFile) sysMsgFile = modal.dataset.sysMsgFile;
        }
        if (t.type === 'assistant') {
          t.card.dataset.systemMessage = sysMsg;
          t.card.dataset.systemMessageFile = sysMsgFile;
          var label = t.card.querySelector('.sysmsg-label');
          if (label) {
            label.textContent = systemMessageSummary(sysMsgFile, sysMsg);
            label.title = sysMsgFile || sysMsg || '';
          }
        } else if (t.type === 'command') {
          var C = window.Cmds;
          if (C) {
            var cmd = C.commands()[t.idx];
            if (cmd) { cmd.systemMessage = sysMsg; cmd.systemMessageFile = sysMsgFile; }
            C.selectCommand(t.idx);
          }
        }
        if (modal) modal.classList.remove('open');
        S.markDirty();
      });
    });
  }
})();
