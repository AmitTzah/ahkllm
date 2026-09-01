// ======================================================
// ui-theme.js — UI & Theme settings section
// ======================================================

(function() {
  var sectionName = 'ui';
  var S = window.SettingsShared;

  // A fixed-option <select> cannot display a custom stored value; preserve it explicitly.
  // custom value, so load() records the stored value on the element and save()
  // falls back to it when the select has no matching option - otherwise the
  // first Settings save wipes the custom font (responseFont / iwFontFace /
  // sbFontFace).
  function _loadFontFace(id, selectValue, storedValue) {
    var el = document.getElementById(id);
    if (!el) return;
    if (!el.dataset) el.dataset = {};
    el.dataset.storedValue = storedValue || '';
    el.value = selectValue || '';
  }

  function _saveFontFace(id) {
    var el = document.getElementById(id);
    if (!el) return '';
    var v = el.value;
    if (v) return v;
    return (el.dataset && el.dataset.storedValue) || '';
  }

  function load(data) {
    // UI
    if (data && data.ui) {
      var u = data.ui;
      // responseFont: stored as CSS stack, UI shows single name
      var fontName = (u.responseFont || '').split(',')[0].trim();
      _loadFontFace('responseFont', fontName, u.responseFont);
      if (fontName) document.documentElement.style.setProperty('--chat-font-family', fontName + ', sans-serif');
      // responseFontSize: only sets the select value, does NOT apply CSS var.
      // Per-chat font size is applied by populateCurrentSettings from DB.
      var fontSize = u.responseFontSize || '17';
      S.setVal('responseFontSize', fontSize);
      if (u.inputWindow) {
        var iw = u.inputWindow;
        S.setVal('iwBackground', iw.background ? iw.background.replace('0x', '#') : '#FFFFFF');
        S.setVal('iwBackgroundHex', iw.background || '0xFFFFFF');
        S.setVal('iwFontSize', iw.fontSize);
        S.setVal('iwFontColor', iw.fontColor);
        _loadFontFace('iwFontFace', iw.fontFace, iw.fontFace);
        S.setVal('iwWidth', iw.width);
        S.setVal('iwHeight', iw.height);
      }
      if (u.suspendBanner) {
        var sb = u.suspendBanner;
        S.setVal('sbText', sb.text);
        S.setVal('sbFontSize', sb.fontSize);
        S.setVal('sbFontColor', sb.textColor);
        _loadFontFace('sbFontFace', sb.fontFace, sb.fontFace);
        S.setVal('sbBackground', sb.background ? sb.background.replace('0x', '#') : '#FFDF00');
        S.setVal('sbBackgroundHex', sb.background || '0xFFDF00');
      }
    }
  }

  function save() {
    return {
      ui: {
        responseFont: _saveFontFace('responseFont'),
        responseFontSize: S.getVal('responseFontSize'),
        inputWindow: {
          background: '0x' + S.getVal('iwBackground').replace('#', ''),
          fontSize: S.getVal('iwFontSize'),
          fontColor: S.getVal('iwFontColor'),
          fontFace: _saveFontFace('iwFontFace'),
          width: parseInt(S.getVal('iwWidth')) || 500,
          height: parseInt(S.getVal('iwHeight')) || 250
        },
        suspendBanner: {
          text: S.getVal('sbText'),
          fontSize: S.getVal('sbFontSize'),
          textColor: S.getVal('sbFontColor'),
          fontFace: _saveFontFace('sbFontFace'),
          background: '0x' + S.getVal('sbBackground').replace('#', '')
        }
      }
    };
  }

  // Wire color pickers to update hex display
  function wireColorPair(colorId, hexId) {
    var colorEl = document.getElementById(colorId);
    var hexEl = document.getElementById(hexId);
    if (!colorEl || !hexEl) return;
    colorEl.addEventListener('input', function() {
      hexEl.value = '0x' + this.value.replace('#', '');
      S.markDirty();
    });
  }

  function wireColors() {
    wireColorPair('iwBackground', 'iwBackgroundHex');
    wireColorPair('sbBackground', 'sbBackgroundHex');
  }

  // Wire responseFontSize: only marks dirty on change.
  // Does NOT apply CSS var — per-chat font size is controlled by the header +/- buttons.
  function wireResponseFontSize() {
    var sel = document.getElementById('responseFontSize');
    if (!sel) return;
    sel.addEventListener('change', function() {
      S.markDirty();
    });
  }

  if (typeof document !== 'undefined' && document.addEventListener) {
    document.addEventListener('DOMContentLoaded', function() {
      wireColors();
      S.wireDirty('sec-ui', S.markDirty);
      wireResponseFontSize();
    });
  }

  S.registerSection(sectionName, { load: load, save: save });
})();
