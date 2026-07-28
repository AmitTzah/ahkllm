// models.js — Models settings section
(function() {
  var sectionName = 'models';
  var _providerKeys = ['deepseek', 'openai', 'google', 'anthropic'];

  function load(data) {
    if (!data || !data.models) return;
    if (data.providers) _providerKeys = Object.keys(data.providers).sort();
    renderTable(data.models);
  }

  function buildProviderSelect(keys, current) {
    var html = '<select data-field="provider" style="border:1px solid transparent;font-size:11px;">';
    var all = keys.slice();
    if (current && all.indexOf(current) < 0) all.unshift(current);
    all.forEach(function(k) { html += '<option' + (k === current ? ' selected' : '') + '>' + k + '</option>'; });
    html += '</select>';
    return html;
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
        '<td>' + buildProviderSelect(_providerKeys, m.provider) + '</td>' +
        '<td><input value="' + (m.input || 0) + '" style="width:68px;" data-field="input"></td>' +
        '<td><input value="' + (m.cachedInput || '') + '" style="width:68px;" data-field="cachedInput"></td>' +
        '<td><input value="' + (m.output || 0) + '" style="width:68px;" data-field="output"></td>' +
        '<td><input value="' + (m.context || 0) + '" style="width:60px;" data-field="context"></td>' +
        '<td style="text-align:center;"><input type="checkbox" ' + (m.vision ? 'checked' : '') + ' data-field="vision"></td>' +
        '<td style="text-align:center;"><input type="checkbox" ' + (m.reasoning ? 'checked' : '') + ' data-field="reasoning"></td>' +
        '<td class="actions"><button class="btn-sm danger">\u2715</button></td>';
      tbody.appendChild(tr);
      tr.querySelectorAll('input, select').forEach(function(el) { el.addEventListener('change', mark); el.addEventListener('input', mark); });
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
      '<td>' + buildProviderSelect(_providerKeys, '') + '</td>' +
      '<td><input value="" style="width:68px;" data-field="input"></td><td><input value="" style="width:68px;" data-field="cachedInput"></td><td><input value="" style="width:68px;" data-field="output"></td>' +
      '<td><input value="" style="width:60px;" data-field="context"></td><td style="text-align:center;"><input type="checkbox" data-field="vision"></td><td style="text-align:center;"><input type="checkbox" data-field="reasoning"></td>' +
      '<td class="actions"><button class="btn-sm danger">\u2715</button></td>';
    tbody.appendChild(tr);
    tr.querySelectorAll('input, select').forEach(function(el) { el.addEventListener('change', mark); el.addEventListener('input', mark); });
    tr.querySelector('.btn-sm.danger').addEventListener('click', function() { tr.remove(); mark(); });
    mark();
  }

  function openRefreshModal() {
    var m = document.getElementById('refreshModal'); if (m) m.classList.add('open');
    window.chrome.webview.postMessage(JSON.stringify({action:'refreshModelPricing'}));
  }

  function escHtml(s) { return String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;'); }

  if (typeof document !== 'undefined') {
    document.addEventListener('DOMContentLoaded', function() {
      var addBtn = document.getElementById('addModelBtn');
      if (addBtn) addBtn.addEventListener('click', addRow);
      var refreshBtn = document.getElementById('refreshPricingBtn');
      if (refreshBtn) refreshBtn.addEventListener('click', openRefreshModal);
    });
  }

  window.SettingsModels = {
    handleRefreshResult: function(data) {
      var leftPanel = document.querySelector('#refreshModal .modal-panel');
      if (!leftPanel) return;
      if (data.success && data.models) {
        var html = '<div style="font-size:13px;font-weight:600;margin-bottom:8px;">Models from PowerShell (' + data.models.length + ')</div>';
        data.models.forEach(function(m) {
          html += '<div style="display:flex;align-items:center;justify-content:space-between;padding:4px 0;border-bottom:1px solid var(--border-light);"><span style="font-family:var(--font-mono);font-size:11px;">' + escHtml(m.id) + '</span><button class="btn-sm" style="font-size:10px;">Add</button></div>';
        });
        leftPanel.innerHTML = html;
        leftPanel.querySelectorAll('button').forEach(function(btn, i) {
          btn.addEventListener('click', function() {
            window.SettingsModels.addFromRefresh(data.models[i].id);
          });
        });
        var rightPanel = document.querySelectorAll('#refreshModal .modal-panel')[1];
        if (rightPanel) {
          var models = {};
          document.querySelectorAll('#modelsTableBody tr').forEach(function(tr) {
            var idEl = tr.querySelector('[data-field="id"]');
            if (idEl && idEl.value) models[idEl.value] = true;
          });
          var currentIds = Object.keys(models).sort();
          var rightHtml = '<div style="font-size:13px;font-weight:600;margin-bottom:8px;">Current Models (' + currentIds.length + ')</div>';
          currentIds.forEach(function(id) { rightHtml += '<div style="font-family:var(--font-mono);font-size:11px;padding:2px 0;">' + escHtml(id) + '</div>'; });
          rightPanel.innerHTML = rightHtml;
        }
      } else {
        leftPanel.innerHTML = '<div style="color:var(--danger);">Error: ' + escHtml(data.error || 'Unknown error') + '</div>';
      }
    },
    addFromRefresh: function(modelId) {
      var tbody = document.getElementById('modelsTableBody');
      if (!tbody) return;
      var parts = modelId.split('/');
      var provider = parts.length > 1 ? parts[0] : '';
      var tr = document.createElement('tr');
      tr.innerHTML = '<td><input value="' + escHtml(modelId) + '" style="width:170px;" data-field="id"></td>' +
        '<td>' + buildProviderSelect(_providerKeys, provider) + '</td>' +
        '<td><input value="" style="width:68px;" data-field="input"></td><td><input value="" style="width:68px;" data-field="cachedInput"></td><td><input value="" style="width:68px;" data-field="output"></td>' +
        '<td><input value="" style="width:60px;" data-field="context"></td><td style="text-align:center;"><input type="checkbox" data-field="vision"></td><td style="text-align:center;"><input type="checkbox" data-field="reasoning"></td>' +
        '<td class="actions"><button class="btn-sm danger">\u2715</button></td>';
      tbody.appendChild(tr);
      tr.querySelectorAll('input, select').forEach(function(el) { el.addEventListener('change', mark); el.addEventListener('input', mark); });
      tr.querySelector('.btn-sm.danger').addEventListener('click', function() { tr.remove(); mark(); });
      mark();
    }
  };

  (function reg() { if (window.SettingsPanel) window.SettingsPanel.registerSection(sectionName, {load:load, save:save}); else setTimeout(reg, 50); })();
})();
