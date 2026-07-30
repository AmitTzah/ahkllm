// assistants.js — Assistants settings section
(function() {
  var sectionName = 'assistants';
  var _editingCard = null;
  var _modelKeys = ['deepseek/deepseek-v4-pro', 'deepseek/deepseek-v4-flash', 'openai/gpt-4o', 'google/gemini-2.5-flash'];

  function load(data) {
    if (!data || !data.assistants) return;
    if (data.models) _modelKeys = Object.keys(data.models).sort();
    renderCards(data.assistants, data.models);
  }

  // --- Card HTML template (shared by renderCards and addAssistant) ---

  function cardHTML(a, modelKeys) {
    var modelOpts = buildModelOptions(modelKeys, a.baseModel || '');
    var sysMsgLabel = '\uD83D\uDCC4 ' + (a.systemMessageFile || (a.systemMessage ? '(inline)' : '(none)'));
    return '<div class="provider-card-header"><input value="' + escHtml(a.name || '') + '" data-field="name" style="border:none;font-weight:600;font-size:14px;background:transparent;width:auto;">' +
      (a.isDefault ? '<span class="badge" style="margin-left:8px;">default</span>' : '') +
      '<button class="btn-sm danger" style="margin-left:auto;">Remove</button></div>' +
      '<div class="grid-2"><div class="field"><label class="field-label">Base Model</label><select data-field="baseModel">' + modelOpts + '</select></div>' +
      '<div class="field"><label class="field-label">Reasoning</label><select data-field="reasoning"><option value="">Model Default</option><option value="none">None</option><option value="minimal">Minimal</option><option value="low">Low</option><option value="medium">Medium</option><option value="high">High</option></select></div></div>' +
      '<div class="field"><label class="field-label">System Message</label><div style="display:flex;align-items:center;gap:8px;"><span class="sysmsg-label" style="font-size:12px;font-family:var(--font-mono);color:var(--text-secondary);">' + escHtml(sysMsgLabel) + '</span><button class="btn-sm edit-sysmsg">Edit</button></div><div class="field-hint">From app defaults (system-messages/). Create your own in AppData\\...\\system-messages\\</div></div>' +
      '<div class="field"><label class="field-label">Description</label><input type="text" value="' + escHtml(a.description || '') + '" data-field="description"></div>' +
      '<div class="toggle-row"><span class="lbl">Set as Default Assistant</span><div class="switch' + (a.isDefault ? ' on' : '') + '" data-field="isDefault" data-type="radio"><div class="knob"></div></div></div>';
  }

  // --- Card wiring (event listeners) ---

  function wireCard(card, grid) {
    // Set select values from dataset
    card.querySelectorAll('select').forEach(function(sel) {
      var field = sel.dataset.field;
      var val = card.dataset['orig_' + field];
      if (val === undefined) return;
      for (var i = 0; i < sel.options.length; i++) {
        if (sel.options[i].value === val) { sel.selectedIndex = i; break; }
      }
    });
    // Input change tracking
    card.querySelectorAll('input, select').forEach(function(el) { el.addEventListener('change', mark); el.addEventListener('input', mark); });
    // Switches
    card.querySelectorAll('.switch').forEach(function(sw) {
      sw.addEventListener('click', function() {
        if (sw.dataset.type === 'radio') {
          if (!sw.classList.contains('on')) {
            grid.querySelectorAll('.switch[data-type=radio]').forEach(function(s) { s.classList.remove('on'); });
            sw.classList.add('on');
          }
        } else { sw.classList.toggle('on'); }
        mark();
      });
    });
    // Remove button
    card.querySelector('.btn-sm.danger').addEventListener('click', function() { card.remove(); mark(); });
    // Edit system message
    card.querySelector('.edit-sysmsg').addEventListener('click', function() { openSysMsgModal(card); });
  }

  function openSysMsgModal(card) {
    window._sysMsgTarget = { type: 'assistant', card: card };
    var modal = document.getElementById('sysMsgEditModal');
    if (!modal) return;
    var inlineText = document.getElementById('smInlineText');
    var fileSelect = document.getElementById('smFileSelect');
    var inlineRadio = modal.querySelector('input[name="sysMsgMode"][value="inline"]');
    var fileRadio = modal.querySelector('input[name="sysMsgMode"][value="file"]');
    var inlineSection = document.getElementById('smInlineSection');
    var fileSection = document.getElementById('smFileSection');
    if (card.dataset.systemMessageFile) {
      if (fileRadio) fileRadio.checked = true;
      if (inlineRadio) inlineRadio.checked = false;
      if (inlineSection) inlineSection.style.display = 'none';
      if (fileSection) fileSection.style.display = '';
      if (fileSelect) fileSelect.value = card.dataset.systemMessageFile;
    } else {
      if (inlineRadio) inlineRadio.checked = true;
      if (fileRadio) fileRadio.checked = false;
      if (inlineSection) inlineSection.style.display = '';
      if (fileSection) fileSection.style.display = 'none';
      if (inlineText) inlineText.value = card.dataset.systemMessage || '';
    }
    modal.classList.add('open');
  }

  // --- Main render ---

  function renderCards(assistants, models) {
    var grid = document.getElementById('assistantGrid');
    if (!grid) return;
    grid.innerHTML = '';
    var countEl = document.getElementById('assistantCount');
    if (countEl) countEl.textContent = assistants.length + ' assistants defined — click + to add inline';
    var modelKeys = models ? Object.keys(models).sort() : _modelKeys;
    assistants.forEach(function(a) {
      var card = createCard(a, modelKeys, grid);
      grid.appendChild(card);
    });
  }

  function createCard(a, modelKeys, grid) {
    var card = document.createElement('div');
    card.className = 'provider-card';
    card.dataset.id = a.id || '';
    card.dataset.systemMessage = a.systemMessage || '';
    card.dataset.systemMessageFile = a.systemMessageFile || '';
    // Stash original values for select restoration
    card.dataset.orig_baseModel = a.baseModel || '';
    card.dataset.orig_reasoning = a.reasoning || '';
    card.innerHTML = cardHTML(a, modelKeys);
    wireCard(card, grid);
    return card;
  }

  function buildModelOptions(keys, current) {
    var html = '';
    var all = keys.slice();
    if (current != null && all.indexOf(current) < 0) all.unshift(current);
    all.forEach(function(k) { html += '<option' + (k === current ? ' selected' : '') + '>' + k + '</option>'; });
    return html;
  }

  function mark() { if (window.SettingsPanel) window.SettingsPanel.markDirty(); }

  function save() {
    var assistants = [];
    document.querySelectorAll('#assistantGrid .provider-card').forEach(function(card) {
      var obj = { id: card.dataset.id || generateUUID() };
      card.querySelectorAll('[data-field]').forEach(function(el) {
        if (el.classList.contains('switch')) obj[el.dataset.field] = el.classList.contains('on');
        else obj[el.dataset.field] = el.value || '';
      });
      obj.systemMessage = card.dataset.systemMessage || '';
      obj.systemMessageFile = card.dataset.systemMessageFile || '';
      assistants.push(obj);
    });
    return { assistants: assistants };
  }

  function addAssistant() {
    var grid = document.getElementById('assistantGrid'); if (!grid) return;
    var a = { id: generateUUID(), name: 'New Assistant', baseModel: '', reasoning: '', systemMessage: '', systemMessageFile: '', description: '', isDefault: false };
    var card = createCard(a, _modelKeys, grid);
    grid.appendChild(card);
    mark();
  }

  function generateUUID() { return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, function(c) { var r = Math.random()*16|0, v = c=='x'?r:(r&0x3|0x8); return v.toString(16); }); }
  function escHtml(s) { return String(s).replace(/&/g,'\x26amp;').replace(/</g,'\x26lt;').replace(/>/g,'\x26gt;').replace(/"/g,'\x26quot;'); }

  // Shared sysMsg modal save handler (used by both assistants and commands)
  if (typeof document !== 'undefined') {
    document.addEventListener('DOMContentLoaded', function() {
      var addBtn = document.getElementById('addAssistantBtn');
      if (addBtn) addBtn.addEventListener('click', addAssistant);
      var saveBtn = document.getElementById('sysMsgEditSave');
      if (saveBtn) {
        saveBtn.addEventListener('click', function() {
          var t = window._sysMsgTarget;
          if (!t) return;
          var inlineRadio = document.querySelector('input[name="sysMsgMode"][value="inline"]');
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
            var cmd = C.commands()[t.idx];
            if (cmd) { cmd.systemMessage = sysMsg; cmd.systemMessageFile = sysMsgFile; }
            C.selectCommand(t.idx); // refresh detail
          }
          var modal = document.getElementById('sysMsgEditModal');
          if (modal) modal.classList.remove('open');
          mark();
        });
      }
    });
  }
  (function reg() { if (window.SettingsPanel) window.SettingsPanel.registerSection(sectionName, {load:load, save:save}); else setTimeout(reg, 50); })();
})();
