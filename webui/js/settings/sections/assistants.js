// assistants.js — Assistants settings section
(function() {
  var sectionName = 'assistants';

  function load(data) {
    if (!data || !data.assistants) return;
    renderCards(data.assistants);
  }

  function renderCards(assistants) {
    var grid = document.getElementById('assistantGrid');
    if (!grid) return;
    grid.innerHTML = '';
    assistants.forEach(function(a) {
      var card = document.createElement('div'); card.className = 'provider-card'; card.dataset.id = a.id || '';
      card.innerHTML = '<div class="provider-card-header"><input value="' + escHtml(a.name || '') + '" data-field="name" style="border:none;font-weight:600;font-size:14px;background:transparent;width:auto;">' +
        (a.isDefault ? '<span class="badge">default</span>' : '') + '<button class="btn-sm danger" style="margin-left:auto;">Remove</button></div>' +
        '<div class="grid-2"><div class="field"><label class="field-label">Base Model</label><select data-field="baseModel"><option>deepseek/deepseek-v4-pro</option><option>deepseek/deepseek-v4-flash</option><option>openai/gpt-4o</option><option>google/gemini-2.5-flash</option></select></div>' +
        '<div class="field"><label class="field-label">Reasoning</label><select data-field="reasoning"><option value="">Model Default</option><option value="none">None</option><option value="minimal">Minimal</option><option value="low">Low</option><option value="medium">Medium</option><option value="high">High</option></select></div></div>' +
        '<div class="field"><label class="field-label">System Message</label><div style="display:flex;align-items:center;gap:8px;"><span style="font-size:12px;font-family:var(--font-mono);color:var(--text-secondary);flex:1;">📄 ' + escHtml(a.systemMessageFile || (a.systemMessage ? '(inline)' : '(none)')) + '</span><button class="btn-sm edit-sysmsg">Edit</button></div></div>' +
        '<div class="field"><label class="field-label">Description</label><input value="' + escHtml(a.description || '') + '" data-field="description"></div>' +
        '<div class="toggle-row"><span class="lbl">Set as Default</span><div class="switch' + (a.isDefault ? ' on' : '') + '" data-field="isDefault" data-type="radio"><div class="knob"></div></div></div>';
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
        var modal = document.getElementById('sysMsgEditModal');
        if (modal) modal.classList.add('open');
      });
    });
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
      assistants.push(obj);
    });
    return { assistants: assistants };
  }

  function addAssistant() {
    var grid = document.getElementById('assistantGrid'); if (!grid) return;
    var id = generateUUID();
    var card = document.createElement('div'); card.className = 'provider-card'; card.dataset.id = id;
    card.innerHTML = '<div class="provider-card-header"><input value="New Assistant" data-field="name" style="border:none;font-weight:600;font-size:14px;background:transparent;width:auto;"><button class="btn-sm danger" style="margin-left:auto;">Remove</button></div>' +
      '<div class="grid-2"><div class="field"><label class="field-label">Base Model</label><select data-field="baseModel"><option>deepseek/deepseek-v4-pro</option><option>deepseek/deepseek-v4-flash</option><option>openai/gpt-4o</option></select></div>' +
      '<div class="field"><label class="field-label">Reasoning</label><select data-field="reasoning"><option value="">Model Default</option><option value="none">None</option><option value="medium">Medium</option><option value="high">High</option></select></div></div>' +
      '<div class="field"><label class="field-label">System Message</label><div style="display:flex;align-items:center;gap:8px;"><span style="font-size:12px;font-family:var(--font-mono);color:var(--text-secondary);">(none)</span><button class="btn-sm edit-sysmsg">Edit</button></div></div>' +
      '<div class="field"><label class="field-label">Description</label><input value="" data-field="description"></div>' +
      '<div class="toggle-row"><span class="lbl">Set as Default</span><div class="switch" data-field="isDefault" data-type="radio"><div class="knob"></div></div></div>';
    grid.appendChild(card);
    card.querySelectorAll('input, select').forEach(function(el) { el.addEventListener('change', mark); el.addEventListener('input', mark); });
    card.querySelector('.btn-sm.danger').addEventListener('click', function() { card.remove(); mark(); });
    card.querySelector('.edit-sysmsg').addEventListener('click', function() { var m = document.getElementById('sysMsgEditModal'); if (m) m.classList.add('open'); });
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
  function escHtml(s) { return String(s).replace(/&/g,'&').replace(/</g,'<').replace(/>/g,'>').replace(/"/g,'"'); }

  if (typeof document !== 'undefined') {
    document.addEventListener('DOMContentLoaded', function() {
      var addBtn = document.getElementById('addAssistantBtn');
      if (addBtn) addBtn.addEventListener('click', addAssistant);
    });
  }
  (function reg() { if (window.SettingsPanel) window.SettingsPanel.registerSection(sectionName, {load:load, save:save}); else setTimeout(reg, 50); })();
})();
