// assistants.js — Assistants settings section
(function() {
  var sectionName = 'assistants';
  var S = window.SettingsShared;
  var _modelKeys = ['deepseek/deepseek-v4-pro', 'deepseek/deepseek-v4-flash', 'openai/gpt-4o', 'google/gemini-2.5-flash'];
  var _models = null;
  var _reasoningLevels = (typeof window !== 'undefined' && window.ReasoningLevels) ? window.ReasoningLevels : null;

  function load(data) {
    if (!data || !data.assistants) return;
    if (data.models) { _models = data.models; _modelKeys = Object.keys(data.models).sort(); }
    renderCards(data.assistants, data.models);
  }

  function systemMessageSummary(filePath, inlineText) {
    if (filePath) return { text: '\uD83D\uDCC4 ' + String(filePath), title: String(filePath) };
    var normalized = String(inlineText || '').replace(/\s+/g, ' ').trim();
    if (!normalized) return { text: '\uD83D\uDCC4 (none)', title: '' };
    var preview = normalized.length > 96 ? normalized.slice(0, 93) + '...' : normalized;
    return { text: '\uD83D\uDCC4 (inline) \u00B7 ' + preview, title: String(inlineText || '') };
  }

  function cardHTML(a, models, modelKeys) {
    var modelOpts = S.buildModelOptionsHtml(modelKeys, a.baseModel || '');
    var reasoningOpts = _reasoningLevels
      ? _reasoningLevels.buildOptionsHtml(models, a.baseModel || '')
      : '<option value="">Model Default</option><option value="none">None (Disabled)</option><option value="minimal">Minimal</option><option value="low">Low</option><option value="medium">Medium</option><option value="high">High</option>';
    var sysMsg = systemMessageSummary(a.systemMessageFile, a.systemMessage);
    return '<div class="provider-card-header"><input class="settings-card-title-input" value="' + S.escHtml(a.name || '') + '" data-field="name">' +
      '<button class="btn-sm danger settings-ml-auto">Remove</button></div>' +
      '<div class="grid-2"><div class="field"><label class="field-label">Base Model</label><select data-field="baseModel">' + modelOpts + '</select></div>' +
      '<div class="field"><label class="field-label">Reasoning</label><select data-field="reasoning">' + reasoningOpts + '</select></div></div>' +
      '<div class="field"><label class="field-label">System Message</label><div class="settings-flex-row-center settings-sysmsg-summary-row"><span class="sysmsg-label settings-sysmsg-label" title="' + S.escHtml(sysMsg.title) + '">' + S.escHtml(sysMsg.text) + '</span><button class="btn-sm edit-sysmsg">Edit</button></div><div class="field-hint">Choose inline text or a .txt file. Edit to switch modes.</div></div>' +
      '<div class="field"><label class="field-label">Description</label><input type="text" value="' + S.escHtml(a.description || '') + '" data-field="description"></div>';
  }

  function wireCard(card, grid, models) {
    card.querySelectorAll('select').forEach(function(sel) {
      var field = sel.dataset.field;
      var val = card.dataset['orig_' + field];
      if (val === undefined) return;
      for (var i = 0; i < sel.options.length; i++) {
        if (sel.options[i].value === val) { sel.selectedIndex = i; break; }
      }
    });
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
    card.querySelectorAll('input, select').forEach(function(el) { el.addEventListener('change', mark); el.addEventListener('input', mark); });
    card.querySelector('.btn-sm.danger').addEventListener('click', function() { card.remove(); mark(); });
    card.querySelector('.edit-sysmsg').addEventListener('click', function() { openSysMsgModal(card); });
  }

  function openSysMsgModal(card) {
    window._sysMsgTarget = { type: 'assistant', card: card };
    window.populateSysMsgModal({ systemMessageFile: card.dataset.systemMessageFile, systemMessage: card.dataset.systemMessage });
  }

  function renderCards(assistants, models) {
    var grid = document.getElementById('assistantGrid');
    if (!grid) return;
    grid.innerHTML = '';
    var countEl = document.getElementById('assistantCount');
    if (countEl) countEl.textContent = assistants.length + ' assistants defined. Click + to add one.';
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
    card.dataset.temperature = (a.temperature !== undefined && a.temperature !== null) ? String(a.temperature) : '';
    // Kept only so old settings round-trip without churn. It no longer controls new chats.
    card.dataset.isDefault = a.isDefault ? 'true' : 'false';
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
      card.querySelectorAll('[data-field]').forEach(function(el) { obj[el.dataset.field] = el.value || ''; });
      if (card.dataset.temperature) obj.temperature = card.dataset.temperature;
      obj.isDefault = card.dataset.isDefault === 'true';
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
  if (typeof document !== 'undefined') {
    document.addEventListener('DOMContentLoaded', function() {
      var addBtn = document.getElementById('addAssistantBtn');
      if (addBtn) addBtn.addEventListener('click', addAssistant);
    });
  }
  S.registerSection(sectionName, {load: load, save: save});
})();
