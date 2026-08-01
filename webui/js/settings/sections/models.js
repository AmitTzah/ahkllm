// models.js — Models settings section
(function() {
  var sectionName = 'models';
  var _providerKeys = ['deepseek', 'openai', 'google', 'anthropic'];

  function stripProvider(id) {
    var i = id.indexOf('/');
    return i >= 0 ? id.substring(i + 1) : id;
  }

  function ensureFullId(id, provider) {
    if (id.indexOf('/') >= 0) return id;
    return provider ? provider + '/' + id : id;
  }

  function load(data) {
    if (!data || !data.models) return;
    if (data.providers) _providerKeys = Object.keys(data.providers).sort();
    renderTable(data.models);
  }

  function buildProviderSelect(keys, current) {
    var html = '<select data-field="provider" style="border:1px solid transparent;font-size:11px;">';
    var all = keys.slice();
    if (current != null && current !== '' && all.indexOf(current) < 0) all.unshift(current);
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
      tr.innerHTML = '<td><input value="' + escHtml(stripProvider(key)) + '" style="width:200px;" data-field="id"></td>' +
        '<td>' + buildProviderSelect(_providerKeys, m.provider) + '</td>' +
        '<td><input value="' + fmtPrice(m.input) + '" style="width:80px;" data-field="input" data-price-raw="' + (m.input || 0) + '"></td>' +
        '<td><input value="' + fmtPrice(m.cachedInput) + '" style="width:80px;" data-field="cachedInput" data-price-raw="' + (m.cachedInput || '') + '"></td>' +
        '<td><input value="' + fmtPrice(m.output) + '" style="width:80px;" data-field="output" data-price-raw="' + (m.output || 0) + '"></td>' +
        '<td><input value="' + formatContext(m.context || 0) + '" style="width:60px;" data-field="context" data-context-raw="' + (m.context || 0) + '"></td>' +
        '<td style="text-align:center;"><input type="checkbox" ' + (m.vision ? 'checked' : '') + ' data-field="vision"></td>' +
        '<td style="text-align:center;"><input type="checkbox" ' + (m.reasoning ? 'checked' : '') + ' data-field="reasoning"></td>' +
        '<td class="actions"><button class="btn-sm danger">\u2715</button></td>';
      tbody.appendChild(tr);
      tr.querySelectorAll('input, select').forEach(function(el) { el.addEventListener('change', mark); el.addEventListener('input', mark); });
      tr.querySelectorAll('[data-price-raw]').forEach(function(el) { _wirePriceInput(el); });
      var ctxInp = tr.querySelector('[data-field="context"]');
      if (ctxInp) _wireContextInput(ctxInp);
      tr.querySelector('.btn-sm.danger').addEventListener('click', function() { tr.remove(); mark(); });
    });
  }

  function mark() { if (window.SettingsPanel) window.SettingsPanel.markDirty(); }

  function _parseContext(el) {
    var raw = el.getAttribute('data-context-raw');
    if (raw !== null && raw !== '') return parseInt(raw) || 0;
    var v = el.value || '';
    if (/^\d+[kK]$/.test(v)) return parseInt(v) * 1000;
    if (/^\d+[mM]$/.test(v)) return parseInt(v) * 1000000;
    if (/^\d+(\.\d+)?[kK]$/.test(v)) return Math.round(parseFloat(v) * 1000);
    if (/^\d+(\.\d+)?[mM]$/.test(v)) return Math.round(parseFloat(v) * 1000000);
    return parseInt(v) || 0;
  }

  function _parsePrice(el) {
    var raw = el.getAttribute('data-price-raw');
    if (raw !== null && raw !== '') return parseFloat(raw) || 0;
    return parseFloat((el.value || '').replace(/^\$/, '')) || 0;
  }

  function _wirePriceInput(input) {
    input.addEventListener('focus', function() {
      var raw = input.getAttribute('data-price-raw');
      if (raw !== null && raw !== '') input.value = raw;
    });
    input.addEventListener('blur', function() {
      var v = parseFloat(input.value) || 0;
      input.setAttribute('data-price-raw', v);
      input.value = fmtPrice(v);
    });
  }

  function _wireContextInput(input) {
    input.addEventListener('focus', function() {
      var raw = input.getAttribute('data-context-raw');
      if (raw !== null && raw !== '') input.value = raw;
    });
    input.addEventListener('blur', function() {
      var v = parseInt(input.value) || 0;
      input.setAttribute('data-context-raw', v);
      input.value = formatContext(v);
    });
  }

  function save() {
    var models = {};
    document.querySelectorAll('#modelsTableBody tr').forEach(function(tr) {
      var id = (tr.querySelector('[data-field="id"]') || {}).value || '';
      if (!id) return;
      var ctxEl = tr.querySelector('[data-field="context"]');
      var provider = (tr.querySelector('[data-field="provider"]') || {}).value || '';
      var fullId = ensureFullId(id, provider);
      models[fullId] = {
        provider: provider,
        input: _parsePrice(tr.querySelector('[data-field="input"]') || {}),
        cachedInput: _parsePrice(tr.querySelector('[data-field="cachedInput"]') || {}),
        output: _parsePrice(tr.querySelector('[data-field="output"]') || {}),
        context: ctxEl ? _parseContext(ctxEl) : 0,
        vision: (tr.querySelector('[data-field="vision"]') || {}).checked || false,
        reasoning: (tr.querySelector('[data-field="reasoning"]') || {}).checked || false
      };
    });
    return { models: models };
  }

  function addRow() {
    var tbody = document.getElementById('modelsTableBody'); if (!tbody) return;
    var tr = document.createElement('tr');
    tr.innerHTML = '<td><input value="" placeholder="provider/model" style="width:200px;\width:170px;" data-field="id"></td>' +
      '<td>' + buildProviderSelect(_providerKeys, '') + '</td>' +
      '<td><input value="" style="width:68px;" data-field="input"></td><td><input value="" style="width:68px;" data-field="cachedInput"></td><td><input value="" style="width:68px;" data-field="output"></td>' +
      '<td><input value="" style="width:60px;" data-field="context"></td><td style="text-align:center;"><input type="checkbox" data-field="vision"></td><td style="text-align:center;"><input type="checkbox" data-field="reasoning"></td>' +
      '<td class="actions"><button class="btn-sm danger">\u2715</button></td>';
    tbody.appendChild(tr);
    tr.querySelectorAll('input, select').forEach(function(el) { el.addEventListener('change', mark); el.addEventListener('input', mark); });
    tr.querySelectorAll('[data-price-raw]').forEach(function(el) { _wirePriceInput(el); });
    var ctxInp = tr.querySelector('[data-field="context"]');
    if (ctxInp) _wireContextInput(ctxInp);
    tr.querySelector('.btn-sm.danger').addEventListener('click', function() { tr.remove(); mark(); });
    mark();
  }

  function openRefreshModal() {
    var m = document.getElementById('refreshModal'); if (m) m.classList.add('open');
    _populateRightPanel();
    window.chrome.webview.postMessage(JSON.stringify({action:'refreshModelPricing'}));
  }

  function escHtml(s) { return String(s).replace(/&/g,'&').replace(/</g,'<').replace(/>/g,'>').replace(/"/g,'"'); }

  // --- Refresh Modal ---

  var _refreshData = {}; // cached parsed refresh data: { modelId: {input, cachedInput, output, context, vision, reasoning} }

  function parsePricingRaw(raw) {
    var fields = {};
    var m = raw.match(/input:\s*([\d.]+)/);
    if (m) fields.input = parseFloat(m[1]);
    m = raw.match(/cachedInput:\s*([\d.]+)/);
    if (m) fields.cachedInput = parseFloat(m[1]);
    m = raw.match(/output:\s*([\d.]+)/);
    if (m) fields.output = parseFloat(m[1]);
    m = raw.match(/context:\s*(\d+)/);
    if (m) fields.context = parseInt(m[1], 10);
    m = raw.match(/reasoning:\s*(true|false)/i);
    fields.reasoning = m ? m[1].toLowerCase() === 'true' : false;
    m = raw.match(/vision:\s*(true|false)/i);
    fields.vision = m ? m[1].toLowerCase() === 'true' : false;
    return fields;
  }

  function formatContext(n) {
    if (n === undefined || n === null || n === '' || n === 0) return '';
    n = parseInt(n);
    if (isNaN(n)) return '';
    if (n >= 1000000) return (n / 1000000).toFixed(1).replace(/\.0$/, '') + 'M';
    if (n >= 1000) return (n / 1000).toFixed(0) + 'K';
    return n.toString();
  }

  function fmtPrice(v) {
    if (v === undefined || v === null || v === '') return '';
    v = parseFloat(v);
    if (isNaN(v)) return '';
    return (v < 0.01 ? '$' + v.toFixed(4) : v < 1 ? '$' + v.toFixed(3) : '$' + v.toFixed(2));
  }

  function _editableRow(trHtml) {
    return '<tr>' + trHtml + '</tr>';
  }

  function _rightRowHtml(id, m) {
    var prov = m.provider || '';
    var parts = id.split('/');
    if (!prov && parts.length > 1) prov = parts[0];
    var displayId = stripProvider(id);
    return '<td><input value="' + escHtml(displayId) + '" style="width:180px;" data-field="id" data-full-id="' + escHtml(id) + '"></td>' +
      '<td>' + buildProviderSelect(_providerKeys, prov) + '</td>' +
      '<td><input value="' + fmtPrice(m.input) + '" style="width:70px;" data-field="input" data-price-raw="' + (m.input || 0) + '" type="number" step="any"></td>' +
      '<td><input value="' + fmtPrice(m.cachedInput) + '" style="width:70px;" data-field="cachedInput" data-price-raw="' + (m.cachedInput !== undefined ? m.cachedInput : '') + '" type="number" step="any"></td>' +
      '<td><input value="' + fmtPrice(m.output) + '" style="width:70px;" data-field="output" data-price-raw="' + (m.output || 0) + '" type="number" step="any"></td>' +
      '<td><input value="' + formatContext(m.context || 0) + '" style="width:50px;" data-field="context" data-context-raw="' + (m.context || 0) + '"></td>' +
      '<td style="text-align:center;"><input type="checkbox" ' + (m.vision ? 'checked' : '') + ' data-field="vision"></td>' +
      '<td style="text-align:center;"><input type="checkbox" ' + (m.reasoning ? 'checked' : '') + ' data-field="reasoning"></td>' +
      '<td class="actions"><button class="btn-sm danger">\u2715</button></td>';
  }

  function _populateRightPanel() {
    var tbody = document.getElementById('refreshRightTbody');
    if (!tbody) return;
    tbody.innerHTML = '';
    _collectCurrentModels().forEach(function(m) {
      var tr = document.createElement('tr');
      tr.innerHTML = _rightRowHtml(m.id, m);
      tbody.appendChild(tr);
      tr.querySelectorAll('[data-price-raw]').forEach(function(el) { _wirePriceInput(el); });
      var ctxInp = tr.querySelector('[data-field="context"]');
      if (ctxInp) _wireContextInput(ctxInp);
      tr.querySelector('.btn-sm.danger').addEventListener('click', function() { tr.remove(); });
    });
    if (!tbody.children.length)
      tbody.innerHTML = '<tr><td colspan="9" style="text-align:center;color:var(--text-tertiary);padding:20px;">No models defined</td></tr>';
  }

  function _collectCurrentModels() {
    var models = [];
    document.querySelectorAll('#modelsTableBody tr').forEach(function(tr) {
      var idEl = tr.querySelector('[data-field="id"]');
      if (!idEl || !idEl.value) return;
      models.push({
        id: idEl.value, // full ID for internal use
        displayId: stripProvider(idEl.value), // display without provider prefix
        provider: (tr.querySelector('[data-field="provider"]') || {}).value || '',
        input: _parsePrice(tr.querySelector('[data-field="input"]') || {}),
        cachedInput: _parsePrice(tr.querySelector('[data-field="cachedInput"]') || {}),
        output: _parsePrice(tr.querySelector('[data-field="output"]') || {}),
        context: _parseContext(tr.querySelector('[data-field="context"]') || {}),
        vision: (tr.querySelector('[data-field="vision"]') || {}).checked || false,
        reasoning: (tr.querySelector('[data-field="reasoning"]') || {}).checked || false
      });
    });
    return models;
  }

  window.SettingsModels = {
    parsePricingRaw: parsePricingRaw,

    handleRefreshResult: function(data) {
      var leftTbody = document.getElementById('refreshLeftTbody');
      if (!leftTbody) return;
      if (data.success && data.models) {
        _refreshData = {};
        var leftHtml = '';
        data.models.forEach(function(m) {
          var p = m.raw ? parsePricingRaw(m.raw) : {};
          _refreshData[m.id] = p;
          leftHtml += '<tr><td style="font-size:10px;">' + escHtml(stripProvider(m.id)) + '</td>' +
            '<td>' + fmtPrice(p.input) + '</td>' +
            '<td>' + fmtPrice(p.output) + '</td>' +
            '<td>' + formatContext(p.context) + '</td>' +
            '<td><button class="btn-sm add-refresh-model" data-id="' + escHtml(m.id) + '" style="white-space:nowrap;">+ Add</button></td></tr>';
        });
        leftTbody.innerHTML = leftHtml;
        leftTbody.querySelectorAll('.add-refresh-model').forEach(function(btn) {
          btn.addEventListener('click', function() {
            window.SettingsModels.addFromRefresh(this.getAttribute('data-id'));
          });
        });
      } else {
        leftTbody.innerHTML = '<tr><td colspan="5" style="color:var(--danger);">Error: ' + escHtml(data.error || 'Unknown error') + '</td></tr>';
      }
    },

    addFromRefresh: function(modelId) {
      var p = _refreshData[modelId] || {};
      var tbody = document.getElementById('refreshRightTbody');
      if (!tbody) return;
      // Remove placeholder row if present
      var placeholder = tbody.querySelector('td[colspan]');
      if (placeholder) tbody.innerHTML = '';
      // Check duplicate
      var exists = false;
      tbody.querySelectorAll('[data-field="id"]').forEach(function(el) {
        if ((el.getAttribute('data-full-id') || el.value) === modelId) exists = true;
      });
      if (exists) return;
      var m = {
        provider: p.provider || '',
        input: p.input !== undefined ? p.input : 0,
        cachedInput: p.cachedInput !== undefined ? p.cachedInput : '',
        output: p.output !== undefined ? p.output : 0,
        context: p.context || 0,
        vision: p.vision || false,
        reasoning: p.reasoning || false
      };
      var tr = document.createElement('tr');
      tr.innerHTML = _rightRowHtml(modelId, m);
      tbody.appendChild(tr);
      tr.querySelectorAll('[data-price-raw]').forEach(function(el) { _wirePriceInput(el); });
      var ctxInp = tr.querySelector('[data-field="context"]');
      if (ctxInp) _wireContextInput(ctxInp);
      tr.querySelector('.btn-sm.danger').addEventListener('click', function() { tr.remove(); });
    },

    cancelRefresh: function() {
      document.getElementById('refreshModal').classList.remove('open');
    },

    saveRefresh: function() {
      var mainTbody = document.getElementById('modelsTableBody');
      var refreshTbody = document.getElementById('refreshRightTbody');
      if (!mainTbody || !refreshTbody) return;
      mainTbody.innerHTML = '';
      refreshTbody.querySelectorAll('tr').forEach(function(tr) {
        var idEl = tr.querySelector('[data-field="id"]') || {};
        var id = (idEl.getAttribute('data-full-id')) || idEl.value || '';
        if (!id) return;
        var newTr = document.createElement('tr');
        newTr.innerHTML = '<td><input value="' + escHtml(stripProvider(id)) + '" style="width:200px;" data-field="id"></td>' +
          '<td>' + buildProviderSelect(_providerKeys, (tr.querySelector('[data-field="provider"]') || {}).value || '') + '</td>' +
          '<td><input value="' + fmtPrice(_parsePrice(tr.querySelector('[data-field="input"]') || {})) + '" style="width:80px;" data-field="input" data-price-raw="' + _parsePrice(tr.querySelector('[data-field="input"]') || {}) + '"></td>' +
          '<td><input value="' + fmtPrice(_parsePrice(tr.querySelector('[data-field="cachedInput"]') || {})) + '" style="width:80px;" data-field="cachedInput" data-price-raw="' + _parsePrice(tr.querySelector('[data-field="cachedInput"]') || {}) + '"></td>' +
          '<td><input value="' + fmtPrice(_parsePrice(tr.querySelector('[data-field="output"]') || {})) + '" style="width:80px;" data-field="output" data-price-raw="' + _parsePrice(tr.querySelector('[data-field="output"]') || {}) + '"></td>' +
          '<td><input value="' + formatContext(_parseContext(tr.querySelector('[data-field="context"]') || {})) + '" style="width:60px;" data-field="context" data-context-raw="' + _parseContext(tr.querySelector('[data-field="context"]') || {}) + '"></td>' +
          '<td style="text-align:center;"><input type="checkbox" ' + ((tr.querySelector('[data-field="vision"]') || {}).checked ? 'checked' : '') + ' data-field="vision"></td>' +
          '<td style="text-align:center;"><input type="checkbox" ' + ((tr.querySelector('[data-field="reasoning"]') || {}).checked ? 'checked' : '') + ' data-field="reasoning"></td>' +
          '<td class="actions"><button class="btn-sm danger">\u2715</button></td>';
        mainTbody.appendChild(newTr);
        newTr.querySelectorAll('input, select').forEach(function(el) { el.addEventListener('change', mark); el.addEventListener('input', mark); });
        newTr.querySelectorAll('[data-price-raw]').forEach(function(el) { _wirePriceInput(el); });
        var ctxInp = newTr.querySelector('[data-field="context"]');
        if (ctxInp) _wireContextInput(ctxInp);
        newTr.querySelector('.btn-sm.danger').addEventListener('click', function() { newTr.remove(); mark(); });
      });
      mark();
      document.getElementById('refreshModal').classList.remove('open');
    }
  };

  if (typeof document !== 'undefined') {
    document.addEventListener('DOMContentLoaded', function() {
      var addBtn = document.getElementById('addModelBtn');
      if (addBtn) addBtn.addEventListener('click', addRow);
      var refreshBtn = document.getElementById('refreshPricingBtn');
      if (refreshBtn) refreshBtn.addEventListener('click', openRefreshModal);
      // Wire modal buttons
      var saveBtn = document.getElementById('refreshSaveBtn');
      if (saveBtn) saveBtn.addEventListener('click', function() { window.SettingsModels.saveRefresh(); });
      var modalRefreshBtn = document.getElementById('refreshPricingRefreshBtn');
      if (modalRefreshBtn) modalRefreshBtn.addEventListener('click', function() {
        window.chrome.webview.postMessage(JSON.stringify({action:'refreshModelPricing'}));
      });
    });
  }

  (function reg() { if (window.SettingsPanel) window.SettingsPanel.registerSection(sectionName, {load:load, save:save}); else setTimeout(reg, 50); })();
})();
