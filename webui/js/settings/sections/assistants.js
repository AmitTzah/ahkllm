// assistants.js — Assistants settings section
(function() {
  var sectionName = 'assistants';
  var _editingCard = null;
  var _modelKeys = ['deepseek/deepseek-v4-pro', 'deepseek/deepseek-v4-flash', 'openai/gpt-4o', 'google/gemini-2.5-flash'];
  var _models = null;
  var _reasoningLevels = (typeof window !== 'undefined' && window.ReasoningLevels) ? window.ReasoningLevels : null;

  function load(data) {
    if (!data || !data.assistants) return;
    if (data.models) { _models = data.models; _modelKeys = Object.keys(data.models).sort(); }
    renderCards(data.assistants, data.models);
  }

  // --- Card HTML template (shared by renderCards and addAssistant) ---

  function cardHTML(a, models, modelKeys) {
    var modelOpts = buildModelOptions(modelKeys, a.baseModel || '');
    var reasoningOpts = _reasoningLevels
      ? _reasoningLevels.buildOptionsHtml(models, a.baseModel || '')
      : '<option value="">Model Default</option><option value="none">None (Disabled)</option><option value="minimal">Minimal</option><option value="low">Low</option><option value="medium">Medium</option><option value="high">High</option>';
    var sysMsgLabel = '\uD83D\uDCC4 ' + (a.systemMessageFile || (a.systemMessage ? '(inline)' : '(none)'));
    return '<div class="provider-card-header"><input value="' + escHtml(a.name || '') + '" data-field="name" style="border:none;font-weight:600;font-size:14px;background:transparent;width:auto;">' +
      (a.isDefault ? '<span class="badge" style="margin-left:8px;">default</span>' : '') +
      '<button class="btn-sm danger" style="margin-left:auto;">Remove</button></div>' +
      '<div class="grid-2"><div class="field"><label class="field-label">Base Model</label><select data-field="baseModel">' + modelOpts + '</select></div>' +
      '<div class="field"><label class="field-label">Reasoning</label><select data-field="reasoning">' + reasoningOpts + '</select></div></div>' +
      '<div class="field"><label class="field-label">System Message</label><div style="display:flex;align-items:center;gap:8px;"><span class="sysmsg-label" style="font-size:12px;font-family:var(--font-mono);color:var(--text-secondary);">' + escHtml(sysMsgLabel) + '</span><button class="btn-sm edit-sysmsg">Edit</button></div><div class="field-hint">From app defaults (system-messages/). Create your own in AppData\\...\\system-messages\\</div></div>' +
      '<div class="field"><label class="field-label">Description</label><input type="text" value="' + escHtml(a.description || '') + '" data-field="description"></div>' +
      '<div class="toggle-row"><span class="lbl">Set as Default Assistant</span><div class="switch' + (a.isDefault ? ' on' : '') + '" data-field="isDefault" data-type="radio"><div class="knob"></div></div></div>';
  }

  // --- Card wiring (event listeners) ---

  function wireCard(card, grid, models) {
    // Set select values from dataset
    card.querySelectorAll('select').forEach(function(sel) {
      var field = sel.dataset.field;
      var val = card.dataset['orig_' + field];
      if (val === undefined) return;
      for (var i = 0; i < sel.options.length; i++) {
        if (sel.options[i].value === val) { sel.selectedIndex = i; break; }
      }
    });
    // Changing the base model rebuilds the Reasoning dropdown to that
    // model's supported levels, resetting to "Model Default".
    var baseSel = card.querySelector('select[data-field="baseModel"]');
    if (baseSel) {
      baseSel.addEventListener('change', function() {
        var reasoningSel = card.querySelector('select[data-field="reasoning"]');
        if (reasoningSel) {
          reasoningSel.innerHTML = _reasoningLevels
            ? _reasoningLevels.buildOptionsHtml(models, baseSel.value)
            : reasoningSel.innerHTML;
          reasoningSel.value = '';
        }
      });
    }
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
    window.populateSysMsgModal({ systemMessageFile: card.dataset.systemMessageFile, systemMessage: card.dataset.systemMessage });
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
      var card = createCard(a, models, modelKeys, grid);
      grid.appendChild(card);
    });
  }

  function createCard(a, models, modelKeys, grid) {
    var card = document.createElement('div');
    card.className = 'provider-card';
    card.dataset.id = a.id || '';
    card.dataset.systemMessage = a.systemMessage || '';
    card.dataset.systemMessageFile = a.systemMessageFile || '';
    // Stash original values for select restoration
    card.dataset.orig_baseModel = a.baseModel || '';
    card.dataset.orig_reasoning = a.reasoning || '';
    card.innerHTML = cardHTML(a, models, modelKeys);
    wireCard(card, grid, models);
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
    var card = createCard(a, _models, _modelKeys, grid);
    grid.appendChild(card);
    mark();
  }

  function generateUUID() { return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, function(c) { var r = Math.random()*16|0, v = c=='x'?r:(r&0x3|0x8); return v.toString(16); }); }
  function escHtml(s) { return String(s).replace(/&/g,'\x26amp;').replace(/</g,'\x26lt;').replace(/>/g,'\x26gt;').replace(/"/g,'\x26quot;'); }

  if (typeof document !== 'undefined') {
    document.addEventListener('DOMContentLoaded', function() {
      var addBtn = document.getElementById('addAssistantBtn');
      if (addBtn) addBtn.addEventListener('click', addAssistant);
    });
  }
  (function reg() { if (window.SettingsPanel) window.SettingsPanel.registerSection(sectionName, {load:load, save:save}); else setTimeout(reg, 50); })();
})();
