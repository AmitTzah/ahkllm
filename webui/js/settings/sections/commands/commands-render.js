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
    var keys = models ? Object.keys(models).sort() : [];
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
    d.getElementById('cmdDetailTitle').value = cmd.commandName || '';
    d.getElementById('cmdMenuLabel').value = cmd.menuText ? cmd.menuText.replace(/^&\S+\s*-\s*/, '') : '';
    var sm = (cmd.menuText||'').match(/&(.)/);
    d.getElementById('cmdMenuShortcut').value = sm ? sm[1] : '';
    d.getElementById('cmdDirectShortcut').value = cmd.directAccelerator ? cmd.directAccelerator.replace('&','') : '';
    var apiModelInput = d.getElementById('cmdApiModel');
    apiModelInput.value = cmd.APIModels || '';
    apiModelInput.addEventListener('change', function() {
      var thinkingSel = d.getElementById('cmdThinking');
      if (thinkingSel) {
        thinkingSel.innerHTML = _thinkingOptionsHtml(this.value);
        thinkingSel.value = '';
      }
    });
    d.getElementById('cmdPasteMode').value = cmd.pasteMode || 'chat';
    d.getElementById('cmdTemperature').value = cmd.temperature || '';
    d.getElementById('cmdUserMessage').value = cmd.userMessage || '';
    d.getElementById('cmdShowInputBox').classList.toggle('on', !!cmd.showInputBox);
    d.getElementById('cmdStream').classList.toggle('on', !!cmd.stream);
    d.getElementById('cmdFim').classList.toggle('on', !!cmd.isFIM);
    var thinkingSel = d.getElementById('cmdThinking');
    if (thinkingSel) {
      thinkingSel.innerHTML = _thinkingOptionsHtml(cmd.APIModels || '');
      thinkingSel.value = (cmd.thinking && cmd.thinking.type === 'enabled' && cmd.thinking.level) ? cmd.thinking.level : '';
    }
    d.getElementById('cmdMaxTokens').value = cmd.maxTokens || '';
    var td = d.getElementById('cmdTags'); if (td) { td.innerHTML = ''; (cmd.tags||[]).forEach(function(t){td.appendChild(_createTagBadge(t));}); }
    var lbl = d.getElementById('cmdSysMsgLabel');
    if (lbl) lbl.textContent = '\uD83D\uDCC4 ' + (cmd.systemMessageFile || (cmd.systemMessage ? '(inline)' : '(none)'));
    d.getElementById('cmdInputBoxDefault').value = cmd.inputBoxDefault || '';
    d.getElementById('cmdStop').value = Array.isArray(cmd.stop) ? cmd.stop.join(', ') : (typeof cmd.stop==='string'?cmd.stop:'');
    var mcw=cmd.maxContextWords; d.getElementById('cmdMaxContextWords').value = (mcw===undefined||mcw===null)?'':mcw;
    d.getElementById('cmdExpandNewlines').classList.toggle('on', !!cmd.expandNewlines);
    _updateMenuPreview();
    _wireDetail();
  };

  function _buildDetailHTML(cmd) {
    // Card-based layout matching the settings panel redesign
    return ''+
      // ── Title header ──
      '<div style="margin-bottom:16px;"><input type="text" id="cmdDetailTitle" placeholder="Command Title" style="border:1px solid transparent;background:transparent;font-weight:600;font-size:18px;padding:2px 4px;border-radius:4px;width:auto;"></div>'+

      // ── Identity ──
      '<div class="cmd-card">'+
        '<div class="cmd-card-header">Identity</div>'+
        '<div class="field"><label class="field-label">Menu Label <span class="tt" data-tip="The text shown in the backtick menu for this command.">?</span></label><input type="text" id="cmdMenuLabel" placeholder="Quick Ask" style="max-width:400px;"></div>'+
        '<div style="display:flex;gap:24px;">'+
          '<div class="field" style="margin-bottom:0;"><label class="field-label">Menu Shortcut <span class="tt" data-tip="Press backtick then this key. Use any letter or digit.">?</span></label><input type="text" id="cmdMenuShortcut" placeholder="e.g. 2" maxlength="1" style="width:70px;"></div>'+
          '<div class="field" style="margin-bottom:0;"><label class="field-label">Direct Shortcut <span class="tt" data-tip="For commands inside tagged submenus. Press backtick then this key to fire directly without navigating the submenu. Only useful with tags.">?</span></label><input type="text" id="cmdDirectShortcut" placeholder="e.g. 1" maxlength="1" style="width:70px;"></div>'+
        '</div>'+
        '<div class="field" style="margin-bottom:0;margin-top:8px;">'+
          '<label class="field-label">Tags <span class="tt" data-tip="Array of submenu names. Each tag creates a grouped submenu in the backtick menu.">?</span></label>'+
          '<div style="display:flex;gap:4px;flex-wrap:wrap;" id="cmdTags"></div>'+
          '<button class="btn-sm" id="addCmdTagBtn" style="margin-top:4px;">+ Add Tag</button>'+
        '</div>'+
      '</div>'+

      // ── Model Configuration ──
      '<div class="cmd-card">'+
        '<div class="cmd-card-header">Model Configuration</div>'+
        '<div class="field"><label class="field-label">API Model <span class="tt" data-tip="Select the model for this command from the available models, or Default for the chat default model.">?</span></label><select id="cmdApiModel" style="max-width:400px;">' + _modelOptionsHtml((cmd && cmd.APIModels) || '') + '</select></div>'+
        '<div class="grid-2">'+
          '<div class="field"><label class="field-label">Paste Mode <span class="tt" data-tip="chat = show in chat window. replace = overwrite selection. append = after cursor.">?</span></label><select id="cmdPasteMode"><option>chat</option><option>replace</option><option>append</option></select></div>'+
          '<div class="field"><label class="field-label">Temperature <span class="tt" data-tip="0-2. Higher = more creative. Leave empty for model default.">?</span></label><input type="text" id="cmdTemperature" placeholder="Model default"></div>'+
        '</div>'+
        '<div class="grid-2">'+
          '<div class="field"><label class="field-label">Max Tokens <span class="tt" data-tip="Maximum tokens in the response. Leave empty for API default. FIM commands should set explicitly (default: 4000).">?</span></label><input type="number" id="cmdMaxTokens" placeholder="Model default"></div>'+
          '<div class="field"><label class="field-label">Thinking <span class="tt" data-tip="Model Default sends no thinking config. Pick a level to enable thinking at that level.">?</span></label><select id="cmdThinking" style="flex:1;"></select></div>'+
        '</div>'+
      '</div>'+

      // ── Message Content ──
      '<div class="cmd-card">'+
        '<div class="cmd-card-header">Message Content</div>'+
        '<div class="field"><label class="field-label">User Message <span class="tt" data-tip="Supports {{selection}}, {{fullText}}, {{input}}. Use Enter for newlines &mdash; they are automatically converted.">?</span></label><textarea id="cmdUserMessage" placeholder="{{input}}&#10;&#10;{{selection}}"></textarea></div>'+
        '<div class="field" style="margin-bottom:0;">'+
          '<label class="field-label">System Message <span class="tt" data-tip="Instructions for the LLM. Supports {{selection}}, {{fullText}}, {{input}}. Edit to pick a file or write inline text.">?</span></label>'+
          '<div style="display:flex;align-items:center;gap:8px;">'+
            '<span id="cmdSysMsgLabel" style="font-size:12px;font-family:var(--font-mono);color:var(--text-secondary);">\uD83D\uDCC4 (none)</span>'+
            '<button class="btn-sm" id="cmdEditSysMsg">Edit</button>'+
          '</div>'+
          '<div class="field-hint">From app defaults (system-messages/). Create your own in AppData\\...\\system-messages\\</div>'+
        '</div>'+
      '</div>'+

      // ── Behavior ──
      '<div class="cmd-card">'+
        '<div class="cmd-card-header">Behavior</div>'+
        '<div class="toggle-row"><div><div class="lbl">Show Input Box <span class="tt" data-tip="Opens a text box before sending. User input becomes {{input}}. Ignored in FIM mode.">?</span></div><div class="cmd-behavior-desc">Display a text field for typing a prompt before sending.</div></div><div class="switch" id="cmdShowInputBox"><div class="knob"></div></div></div>'+
        '<div class="toggle-row"><div><div class="lbl">Stream Response <span class="tt" data-tip="Real-time token-by-token output. Requires pasteMode: chat.">?</span></div><div class="cmd-behavior-desc">Show output token-by-token as it\'s generated.</div></div><div class="switch" id="cmdStream"><div class="knob"></div></div></div>'+
        '<div class="toggle-row"><div><div class="lbl">FIM Mode <span class="tt" data-tip="Uses DeepSeek FIM beta endpoint. When on, prompt fields above are ignored.">?</span></div><div class="cmd-behavior-desc">Fill-in-the-middle. When on, prompt fields above are ignored.</div></div><div class="switch" id="cmdFim"><div class="knob"></div></div></div>'+
      '</div>'+

      // ── Advanced (collapsible) ──
      '<div class="cmd-card cmd-advanced-wrap" onclick="var b=this.querySelector(\'.cmd-advanced-body\');var c=this.querySelector(\'.cmd-chevron\');if(!b)return;b.style.display=b.style.display===\'none\'?\'block\':\'none\';if(c)c.classList.toggle(\'open\');">'+
        '<div class="cmd-advanced-toggle">'+
          '<span class="cmd-card-header" style="margin-bottom:0;">Advanced</span>'+
          '<span class="cmd-chevron"></span>'+
        '</div>'+
        '<div class="cmd-advanced-body" style="display:none;padding-top:12px;">'+
          '<div class="grid-2">'+
            '<div class="field"><label class="field-label">Input Box Default <span class="tt" data-tip="Text pre-filled in the input box. Only used when Show Input Box is on.">?</span></label><input type="text" id="cmdInputBoxDefault"></div>'+
            '<div class="field"><label class="field-label">Stop Sequences <span class="tt" data-tip="Array of strings that stop generation. e.g. \\n\\n. Leave empty for none.">?</span></label><input type="text" id="cmdStop" placeholder=\'e.g. ["\n\n\"]\'></div>'+
          '</div>'+
          '<div class="grid-2" style="margin-bottom:0;">'+
            '<div class="field"><label class="field-label">Max Context Words <span class="tt" data-tip="Max words of surrounding context sent to API. 0 = no limit. FIM Fill splits above/below cursor.">?</span></label><input type="number" id="cmdMaxContextWords" placeholder="0 = no limit"></div>'+
            '<div class="field" style="margin-bottom:0;">'+
              '<label class="toggle-row" style="padding-top:8px;"><span class="lbl">Expand Newlines <span class="tt" data-tip="Expands single newlines to double (standard LLM paragraph break). Useful for FIM and prose.">?</span></span><div class="switch" id="cmdExpandNewlines"><div class="knob"></div></div></label>'+
            '</div>'+
          '</div>'+
        '</div>'+
      '</div>'+

      // ── Delete ──
      '<div style="display:flex;gap:8px;margin-top:16px;"><button class="btn-ghost" id="cmdDeleteBtn">Delete Command</button></div>';
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

  function _wireDetail() {
    var d = document.getElementById('cmdDetail'); if (!d) return;
    d.querySelectorAll('input,select,textarea').forEach(function(el){el.addEventListener('change',C.mark);el.addEventListener('input',C.mark);});
    d.querySelectorAll('.switch').forEach(function(sw){sw.addEventListener('click',function(){sw.classList.toggle('on');C.mark();});});
    var ml=document.getElementById('cmdMenuLabel'),ms=document.getElementById('cmdMenuShortcut');
    if(ml)ml.addEventListener('input',_updateMenuPreview);
    if(ms)ms.addEventListener('input',_updateMenuPreview);
    var esm=document.getElementById('cmdEditSysMsg'); if(esm)esm.addEventListener('click',_openSysMsgModal);
    var atb=document.getElementById('addCmdTagBtn'); if(atb)atb.addEventListener('click',_addTag);
    var db=document.getElementById('cmdDeleteBtn'); if(db)db.addEventListener('click',function(){
      if(C.selectedIdx()<0||C.selectedIdx()>=C.commands().length)return;
      var idx = C.selectedIdx();
      C.commands().splice(idx,1);
      C.setSelectedIdx(-1);
      // Remove from all group orders
      var orders = C.groupOrders();
      Object.keys(orders).forEach(function(tag) {
        var arr = orders[tag];
        var pos = arr.indexOf(idx);
        if (pos >= 0) arr.splice(pos, 1);
        // Adjust indices > idx
        for (var k = 0; k < arr.length; k++) { if (arr[k] > idx) arr[k]--; }
      });
      C.ensureGroupOrders();
      C.renderList(0);
      if(C.commands().length>0)C.selectCommand(0);else C.showPlaceholder();
      C.mark();
    });
  }

  function _addTag() {
    var td=document.getElementById('cmdTags'); if(!td)return;
    var tn=prompt('Tag name (submenu name):'); if(!tn||!tn.trim())return;
    td.appendChild(_createTagBadge(tn.trim())); C.mark();
  }

  function _createTagBadge(tag) {
    var b=document.createElement('span'); b.className='badge'; b.textContent=tag;
    var x=document.createElement('span'); x.textContent='\u00D7'; x.style.cssText='cursor:pointer;margin-left:4px;';
    x.addEventListener('click',function(e){e.stopPropagation();b.remove();C.mark();});
    b.appendChild(x); return b;
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
    cmd.stream = d.getElementById('cmdStream').classList.contains('on');
    cmd.isFIM = d.getElementById('cmdFim').classList.contains('on');
    var thinkingLevel = d.getElementById('cmdThinking') ? d.getElementById('cmdThinking').value : '';
    cmd.thinking = thinkingLevel ? {type:'enabled', level:thinkingLevel} : '';
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
