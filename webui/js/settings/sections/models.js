// models.js — Models settings section (pricing/metadata table + refresh modal)
(function() {
  var sectionName = 'models';
  var S = window.SettingsShared;
  var _providerKeys = ['deepseek', 'openai', 'google', 'anthropic'];

  // --- Model id helpers ---

  function stripProvider(id) {
    var i = id.indexOf('/');
    return i >= 0 ? id.substring(i + 1) : id;
  }

  function ensureFullId(id, provider) {
    if (id.indexOf('/') >= 0) return id;
    return provider ? provider + '/' + id : id;
  }

  // --- Pricing / context formatting and parsing ---

  function fmtPrice(v) {
    if (v === undefined || v === null || v === '') return '';
    v = parseFloat(v);
    if (isNaN(v)) return '';
    return (v < 0.01 ? '$' + v.toFixed(4) : v < 1 ? '$' + v.toFixed(3) : '$' + v.toFixed(2));
  }

  function formatContext(n) {
    if (n === undefined || n === null || n === '' || n === 0) return '';
    n = parseInt(n);
    if (isNaN(n)) return '';
    if (n >= 1000000) return (n / 1000000).toFixed(1).replace(/\.0$/, '') + 'M';
    if (n >= 1000) return (n / 1000).toFixed(0) + 'K';
    return n.toString();
  }

  function _parsePrice(el) {
    if (!el) return 0;
    var raw = el.getAttribute('data-price-raw');
    if (raw !== null && raw !== '') return parseFloat(raw) || 0;
    return parseFloat((el.value || '').replace(/^\$/, '')) || 0;
  }

  function _parseContext(el) {
    if (!el) return 0;
    var raw = el.getAttribute('data-context-raw');
    if (raw !== null && raw !== '') return parseInt(raw) || 0;
    var v = el.value || '';
    if (/^\d+[kK]$/.test(v)) return parseInt(v) * 1000;
    if (/^\d+[mM]$/.test(v)) return parseInt(v) * 1000000;
    if (/^\d+(\.\d+)?[kK]$/.test(v)) return Math.round(parseFloat(v) * 1000);
    if (/^\d+(\.\d+)?[mM]$/.test(v)) return Math.round(parseFloat(v) * 1000000);
    return parseInt(v) || 0;
  }

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

  function buildProviderSelect(keys, current) {
    var html = '<select class="settings-provider-select" data-field="provider">';
    var all = keys.slice();
    if (current != null && current !== '' && all.indexOf(current) < 0) all.unshift(current);
    all.forEach(function(k) { html += '<option' + (k === current ? ' selected' : '') + '>' + S.escHtml(k) + '</option>'; });
    html += '</select>';
    return html;
  }

  // Emit a data-*-raw attribute only when a value actually exists, so empty
  // rows keep their blank display until the user edits them.
  function _rawAttr(name, value) {
    if (value === undefined || value === null || value === '') return '';
    return ' data-' + name + '-raw="' + value + '"';
  }

  // --- Row builders (single source for the main table and refresh modal) ---

  function _mainRowHtml(id, provider, values, placeholder) {
    var m = values || {};
    var ph = placeholder ? ' placeholder="' + placeholder + '"' : '';
    return '<td><input class="settings-w-200" value="' + S.escHtml(stripProvider(id)) + '"' + ph + ' data-field="id"></td>' +
      '<td>' + buildProviderSelect(_providerKeys, provider) + '</td>' +
      '<td><input class="settings-w-80" value="' + fmtPrice(m.input) + '" data-field="input"' + _rawAttr('price', m.input) + '></td>' +
      '<td><input class="settings-w-80" value="' + fmtPrice(m.cachedInput) + '" data-field="cachedInput"' + _rawAttr('price', m.cachedInput) + '></td>' +
      '<td><input class="settings-w-80" value="' + fmtPrice(m.output) + '" data-field="output"' + _rawAttr('price', m.output) + '></td>' +
      '<td><input class="settings-w-60" value="' + formatContext(m.context || 0) + '" data-field="context"' + _rawAttr('context', m.context) + '></td>' +
      '<td class="settings-text-center"><input type="checkbox" ' + (m.vision ? 'checked' : '') + ' data-field="vision"></td>' +
      '<td class="settings-text-center"><input type="checkbox" ' + (m.reasoning ? 'checked' : '') + ' data-field="reasoning"></td>' +
      '<td class="actions"><button class="btn-sm danger">\u2715</button></td>';
  }

  function _rightRowHtml(id, m) {
    var prov = m.provider || '';
    var parts = id.split('/');
    if (!prov && parts.length > 1) prov = parts[0];
    return '<td><input class="settings-w-180" value="' + S.escHtml(stripProvider(id)) + '" data-field="id" data-full-id="' + S.escHtml(id) + '"></td>' +
      '<td>' + buildProviderSelect(_providerKeys, prov) + '</td>' +
      '<td><input class="settings-w-70" value="' + fmtPrice(m.input) + '" data-field="input"' + _rawAttr('price', m.input) + ' type="number" step="any"></td>' +
      '<td><input class="settings-w-70" value="' + fmtPrice(m.cachedInput) + '" data-field="cachedInput"' + _rawAttr('price', m.cachedInput) + ' type="number" step="any"></td>' +
      '<td><input class="settings-w-70" value="' + fmtPrice(m.output) + '" data-field="output"' + _rawAttr('price', m.output) + ' type="number" step="any"></td>' +
      '<td><input class="settings-w-50" value="' + formatContext(m.context || 0) + '" data-field="context"' + _rawAttr('context', m.context) + '></td>' +
      '<td class="settings-text-center"><input type="checkbox" ' + (m.vision ? 'checked' : '') + ' data-field="vision"></td>' +
      '<td class="settings-text-center"><input type="checkbox" ' + (m.reasoning ? 'checked' : '') + ' data-field="reasoning"></td>' +
      '<td class="actions"><button class="btn-sm danger">\u2715</button></td>';
  }

  // --- Row wiring ---

  function _wireFields(tr) {
    tr.querySelectorAll('input, select').forEach(function(el) {
      el.addEventListener('change', mark);
      el.addEventListener('input', mark);
    });
  }

  function _wirePriceContext(tr) {
    tr.querySelectorAll('[data-price-raw]').forEach(function(el) { _wirePriceInput(el); });
    var ctxInp = tr.querySelector('[data-field="context"]');
    if (ctxInp) _wireContextInput(ctxInp);
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

  function _wireMainRow(tr) {
    _wireFields(tr);
    _wirePriceContext(tr);
    tr.querySelector('.btn-sm.danger').addEventListener('click', function() { tr.remove(); mark(); });
  }

  function _wireRightRow(tr, onRemove) {
    _wirePriceContext(tr);
    tr.querySelector('.btn-sm.danger').addEventListener('click', onRemove);
  }

  // Read a row's current values from its DOM elements.
  function _readRowValues(tr) {
    return {
      provider: (tr.querySelector('[data-field="provider"]') || {}).value || '',
      input: _parsePrice(tr.querySelector('[data-field="input"]')),
      cachedInput: _parsePrice(tr.querySelector('[data-field="cachedInput"]')),
      output: _parsePrice(tr.querySelector('[data-field="output"]')),
      context: _parseContext(tr.querySelector('[data-field="context"]')),
      vision: (tr.querySelector('[data-field="vision"]') || {}).checked || false,
      reasoning: (tr.querySelector('[data-field="reasoning"]') || {}).checked || false
    };
  }

  function mark() { S.markDirty(); }

  // --- Main table ---

  function load(data) {
    if (!data || !data.models) return;
    if (data.providers) _providerKeys = Object.keys(data.providers).sort();
    renderTable(data.models);
  }

  function renderTable(models) {
    var tbody = document.getElementById('modelsTableBody');
    if (!tbody) return;
    tbody.innerHTML = '';
    Object.keys(models).sort().forEach(function(key) {
      var m = models[key];
      var tr = document.createElement('tr');
      tr.innerHTML = _mainRowHtml(key, m.provider, m);
      tbody.appendChild(tr);
      _wireMainRow(tr);
    });
  }

  function addRow() {
    var tbody = document.getElementById('modelsTableBody'); if (!tbody) return;
    var tr = document.createElement('tr');
    tr.innerHTML = _mainRowHtml('', '', {}, 'provider/model');
    tbody.appendChild(tr);
    _wireMainRow(tr);
    mark();
  }

  function save() {
    var models = {};
    document.querySelectorAll('#modelsTableBody tr').forEach(function(tr) {
      var id = (tr.querySelector('[data-field="id"]') || {}).value || '';
      if (!id) return;
      var values = _readRowValues(tr);
      var fullId = ensureFullId(id, values.provider);
      models[fullId] = {
        provider: values.provider,
        input: values.input,
        cachedInput: values.cachedInput,
        output: values.output,
        context: values.context,
        vision: values.vision,
        reasoning: values.reasoning
      };
    });
    return { models: models };
  }

  function _collectCurrentModels() {
    var models = [];
    document.querySelectorAll('#modelsTableBody tr').forEach(function(tr) {
      var idEl = tr.querySelector('[data-field="id"]');
      if (!idEl || !idEl.value) return;
      var values = _readRowValues(tr);
      models.push({
        id: ensureFullId(idEl.value, values.provider), // full ID for internal use
        displayId: stripProvider(idEl.value), // display without provider prefix
        provider: values.provider,
        input: values.input,
        cachedInput: values.cachedInput,
        output: values.output,
        context: values.context,
        vision: values.vision,
        reasoning: values.reasoning
      });
    });
    return models;
  }

  // --- Refresh modal ---

  var _refreshData = {}; // cached parsed refresh data: { modelId: {input, cachedInput, output, context, vision, reasoning} }
  var _refreshAvailable = []; // fetched models from the last refresh: [{ id, raw }]
  var _refreshQuery = '';     // current search filter text

  function openRefreshModal() {
    var m = document.getElementById('refreshModal'); if (m) m.classList.add('open');
    var searchInput = document.getElementById('refreshModelSearch');
    if (searchInput) searchInput.value = '';
    _refreshQuery = '';
    _populateRightPanel();
    if (_refreshAvailable.length) _renderAvailableModels();
    window.chrome.webview.postMessage(JSON.stringify({action:'refreshModelPricing'}));
  }

  function filterAvailableModels(list, query) {
    var q = String(query || '').trim().toLowerCase();
    if (!q) return list.slice();
    return list.filter(function(m) {
      return m.id.toLowerCase().indexOf(q) >= 0 || stripProvider(m.id).toLowerCase().indexOf(q) >= 0;
    });
  }

  function buildAddButtonHtml(modelId, isAdded) {
    var dataId = 'data-id="' + S.escHtml(modelId) + '"';
    if (isAdded)
      return '<button class="btn-sm add-refresh-model settings-nowrap" ' + dataId + ' disabled>Added</button>';
    return '<button class="btn-sm add-refresh-model settings-nowrap" ' + dataId + '>+ Add</button>';
  }

  function _rightPanelIds() {
    var ids = [];
    var tbody = document.getElementById('refreshRightTbody');
    if (!tbody) return ids;
    tbody.querySelectorAll('tr').forEach(function(tr) {
      var idEl = tr.querySelector('[data-field="id"]');
      if (!idEl) return;
      var id = idEl.getAttribute('data-full-id') || idEl.value;
      if (!id) return;
      // Rows copied from the settings table only hold the display id; fall
      // back to the provider column so they match fetched full ids like
      // "google/gemini-3-flash-preview".
      if (id.indexOf('/') < 0) {
        var provEl = tr.querySelector('[data-field="provider"]');
        var provider = provEl ? provEl.value || '' : '';
        if (provider) id = provider + '/' + id;
      }
      ids.push(id);
    });
    return ids;
  }

  function _renderAvailableModels() {
    var tbody = document.getElementById('refreshLeftTbody');
    if (!tbody) return;
    var added = _rightPanelIds();
    var list = filterAvailableModels(_refreshAvailable, _refreshQuery);
    var html = '';
    list.forEach(function(m) {
      var p = _refreshData[m.id] || {};
      var isAdded = added.indexOf(m.id) >= 0;
      html += '<tr><td class="settings-text-10">' + S.escHtml(stripProvider(m.id)) + '</td>' +
        '<td>' + fmtPrice(p.input) + '</td>' +
        '<td>' + fmtPrice(p.output) + '</td>' +
        '<td>' + formatContext(p.context) + '</td>' +
        '<td>' + buildAddButtonHtml(m.id, isAdded) + '</td></tr>';
    });
    tbody.innerHTML = html || '<tr><td class="settings-empty-state" colspan="5">' +
      (_refreshAvailable.length ? 'No matching models' : 'Click Refresh to pull latest pricing data') + '</td></tr>';
    tbody.querySelectorAll('.add-refresh-model').forEach(function(btn) {
      btn.addEventListener('click', function() {
        window.SettingsModels.addFromRefresh(this.getAttribute('data-id'));
      });
    });
    var countEl = document.getElementById('refreshModelCount');
    if (countEl) countEl.textContent = _refreshAvailable.length ? list.length + ' of ' + _refreshAvailable.length + ' models' : '';
  }

  function _populateRightPanel() {
    var tbody = document.getElementById('refreshRightTbody');
    if (!tbody) return;
    tbody.innerHTML = '';
    _collectCurrentModels().forEach(function(m) {
      var tr = document.createElement('tr');
      tr.innerHTML = _rightRowHtml(m.id, m);
      tbody.appendChild(tr);
      _wireRightRow(tr, function() { tr.remove(); _renderAvailableModels(); });
    });
    if (!tbody.children.length)
      tbody.innerHTML = '<tr><td class="settings-empty-state" colspan="9">No models defined</td></tr>';
  }

  window.SettingsModels = {
    parsePricingRaw: parsePricingRaw,
    filterAvailableModels: filterAvailableModels,
    buildAddButton: buildAddButtonHtml,
    collectCurrentModels: function() { return _collectCurrentModels(); },
    rightPanelIds: function() { return _rightPanelIds(); },

    handleRefreshResult: function(data) {
      var leftTbody = document.getElementById('refreshLeftTbody');
      if (!leftTbody) return;
      if (data.success && data.models) {
        _refreshData = {};
        _refreshAvailable = data.models;
        data.models.forEach(function(m) {
          _refreshData[m.id] = m.raw ? parsePricingRaw(m.raw) : {};
        });
        _renderAvailableModels();
      } else {
        _refreshAvailable = [];
        _refreshQuery = '';
        leftTbody.innerHTML = '<tr><td class="settings-danger" colspan="5">Error: ' + S.escHtml(data.error || 'Unknown error') + '</td></tr>';
        var countEl = document.getElementById('refreshModelCount');
        if (countEl) countEl.textContent = '';
      }
    },

    addFromRefresh: function(modelId) {
      if (_rightPanelIds().indexOf(modelId) >= 0) return; // already added
      var p = _refreshData[modelId] || {};
      var tbody = document.getElementById('refreshRightTbody');
      if (!tbody) return;
      // Remove placeholder row if present
      var placeholder = tbody.querySelector('td[colspan]');
      if (placeholder) tbody.innerHTML = '';
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
      tr.classList.add('refresh-row-added');
      _wireRightRow(tr, function() { tr.remove(); _renderAvailableModels(); });
      _renderAvailableModels();
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
        var idEl = tr.querySelector('[data-field="id"]');
        if (!idEl) return;
        var id = idEl.getAttribute('data-full-id') || idEl.value || '';
        if (!id) return;
        var values = _readRowValues(tr);
        var newTr = document.createElement('tr');
        newTr.innerHTML = _mainRowHtml(id, values.provider, values);
        mainTbody.appendChild(newTr);
        _wireMainRow(newTr);
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
      var refreshSearch = document.getElementById('refreshModelSearch');
      if (refreshSearch) refreshSearch.addEventListener('input', function() {
        _refreshQuery = refreshSearch.value;
        _renderAvailableModels();
      });
    });
  }

  S.registerSection(sectionName, {load: load, save: save});
})();
