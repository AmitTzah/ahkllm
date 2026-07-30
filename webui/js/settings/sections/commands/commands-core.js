// commands-core.js — state, load, save, validate, helpers, registration
(function() {
  var _commands = [];
  var _selectedIdx = -1;
  var _submenuOrder = [];
  // Per-group independent ordering: { '__main__': [idx,...], 'TagName': [idx,...] }
  var _groupOrders = {};

  function _ensureGroupOrders() {
    _groupOrders['__main__'] = _groupOrders['__main__'] || [];
    _commands.forEach(function(cmd, i) {
      var tags = cmd.tags || [];
      var hasDirect = !!cmd.directAccelerator;
      // Always rebuild main: untagged AND direct commands
      if (tags.length === 0 || hasDirect) {
        if (_groupOrders['__main__'].indexOf(i) < 0) _groupOrders['__main__'].push(i);
      }
      // Tag groups: only tagged commands without direct go in tag groups
      if (!hasDirect) {
        tags.forEach(function(t) {
          var tag = t.trim();
          if (!tag) return;
          _groupOrders[tag] = _groupOrders[tag] || [];
          if (_groupOrders[tag].indexOf(i) < 0) _groupOrders[tag].push(i);
        });
      }
      // Also add to tag group for reference (dual display for direct commands with tags)
      if (hasDirect && tags.length > 0) {
        tags.forEach(function(t) {
          var tag = t.trim();
          if (!tag) return;
          _groupOrders[tag] = _groupOrders[tag] || [];
          if (_groupOrders[tag].indexOf(i) < 0) _groupOrders[tag].push(i);
        });
      }
    });
  }

  function load(data) {
    _commands = (data && data.commands) ? data.commands : [];
    _submenuOrder = (data && data.submenuOrder) ? data.submenuOrder : [];
    _selectedIdx = -1;
    _groupOrders = {};
    _ensureGroupOrders();
    window.Cmds.renderList(0);
    if (_commands.length > 0) window.Cmds.selectCommand(0);
    else window.Cmds.showPlaceholder();
  }

  function save() {
    window.Cmds.syncDetail();
    _ensureGroupOrders();
    // Rebuild _commands from group orders: main first, then tagged groups
    var newCmds = [];
    var seen = {};
    var main = _groupOrders['__main__'] || [];
    main.forEach(function(i) { if (!seen[i]) { newCmds.push(_commands[i]); seen[i] = true; } });
    var so = _submenuOrder.slice();
    Object.keys(_groupOrders).forEach(function(t) { if (t !== '__main__' && so.indexOf(t) < 0) so.push(t); });
    so.forEach(function(tag) {
      (_groupOrders[tag] || []).forEach(function(i) { if (!seen[i]) { newCmds.push(_commands[i]); seen[i] = true; } });
    });
    // Build old-position → new-position mapping
    var oldToNew = [];
    newCmds.forEach(function(cmd, newPos) {
      // cmd._oldIdx was set to the old _commands index during rebuild
      // but we didn't track it. Instead, find by object reference:
      for (var oldPos = 0; oldPos < _commands.length; oldPos++) {
        if (_commands[oldPos] === cmd) { oldToNew[oldPos] = newPos; break; }
      }
    });
    _commands = newCmds;
    // Remap _selectedIdx and remap _groupOrders indices using old→new mapping
    _selectedIdx = oldToNew[_selectedIdx] !== undefined ? oldToNew[_selectedIdx] : -1;
    var mappedOrders = {};
    Object.keys(_groupOrders).forEach(function(tag) {
      mappedOrders[tag] = [];
      _groupOrders[tag].forEach(function(oldIdx) {
        var newIdx = oldToNew[oldIdx];
        if (newIdx !== undefined) mappedOrders[tag].push(newIdx);
      });
    });
    _groupOrders = mappedOrders;
    // Re-render to update DOM data-index attributes with new indices
    window.Cmds.renderList(_selectedIdx >= 0 ? _selectedIdx : 0);
    return { commands: _commands, submenuOrder: _submenuOrder };
  }

  // Collect submenu tag accelerators. Returns { tagAccels: {...} }.
  function _collectTagAccels() {
    var tagAccels = {};  // accelerator char → { tag, firstCmdName }
    for (var i = 0; i < _commands.length; i++) {
      var tags = _commands[i].tags || [];
      for (var t = 0; t < tags.length; t++) {
        var tag = tags[t].trim();
        var tagM = tag.match(/^&(.)/);
        if (!tagM) continue;
        var tagKey = tagM[1].toLowerCase();
        if (!tagAccels[tagKey]) {
          tagAccels[tagKey] = { tag: tag, firstCmdName: _commands[i].commandName || 'Unnamed' };
        }
      }
    }
    return tagAccels;
  }

  function validate() {
    window.Cmds.syncDetail();
    var cs = (document.getElementById('chatShortcut') || {}).value || '';
    if (cs) cs = cs.toLowerCase();

    var tagAccels = _collectTagAccels();

    // Check chatShortcut against submenu tag accelerators
    if (cs && tagAccels[cs]) {
      return { valid: false, message: 'Chat Shortcut "' + cs.toUpperCase() + '" conflicts with submenu "' + tagAccels[cs].tag + '" (used by "' + tagAccels[cs].firstCmdName + '").' };
    }

    for (var i = 0; i < _commands.length; i++) {
      var ci = _commands[i];
      var msI = (ci.menuText || '').match(/&(.)/);
      var hasTagsI = ci.tags && ci.tags.length > 0;
      var msKey = msI ? msI[1].toLowerCase() : '';
      var directKey = ci.directAccelerator ? ci.directAccelerator.replace('&', '').toLowerCase() : '';

      // Check chatShortcut against command accelerators (existing logic)
      if (cs && ((!hasTagsI && msKey === cs) || (directKey === cs)))
        return { valid: false, message: 'Chat Shortcut "' + cs.toUpperCase() + '" conflicts with "' + (ci.commandName||'Unnamed') + '".', selectIdx: i };

      // Check directAccelerator / untagged menuText against submenu tag accelerators
      if (directKey && tagAccels[directKey])
        return { valid: false, message: 'Direct accelerator "&' + directKey.toUpperCase() + '" in "' + (ci.commandName||'Unnamed') + '" conflicts with submenu "' + tagAccels[directKey].tag + '".', selectIdx: i };
      if (!hasTagsI && msKey && tagAccels[msKey])
        return { valid: false, message: 'Accelerator "&' + msKey.toUpperCase() + '" in "' + (ci.commandName||'Unnamed') + '" conflicts with submenu "' + tagAccels[msKey].tag + '".', selectIdx: i };

      for (var j = i + 1; j < _commands.length; j++) {
        var cj = _commands[j];
        var msJ = (cj.menuText || '').match(/&(.)/);
        var hasTagsJ = cj.tags && cj.tags.length > 0;
        var msKeyJ = msJ ? msJ[1].toLowerCase() : '';
        var directKeyJ = cj.directAccelerator ? cj.directAccelerator.replace('&', '').toLowerCase() : '';
        if ((directKey && directKey === directKeyJ) ||
            (!hasTagsI && !hasTagsJ && msKey && msKey === msKeyJ) ||
            (directKey && !hasTagsJ && msKeyJ && directKey === msKeyJ) ||
            (!hasTagsI && msKey && directKeyJ && msKey === directKeyJ))
          return { valid: false, message: 'Shortcut "' + (directKey||msKey||'?').toUpperCase() + '" used by "' + (ci.commandName||'Unnamed') + '" and "' + (cj.commandName||'Unnamed') + '".', selectIdx: i };
      }
    }
    return { valid: true };
  }

  function mark() { if (window.SettingsPanel) window.SettingsPanel.markDirty(); }
  function escHtml(s) { return String(s).replace(/&/g,'&').replace(/</g,'<').replace(/>/g,'>').replace(/"/g,'"'); }

  function addCommand() {
    _commands.push({ commandName:'New Command', menuText:'New Command', APIModels:'', pasteMode:'chat', stream:false, isFIM:false, showInputBox:false, userMessage:'', tags:[] });
    var idx = _commands.length - 1;
    _groupOrders['__main__'].push(idx);
    window.Cmds.selectCommand(idx);
    mark();
  }

  window.Cmds = {
    commands: function() { return _commands; },
    setCommands: function(c) { _commands = c; },
    selectedIdx: function() { return _selectedIdx; },
    setSelectedIdx: function(i) { _selectedIdx = i; },
    submenuOrder: function() { return _submenuOrder; },
    setSubmenuOrder: function(o) { _submenuOrder = o; },
    groupOrders: function() { return _groupOrders; },
    setGroupOrders: function(g) { _groupOrders = g; },
    load: load, save: save, validate: validate,
    mark: mark, escHtml: escHtml, addCommand: addCommand,
    ensureGroupOrders: _ensureGroupOrders
  };

  if (typeof document !== 'undefined') {
    document.addEventListener('DOMContentLoaded', function() {
      var addBtn = document.getElementById('addCommandBtn');
      if (addBtn) addBtn.addEventListener('click', addCommand);
    });
  }

  (function reg() {
    if (window.SettingsPanel) window.SettingsPanel.registerSection('commands', {load:load, save:save, validate:validate, selectCommand:function(i){window.Cmds.selectCommand(i);}});
    else setTimeout(reg, 50);
  })();
})();
