// ======================================================
// settings-shared.js — Shared helpers for settings sections.
// Single home for HTML escaping, select filling, dirty
// tracking, and section registration so each sections/*.js
// module only holds its own section logic.
// ======================================================

window.SettingsShared = (function() {
  function escHtml(s) {
    return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  }

  function num(v, dflt) {
    var n = parseInt(v, 10);
    return isNaN(n) ? dflt : n;
  }

  // Fill a <select> with keys, keeping an unknown current value visible.
  function fillSelect(sel, keys, current) {
    if (!sel) return;
    sel.innerHTML = '';
    if (current != null && keys.indexOf(current) < 0) keys.unshift(current);
    keys.forEach(function(k) {
      var o = document.createElement('option');
      o.value = k;
      o.textContent = k;
      sel.appendChild(o);
    });
    if (current != null) sel.value = current;
  }

  // Build <option> HTML for a key list, optionally marking one selected.
  function buildModelOptionsHtml(keys, current) {
    var html = '';
    var all = keys.slice();
    if (current != null && all.indexOf(current) < 0) all.unshift(current);
    all.forEach(function(k) {
      html += '<option' + (k === current ? ' selected' : '') + '>' + escHtml(k) + '</option>';
    });
    return html;
  }

  function setVal(id, v) {
    var el = document.getElementById(id);
    if (el && v !== undefined && v !== null) el.value = v;
  }

  function getVal(id) {
    var el = document.getElementById(id);
    return el ? el.value : '';
  }

  // Wire change/input on every field and click on every switch inside a section.
  function wireDirty(containerId, mark) {
    var container = document.getElementById(containerId);
    if (!container) return;
    container.querySelectorAll('input, select, textarea').forEach(function(el) {
      el.addEventListener('change', mark);
      el.addEventListener('input', mark);
    });
    container.querySelectorAll('.switch').forEach(function(sw) {
      sw.addEventListener('click', mark);
    });
  }

  function markDirty() {
    if (window.SettingsPanel && typeof window.SettingsPanel.markDirty === 'function') {
      window.SettingsPanel.markDirty();
    }
  }

  // Register a section module; retry until the panel is available.
  function registerSection(name, module) {
    if (window.SettingsPanel && typeof window.SettingsPanel.registerSection === 'function') {
      window.SettingsPanel.registerSection(name, module);
      return;
    }
    setTimeout(function() { registerSection(name, module); }, 50);
  }

  return {
    escHtml: escHtml,
    num: num,
    fillSelect: fillSelect,
    buildModelOptionsHtml: buildModelOptionsHtml,
    setVal: setVal,
    getVal: getVal,
    wireDirty: wireDirty,
    markDirty: markDirty,
    registerSection: registerSection
  };
})();
