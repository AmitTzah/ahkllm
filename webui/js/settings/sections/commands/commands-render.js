// commands-render.js — grouped list rendering, detail panel, sync
(function() {
  var C = window.Cmds;

  // Resolve a command's effective model to a models-map key (full or bare name,
  // else the chat default model) so the Thinking dropdown can offer only the
  // levels that model actually supports.
  function _resolveModelKey(m) {
    var models = C.models();
    if (!m) m = C.defaultModel() || '';
    if (models && m) {
      if (models[m]) return m;
      var bare = m.indexOf('/') >= 0 ? m.split('/')[1] : m;
      var keys = Object.keys(models);
      for (var i = 0; i < keys.length; i++) {
        if (keys[i].split('/')[1] === bare) return keys[i];
      }
    }
    return m;
  }

  // <option> HTML for the Thinking dropdown: "Model Default" + the model's
  // supported levels, sorted least → most thinking.
  function _thinkingOptionsHtml(modelKey) {
    var rl = window.ReasoningLevels;
    if (!rl) return '<option value="">Model Default</option>';
    return rl.buildOptionsHtml(C.models(), _resolveModelKey(modelKey));
  }

  // <option> HTML for the API Model dropdown: every available model ID (sorted)
  // plus an empty "Default" entry. If the command's current value isn't among
  // the known models (e.g. a custom or comma-separated value), it is prepended
  // so it stays visible and isn't silently dropped on save.
  function _modelOptionsHtml(current) {
    var models = C.models();
    var keys = models ? Object.keys(models).sort(function(a, b) {
      if (a === 'openrouter/free') return b === 'openrouter/free' ? 0 : -1;
      if (b === 'openrouter/free') return 1;
      return a < b ? -1 : a > b ? 1 : 0;
    }) : [];
    // "Default" is selected whenever the command has no explicit model.
    var html = '<option value=""' + (current ? '' : ' selected') + '>Default</option>';
    var all = keys.slice();
    if (current && all.indexOf(current) < 0) all.unshift(current);
    for (var i = 0; i < all.length; i++) {
      var k = all[i];
      html += '<option value="' + C.escHtml(k) + '"' + (k === current ? ' selected' : '') + '>' + C.escHtml(k) + '</option>';
    }
    return html;
  }

  function _buildListItem(cmd, idx, groupTag) {
    var label = cmd.menuText || cmd.commandName || 'Unnamed';
    var shortcut = label.match(/&(.)/);
    var shortKey = shortcut ? shortcut[1] : '';
    var isDirect = !!cmd.directAccelerator;
    var isMainMenu = groupTag === '__main__';
    // Badge: only show direct badge in Main Menu
    var badges = '';
    if (isMainMenu && isDirect) {
      var dk = cmd.directAccelerator.replace('&','');
      badges = '<span class="cmd-badges"><span class="cmd-badge direct-badge" title="Direct: &' + C.escHtml(dk) + '">DIR &' + C.escHtml(dk) + '</span></span>';
    }
    // When a direct shortcut is set AND we're in the Main Menu group (where
    // the direct badge is shown), suppress the menu shortcut to avoid showing
    // two shortcut indicators. In submenu groups, the menu shortcut still
    // appears since the direct badge is only rendered in Main Menu.
    var displayShortcut = (isDirect && isMainMenu) ? '' : (shortKey ? '&' + C.escHtml(shortKey) + ' ' : '');
    var el = document.createElement('div');
    el.className = 'cmd-item' + (idx === C.selectedIdx() ? ' active' : '');
    el.dataset.index = idx;
    el.draggable = true;
    el.innerHTML = '<span class="drag-handle">&#9776;</span><span class="cmd-item-label"><span class="cmd-item-shortcut">' + displayShortcut + '</span>' + C.escHtml(label.replace(/^&\S\s*(-\s*)?/, '')) + '</span>' + badges;
    return el;
  }

  C.renderList = function(activeIdx) {
    var list = document.getElementById('commandsListBody');
    if (!list) return;
    list.innerHTML = '';
    var orders = C.groupOrders();
    var so = C.submenuOrder();
    var seen = {};
    var orderedTags = ['__main__'];
    so.forEach(function(t) { if (orders[t]) { orderedTags.push(t); seen[t] = true; } });
    Object.keys(orders).forEach(function(t) { if (!seen[t] && t !== '__main__') orderedTags.push(t); });

    orderedTags.forEach(function(tag) {
      var indices = orders[tag] || [];
      if (!indices.length) return;
      var headerLabel = tag === '__main__' ? 'Main Menu' : tag;
      var groupEl = document.createElement('div');
      groupEl.className = 'cmd-group';
      groupEl.dataset.tag = tag === '__main__' ? '' : tag;
      groupEl.innerHTML = '<div class="cmd-group-header" draggable="true"><span class="drag-handle">&#9776;</span><span>' + C.escHtml(headerLabel) + '</span></div><div class="cmd-group-body" data-group="' + tag + '"></div>';
      var body = groupEl.querySelector('.cmd-group-body');
      indices.forEach(function(idx) {
        if (idx >= 0 && idx < C.commands().length) {
          var cmd = C.commands()[idx];
          body.appendChild(_buildListItem(cmd, idx, tag));
        }
      });
      list.appendChild(groupEl);
    });

    if (C._wireItemDrag) C._wireItemDrag(list);
    if (C._wireGroupDrag) C._wireGroupDrag(list);
    list.querySelectorAll('.cmd-item').forEach(function(item) {
      item.addEventListener('click', function(e) {
        C.selectCommand(parseInt(this.dataset.index));
      });
    });
  };

  C.showPlaceholder = function() {
    var detail = document.getElementById('cmdDetail');
    if (detail) detail.style.display = 'none';
  };

  // --- Detail field helpers ---

  function _setField(id, value) {
    var el = document.getElementById(id);
    if (el) el.value = value;
  }

  function _setToggle(id, on) {
    var el = document.getElementById(id);
    if (el) el.classList.toggle('on', !!on);
  }

  C.selectCommand = function(idx) {
    if (idx < 0 || idx >= C.commands().length) return;
    C.syncDetail();
    C.setSelectedIdx(idx);
    C.renderList(idx);
    var cmd = C.commands()[idx], detail = document.getElementById('cmdDetail');
    if (!detail) return;
    detail.style.display = '';
    detail.innerHTML = _buildDetailHTML(cmd);
    var d = document;
    _setField('cmdDetailTitle', cmd.commandName || '');
    _setField('cmdMenuLabel', cmd.menuText ? cmd.menuText.replace(/^&\S+\s*-\s*/, '') : '');
    var sm = (cmd.menuText||'').match(/&(.)/);
    _setField('cmdMenuShortcut', sm ? sm[1] : '');
    _setField('cmdDirectShortcut', cmd.directAccelerator ? cmd.directAccelerator.replace('&','') : '');
    _setField('cmdApiModel', cmd.APIModels || '');
    var apiModelInput = d.getElementById('cmdApiModel');
    apiModelInput.addEventListener('change', function() {
      var thinkingSel = d.getElementById('cmdThinking');
      if (thinkingSel) {
        // Keep the user's chosen level across a model change. If the new
        // model doesn't support it, the select naturally falls back to the
        // empty "Model Default" option.
        var prevLevel = thinkingSel.value;
        thinkingSel.innerHTML = _thinkingOptionsHtml(this.value);
        thinkingSel.value = prevLevel;
      }
    });
    _setField('cmdPasteMode', cmd.pasteMode || 'chat');
    _setField('cmdTemperature', cmd.temperature || '');
    _setField('cmdUserMessage', cmd.userMessage || '');
    _setToggle('cmdShowInputBox', !!cmd.showInputBox);
    _setToggle('cmdIncludeImageContext', !!cmd.includeImageContext);
    _setToggle('cmdStream', !!cmd.stream);
    _setToggle('cmdFim', !!cmd.isFIM);
    var thinkingSel = d.getElementById('cmdThinking');
    if (thinkingSel) {
      thinkingSel.innerHTML = _thinkingOptionsHtml(cmd.APIModels || '');
      // The dropdown stores the effective level. "none" is an explicit off
      // choice even though the persisted command shape uses type:"disabled".
      thinkingSel.value = (cmd.thinking && cmd.thinking.level) ? cmd.thinking.level : '';
    }
    _setField('cmdMaxTokens', cmd.maxTokens || '');
    var td = d.getElementById('cmdTags'); if (td) { td.innerHTML = ''; (cmd.tags||[]).forEach(function(t){td.appendChild(C.createTagBadge(t));}); }
    var lbl = d.getElementById('cmdSysMsgLabel');
    if (lbl) lbl.textContent = '\uD83D\uDCC4 ' + (cmd.systemMessageFile || (cmd.systemMessage ? '(inline)' : '(none)'));
    _setField('cmdInputBoxDefault', cmd.inputBoxDefault || '');
    _setField('cmdStop', Array.isArray(cmd.stop) ? cmd.stop.join(', ') : (typeof cmd.stop==='string'?cmd.stop:''));
    var mcw = cmd.maxContextWords; _setField('cmdMaxContextWords', (mcw === undefined || mcw === null) ? '' : mcw);
    _setToggle('cmdExpandNewlines', !!cmd.expandNewlines);
    _updateMenuPreview();
    _wireDetail();
  };

  // --- Detail panel HTML (one builder per card) ---

  function _titleHeaderHTML() {
    return '<div class="settings-mb-16"><input class="settings-title-input-lg" type="text" id="cmdDetailTitle" placeholder="Command Title"></div>';
  }

  function _identityCardHTML() {
    return '<div class="cmd-card">' +
      '<div class="cmd-card-header">Identity</div>' +
      '<div class="field"><label class="field-label">Menu Label <span class="tt" data-tip="The text shown in the backtick menu for this command.">?</span></label><input class="settings-max-w-400" type="text" id="cmdMenuLabel" placeholder="Quick Ask"></div>' +
      '<div class="settings-flex-row-24">' +
        '<div class="field settings-mb-0"><label class="field-label">Menu Shortcut <span class="tt" data-tip="Press backtick then this key. Use any letter or digit.">?</span></label><input class="settings-w-70" type="text" id="cmdMenuShortcut" placeholder="e.g. 2" maxlength="1"></div>' +
        '<div class="field settings-mb-0"><label class="field-label">Direct Shortcut <span class="tt" data-tip="For commands inside tagged submenus. Press backtick then this key to fire directly without navigating the submenu. Only useful with tags.">?</span></label><input class="settings-w-70" type="text" id="cmdDirectShortcut" placeholder="e.g. 1" maxlength="1"></div>' +
      '</div>' +
      '<div class="field settings-mb-0 settings-mt-8">' +
        '<label class="field-label">Tags <span class="tt" data-tip="Array of submenu names. Each tag creates a grouped submenu in the backtick menu.">?</span></label>' +
        '<div class="settings-tag-list" id="cmdTags"></div>' +
        '<button class="btn-sm settings-mt-4" id="addCmdTagBtn">+ Add Tag</button>' +
      '</div>' +
    '</div>';
  }

  function _modelCardHTML(cmd) {
    return '<div class="cmd-card">' +
      '<div class="cmd-card-header">Model Configuration</div>' +
      '<div class="field"><label class="field-label">API Model <span class="tt" data-tip="Select the model for this command from the available models, or Default for the chat default model.">?</span></label><select class="settings-max-w-400" id="cmdApiModel">' + _modelOptionsHtml((cmd && cmd.APIModels) || '') + '</select></div>' +
      '<div class="grid-2">' +
        '<div class="field"><label class="field-label">Paste Mode <span class="tt" data-tip="chat = show in chat window. replace = overwrite selection. append = after cursor.">?</span></label><select id="cmdPasteMode"><option>chat</option><option>replace</option><option>append</option></select></div>' +
        '<div class="field"><label class="field-label">Temperature <span class="tt" data-tip="0-2. Higher = more creative. Leave empty for model default.">?</span></label><input type="text" id="cmdTemperature" placeholder="Model default"></div>' +
      '</div>' +
      '<div class="grid-2">' +
        '<div class="field"><label class="field-label">Max Tokens <span class="tt" data-tip="Maximum tokens in the response. Leave empty for API default. FIM commands should set explicitly (default: 4000).">?</span></label><input type="number" id="cmdMaxTokens" placeholder="Model default"></div>' +
        '<div class="field"><label class="field-label">Thinking <span class="tt" data-tip="Model Default sends no thinking config. Pick None to explicitly disable thinking when supported, or choose a level to enable it.">?</span></label><select class="settings-flex-1" id="cmdThinking"></select></div>' +
      '</div>' +
    '</div>';
  }

  function _messageCardHTML() {
    return '<div class="cmd-card">' +
      '<div class="cmd-card-header">Message Content</div>' +
      '<div class="field"><label class="field-label">User Message <span class="tt" data-tip="Supports {{selection}}, {{fullText}}, {{input}}. Use Enter for newlines &mdash; they are automatically converted.">?</span></label><textarea id="cmdUserMessage" placeholder="{{input}}&#10;&#10;{{selection}}"></textarea></div>' +
      '<div class="field settings-mb-0">' +
        '<label class="field-label">System Message <span class="tt" data-tip="Instructions for the LLM. Supports {{selection}}, {{fullText}}, {{input}}. Edit to pick a file or write inline text.">?</span></label>' +
        '<div class="settings-flex-row-center">' +
          '<span class="settings-sysmsg-label" id="cmdSysMsgLabel">\uD83D\uDCC4 (none)</span>' +
          '<button class="btn-sm" id="cmdEditSysMsg">Edit</button>' +
        '</div>' +
        '<div class="field-hint">From app defaults (default-settings/system-messages/). Create your own in AppData\\...\\system-messages\\</div>' +
      '</div>' +
    '</div>';
  }

  function _behaviorCardHTML() {
    return '<div class="cmd-card">' +
      '<div class="cmd-card-header">Behavior</div>' +
      '<div class="toggle-row"><div><div class="lbl">Show Input Box <span class="tt" data-tip="Opens a text box before sending. User input becomes {{input}}. Ignored in FIM mode.">?</span></div><div class="cmd-behavior-desc">Display a text field for typing a prompt before sending.</div></div><div class="switch" id="cmdShowInputBox"><div class="knob"></div></div></div>' +
      '<div class="toggle-row"><div><div class="lbl">Attach Screenshot <span class="tt" data-tip="Lets you select a screen region when the command runs and attaches it to the chat message. Requires chat mode and a vision-capable model; cannot be used with FIM.">?</span></div><div class="cmd-behavior-desc">Select a screen region and attach it to the chat message.</div></div><div class="switch" id="cmdIncludeImageContext"><div class="knob"></div></div></div>' +
      '<div class="toggle-row"><div><div class="lbl">Stream Response <span class="tt" data-tip="Real-time token-by-token output. Requires pasteMode: chat.">?</span></div><div class="cmd-behavior-desc">Show output token-by-token as it\'s generated.</div></div><div class="switch" id="cmdStream"><div class="knob"></div></div></div>' +
      '<div class="toggle-row"><div><div class="lbl">FIM Mode <span class="tt" data-tip="Uses DeepSeek FIM beta endpoint. When on, prompt fields above are ignored.">?</span></div><div class="cmd-behavior-desc">Fill-in-the-middle. When on, prompt fields above are ignored.</div></div><div class="switch" id="cmdFim"><div class="knob"></div></div></div>' +
    '</div>';
  }

  function _advancedCardHTML() {
    return '<div class="cmd-card cmd-advanced-wrap">' +
      '<div class="cmd-advanced-toggle">' +
        '<span class="cmd-card-header settings-mb-0">Advanced</span>' +
        '<span class="cmd-chevron"></span>' +
      '</div>' +
      '<div style="display:none;" class="cmd-advanced-body settings-advanced-body">' +
        '<div class="grid-2">' +
          '<div class="field"><label class="field-label">Input Box Default <span class="tt" data-tip="Text pre-filled in the input box. Only used when Show Input Box is on.">?</span></label><input type="text" id="cmdInputBoxDefault"></div>' +
          '<div class="field"><label class="field-label">Stop Sequences <span class="tt" data-tip="Array of strings that stop generation. e.g. \\n\\n. Leave empty for none.">?</span></label><input type="text" id="cmdStop" placeholder=\'e.g. ["\n\n\"]\'></div>' +
        '</div>' +
        '<div class="grid-2 settings-mb-0">' +
          '<div class="field"><label class="field-label">Max Context Words <span class="tt" data-tip="Max words of surrounding context sent to API. 0 = no limit. FIM Fill splits above/below cursor.">?</span></label><input type="number" id="cmdMaxContextWords" placeholder="0 = no limit"></div>' +
          '<div class="field settings-mb-0">' +
            '<label class="toggle-row settings-pt-8"><span class="lbl">Expand Newlines <span class="tt" data-tip="Expands single newlines to double (standard LLM paragraph break). Useful for FIM and prose.">?</span></span><div class="switch" id="cmdExpandNewlines"><div class="knob"></div></div></label>' +
          '</div>' +
        '</div>' +
      '</div>' +
    '</div>';
  }

  function _deleteButtonHTML() {
    return '<div class="settings-delete-row"><button class="btn-ghost" id="cmdDeleteBtn">Delete Command</button></div>';
  }

  function _buildDetailHTML(cmd) {
    return _titleHeaderHTML() +
      _identityCardHTML() +
      _modelCardHTML(cmd) +
      _messageCardHTML() +
      _behaviorCardHTML() +
      _advancedCardHTML() +
      _deleteButtonHTML();
  }

  function _openSysMsgModal() {
    var idx = C.selectedIdx();
    if (idx < 0) return;
    var cmd = C.commands()[idx];
    if (!window.populateSysMsgModal) return;
    window._sysMsgTarget = { type: 'command', idx: idx };
    window.populateSysMsgModal({ systemMessageFile: cmd.systemMessageFile, systemMessage: cmd.systemMessage });
  }

  function _updateMenuPreview() {
    var p = document.getElementById('cmdMenuTextPreview'); if (!p) return;
    var l = document.getElementById('cmdMenuLabel'), s = document.getElementById('cmdMenuShortcut');
    p.textContent = s && s.value ? '&' + s.value + ' - ' + (l?l.value:'') : (l?l.value:'');
  }

  function _toggleAdvanced(advancedWrap) {
    var body = advancedWrap.querySelector('.cmd-advanced-body');
    if (!body) return;
    var isOpen = body.style.display !== 'none';
    body.style.display = isOpen ? 'none' : 'block';
    var chevron = advancedWrap.querySelector('.cmd-chevron');
    if (chevron) chevron.classList.toggle('open', !isOpen);
  }

  function _wireDetail() {
    var d = document.getElementById('cmdDetail'); if (!d) return;
    d.querySelectorAll('input,select,textarea').forEach(function(el){el.addEventListener('change',C.mark);el.addEventListener('input',C.mark);});
    d.querySelectorAll('.switch').forEach(function(sw){sw.addEventListener('click',function(){sw.classList.toggle('on');C.mark();});});
    var ml=document.getElementById('cmdMenuLabel'),ms=document.getElementById('cmdMenuShortcut');
    if(ml)ml.addEventListener('input',_updateMenuPreview);
    if(ms)ms.addEventListener('input',_updateMenuPreview);
    var esm=document.getElementById('cmdEditSysMsg'); if(esm)esm.addEventListener('click',_openSysMsgModal);
    var atb=document.getElementById('addCmdTagBtn'); if(atb)atb.addEventListener('click',C.addTagToSelected);
    var db=document.getElementById('cmdDeleteBtn'); if(db)db.addEventListener('click',C.deleteSelected);
    var aw=document.querySelector('.cmd-advanced-wrap');
    if(aw){
      // Toggle only from the header, not from clicks inside the body - the
      // old whole-wrap listener collapsed the card on the first click into a
      // field, making the Advanced inputs unusable (bug #27).
      var at=aw.querySelector('.cmd-advanced-toggle');
      if(at)at.addEventListener('click',function() { _toggleAdvanced(aw); });
    }
  }

  C.syncDetail = function() {
    var i=C.selectedIdx(); if(i<0||i>=C.commands().length)return;
    var cmd=C.commands()[i], d=document;
    cmd.commandName = d.getElementById('cmdDetailTitle').value;
    var lbl=d.getElementById('cmdMenuLabel').value, sc=d.getElementById('cmdMenuShortcut').value;
    cmd.menuText = sc ? '&' + sc + ' - ' + lbl : lbl;
    var ds=d.getElementById('cmdDirectShortcut').value; cmd.directAccelerator = ds ? '&'+ds : '';
    cmd.APIModels = d.getElementById('cmdApiModel').value;
    cmd.pasteMode = d.getElementById('cmdPasteMode').value;
    var t=d.getElementById('cmdTemperature').value; cmd.temperature = t===''?'':(isNaN(parseFloat(t))?'':parseFloat(t));
    cmd.userMessage = d.getElementById('cmdUserMessage').value;
    cmd.showInputBox = d.getElementById('cmdShowInputBox').classList.contains('on');
    cmd.includeImageContext = d.getElementById('cmdIncludeImageContext').classList.contains('on');
    cmd.stream = d.getElementById('cmdStream').classList.contains('on');
    cmd.isFIM = d.getElementById('cmdFim').classList.contains('on');
    var thinkingLevel = d.getElementById('cmdThinking') ? d.getElementById('cmdThinking').value : '';
    if (!thinkingLevel) cmd.thinking = '';
    else if (thinkingLevel === 'none') cmd.thinking = {type:'disabled', level:'none'};
    else cmd.thinking = {type:'enabled', level:thinkingLevel};
    var mt=d.getElementById('cmdMaxTokens').value; cmd.maxTokens = mt===''?'':(isNaN(parseInt(mt,10))?'':parseInt(mt,10));
    var tags=[]; d.querySelectorAll('#cmdTags .badge').forEach(function(b){tags.push(b.textContent.replace('\u00D7','').trim());});
    cmd.tags = tags;
    cmd.inputBoxDefault = d.getElementById('cmdInputBoxDefault').value;
    var sr=d.getElementById('cmdStop').value; cmd.stop = sr ? sr.split(',').map(function(s){return s.trim();}) : [];
    var mcw=d.getElementById('cmdMaxContextWords').value; cmd.maxContextWords = mcw===''?0:(isNaN(parseInt(mcw,10))?0:parseInt(mcw,10));
    cmd.expandNewlines = d.getElementById('cmdExpandNewlines').classList.contains('on');
    C.renderList(i);
  };
})();
