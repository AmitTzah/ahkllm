// commands.js — Commands settings section (master-detail)
(function() {
  var sectionName = 'commands';
  var _commands = [];
  var _selectedIdx = -1;
  var _submenuOrder = [];

  function load(data) {
    _commands = (data && data.commands) ? data.commands : [];
    _submenuOrder = (data && data.submenuOrder) ? data.submenuOrder : [];
    renderList(0);
    renderSubmenuOrder();
    if (_commands.length > 0) selectCommand(0);
    else showPlaceholder();
  }

  function showPlaceholder() {
    var detail = document.getElementById('cmdDetail');
    if (!detail) return;
    detail.style.display = '';
    detail.innerHTML = '<div class="placeholder">Select a command or create a new one</div>';
  }

  function renderSubmenuOrder() {
    var container = document.getElementById('submenuOrderBadges');
    if (!container) return;
    container.innerHTML = '';
    if (!_submenuOrder.length) {
      container.innerHTML = '<span style="font-size:11px;color:var(--text-tertiary);">No submenus defined</span>';
      return;
    }
    _submenuOrder.forEach(function(tag) {
      var badge = document.createElement('span');
      badge.className = 'badge';
      badge.textContent = tag;
      container.appendChild(badge);
    });
  }

  function renderList(activeIdx) {
    if (activeIdx === undefined) activeIdx = _selectedIdx;
    var list = document.getElementById('commandsListBody');
    if (!list) return;
    list.innerHTML = '';
    _commands.forEach(function(cmd, idx) {
      var item = document.createElement('div');
      item.className = 'command-item' + (idx === activeIdx ? ' active' : '');
      item.dataset.index = idx;
      item.innerHTML = '<span class="drag-handle">\u22EE\u22EE</span><div style="flex:1;"><strong>' + escHtml(cmd.commandName || cmd.menuText || 'Unnamed') + '</strong><div class="tag">' + escHtml((cmd.tags || []).join(', ') || 'no tag') + '</div></div>' +
        '<div class="order-arrows"><button class="btn-sm" style="font-size:10px;padding:1px 4px;">\u2191</button><button class="btn-sm" style="font-size:10px;padding:1px 4px;">\u2193</button></div>';
      item.addEventListener('click', function(e) {
        if (e.target.closest('.order-arrows')) return;
        list.querySelectorAll('.command-item').forEach(function(i) { i.classList.remove('active'); });
        this.classList.add('active');
        selectCommand(parseInt(this.dataset.index));
      });
      // Arrow buttons
      item.querySelector('.order-arrows').addEventListener('click', function(e) {
        e.stopPropagation();
        var isUp = e.target.textContent.trim() === '\u2191';
        var newIdx = isUp ? idx - 1 : idx + 1;
        if (newIdx >= 0 && newIdx < _commands.length) {
          var tmp = _commands[idx]; _commands[idx] = _commands[newIdx]; _commands[newIdx] = tmp;
          renderList(newIdx); selectCommand(newIdx); mark();
        }
      });
      list.appendChild(item);
    });
  }

  function selectCommand(idx) {
    if (idx < 0 || idx >= _commands.length) return;
    // Sync previous selection before switching
    syncDetail();
    _selectedIdx = idx;
    renderList(idx);
    var cmd = _commands[idx];
    var detail = document.getElementById('cmdDetail');
    if (!detail) return;
    detail.style.display = '';
    // Rebuild the detail form template
    detail.innerHTML = buildDetailHTML();
    document.getElementById('cmdDetailTitle').value = cmd.commandName || '';
    document.getElementById('cmdMenuLabel').value = cmd.menuText ? cmd.menuText.replace(/^&\d+\s*-\s*/, '') : '';
    // Extract shortcut number from menuText
    var shortcutMatch = (cmd.menuText || '').match(/&(\d)/);
    var shortcutSel = document.getElementById('cmdMenuShortcut');
    if (shortcutSel) shortcutSel.value = shortcutMatch ? shortcutMatch[1] : '';
    document.getElementById('cmdDirectShortcut').value = cmd.directAccelerator ? cmd.directAccelerator.replace('&', '') : '';
    document.getElementById('cmdApiModel').value = cmd.APIModels || '';
    document.getElementById('cmdPasteMode').value = cmd.pasteMode || 'chat';
    document.getElementById('cmdTemperature').value = cmd.temperature || '';
    document.getElementById('cmdUserMessage').value = (cmd.userMessage || '').replace(/``n/g, '\n');
    document.getElementById('cmdShowInputBox').classList.toggle('on', !!cmd.showInputBox);
    document.getElementById('cmdStream').classList.toggle('on', !!cmd.stream);
    document.getElementById('cmdFim').classList.toggle('on', !!cmd.isFIM);
    document.getElementById('cmdThinkingType').value = (cmd.thinking && cmd.thinking.type) || 'disabled';
    document.getElementById('cmdThinkingLevel').value = (cmd.thinking && cmd.thinking.level) || '';
    document.getElementById('cmdMaxTokens').value = cmd.maxTokens || '';
    // Tags
    var tagsDiv = document.getElementById('cmdTags');
    if (tagsDiv) {
      tagsDiv.innerHTML = '';
      (cmd.tags || []).forEach(function(t) { tagsDiv.appendChild(createTagBadge(t)); });
    }
    // Advanced fields
    document.getElementById('cmdSystemMessage').value = cmd.systemMessage || '';
    document.getElementById('cmdSystemMessageFile').value = cmd.systemMessageFile || '';
    document.getElementById('cmdInputBoxDefault').value = cmd.inputBoxDefault || '';
    // stop: array ↔ comma-separated string
    var stopVal = '';
    if (Array.isArray(cmd.stop)) stopVal = cmd.stop.join(', ');
    else if (typeof cmd.stop === 'string') stopVal = cmd.stop;
    document.getElementById('cmdStop').value = stopVal;
    var mcw = cmd.maxContextWords;
    document.getElementById('cmdMaxContextWords').value = (mcw === undefined || mcw === null) ? '' : mcw;
    document.getElementById('cmdExpandNewlines').classList.toggle('on', !!cmd.expandNewlines);
    // Update menu text preview
    updateMenuPreview();
    // Wire everything
    wireDetail();
  }

  function buildDetailHTML() {
    return '<div style="font-weight:600;font-size:14px;margin-bottom:16px;"><input type="text" id="cmdDetailTitle" value="" style="border:1px solid transparent;background:transparent;font-weight:600;font-size:14px;padding:2px 4px;border-radius:4px;width:auto;" placeholder="Command Title"></div>' +
      '<div class="grid-2"><div class="field"><label class="field-label">Menu Label <span class="tt" data-tip="The text shown in the backtick menu for this command.">?</span></label><input type="text" id="cmdMenuLabel" placeholder="Quick Ask DeepSeek V4 Flash"></div>' +
      '<div class="field"><label class="field-label">Menu Shortcut <span class="tt" data-tip="Press backtick then this number to activate. Key 1 is reserved for chat window.">?</span></label><select id="cmdMenuShortcut"><option value="">None</option><option disabled>1 (reserved \u2014 Chat Window)</option><option>2</option><option>3</option><option>4</option><option>5</option><option>6</option><option>7</option><option>8</option><option>9</option></select><div style="font-size:11px;color:var(--text-tertiary);margin-top:2px;">Shows as: <code id="cmdMenuTextPreview" style="background:var(--bg-hover);padding:1px 3px;border-radius:2px;"></code></div></div></div>' +
      '<div class="field"><label class="field-label">Direct Shortcut <span class="tt" data-tip="For commands inside tagged submenus. Press backtick then this key to fire directly without navigating the submenu. Only useful with tags.">?</span></label><select id="cmdDirectShortcut"><option value="">None</option><option>1</option><option>2</option><option>3</option><option>4</option><option>5</option></select></div>' +
      '<div class="field"><label class="field-label">API Model <span class="tt" data-tip="Supports provider/model format (e.g. openai/gpt-4o) or direct name.">?</span></label><input type="text" id="cmdApiModel" placeholder="deepseek-v4-flash"></div>' +
      '<div class="grid-2"><div class="field"><label class="field-label">Paste Mode <span class="tt" data-tip="chat = show in chat window. replace = overwrite selection. append = after cursor.">?</span></label><select id="cmdPasteMode"><option>chat</option><option>replace</option><option>append</option></select></div>' +
      '<div class="field"><label class="field-label">Temperature <span class="tt" data-tip="0\u20132. Higher = more creative. Leave empty for model default.">?</span></label><input type="text" id="cmdTemperature" placeholder="Model default"></div></div>' +
      '<div class="field"><label class="field-label">User Message Template <span class="tt" data-tip="Supports {{selection}}, {{fullText}}, {{input}}. Use Enter for newlines \u2014 they are automatically converted.">?</span></label><textarea id="cmdUserMessage" placeholder="{{input}}&#10;&#10;{{selection}}"></textarea></div>' +
      '<div class="toggle-row"><div><div class="lbl">Show Input Box <span class="tt" data-tip="Opens a text box before sending. User input becomes {{input}} variable. Ignored in FIM mode.">?</span></div></div><div class="switch" id="cmdShowInputBox"><div class="knob"></div></div></div>' +
      '<div class="toggle-row"><div><div class="lbl">Stream Response <span class="tt" data-tip="Real-time token-by-token output. Requires pasteMode: chat.">?</span></div></div><div class="switch" id="cmdStream"><div class="knob"></div></div></div>' +
      '<div class="toggle-row"><div><div class="lbl">FIM Mode <span class="tt" data-tip="Uses DeepSeek FIM beta endpoint. When on, all prompt fields above are ignored. FIM Fill (replace) fills gap. FIM Continue (append) continues from cursor.">?</span></div></div><div class="switch" id="cmdFim"><div class="knob"></div></div></div>' +
      '<div class="field" style="margin-top:12px;"><label class="field-label">Thinking <span class="tt" data-tip="{ type: enabled|disabled, level?: low|medium|high|xhigh }. Enabled works across providers. Level defaults to medium.">?</span></label><div class="field-row"><select id="cmdThinkingType" style="flex:1;"><option>disabled</option><option>enabled</option></select><select id="cmdThinkingLevel" style="flex:1;"><option value="">Default level</option><option>low</option><option>medium</option><option>high</option></select></div></div>' +
      '<div class="field"><label class="field-label">Tags <span class="tt" data-tip="Array of submenu names. Each tag creates a grouped submenu in the backtick menu.">?</span></label><div style="display:flex;gap:4px;flex-wrap:wrap;" id="cmdTags"></div><button class="btn-sm" id="addCmdTagBtn" style="margin-top:4px;">+ Add Tag</button></div>' +
      '<div class="field"><label class="field-label">Max Tokens <span class="tt" data-tip="Maximum tokens in the response. Leave empty for API default. FIM commands should set explicitly (default: 4000).">?</span></label><input type="number" id="cmdMaxTokens" placeholder="Model default"></div>' +
      '<div class="advanced-wrap" style="margin-top:16px;border:1px solid var(--border-main);border-radius:var(--radius-md);"><div class="advanced-toggle" style="padding:10px 14px;display:flex;justify-content:space-between;background:var(--bg-main);cursor:pointer;font-weight:500;font-size:13px;" onclick="this.parentElement.classList.toggle(\'open\')"><span>Advanced</span><span style="color:var(--text-tertiary);">\u203A</span></div><div class="advanced-body" style="padding:14px;border-top:1px solid var(--border-main);">' +
      '<div class="grid-2"><div class="field"><label class="field-label">System Message <span class="tt" data-tip="Instructions for the LLM. Supports {{selection}}, {{fullText}}, {{input}}.">?</span></label><input type="text" id="cmdSystemMessage" placeholder="Optional system prompt"></div>' +
      '<div class="field"><label class="field-label">System Message File <span class="tt" data-tip="Path to .txt file with system prompt. Takes precedence over inline text above.">?</span></label><input type="text" id="cmdSystemMessageFile" placeholder="system-messages/my-prompt.txt"></div></div>' +
      '<div class="grid-2"><div class="field"><label class="field-label">Input Box Default <span class="tt" data-tip="Text pre-filled in the input box. Only used when Show Input Box is on.">?</span></label><input type="text" id="cmdInputBoxDefault" placeholder="Default input text"></div>' +
      '<div class="field"><label class="field-label">Stop Sequences <span class="tt" data-tip="Array of strings that stop generation. e.g. \n\n. Leave empty for none.">?</span></label><input type="text" id="cmdStop" placeholder=\'e.g. ["\n\n\"]\'></div></div>' +
      '<div class="grid-2"><div class="field"><label class="field-label">Max Context Words <span class="tt" data-tip="Max words of surrounding context sent to API. 0 = no limit. FIM Fill splits above/below cursor.">?</span></label><input type="number" id="cmdMaxContextWords" placeholder="0 = no limit"></div>' +
      '<div class="field"><label class="toggle-row" style="margin-top:8px;"><span class="lbl">Expand Newlines <span class="tt" data-tip="Expands single newlines to double (standard LLM paragraph break). Useful for FIM and prose.">?</span></span><div class="switch" id="cmdExpandNewlines"><div class="knob"></div></div></label></div></div>' +
      '</div></div>' +
      '<div style="display:flex; gap:8px; margin-top:16px;"><button class="btn-primary" id="cmdSaveBtn" style="font-size:13px;">Save Command</button><button class="btn-ghost" id="cmdDeleteBtn" style="font-size:13px;">Delete Command</button></div>';
  }

  function wireDetail() {
    var detail = document.getElementById('cmdDetail');
    if (!detail) return;
    detail.querySelectorAll('input, select, textarea').forEach(function(el) { el.addEventListener('change', mark); el.addEventListener('input', mark); });
    detail.querySelectorAll('.switch').forEach(function(sw) { sw.addEventListener('click', function() { sw.classList.toggle('on'); mark(); }); });
    // Wire Menu Label / Shortcut changes to update preview
    var menuLabel = document.getElementById('cmdMenuLabel');
    var menuShortcut = document.getElementById('cmdMenuShortcut');
    if (menuLabel) menuLabel.addEventListener('input', updateMenuPreview);
    if (menuShortcut) menuShortcut.addEventListener('change', updateMenuPreview);
    // Wire Add Tag button
    var addTagBtn = document.getElementById('addCmdTagBtn');
    if (addTagBtn) addTagBtn.addEventListener('click', addTag);
    // Wire Save button
    var saveBtn = document.getElementById('cmdSaveBtn');
    if (saveBtn) saveBtn.addEventListener('click', function() {
      syncDetail();
      renderList(_selectedIdx);
      if (window.SettingsPanel) window.SettingsPanel.saveSettings();
    });
    // Wire Delete button
    var deleteBtn = document.getElementById('cmdDeleteBtn');
    if (deleteBtn) deleteBtn.addEventListener('click', function() {
      if (_selectedIdx < 0 || _selectedIdx >= _commands.length) return;
      _commands.splice(_selectedIdx, 1);
      _selectedIdx = -1;
      renderList(0);
      if (_commands.length > 0) selectCommand(0);
      else showPlaceholder();
      mark();
    });
  }

  function updateMenuPreview() {
    var preview = document.getElementById('cmdMenuTextPreview');
    if (!preview) return;
    var label = document.getElementById('cmdMenuLabel');
    var shortcut = document.getElementById('cmdMenuShortcut');
    var labelVal = label ? label.value : '';
    var shortcutVal = shortcut ? shortcut.value : '';
    preview.textContent = shortcutVal ? '&' + shortcutVal + ' - ' + labelVal : labelVal;
  }

  function syncDetail() {
    if (_selectedIdx < 0 || _selectedIdx >= _commands.length) return;
    var cmd = _commands[_selectedIdx];
    cmd.commandName = document.getElementById('cmdDetailTitle').value;
    var label = document.getElementById('cmdMenuLabel').value;
    var shortcut = document.getElementById('cmdMenuShortcut').value;
    cmd.menuText = shortcut ? '&' + shortcut + ' - ' + label : label;
    var ds = document.getElementById('cmdDirectShortcut').value;
    cmd.directAccelerator = ds ? '&' + ds : '';
    cmd.APIModels = document.getElementById('cmdApiModel').value;
    cmd.pasteMode = document.getElementById('cmdPasteMode').value;
    var temp = document.getElementById('cmdTemperature').value;
    cmd.temperature = temp === '' ? '' : (isNaN(parseFloat(temp)) ? '' : parseFloat(temp));
    cmd.userMessage = document.getElementById('cmdUserMessage').value.replace(/\n/g, '``n');
    cmd.showInputBox = document.getElementById('cmdShowInputBox').classList.contains('on');
    cmd.stream = document.getElementById('cmdStream').classList.contains('on');
    cmd.isFIM = document.getElementById('cmdFim').classList.contains('on');
    cmd.thinking = { type: document.getElementById('cmdThinkingType').value, level: document.getElementById('cmdThinkingLevel').value };
    var mt = document.getElementById('cmdMaxTokens').value;
    cmd.maxTokens = mt === '' ? '' : (isNaN(parseInt(mt, 10)) ? '' : parseInt(mt, 10));
    var tags = [];
    document.querySelectorAll('#cmdTags .badge').forEach(function(b) { tags.push(b.textContent.replace('\u00D7', '').trim()); });
    cmd.tags = tags;
    // Advanced fields
    cmd.systemMessage = document.getElementById('cmdSystemMessage').value;
    cmd.systemMessageFile = document.getElementById('cmdSystemMessageFile').value;
    cmd.inputBoxDefault = document.getElementById('cmdInputBoxDefault').value;
    var stopRaw = document.getElementById('cmdStop').value.trim();
    if (stopRaw) {
      var stopParts = stopRaw.split(',').map(function(s) { return s.trim(); }).filter(function(s) { return s !== ''; });
      cmd.stop = stopParts;
    } else {
      cmd.stop = [];
    }
    var mcw = document.getElementById('cmdMaxContextWords').value;
    cmd.maxContextWords = mcw === '' ? 0 : (isNaN(parseInt(mcw, 10)) ? 0 : parseInt(mcw, 10));
    cmd.expandNewlines = document.getElementById('cmdExpandNewlines').classList.contains('on');
  }

  function createTagBadge(text) {
    var span = document.createElement('span'); span.className = 'badge';
    span.innerHTML = escHtml(text) + ' <span class="remove">\u00D7</span>';
    span.querySelector('.remove').addEventListener('click', function() { span.remove(); mark(); });
    return span;
  }

  function addTag() {
    var tagsDiv = document.getElementById('cmdTags'); if (!tagsDiv) return;
    var inp = document.createElement('input');
    inp.style.cssText = 'width:80px;border:1px solid var(--border-main);border-radius:4px;padding:2px 6px;font-size:11px;';
    inp.addEventListener('blur', function() {
      if (inp.value.trim()) tagsDiv.insertBefore(createTagBadge(inp.value.trim()), inp);
      inp.remove(); mark();
    });
    inp.addEventListener('keydown', function(e) { if (e.key === 'Enter') inp.blur(); });
    tagsDiv.appendChild(inp); inp.focus();
  }

  function mark() { if (window.SettingsPanel) window.SettingsPanel.markDirty(); }

  function save() {
    syncDetail();
    return {
      commands: _commands,
      submenuOrder: _submenuOrder
    };
  }

  function addCommand() {
    _commands.push({ commandName: 'New Command', menuText: 'New Command', APIModels: '', pasteMode: 'chat', stream: false, isFIM: false, showInputBox: false, userMessage: '', tags: [] });
    renderList(_commands.length - 1); selectCommand(_commands.length - 1); mark();
  }

  function escHtml(s) { return String(s).replace(/&/g,'\x26amp;').replace(/</g,'\x26lt;').replace(/>/g,'\x26gt;').replace(/"/g,'\x26quot;'); }

  if (typeof document !== 'undefined') {
    document.addEventListener('DOMContentLoaded', function() {
      var addBtn = document.getElementById('addCommandBtn');
      if (addBtn) addBtn.addEventListener('click', addCommand);
    });
  }
  (function reg() { if (window.SettingsPanel) window.SettingsPanel.registerSection(sectionName, {load:load, save:save}); else setTimeout(reg, 50); })();
})();
