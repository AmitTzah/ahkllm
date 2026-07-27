// models.js — Models settings section
(function() {
  var sectionName = 'models';

  function load(data) {
    if (!data || !data.models) return;
    renderTable(data.models);
  }

  function renderTable(models) {
    var tbody = document.getElementById('modelsTableBody');
    if (!tbody) return;
    tbody.innerHTML = '';
    var keys = Object.keys(models).sort();
    keys.forEach(function(key) {
      var m = models[key];
      var tr = document.createElement('tr');
      tr.innerHTML = '<td><input value="' + escHtml(key) + '" style="width:170px;" data-field="id"></td>' +
        '<td><select data-field="provider" style="border:1px solid transparent;font-size:11px;"><option>deepseek</option><option>openai</option><option>google</option><option>anthropic</option></select></td>' +
        '<td><input value="' + (m.input || 0) + '" style="width:68px;" data-field="input"></td>' +
        '<td><input value="' + (m.cachedInput || '') + '" style="width:68px;" data-field="cachedInput"></td>' +
        '<td><input value="' + (m.output || 0) + '" style="width:68px;" data-field="output"></td>' +
        '<td><input value="' + (m.context || 0) + '" style="width:60px;" data-field="context"></td>' +
        '<td style="text-align:center;"><input type="checkbox" ' + (m.vision ? 'checked' : '') + ' data-field="vision"></td>' +
        '<td style="text-align:center;"><input type="checkbox" ' + (m.reasoning ? 'checked' : '') + ' data-field="reasoning"></td>' +
        '<td class="actions"><button class="btn-sm danger">✕</button></td>';
      tbody.appendChild(tr);
      // Set provider select
      var sel = tr.querySelector('select');
      if (sel && m.provider) {
        for (var i = 0; i < sel.options.length; i++) { if (sel.options[i].value === m.provider) { sel.selectedIndex = i; break; } }
      }
      // Wire inputs
      tr.querySelectorAll('input, select').forEach(function(el) { el.addEventListener('change', mark); el.addEventListener('input', mark); });
      // Wire delete
      tr.querySelector('.btn-sm.danger').addEventListener('click', function() { tr.remove(); mark(); });
    });
  }

  function mark() { if (window.SettingsPanel) window.SettingsPanel.markDirty(); }

  function save() {
    var models = {};
    document.querySelectorAll('#modelsTableBody tr').forEach(function(tr) {
      var id = (tr.querySelector('[data-field="id"]') || {}).value || '';
      if (!id) return;
      models[id] = {
        provider: (tr.querySelector('[data-field="provider"]') || {}).value || '',
        input: parseFloat((tr.querySelector('[data-field="input"]') || {}).value) || 0,
        cachedInput: (tr.querySelector('[data-field="cachedInput"]') || {}).value || '',
        output: parseFloat((tr.querySelector('[data-field="output"]') || {}).value) || 0,
        context: parseInt((tr.querySelector('[data-field="context"]') || {}).value) || 0,
        vision: (tr.querySelector('[data-field="vision"]') || {}).checked || false,
        reasoning: (tr.querySelector('[data-field="reasoning"]') || {}).checked || false
      };
    });
    return { models: models };
  }

  function addRow() {
    var tbody = document.getElementById('modelsTableBody'); if (!tbody) return;
    var tr = document.createElement('tr');
    tr.innerHTML = '<td><input value="" placeholder="provider/model" style="width:170px;" data-field="id"></td>' +
      '<td><select data-field="provider" style="border:1px solid transparent;font-size:11px;"><option>deepseek</option><option>openai</option><option>google</option><option>anthropic</option></select></td>' +
      '<td><input value="" style="width:68px;" data-field="input"></td><td><input value="" style="width:68px;" data-field="cachedInput"></td><td><input value="" style="width:68px;" data-field="output"></td>' +
      '<td><input value="" style="width:60px;" data-field="context"></td><td style="text-align:center;"><input type="checkbox" data-field="vision"></td><td style="text-align:center;"><input type="checkbox" data-field="reasoning"></td>' +
      '<td class="actions"><button class="btn-sm danger">✕</button></td>';
    tbody.appendChild(tr);
    tr.querySelectorAll('input, select').forEach(function(el) { el.addEventListener('change', mark); el.addEventListener('input', mark); });
    tr.querySelector('.btn-sm.danger').addEventListener('click', function() { tr.remove(); mark(); });
    mark();
  }

  function openRefreshModal() { var m = document.getElementById('refreshModal'); if (m) m.classList.add('open'); }

  function escHtml(s) { return String(s).replace(/&/g,'&').replace(/</g,'<').replace(/>/g,'>').replace(/"/g,'"'); }

  if (typeof document !== 'undefined') {
    document.addEventListener('DOMContentLoaded', function() {
      var addBtn = document.getElementById('addModelBtn');
      if (addBtn) addBtn.addEventListener('click', addRow);
      var refreshBtn = document.getElementById('refreshPricingBtn');
      if (refreshBtn) refreshBtn.addEventListener('click', openRefreshModal);
    });
  }
  (function reg() { if (window.SettingsPanel) window.SettingsPanel.registerSection(sectionName, {load:load, save:save}); else setTimeout(reg, 50); })();
})();
