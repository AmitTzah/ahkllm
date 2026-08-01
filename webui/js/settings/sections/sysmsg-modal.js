// sysmsg-modal.js — shared system message edit modal (open + save)
(function() {
  var S = window.SettingsShared;

  // Populate the modal when opening — called by both commands and assistants.
  window.populateSysMsgModal = function(opts) {
    var modal = document.getElementById('sysMsgEditModal');
    if (!modal) return;
    var fileRadio = modal.querySelector('input[name="sysMsgMode"][value="file"]');
    var inlineRadio = modal.querySelector('input[name="sysMsgMode"][value="inline"]');
    var fileSection = document.getElementById('smFileSection');
    var inlineSection = document.getElementById('smInlineSection');
    var fileSelect = document.getElementById('smFileSelect');
    var inlineText = document.getElementById('smInlineText');
    if (opts.systemMessageFile) {
      if (fileRadio) fileRadio.checked = true;
      if (inlineRadio) inlineRadio.checked = false;
      if (fileSection) fileSection.style.display = '';
      if (inlineSection) inlineSection.style.display = 'none';
      if (fileSelect) {
        fileSelect.value = opts.systemMessageFile;
        // Stored value may include a directory prefix (e.g. "system-messages/refine.txt")
        // while the select options are bare filenames. Strip the prefix if no match.
        if (fileSelect.selectedIndex === -1 && opts.systemMessageFile.indexOf('/') >= 0) {
          var bareName = opts.systemMessageFile.replace(/^.*[\\/]/, '');
          fileSelect.value = bareName;
        }
      }
    } else {
      if (inlineRadio) inlineRadio.checked = true;
      if (fileRadio) fileRadio.checked = false;
      if (inlineSection) inlineSection.style.display = '';
      if (fileSection) fileSection.style.display = 'none';
      if (inlineText) inlineText.value = opts.systemMessage || '';
    }
    modal.classList.add('open');
  };

  // Save button handler — wired once on DOMContentLoaded.
  if (typeof document !== 'undefined') {
    document.addEventListener('DOMContentLoaded', function() {
      // File/inline radio: swap which section is visible.
      var modal = document.getElementById('sysMsgEditModal');
      var fileRadio = modal ? modal.querySelector('input[name="sysMsgMode"][value="file"]') : null;
      var inlineRadio = modal ? modal.querySelector('input[name="sysMsgMode"][value="inline"]') : null;
      function syncSysMsgSections() {
        var isInline = !!(inlineRadio && inlineRadio.checked);
        var fileSection = document.getElementById('smFileSection');
        var inlineSection = document.getElementById('smInlineSection');
        if (fileSection) fileSection.style.display = isInline ? 'none' : '';
        if (inlineSection) inlineSection.style.display = isInline ? '' : 'none';
      }
      if (fileRadio) fileRadio.addEventListener('change', syncSysMsgSections);
      if (inlineRadio) inlineRadio.addEventListener('change', syncSysMsgSections);

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
        }
        if (t.type === 'assistant') {
          t.card.dataset.systemMessage = sysMsg;
          t.card.dataset.systemMessageFile = sysMsgFile;
          var label = t.card.querySelector('.sysmsg-label');
          if (label) label.textContent = '\uD83D\uDCC4 ' + (sysMsgFile || (sysMsg ? '(inline)' : '(none)'));
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
