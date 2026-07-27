// hotkeys.js — Hotkeys settings section
(function() {
  var sectionName = 'hotkeys';
  function load(data) {
    if (data && data.hotkeys) {
      setVal('hkMain', data.hotkeys.main);
      setVal('hkSaveReload', data.hotkeys.saveReload);
      setVal('hkCloseWindows', data.hotkeys.closeWindows);
      setVal('hkSuspend', data.hotkeys.suspend);
    }
  }
  function setVal(id, v) { var el = document.getElementById(id); if (el && v !== undefined) el.value = v; }
  function getVal(id) { var el = document.getElementById(id); return el ? el.value : ''; }
  function save() {
    return { hotkeys: { main: getVal('hkMain'), saveReload: getVal('hkSaveReload'), closeWindows: getVal('hkCloseWindows'), suspend: getVal('hkSuspend') } };
  }
  function wireDirty() {
    var c = document.getElementById('sec-hotkeys'); if (!c) return;
    c.querySelectorAll('input').forEach(function(el) { el.addEventListener('input', function() { if (window.SettingsPanel) window.SettingsPanel.markDirty(); }); });
  }
  if (typeof document !== 'undefined') document.addEventListener('DOMContentLoaded', wireDirty);
  (function reg() { if (window.SettingsPanel) window.SettingsPanel.registerSection(sectionName, {load:load, save:save}); else setTimeout(reg, 50); })();
})();
