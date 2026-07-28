// ======================================================
// ui-theme.js — UI & Theme settings section
// ======================================================

(function() {
  var sectionName = 'ui';

  var _modelKeys = null;

  function load(data) {
    // Dark mode
    if (data && data.theme) {
      var darkToggle = document.getElementById('darkModeToggle');
      if (darkToggle) {
        if (data.theme.darkMode) darkToggle.classList.add('on');
        else darkToggle.classList.remove('on');
      }
      // Cache model keys for chatDefaultModel dropdown
      if (data.models) _modelKeys = Object.keys(data.models).sort();
    }
    // UI
    if (data && data.ui) {
      var u = data.ui;
      var modelSel = document.getElementById('chatDefaultModel');
      if (modelSel && _modelKeys) fillModelSelect(modelSel, _modelKeys, u.chatDefaultModel);
      // responseFont: stored as CSS stack, UI shows single name
      setVal('responseFont', (u.responseFont || '').split(',')[0].trim());
      if (u.inputWindow) {
        var iw = u.inputWindow;
        setVal('iwBackground', iw.background ? iw.background.replace('0x', '#') : '#212529');
        setVal('iwBackgroundHex', iw.background || '0x212529');
        setVal('iwFontSize', iw.fontSize);
        setVal('iwFontColor', iw.fontColor);
        setVal('iwFontFace', iw.fontFace);
        setVal('iwWidth', iw.width);
        setVal('iwHeight', iw.height);
      }
      if (u.suspendBanner) {
        var sb = u.suspendBanner;
        setVal('sbText', sb.text);
        setVal('sbFontSize', sb.fontSize);
        setVal('sbFontColor', sb.textColor);
        setVal('sbFontFace', sb.fontFace);
        setVal('sbBackground', sb.background ? sb.background.replace('0x', '#') : '#FFDF00');
        setVal('sbBackgroundHex', sb.background || '0xFFDF00');
      }
    }
  }

  function setVal(id, val) {
    var el = document.getElementById(id);
    if (el && val !== undefined && val !== null) el.value = val;
  }

  function getVal(id) {
    var el = document.getElementById(id);
    return el ? el.value : '';
  }

  function save() {
    return {
      theme: {
        darkMode: (document.getElementById('darkModeToggle') || {}).classList ? 
          document.getElementById('darkModeToggle').classList.contains('on') : false
      },
      ui: {
        chatDefaultModel: getVal('chatDefaultModel'),
        responseFont: getVal('responseFont'),
        inputWindow: {
          background: '0x' + getVal('iwBackground').replace('#', ''),
          fontSize: getVal('iwFontSize'),
          fontColor: getVal('iwFontColor'),
          fontFace: getVal('iwFontFace'),
          width: parseInt(getVal('iwWidth')) || 500,
          height: parseInt(getVal('iwHeight')) || 250
        },
        suspendBanner: {
          text: getVal('sbText'),
          fontSize: getVal('sbFontSize'),
          textColor: getVal('sbFontColor'),
          fontFace: getVal('sbFontFace'),
          background: '0x' + getVal('sbBackground').replace('#', '')
        }
      }
    };
  }

  // Wire color pickers to update hex display
  function wireColors() {
    var iwColor = document.getElementById('iwBackground');
    var iwHex = document.getElementById('iwBackgroundHex');
    if (iwColor && iwHex) {
      iwColor.addEventListener('input', function() {
        iwHex.value = '0x' + this.value.replace('#', '');
        if (window.SettingsPanel) window.SettingsPanel.markDirty();
      });
    }
    var sbColor = document.getElementById('sbBackground');
    var sbHex = document.getElementById('sbBackgroundHex');
    if (sbColor && sbHex) {
      sbColor.addEventListener('input', function() {
        sbHex.value = '0x' + this.value.replace('#', '');
        if (window.SettingsPanel) window.SettingsPanel.markDirty();
      });
    }
  }

  // Wire dirty tracking
  function wireDirty() {
    var container = document.getElementById('sec-ui');
    if (!container) return;
    container.querySelectorAll('input, select, textarea').forEach(function(el) {
      el.addEventListener('change', function() {
        if (window.SettingsPanel) window.SettingsPanel.markDirty();
      });
      el.addEventListener('input', function() {
        if (window.SettingsPanel) window.SettingsPanel.markDirty();
      });
    });
    // Switches
    container.querySelectorAll('.switch').forEach(function(sw) {
      sw.addEventListener('click', function() {
        if (window.SettingsPanel) window.SettingsPanel.markDirty();
      });
    });
  }

  if (typeof document !== 'undefined' && document.addEventListener) {
    document.addEventListener('DOMContentLoaded', function() {
      wireColors();
      wireDirty();
      // Wire dark-mode toggle
      var darkToggle = document.getElementById('darkModeToggle');
      if (darkToggle) {
        darkToggle.addEventListener('click', function() {
          this.classList.toggle('on');
          if (window.SettingsPanel) window.SettingsPanel.markDirty();
        });
      }
    });
  }

  function fillModelSelect(sel, keys, current) {
    if (!sel) return;
    sel.innerHTML = '';
    if (current && keys.indexOf(current) < 0) keys.unshift(current);
    keys.forEach(function(k) { var o = document.createElement('option'); o.value = k; o.textContent = k; sel.appendChild(o); });
    if (current) sel.value = current;
  }

  if (typeof window !== 'undefined' && window.SettingsPanel) {
    window.SettingsPanel.registerSection(sectionName, { load: load, save: save });
  } else {
    window.addEventListener('load', function() {
      if (window.SettingsPanel) {
        window.SettingsPanel.registerSection(sectionName, { load: load, save: save });
      }
    });
  }
})();
