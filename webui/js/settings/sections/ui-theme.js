// ======================================================
// ui-theme.js — UI & Theme settings section
// ======================================================

(function() {
  var sectionName = 'ui';
  var S = window.SettingsShared;

  function load(data) {
    // UI
    if (data && data.ui) {
      var u = data.ui;
      // responseFont: stored as CSS stack, UI shows single name
      var fontName = (u.responseFont || '').split(',')[0].trim();
      S.setVal('responseFont', fontName);
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
        S.setVal('iwFontFace', iw.fontFace);
        S.setVal('iwWidth', iw.width);
        S.setVal('iwHeight', iw.height);
      }
      if (u.suspendBanner) {
        var sb = u.suspendBanner;
        S.setVal('sbText', sb.text);
        S.setVal('sbFontSize', sb.fontSize);
        S.setVal('sbFontColor', sb.textColor);
        S.setVal('sbFontFace', sb.fontFace);
        S.setVal('sbBackground', sb.background ? sb.background.replace('0x', '#') : '#FFDF00');
        S.setVal('sbBackgroundHex', sb.background || '0xFFDF00');
      }
    }
  }

  function save() {
    return {
      ui: {
        responseFont: S.getVal('responseFont'),
        responseFontSize: S.getVal('responseFontSize'),
        inputWindow: {
          background: '0x' + S.getVal('iwBackground').replace('#', ''),
          fontSize: S.getVal('iwFontSize'),
          fontColor: S.getVal('iwFontColor'),
          fontFace: S.getVal('iwFontFace'),
          width: parseInt(S.getVal('iwWidth')) || 500,
          height: parseInt(S.getVal('iwHeight')) || 250
        },
        suspendBanner: {
          text: S.getVal('sbText'),
          fontSize: S.getVal('sbFontSize'),
          textColor: S.getVal('sbFontColor'),
          fontFace: S.getVal('sbFontFace'),
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
