// providers.js — Providers settings section
(function() {
  var sectionName = 'providers';
  var containerId = 'sec-providers';

  function load(data) {
    if (!data || !data.providers) return;
    renderCards(data.providers);
  }

  function renderCards(providers) {
    var grid = document.getElementById('providerGrid');
    if (!grid) return;
    grid.innerHTML = '';
    var keys = Object.keys(providers).sort();
    keys.forEach(function(key) {
      var p = providers[key];
      var card = document.createElement('div');
      card.className = 'provider-card';
      card.dataset.providerKey = key;
      card.innerHTML = '<div class="provider-card-header"><span style="font-weight:600;">' + escHtml(p.displayName || key) + '</span><button class="btn-sm danger" style="margin-left:auto;">Remove</button></div>' +
        '<div class="field"><label class="field-label">Display Name</label><input value="' + escHtml(p.displayName || '') + '" data-field="displayName"></div>' +
        '<div class="field"><label class="field-label">Chat Endpoint</label><input value="' + escHtml(p.endpoint || '') + '" data-field="endpoint"></div>' +
        '<div class="field"><label class="field-label">FIM Endpoint</label><input value="' + escHtml(p.fimEndpoint || '') + '" data-field="fimEndpoint"></div>' +
        '<div class="field"><label class="field-label">API Key (env variable)</label><input value="' + escHtml(p.authEnvVar || '') + '" data-field="authEnvVar" style="font-family:var(--font-mono);font-size:12px;"><span style="font-size:10px;color:var(--text-tertiary);">Set via: setx ' + escHtml(p.authEnvVar || 'KEY') + ' your-key</span></div>' +
        '<div class="field"><label class="field-label">API Key (direct entry)</label><input type="password" value="' + escHtml(p.apiKey || '') + '" data-field="apiKey" placeholder="sk-..." style="font-family:var(--font-mono);font-size:12px;"><span style="font-size:10px;color:var(--warning);">⚠ Stored in settings.json</span></div>' +
        '<div class="toggle-row"><div><div class="lbl">Collapse thinking blocks</div><div style="font-size:11px;color:var(--text-tertiary);">Reasoning content hidden until expanded</div></div><div class="switch' + (p.collapseThinking ? ' on' : '') + '" data-field="collapseThinking"><div class="knob"></div></div></div>' +
        '<div class="field"><label class="field-label">Model Name Prefixes</label><div class="prefix-tags" data-field="prefixes">' + renderPrefixes(p.prefixes || []) + '</div></div>';
      grid.appendChild(card);
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
    renderCards({}); // dummy — we'll just append
    var card = document.createElement('div'); card.className = 'provider-card'; card.dataset.providerKey = newKey;
    card.innerHTML = '<div class="provider-card-header"><input value="New Provider" data-field="displayName" style="border:none;font-weight:600;background:transparent;font-size:14px;width:auto;"></div>' +
      '<div class="field"><label class="field-label">Display Name</label><input value="New Provider" data-field="displayName"></div>' +
      '<div class="field"><label class="field-label">Chat Endpoint</label><input placeholder="https://..." data-field="endpoint"></div>' +
      '<div class="field"><label class="field-label">API Key (env variable)</label><input placeholder="API_KEY" data-field="authEnvVar" style="font-family:var(--font-mono);font-size:12px;"></div>' +
      '<div class="field"><label class="field-label">API Key (direct)</label><input type="password" placeholder="sk-..." data-field="apiKey" style="font-family:var(--font-mono);font-size:12px;"></div>';
    grid.appendChild(card);
    card.querySelectorAll('input').forEach(function(inp) { inp.addEventListener('input', mark); });
    mark();
  }

  function escHtml(s) { return String(s).replace(/&/g,'&').replace(/</g,'<').replace(/>/g,'>').replace(/"/g,'"'); }

  if (typeof document !== 'undefined') {
    document.addEventListener('DOMContentLoaded', function() {
      var addBtn = document.getElementById('addProviderBtn');
      if (addBtn) addBtn.addEventListener('click', addProvider);
    });
  }
  (function reg() { if (window.SettingsPanel) window.SettingsPanel.registerSection(sectionName, {load:load, save:save}); else setTimeout(reg, 50); })();
})();
