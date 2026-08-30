// hotkeys.js - Hotkeys settings section
(function() {
  var sectionName = 'hotkeys';
  var S = window.SettingsShared;

  var keyNames = {
    Backspace: 'Backspace', Delete: 'Delete', Insert: 'Insert', Home: 'Home', End: 'End',
    PgUp: 'Page Up', PgDn: 'Page Down', Up: 'Up', Down: 'Down', Left: 'Left', Right: 'Right',
    Enter: 'Enter', Tab: 'Tab', Space: 'Space', CapsLock: 'Caps Lock', NumLock: 'Num Lock',
    ScrollLock: 'Scroll Lock', PrintScreen: 'Print Screen', Pause: 'Pause', AppsKey: 'Menu',
    NumpadAdd: 'Numpad +', NumpadSub: 'Numpad -', NumpadMult: 'Numpad *',
    NumpadDiv: 'Numpad /', NumpadDot: 'Numpad .'
  };

  function inputIdFor(kc) {
    if (!kc) return '';
    if (kc.dataset && kc.dataset.hotkeyInput) return kc.dataset.hotkeyInput;
    return kc.getAttribute ? (kc.getAttribute('data-hotkey-input') || '') : '';
  }

  function storageInput(kc) {
    var id = inputIdFor(kc);
    return id ? document.getElementById(id) : null;
  }

  function stripPrefixes(raw) {
    raw = String(raw || '');
    while (raw && (raw.charAt(0) === '~' || raw.charAt(0) === '*' || raw.charAt(0) === '$')) raw = raw.slice(1);
    return raw;
  }

  function preservedPrefixes(raw) {
    raw = String(raw || '');
    var prefix = '';
    while (raw && (raw.charAt(0) === '~' || raw.charAt(0) === '*' || raw.charAt(0) === '$')) {
      prefix += raw.charAt(0);
      raw = raw.slice(1);
    }
    return prefix;
  }

  function friendlyKeyName(key) {
    if (!key) return '';
    if (key === '`' || key.toUpperCase() === 'SC029') return 'Backtick';
    if (keyNames[key]) return keyNames[key];
    if (/^F([1-9]|1[0-9]|2[0-4])$/i.test(key)) return key.toUpperCase();
    if (/^Numpad[0-9]$/i.test(key)) return 'Numpad ' + key.slice(-1);
    if (key.length === 1 && /[a-z]/i.test(key)) return key.toUpperCase();
    return key;
  }

  function friendlyPart(raw) {
    raw = stripPrefixes(raw);
    var parts = [];
    var modifiers = [
      ['<^', 'Left Ctrl'], ['>^', 'Right Ctrl'], ['<!', 'Left Alt'], ['>!', 'Right Alt'],
      ['<+', 'Left Shift'], ['>+', 'Right Shift'], ['<#', 'Left Win'], ['>#', 'Right Win'],
      ['^', 'Ctrl'], ['!', 'Alt'], ['+', 'Shift'], ['#', 'Win']
    ];
    var matched = true;
    while (raw && matched) {
      matched = false;
      for (var i = 0; i < modifiers.length; i++) {
        if (raw.indexOf(modifiers[i][0]) === 0) {
          parts.push(modifiers[i][1]);
          raw = raw.slice(modifiers[i][0].length);
          matched = true;
          break;
        }
      }
    }
    if (raw) parts.push(friendlyKeyName(raw));
    return parts.join(' + ');
  }

  function formatForDisplay(raw) {
    raw = String(raw || '').trim();
    if (!raw) return 'None';
    var comboAt = raw.indexOf(' & ');
    if (comboAt >= 0) return friendlyPart(raw.slice(0, comboAt)) + ' + ' + friendlyPart(raw.slice(comboAt + 3));
    return friendlyPart(raw) || raw;
  }

  function keyFromEvent(evt) {
    var code = evt.code || '';
    if (/^Key[A-Z]$/.test(code)) return code.slice(3).toLowerCase();
    if (/^Digit[0-9]$/.test(code)) return code.slice(5);
    if (/^Numpad[0-9]$/.test(code)) return code;

    var codeMap = {
      Backquote: '`', Minus: '-', Equal: '=', BracketLeft: '[', BracketRight: ']', Backslash: '\\',
      Semicolon: ';', Quote: "'", Comma: ',', Period: '.', Slash: '/', NumpadAdd: 'NumpadAdd',
      NumpadSubtract: 'NumpadSub', NumpadMultiply: 'NumpadMult', NumpadDivide: 'NumpadDiv', NumpadDecimal: 'NumpadDot'
    };
    if (codeMap[code]) return codeMap[code];

    var key = evt.key || '';
    var keyMap = { PageUp: 'PgUp', PageDown: 'PgDn', ArrowUp: 'Up', ArrowDown: 'Down', ArrowLeft: 'Left', ArrowRight: 'Right', ' ': 'Space' };
    if (keyMap[key]) return keyMap[key];
    if (/^F([1-9]|1[0-9]|2[0-4])$/.test(key)) return key;
    if (['Enter', 'Tab', 'Backspace', 'Delete', 'Insert', 'Home', 'End', 'CapsLock', 'NumLock', 'ScrollLock', 'PrintScreen', 'Pause'].indexOf(key) >= 0) return key;
    if (key === 'ContextMenu') return 'AppsKey';
    if (['Control', 'Shift', 'Alt', 'Meta', 'AltGraph'].indexOf(key) >= 0) return '';
    if (key.length === 1) return key.toLowerCase();
    return '';
  }

  function eventToAhk(evt, currentRaw) {
    var key = keyFromEvent(evt);
    if (!key) return '';
    var mods = '';
    if (evt.ctrlKey) mods += '^';
    if (evt.altKey) mods += '!';
    if (evt.shiftKey) mods += '+';
    if (evt.metaKey) mods += '#';
    return preservedPrefixes(currentRaw) + mods + key;
  }

  function renderCapture(kc) {
    var hidden = storageInput(kc);
    if (!hidden) return;
    var display = kc.querySelector ? kc.querySelector('.key-display') : null;
    var manual = kc.querySelector ? kc.querySelector('.key-manual-input') : null;
    if (display) display.textContent = formatForDisplay(hidden.value);
    if (manual && manual.value !== hidden.value) manual.value = hidden.value;
  }

  function renderAllCaptures() {
    document.querySelectorAll('.key-capture').forEach(renderCapture);
  }

  function setStatus(kc, text) {
    var status = kc.querySelector ? kc.querySelector('.status') : null;
    if (status) status.textContent = text;
  }

  function normalStatus(kc) {
    return kc.classList.contains('pending') ? 'Save Changes to apply' : 'click to record';
  }

  function stopListening(kc) {
    kc.classList.remove('listening');
    setStatus(kc, normalStatus(kc));
  }

  function setPending(kc, pending) {
    if (pending) kc.classList.add('pending');
    else kc.classList.remove('pending');
    if (!kc.classList.contains('listening') && !kc.classList.contains('manual-open')) {
      setStatus(kc, normalStatus(kc));
    }
  }

  function setRawValue(kc, value, markDirty) {
    var hidden = storageInput(kc);
    if (!hidden) return;
    hidden.value = value;
    renderCapture(kc);
    if (markDirty) {
      setPending(kc, true);
      S.markDirty();
    }
  }

  function setManualOpen(kc, open) {
    var btn = kc.querySelector ? kc.querySelector('.key-manual-toggle') : null;
    var manual = kc.querySelector ? kc.querySelector('.key-manual-input') : null;
    if (open) {
      stopListening(kc);
      kc.classList.add('manual-open');
      if (btn) btn.textContent = 'Done';
      setStatus(kc, 'AHK syntax');
      if (manual) {
        var hidden = storageInput(kc);
        manual.value = hidden ? hidden.value : '';
        manual.focus();
        manual.select();
      }
    } else {
      kc.classList.remove('manual-open');
      if (btn) btn.textContent = 'AHK';
      setStatus(kc, normalStatus(kc));
    }
  }

  function beginListening(kc) {
    if (kc.classList.contains('manual-open')) setManualOpen(kc, false);
    kc.classList.add('listening');
    setStatus(kc, 'press shortcut');
    if (kc.focus) kc.focus();
  }

  function load(data) {
    if (data && data.hotkeys) {
      S.setVal('hkMain', data.hotkeys.main);
      S.setVal('hkReload', data.hotkeys.reload);
      S.setVal('hkCloseWindows', data.hotkeys.closeWindows);
      S.setVal('hkSuspend', data.hotkeys.suspend);
    }
    document.querySelectorAll('.key-capture').forEach(function(kc) {
      setPending(kc, false);
      renderCapture(kc);
    });
  }

  function save() {
    return { hotkeys: { main: S.getVal('hkMain'), reload: S.getVal('hkReload'), closeWindows: S.getVal('hkCloseWindows'), suspend: S.getVal('hkSuspend') } };
  }

  function wireKeyCaptures() {
    document.querySelectorAll('.key-capture').forEach(function(kc) {
      var manualBtn = kc.querySelector ? kc.querySelector('.key-manual-toggle') : null;
      var manualInput = kc.querySelector ? kc.querySelector('.key-manual-input') : null;

      kc.addEventListener('click', function(evt) {
        var target = evt && evt.target;
        if (target === manualBtn || target === manualInput) return;
        beginListening(kc);
      });

      kc.addEventListener('keydown', function(evt) {
        if (!kc.classList.contains('listening')) {
          if (evt.key === 'Enter' || evt.key === ' ') {
            evt.preventDefault();
            beginListening(kc);
          }
          return;
        }
        evt.preventDefault();
        if (evt.stopPropagation) evt.stopPropagation();
        if (evt.key === 'Escape') {
          stopListening(kc);
          return;
        }
        if ((evt.key === 'Backspace' || evt.key === 'Delete') && !evt.ctrlKey && !evt.altKey && !evt.shiftKey && !evt.metaKey) {
          setRawValue(kc, '', true);
          stopListening(kc);
          return;
        }
        var hidden = storageInput(kc);
        var next = eventToAhk(evt, hidden ? hidden.value : '');
        if (!next) return;
        setRawValue(kc, next, true);
        stopListening(kc);
      });

      kc.addEventListener('blur', function() {
        if (kc.classList.contains('listening')) stopListening(kc);
      });

      if (manualBtn) {
        manualBtn.addEventListener('click', function(evt) {
          if (evt && evt.stopPropagation) evt.stopPropagation();
          setManualOpen(kc, !kc.classList.contains('manual-open'));
        });
      }
      if (manualInput) {
        manualInput.addEventListener('click', function(evt) {
          if (evt && evt.stopPropagation) evt.stopPropagation();
        });
        manualInput.addEventListener('input', function() {
          setRawValue(kc, manualInput.value, true);
        });
        manualInput.addEventListener('keydown', function(evt) {
          if (evt.key === 'Enter') {
            evt.preventDefault();
            setManualOpen(kc, false);
            if (kc.focus) kc.focus();
          }
        });
      }
      renderCapture(kc);
    });
  }

  if (typeof document !== 'undefined') {
    document.addEventListener('DOMContentLoaded', function() {
      S.wireDirty('sec-hotkeys', S.markDirty);
      wireKeyCaptures();
    });
  }

  S.registerSection(sectionName, { load: load, save: save, formatForDisplay: formatForDisplay, eventToAhk: eventToAhk });
})();
