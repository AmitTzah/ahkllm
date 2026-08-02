// hotkeys.js — Hotkeys settings section
(function() {
  var sectionName = 'hotkeys';
  var S = window.SettingsShared;
  function load(data) {
    if (data && data.hotkeys) {
      S.setVal('hkMain', data.hotkeys.main);
      S.setVal('hkReload', data.hotkeys.reload);
      S.setVal('hkCloseWindows', data.hotkeys.closeWindows);
      S.setVal('hkSuspend', data.hotkeys.suspend);
    }
  }
  function save() {
    return { hotkeys: { main: S.getVal('hkMain'), reload: S.getVal('hkReload'), closeWindows: S.getVal('hkCloseWindows'), suspend: S.getVal('hkSuspend') } };
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
      S.wireDirty('sec-hotkeys', S.markDirty);
      wireKeyCaptures();
    });
  }
  S.registerSection(sectionName, {load: load, save: save});
})();
