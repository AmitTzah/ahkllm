// providers.js — Providers settings section
(function() {
  var sectionName = 'providers';
  var containerId = 'sec-providers';

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

  function renderCards(providers) {
    var grid = document.getElementById('providerGrid');
    if (!grid) return;
    grid.innerHTML = '';
    var keys = Object.keys(providers).sort();
    var palIdx = 0;
    keys.forEach(function(key) {
      var p = providers[key];
      var card = document.createElement('div');
      card.className = 'provider-card';
      card.dataset.providerKey = key;
      card.innerHTML = '<div class="provider-card-header"><div class="provider-icon" style="background:' + PALETTE[palIdx % PALETTE.length].bg + ';color:' + PALETTE[palIdx % PALETTE.length].fg + ';">' + escHtml(getInitials(p.displayName || key)) + '</div><span style="font-weight:600;">' + escHtml(p.displayName || key) + '</span><button class="btn-sm danger" style="margin-left:auto;">Remove</button></div>' +
        '<div class="field"><label class="field-label">Display Name</label><input value="' + escHtml(p.displayName || '') + '" data-field="displayName"></div>' +
        '<div class="field"><label class="field-label">Chat Endpoint</label><input value="' + escHtml(p.endpoint || '') + '" data-field="endpoint"></div>' +
        '<div class="field"><label class="field-label">FIM Endpoint</label><input value="' + escHtml(p.fimEndpoint || '') + '" data-field="fimEndpoint"></div>' +
        '<div class="field"><label class="field-label">API Key <span class="hint">env variable (preferred)</span></label><input value="' + escHtml(p.authEnvVar || '') + '" data-field="authEnvVar" style="font-family:var(--font-mono);font-size:12px;"><div class="field-hint">Set via: setx ' + escHtml(p.authEnvVar || 'KEY') + ' your-key</div></div>' +
        '<div class="field"><label class="field-label">API Key <span class="hint">or enter directly</span></label><div style="display:flex;gap:6px;"><input type="password" value="' + escHtml(p.apiKey || '') + '" data-field="apiKey" placeholder="sk-..." style="font-family:var(--font-mono);font-size:12px;flex:1;"><button class="btn-sm toggle-api-key" title="Show/hide">' + String.fromCharCode(0x1F441) + '</button></div><div class="field-hint" style="color:var(--warning);">⚠ Direct entry stores key in settings.json</div></div>' +
        '<div class="field"><label class="field-label">Model Name Prefixes <span class="hint">routes matching model names to this provider</span></label><div class="prefix-tags" data-field="prefixes">' + renderPrefixes(p.prefixes || []) + '</div></div>' +
        '<div class="toggle-row"><div><div class="lbl">Collapse thinking blocks by default</div><div style="font-size:11px;color:var(--text-tertiary);">When streaming, reasoning/thinking content is hidden until expanded</div></div><div class="switch' + (p.collapseThinking ? ' on' : '') + '" data-field="collapseThinking"><div class="knob"></div></div></div>';
      grid.appendChild(card);
      // Wire prefix badge remove buttons (initial ones are dead without this)
      card.querySelectorAll('.prefix-tags .badge .remove').forEach(function(rm) {
        rm.addEventListener('click', function() { rm.parentElement.remove(); mark(); });
      });
      // Wire switch
      card.querySelectorAll('.switch').forEach(function(sw) {
        sw.addEventListener('click', function() { this.classList.toggle('on'); mark(); });
      });
      // Wire inputs
      card.querySelectorAll('input').forEach(function(inp) {
        inp.addEventListener('input', function() { mark(); });
      });
      // Wire remove
      card.querySelector('.btn-sm.danger').addEventListener('click', function() {
        var count = grid.querySelectorAll('.provider-card').length;
        if (count <= 1) return; // keep at least one
        card.remove(); mark();
      });
      // Wire toggle API key visibility
      var toggleBtn = card.querySelector('.toggle-api-key');
      if (toggleBtn) {
        toggleBtn.addEventListener('click', function() {
          var keyInput = card.querySelector('[data-field="apiKey"]');
          if (keyInput) keyInput.type = keyInput.type === 'password' ? 'text' : 'password';
        });
      }
      // Wire prefix add
      var prefixDiv = card.querySelector('.prefix-tags');
      if (prefixDiv) {
        var addLink = document.createElement('span');
        addLink.style.cssText = 'font-size:11px;color:var(--text-tertiary);cursor:pointer;';
        addLink.textContent = '+ add';
        addLink.addEventListener('click', function() {
          var tag = document.createElement('span'); tag.className = 'badge';
          var inp = document.createElement('input'); inp.style.cssText = 'width:60px;border:none;background:transparent;font-size:10px;outline:none;';
          inp.addEventListener('blur', function() { tag.innerHTML = escHtml(inp.value || '?') + ' <span class=remove>×</span>'; tag.querySelector('.remove').addEventListener('click', function() { tag.remove(); mark(); }); mark(); });
          tag.appendChild(inp); prefixDiv.insertBefore(tag, addLink); inp.focus();
        });
        prefixDiv.appendChild(addLink);
      }
      palIdx++;
    });
  }

  function renderPrefixes(prefixes) {
    var html = '';
    (prefixes || []).forEach(function(p) { html += '<span class="badge">' + escHtml(p) + ' <span class="remove">×</span></span>'; });
    return html;
  }

  function mark() { if (window.SettingsPanel) window.SettingsPanel.markDirty(); }

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
        var txt = tag.textContent.replace('×', '').trim();
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
    var colors = PALETTE[0];
    card.innerHTML = '<div class="provider-card-header"><div class="provider-icon" style="background:' + colors.bg + ';color:' + colors.fg + ';">NP</div><span style="font-weight:600;">New Provider</span><button class="btn-sm danger" style="margin-left:auto;">Remove</button></div>' +
      '<div class="field"><label class="field-label">Display Name</label><input value="New Provider" data-field="displayName"></div>' +
      '<div class="field"><label class="field-label">Chat Endpoint</label><input placeholder="https://..." data-field="endpoint"></div>' +
      '<div class="field"><label class="field-label">FIM Endpoint</label><input placeholder="https://..." data-field="fimEndpoint"></div>' +
      '<div class="field"><label class="field-label">API Key <span class="hint">env variable (preferred)</span></label><input placeholder="API_KEY" data-field="authEnvVar" style="font-family:var(--font-mono);font-size:12px;"><div class="field-hint">Set via: setx API_KEY your-key</div></div>' +
      '<div class="field"><label class="field-label">API Key <span class="hint">or enter directly</span></label><div style="display:flex;gap:6px;"><input type="password" placeholder="sk-..." data-field="apiKey" style="font-family:var(--font-mono);font-size:12px;flex:1;"><button class="btn-sm toggle-api-key" title="Show/hide">' + String.fromCharCode(0x1F441) + '</button></div><div class="field-hint" style="color:var(--warning);">⚠ Direct entry stores key in settings.json</div></div>' +
      '<div class="field"><label class="field-label">Model Name Prefixes <span class="hint">routes matching model names to this provider</span></label><div class="prefix-tags" data-field="prefixes"></div></div>' +
      '<div class="toggle-row"><div><div class="lbl">Collapse thinking blocks by default</div><div style="font-size:11px;color:var(--text-tertiary);">When streaming, reasoning/thinking content is hidden until expanded</div></div><div class="switch" data-field="collapseThinking"><div class="knob"></div></div></div>';
    grid.appendChild(card);
    card.querySelectorAll('input').forEach(function(inp) { inp.addEventListener('input', mark); });
    card.querySelectorAll('.switch').forEach(function(sw) { sw.addEventListener('click', function() { sw.classList.toggle('on'); mark(); }); });
    var toggleBtn = card.querySelector('.toggle-api-key');
    if (toggleBtn) {
      toggleBtn.addEventListener('click', function() {
        var keyInput = card.querySelector('[data-field="apiKey"]');
        if (keyInput) keyInput.type = keyInput.type === 'password' ? 'text' : 'password';
      });
    }
    card.querySelector('.btn-sm.danger').addEventListener('click', function() {
      var count = grid.querySelectorAll('.provider-card').length;
      if (count <= 1) return; card.remove(); mark();
    });
    // Wire prefix add for new card
    var prefixDiv = card.querySelector('.prefix-tags');
    if (prefixDiv) {
      var addLink = document.createElement('span');
      addLink.style.cssText = 'font-size:11px;color:var(--text-tertiary);cursor:pointer;';
      addLink.textContent = '+ add';
      addLink.addEventListener('click', function() {
        var tag = document.createElement('span'); tag.className = 'badge';
        var inp = document.createElement('input'); inp.style.cssText = 'width:60px;border:none;background:transparent;font-size:10px;outline:none;';
        inp.addEventListener('blur', function() { tag.innerHTML = escHtml(inp.value || '?') + ' <span class=remove>×</span>'; tag.querySelector('.remove').addEventListener('click', function() { tag.remove(); mark(); }); mark(); });
        tag.appendChild(inp); prefixDiv.insertBefore(tag, addLink); inp.focus();
      });
      prefixDiv.appendChild(addLink);
    }
    mark();
  }

  function escHtml(s) { return String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;'); }

  if (typeof document !== 'undefined') {
    document.addEventListener('DOMContentLoaded', function() {
      var addBtn = document.getElementById('addProviderBtn');
      if (addBtn) addBtn.addEventListener('click', addProvider);
    });
  }
  (function reg() { if (window.SettingsPanel) window.SettingsPanel.registerSection(sectionName, {load:load, save:save}); else setTimeout(reg, 50); })();
})();
