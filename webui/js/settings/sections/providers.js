// providers.js — Providers settings section
(function() {
  var sectionName = 'providers';
  var containerId = 'sec-providers';
  var S = window.SettingsShared;

  function load(data) {
    if (!data || !data.providers) return;
    renderCards(data.providers);
  }

  var PALETTE = [
    { bg: '#E0E7FF', fg: '#4F46E5' },
    { bg: '#E0F2E0', fg: '#10B981' },
    { bg: '#FEF3C7', fg: '#F59E0B' },
    { bg: '#FCE7F3', fg: '#DB2777' }
  ];

  function getInitials(name) {
    var parts = (name || '').split(/[\s-]+/);
    return (parts[0].charAt(0) + (parts[1] ? parts[1].charAt(0) : '')).toUpperCase();
  }

  // --- Shared card HTML template ---

  function providerCardHTML(p, key, palIdx) {
    var colors = PALETTE[palIdx % PALETTE.length];
    return '<div class="provider-card-header"><div class="provider-icon" style="background:' + colors.bg + ';color:' + colors.fg + ';">' + S.escHtml(getInitials(p.displayName || key)) + '</div><span class="settings-fw-600">' + S.escHtml(p.displayName || key) + '</span><button class="btn-sm danger settings-ml-auto">Remove</button></div>' +
      '<div class="field"><label class="field-label">Display Name</label><input type="text" value="' + S.escHtml(p.displayName || '') + '" data-field="displayName"></div>' +
      '<div class="field"><label class="field-label">Chat Endpoint</label><input type="text" value="' + S.escHtml(p.endpoint || '') + '" data-field="endpoint"></div>' +
      '<div class="field"><label class="field-label">FIM Endpoint</label><input type="text" value="' + S.escHtml(p.fimEndpoint || '') + '" data-field="fimEndpoint"></div>' +
      '<div class="field"><label class="field-label">API Key <span class="hint">env variable (preferred)</span></label><input class="settings-mono-input" type="text" value="' + S.escHtml(p.authEnvVar || '') + '" data-field="authEnvVar"><div class="field-hint">Set via: setx ' + S.escHtml(p.authEnvVar || 'KEY') + ' your-key</div></div>' +
      '<div class="field"><label class="field-label">API Key <span class="hint">or enter directly</span></label><div class="settings-flex-row-6"><input class="settings-mono-flex" type="password" value="' + S.escHtml(p.apiKey || '') + '" data-field="apiKey" placeholder="sk-..."><button class="btn-sm toggle-api-key" title="Show/hide">' + String.fromCharCode(0x1F441) + '</button></div><div class="field-hint settings-warning">\u26A0 Direct entry stores key in settings.json</div></div>' +
      '<div class="field"><label class="field-label">Model Name Prefixes <span class="hint">routes matching model names to this provider</span></label><div class="prefix-tags" data-field="prefixes">' + renderPrefixes(p.prefixes || []) + '</div></div>' +
      '<div class="toggle-row"><div><div class="lbl">Collapse thinking blocks by default</div><div class="settings-text-xs-muted">When streaming, reasoning/thinking content is hidden until expanded</div></div><div class="switch' + (p.collapseThinking ? ' on' : '') + '" data-field="collapseThinking"><div class="knob"></div></div></div>';
  }

  // --- Shared card wiring ---

  function wireProviderCard(card, grid) {
    // Prefix badge remove buttons
    card.querySelectorAll('.prefix-tags .badge .remove').forEach(function(rm) {
      rm.addEventListener('click', function() { rm.parentElement.remove(); mark(); });
    });
    // Switches
    card.querySelectorAll('.switch').forEach(function(sw) {
      sw.addEventListener('click', function() { this.classList.toggle('on'); mark(); });
    });
    // Inputs
    card.querySelectorAll('input').forEach(function(inp) {
      inp.addEventListener('input', function() { mark(); });
    });
    // Remove button (keep at least one provider)
    card.querySelector('.btn-sm.danger').addEventListener('click', function() {
      if (grid.querySelectorAll('.provider-card').length <= 1) return;
      card.remove(); mark();
    });
    // Toggle API key visibility
    var toggleBtn = card.querySelector('.toggle-api-key');
    if (toggleBtn) {
      toggleBtn.addEventListener('click', function() {
        var keyInput = card.querySelector('[data-field="apiKey"]');
        if (keyInput) keyInput.type = keyInput.type === 'password' ? 'text' : 'password';
      });
    }
    // Prefix add link
    var prefixDiv = card.querySelector('.prefix-tags');
    if (prefixDiv) {
      var addLink = document.createElement('span');
      addLink.style.cssText = 'font-size:11px;color:var(--text-tertiary);cursor:pointer;';
      addLink.textContent = '+ add';
      addLink.addEventListener('click', function() {
        var tag = document.createElement('span'); tag.className = 'badge';
        var inp = document.createElement('input'); inp.style.cssText = 'width:60px;border:none;background:transparent;font-size:10px;outline:none;';
        inp.addEventListener('blur', function() { tag.innerHTML = S.escHtml(inp.value || '?') + ' <span class=remove>\u00D7</span>'; tag.querySelector('.remove').addEventListener('click', function() { tag.remove(); mark(); }); mark(); });
        tag.appendChild(inp); prefixDiv.insertBefore(tag, addLink); inp.focus();
      });
      prefixDiv.appendChild(addLink);
    }
  }

  // --- Main render ---

  function renderCards(providers) {
    var grid = document.getElementById('providerGrid');
    if (!grid) return;
    grid.innerHTML = '';
    var keys = Object.keys(providers).sort();
    keys.forEach(function(key, idx) {
      var p = providers[key];
      var card = document.createElement('div');
      card.className = 'provider-card';
      card.dataset.providerKey = key;
      card.innerHTML = providerCardHTML(p, key, idx);
      grid.appendChild(card);
      wireProviderCard(card, grid);
    });
  }

  function renderPrefixes(prefixes) {
    var html = '';
    (prefixes || []).forEach(function(p) { html += '<span class="badge">' + S.escHtml(p) + ' <span class="remove">\u00D7</span></span>'; });
    return html;
  }

  function mark() { S.markDirty(); }

  function save() {
    var providers = {};
    document.querySelectorAll('#providerGrid .provider-card').forEach(function(card) {
      var key = card.dataset.providerKey || 'new-provider';
      var obj = {};
      card.querySelectorAll('[data-field]').forEach(function(el) {
        var field = el.dataset.field;
        if (el.classList.contains('switch')) obj[field] = el.classList.contains('on');
        else obj[field] = el.value || '';
      });
      obj.authMode = (obj.apiKey && !obj.authEnvVar) ? 'direct' : 'env';
      obj.prefixes = [];
      card.querySelectorAll('.prefix-tags .badge').forEach(function(tag) {
        var txt = tag.textContent.replace('\u00D7', '').trim();
        if (txt) obj.prefixes.push(txt);
      });
      providers[key] = obj;
    });
    return { providers: providers };
  }

  function addProvider() {
    var grid = document.getElementById('providerGrid'); if (!grid) return;
    var newKey = 'provider-' + Date.now();
    var card = document.createElement('div'); card.className = 'provider-card'; card.dataset.providerKey = newKey;
    var p = { displayName: 'New Provider', endpoint: '', fimEndpoint: '', authEnvVar: '', apiKey: '', prefixes: [], collapseThinking: false };
    card.innerHTML = providerCardHTML(p, newKey, 0);
    grid.appendChild(card);
    wireProviderCard(card, grid);
    mark();
  }

  if (typeof document !== 'undefined') {
    document.addEventListener('DOMContentLoaded', function() {
      var addBtn = document.getElementById('addProviderBtn');
      if (addBtn) addBtn.addEventListener('click', addProvider);
    });
  }
  S.registerSection(sectionName, {load: load, save: save});
})();
