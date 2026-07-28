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
  function wireKeyCaptures() {
    document.querySelectorAll('.key-capture').forEach(function(kc) {
      kc.addEventListener('click', function() {
        var inp = this.querySelector('input');
        if (inp) { inp.focus(); inp.select(); }
      });
      var inp = kc.querySelector('input');
      if (inp) {
        inp.addEventListener('focus', function() { kc.classList.add('listening'); });
        inp.addEventListener('blur', function() { kc.classList.remove('listening'); });
      }
    });
  }
  if (typeof document !== 'undefined') {
    document.addEventListener('DOMContentLoaded', function() {
      wireDirty();
      wireKeyCaptures();
      var restartBtn = document.getElementById('restartNowBtn');
      if (restartBtn) {
        restartBtn.addEventListener('click', function() {
          window.chrome.webview.postMessage(JSON.stringify({action:'reloadScript'}));
        });
      }
    });
  }
  (function reg() { if (window.SettingsPanel) window.SettingsPanel.registerSection(sectionName, {load:load, save:save}); else setTimeout(reg, 50); })();
})();
