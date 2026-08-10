// assistants.js — Assistants settings section
(function() {
  var sectionName = 'assistants';
  var S = window.SettingsShared;
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
    var modelOpts = S.buildModelOptionsHtml(modelKeys, a.baseModel || '');
    var reasoningOpts = _reasoningLevels
      ? _reasoningLevels.buildOptionsHtml(models, a.baseModel || '')
      : '<option value="">Model Default</option><option value="none">None (Disabled)</option><option value="minimal">Minimal</option><option value="low">Low</option><option value="medium">Medium</option><option value="high">High</option>';
    var sysMsgLabel = '\uD83D\uDCC4 ' + (a.systemMessageFile || (a.systemMessage ? '(inline)' : '(none)'));
    return '<div class="provider-card-header"><input class="settings-card-title-input" value="' + S.escHtml(a.name || '') + '" data-field="name">' +
      '<button class="btn-sm danger settings-ml-auto">Remove</button></div>' +
      '<div class="grid-2"><div class="field"><label class="field-label">Base Model</label><select data-field="baseModel">' + modelOpts + '</select></div>' +
      '<div class="field"><label class="field-label">Reasoning</label><select data-field="reasoning">' + reasoningOpts + '</select></div></div>' +
      '<div class="field"><label class="field-label">System Message</label><div class="settings-flex-row-center"><span class="sysmsg-label settings-sysmsg-label">' + S.escHtml(sysMsgLabel) + '</span><button class="btn-sm edit-sysmsg">Edit</button></div><div class="field-hint">From app defaults (default-settings/system-messages/). Create your own in AppData\\...\\system-messages\\</div></div>' +
      '<div class="field"><label class="field-label">Description</label><input type="text" value="' + S.escHtml(a.description || '') + '" data-field="description"></div>' +
      '<div class="toggle-row"><div><div class="lbl">Default assistant</div><div class="settings-text-xs-muted">Used for new chats when "New Chats Start With" is App Default</div></div><div class="switch' + (a.isDefault ? ' on' : '') + '" data-field="isDefault" data-type="radio"><div class="knob"></div></div></div>';
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
    // model's supported levels. Keep the user's chosen level across the
    // change; if the new model doesn't support it, the select falls back
    // to the empty "Model Default" option.
    var baseSel = card.querySelector('select[data-field="baseModel"]');
    if (baseSel) {
      baseSel.addEventListener('change', function() {
        var reasoningSel = card.querySelector('select[data-field="reasoning"]');
        if (reasoningSel) {
          var prevLevel = reasoningSel.value;
          reasoningSel.innerHTML = _reasoningLevels
            ? _reasoningLevels.buildOptionsHtml(models, baseSel.value)
            : reasoningSel.innerHTML;
          reasoningSel.value = prevLevel;
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
    // Bug #122: temperature and isDefault have no card fields, so preserve the
    // loaded values on the card and re-emit them in save() - otherwise a
    // Settings save silently drops them (temperature falls back to Model
    // Default and can never be restored from the UI).
    card.dataset.temperature = (a.temperature !== undefined && a.temperature !== null) ? String(a.temperature) : '';
    card.dataset.isDefault = a.isDefault ? 'true' : 'false';
    // Stash original values for select restoration
    card.dataset.orig_baseModel = a.baseModel || '';
    card.dataset.orig_reasoning = a.reasoning || '';
    card.innerHTML = cardHTML(a, models, modelKeys);
    wireCard(card, grid, models);
    return card;
  }

  function mark() { S.markDirty(); }

  function save() {
    var assistants = [];
    document.querySelectorAll('#assistantGrid .provider-card').forEach(function(card) {
      var obj = { id: card.dataset.id || generateUUID() };
      card.querySelectorAll('[data-field]').forEach(function(el) {
        if (el.classList.contains('switch')) obj[el.dataset.field] = el.classList.contains('on');
        else obj[el.dataset.field] = el.value || '';
      });
      // Bug #122/#166: read the preserved temperature back (no card field);
      // isDefault now HAS a card switch, which the [data-field] loop above
      // already reads - the old dataset preservation must not overwrite it.
      if (card.dataset.temperature) obj.temperature = card.dataset.temperature;
      obj.systemMessage = card.dataset.systemMessage || '';
      obj.systemMessageFile = card.dataset.systemMessageFile || '';
      assistants.push(obj);
    });
    return { assistants: assistants };
  }

  function addAssistant() {
    var grid = document.getElementById('assistantGrid'); if (!grid) return;
    var a = { id: generateUUID(), name: 'New Assistant', baseModel: '', reasoning: '', systemMessage: '', systemMessageFile: '', description: '' };
    var card = createCard(a, _models, _modelKeys, grid);
    grid.appendChild(card);
    mark();
  }

  function generateUUID() { return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, function(c) { var r = Math.random()*16|0, v = c=='x'?r:(r&0x3|0x8); return v.toString(16); }); }
  if (typeof document !== 'undefined') {
    document.addEventListener('DOMContentLoaded', function() {
      var addBtn = document.getElementById('addAssistantBtn');
      if (addBtn) addBtn.addEventListener('click', addAssistant);
    });
  }
  S.registerSection(sectionName, {load: load, save: save});
})();
