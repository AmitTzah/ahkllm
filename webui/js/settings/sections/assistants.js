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

  function renderCards(assistants, models) {
    var grid = document.getElementById('assistantGrid');
    if (!grid) return;
    grid.innerHTML = '';
    // Update count
    var countEl = document.getElementById('assistantCount');
    if (countEl) countEl.textContent = assistants.length + ' assistants defined — click + to add inline';
    var modelKeys = models ? Object.keys(models).sort() : _modelKeys;
    assistants.forEach(function(a) {
      var card = document.createElement('div'); card.className = 'provider-card'; card.dataset.id = a.id || '';
      // Stash system message data on the card element (not collected by [data-field])
      card.dataset.systemMessage = a.systemMessage || '';
      card.dataset.systemMessageFile = a.systemMessageFile || '';
      var modelOpts = buildModelOptions(modelKeys, a.baseModel);
      card.innerHTML = '<div class="provider-card-header"><input value="' + escHtml(a.name || '') + '" data-field="name" style="border:none;font-weight:600;font-size:14px;background:transparent;width:auto;">' +
        (a.isDefault ? '<span class="badge" style="margin-left:8px;">default</span>' : '') + '<button class="btn-sm danger" style="margin-left:auto;">Remove</button></div>' +
        '<div class="grid-2"><div class="field"><label class="field-label">Base Model</label><select data-field="baseModel">' + modelOpts + '</select></div>' +
        '<div class="field"><label class="field-label">Reasoning</label><select data-field="reasoning"><option value="">Model Default</option><option value="none">None</option><option value="minimal">Minimal</option><option value="low">Low</option><option value="medium">Medium</option><option value="high">High</option></select></div></div>' +
        '<div class="field"><label class="field-label">System Message</label><div style="display:flex;align-items:center;gap:8px;"><span class="sysmsg-label" style="font-size:12px;font-family:var(--font-mono);color:var(--text-secondary);flex:1;">' + String.fromCharCode(0x1F4C4) + ' ' + escHtml(a.systemMessageFile || (a.systemMessage ? '(inline)' : '(none)')) + '</span><button class="btn-sm edit-sysmsg">Edit</button></div><div class="field-hint">From app defaults (system-messages/). Create your own in AppData\\...\\system-messages\\</div></div>' +
        '<div class="field"><label class="field-label">Description</label><input type="text" value="' + escHtml(a.description || '') + '" data-field="description"></div>' +
        '<div class="toggle-row"><span class="lbl">Set as Default Assistant</span><div class="switch' + (a.isDefault ? ' on' : '') + '" data-field="isDefault" data-type="radio"><div class="knob"></div></div></div>';
      grid.appendChild(card);
      // Set selects
      card.querySelectorAll('select').forEach(function(sel) {
        var val = a[sel.dataset.field] || '';
        for (var i = 0; i < sel.options.length; i++) { if (sel.options[i].value === val) { sel.selectedIndex = i; break; } }
      });
      // Wire inputs
      card.querySelectorAll('input, select').forEach(function(el) { el.addEventListener('change', mark); el.addEventListener('input', mark); });
      // Wire switches
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
      // Wire remove
      card.querySelector('.btn-sm.danger').addEventListener('click', function() { card.remove(); mark(); });
      // Wire edit system message
      card.querySelector('.edit-sysmsg').addEventListener('click', function() {
        _editingCard = card;
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
      });
    });
  }

  function buildModelOptions(keys, current) {
    var html = '';
    var all = keys.slice();
    if (current && all.indexOf(current) < 0) all.unshift(current);
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
      // Restore stashed system message data
      obj.systemMessage = card.dataset.systemMessage || '';
      obj.systemMessageFile = card.dataset.systemMessageFile || '';
      assistants.push(obj);
    });
    return { assistants: assistants };
  }

  function addAssistant() {
    var grid = document.getElementById('assistantGrid'); if (!grid) return;
    var id = generateUUID();
    var card = document.createElement('div'); card.className = 'provider-card'; card.dataset.id = id;
    card.dataset.systemMessage = '';
    card.dataset.systemMessageFile = '';
    card.innerHTML = '<div class="provider-card-header"><input value="New Assistant" data-field="name" style="border:none;font-weight:600;font-size:14px;background:transparent;width:auto;"><button class="btn-sm danger" style="margin-left:auto;">Remove</button></div>' +
      '<div class="grid-2"><div class="field"><label class="field-label">Base Model</label><select data-field="baseModel">' + buildModelOptions(_modelKeys, '') + '</select></div>' +
      '<div class="field"><label class="field-label">Reasoning</label><select data-field="reasoning"><option value="">Model Default</option><option value="none">None</option><option value="medium">Medium</option><option value="high">High</option></select></div></div>' +
      '<div class="field"><label class="field-label">System Message</label><div style="display:flex;align-items:center;gap:8px;"><span class="sysmsg-label" style="font-size:12px;font-family:var(--font-mono);color:var(--text-secondary);">(none)</span><button class="btn-sm edit-sysmsg">Edit</button></div><div class="field-hint">From app defaults (system-messages/). Create your own in AppData\\...\\system-messages\\</div></div>' +
      '<div class="field"><label class="field-label">Description</label><input type="text" value="" data-field="description"></div>' +
      '<div class="toggle-row"><span class="lbl">Set as Default Assistant</span><div class="switch" data-field="isDefault" data-type="radio"><div class="knob"></div></div></div>';
    grid.appendChild(card);
    card.querySelectorAll('input, select').forEach(function(el) { el.addEventListener('change', mark); el.addEventListener('input', mark); });
    card.querySelector('.btn-sm.danger').addEventListener('click', function() { card.remove(); mark(); });
    card.querySelector('.edit-sysmsg').addEventListener('click', function() {
      _editingCard = card;
      var m = document.getElementById('sysMsgEditModal');
      if (!m) return;
      var inlineText = document.getElementById('smInlineText');
      var inlineRadio = m.querySelector('input[name="sysMsgMode"][value="inline"]');
      var fileRadio = m.querySelector('input[name="sysMsgMode"][value="file"]');
      var inlineSection = document.getElementById('smInlineSection');
      var fileSection = document.getElementById('smFileSection');
      if (inlineRadio) { inlineRadio.checked = true; }
      if (fileRadio) { fileRadio.checked = false; }
      if (inlineSection) inlineSection.style.display = '';
      if (fileSection) fileSection.style.display = 'none';
      if (inlineText) inlineText.value = '';
      m.classList.add('open');
    });
    card.querySelectorAll('.switch').forEach(function(sw) {
      sw.addEventListener('click', function() {
        if (sw.dataset.type === 'radio') {
          if (!sw.classList.contains('on')) {
            grid.querySelectorAll('.switch[data-type=radio]').forEach(function(s) { s.classList.remove('on'); });
            sw.classList.add('on');
          }
        }
        mark();
      });
    });
    mark();
  }

  function generateUUID() { return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, function(c) { var r = Math.random()*16|0, v = c=='x'?r:(r&0x3|0x8); return v.toString(16); }); }
  function escHtml(s) { return String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;'); }

  // Wire sysMsgEditModal Save button
  if (typeof document !== 'undefined') {
    document.addEventListener('DOMContentLoaded', function() {
      var addBtn = document.getElementById('addAssistantBtn');
      if (addBtn) addBtn.addEventListener('click', addAssistant);
      var saveBtn = document.getElementById('sysMsgEditSave');
      if (saveBtn) {
        saveBtn.addEventListener('click', function() {
          if (!_editingCard) return;
          var inlineRadio = document.querySelector('input[name="sysMsgMode"][value="inline"]');
          var isInline = inlineRadio && inlineRadio.checked;
          if (isInline) {
            var inlineText = document.getElementById('smInlineText');
            _editingCard.dataset.systemMessage = inlineText ? inlineText.value : '';
            _editingCard.dataset.systemMessageFile = '';
          } else {
            var fileSelect = document.getElementById('smFileSelect');
            _editingCard.dataset.systemMessageFile = fileSelect ? fileSelect.value : '';
            _editingCard.dataset.systemMessage = '';
          }
          // Update the label
          var label = _editingCard.querySelector('.sysmsg-label');
          if (label) {
            label.textContent = String.fromCharCode(0x1F4C4) + ' ' + (_editingCard.dataset.systemMessageFile || (_editingCard.dataset.systemMessage ? '(inline)' : '(none)'));
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
