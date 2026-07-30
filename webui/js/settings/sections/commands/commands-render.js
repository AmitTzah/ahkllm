// commands-render.js — grouped list rendering, detail panel, sync
(function() {
  var C = window.Cmds;

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
    var el = document.createElement('div');
    el.className = 'cmd-item' + (idx === C.selectedIdx() ? ' active' : '');
    el.dataset.index = idx;
    el.draggable = true;
    el.innerHTML = '<span class="drag-handle">&#9776;</span><span class="cmd-item-label"><span class="cmd-item-shortcut">' + (shortKey ? '&' + C.escHtml(shortKey) + ' ' : '') + '</span>' + C.escHtml(label.replace(/^&\S\s*-\s*/, '')) + '</span>' + badges;
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
    detail.innerHTML = _buildDetailHTML();
    var d = document;
    d.getElementById('cmdDetailTitle').value = cmd.commandName || '';
    d.getElementById('cmdMenuLabel').value = cmd.menuText ? cmd.menuText.replace(/^&\S+\s*-\s*/, '') : '';
    var sm = (cmd.menuText||'').match(/&(.)/);
    d.getElementById('cmdMenuShortcut').value = sm ? sm[1] : '';
    d.getElementById('cmdDirectShortcut').value = cmd.directAccelerator ? cmd.directAccelerator.replace('&','') : '';
    d.getElementById('cmdApiModel').value = cmd.APIModels || '';
    d.getElementById('cmdPasteMode').value = cmd.pasteMode || 'chat';
    d.getElementById('cmdTemperature').value = cmd.temperature || '';
    d.getElementById('cmdUserMessage').value = cmd.userMessage || '';
    d.getElementById('cmdShowInputBox').classList.toggle('on', !!cmd.showInputBox);
    d.getElementById('cmdStream').classList.toggle('on', !!cmd.stream);
    d.getElementById('cmdFim').classList.toggle('on', !!cmd.isFIM);
    d.getElementById('cmdThinkingType').value = (cmd.thinking&&cmd.thinking.type)||'disabled';
    d.getElementById('cmdThinkingLevel').value = (cmd.thinking&&cmd.thinking.level)||'';
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

  function _buildDetailHTML() {
    return '<div style="font-weight:600;font-size:14px;margin-bottom:16px;"><input type="text" id="cmdDetailTitle" placeholder="Command Title" style="border:1px solid transparent;background:transparent;font-weight:600;font-size:14px;padding:2px 4px;border-radius:4px;width:auto;"></div>'+
      '<div class="grid-2"><div class="field"><label class="field-label">Menu Label <span class="tt" data-tip="The text shown in the backtick menu.">?</span></label><input type="text" id="cmdMenuLabel" placeholder="Quick Ask"></div>'+
      '<div class="field"><label class="field-label">Menu Shortcut <span class="tt" data-tip="Press backtick then this key. Use any letter or digit.">?</span></label><input type="text" id="cmdMenuShortcut" placeholder="e.g. 2 or a" maxlength="1" style="width:80px;"><div style="font-size:11px;color:var(--text-tertiary);margin-top:2px;">Shows as: <code id="cmdMenuTextPreview"></code></div></div></div>'+
      '<div class="field"><label class="field-label">Direct Shortcut <span class="tt" data-tip="Press backtick then this key to fire directly without navigating submenus. Only useful with tags.">?</span></label><input type="text" id="cmdDirectShortcut" placeholder="e.g. 1 or a" maxlength="1" style="width:80px;"></div>'+
      '<div class="field"><label class="field-label">API Model <span class="tt" data-tip="Supports provider/model format (e.g. openai/gpt-4o) or direct name.">?</span></label><input type="text" id="cmdApiModel" placeholder="deepseek-v4-flash"></div>'+
      '<div class="grid-2"><div class="field"><label class="field-label">Paste Mode <span class="tt" data-tip="chat = show in chat window. replace = overwrite selection. append = after cursor.">?</span></label><select id="cmdPasteMode"><option>chat</option><option>replace</option><option>append</option></select></div>'+
      '<div class="field"><label class="field-label">Temperature <span class="tt" data-tip="0-2. Higher = more creative. Leave empty for model default.">?</span></label><input type="text" id="cmdTemperature" placeholder="Model default"></div></div>'+
      '<div class="field"><label class="field-label">User Message Template <span class="tt" data-tip="Supports {{selection}}, {{fullText}}, {{input}}. Use Enter for newlines.">?</span></label><textarea id="cmdUserMessage" placeholder="{{input}}&#10;&#10;{{selection}}"></textarea></div>'+
      '<div class="toggle-row"><div><div class="lbl">Show Input Box <span class="tt" data-tip="Opens a text box before sending. User input becomes {{input}}. Ignored in FIM mode.">?</span></div></div><div class="switch" id="cmdShowInputBox"><div class="knob"></div></div></div>'+
      '<div class="toggle-row"><div><div class="lbl">Stream Response <span class="tt" data-tip="Real-time token-by-token output. Requires pasteMode: chat.">?</span></div></div><div class="switch" id="cmdStream"><div class="knob"></div></div></div>'+
      '<div class="toggle-row"><div><div class="lbl">FIM Mode <span class="tt" data-tip="Uses DeepSeek FIM beta endpoint. When on, prompt fields above are ignored.">?</span></div></div><div class="switch" id="cmdFim"><div class="knob"></div></div></div>'+
      '<div class="field" style="margin-top:12px;"><label class="field-label">Thinking <span class="tt" data-tip="{ type: enabled|disabled, level?: low|medium|high|xhigh }. Enabled works across providers.">?</span></label><div class="field-row"><select id="cmdThinkingType" style="flex:1;"><option>disabled</option><option>enabled</option></select><select id="cmdThinkingLevel" style="flex:1;"><option value="">Default</option><option>low</option><option>medium</option><option>high</option></select></div></div>'+
      '<div class="field"><label class="field-label">Tags <span class="tt" data-tip="Array of submenu names. Each tag creates a grouped submenu in the backtick menu.">?</span></label><div style="display:flex;gap:4px;flex-wrap:wrap;" id="cmdTags"></div><button class="btn-sm" id="addCmdTagBtn" style="margin-top:4px;">+ Add Tag</button></div>'+
      '<div class="field"><label class="field-label">Max Tokens <span class="tt" data-tip="Maximum tokens in the response. Leave empty for API default.">?</span></label><input type="number" id="cmdMaxTokens" placeholder="Model default"></div>'+
      '<div class="field"><label class="field-label">System Message <span class="tt" data-tip="Instructions for the LLM. Edit to pick a file or write inline text.">?</span></label><div style="display:flex;align-items:center;gap:8px;"><span id="cmdSysMsgLabel" style="font-size:12px;font-family:var(--font-mono);color:var(--text-secondary);">\uD83D\uDCC4 (none)</span><button class="btn-sm" id="cmdEditSysMsg">Edit</button></div><div class="field-hint">From app defaults (system-messages/). Create your own in AppData\\...\\system-messages\\</div></div>'+
      '<div class="advanced-wrap" style="margin-top:16px;border:1px solid var(--border-main);border-radius:var(--radius-md);"><div class="advanced-toggle" onclick="this.parentElement.classList.toggle(\'open\')"><span>Advanced</span><span>&#8250;</span></div><div class="advanced-body">'+
      '<div class="grid-2"><div class="field"><label class="field-label">Input Box Default <span class="tt" data-tip="Text pre-filled in the input box. Only used when Show Input Box is on.">?</span></label><input type="text" id="cmdInputBoxDefault"></div>'+
      '<div class="field"><label class="field-label">Stop Sequences <span class="tt" data-tip="Array of strings that stop generation. e.g. \\n\\n. Leave empty for none.">?</span></label><input type="text" id="cmdStop" placeholder=\'e.g. ["\n\n\"]\'></div></div>'+
      '<div class="grid-2"><div class="field"><label class="field-label">Max Context Words <span class="tt" data-tip="Max words of surrounding context sent to API. 0 = no limit.">?</span></label><input type="number" id="cmdMaxContextWords" placeholder="0 = no limit"></div>'+
      '<div class="field"><label class="toggle-row"><span class="lbl">Expand Newlines <span class="tt" data-tip="Expands single newlines to double (standard LLM paragraph break).">?</span></span><div class="switch" id="cmdExpandNewlines"><div class="knob"></div></div></label></div></div>'+
      '</div></div>'+
      '<div style="display:flex;gap:8px;margin-top:16px;"><button class="btn-ghost" id="cmdDeleteBtn">Delete Command</button></div>';
  }

  function _openSysMsgModal() {
    var idx = C.selectedIdx();
    if (idx < 0) return;
    var modal = document.getElementById('sysMsgEditModal');
    if (!modal) return;
    var cmd = C.commands()[idx];
    var inlineRadio = modal.querySelector('input[name="sysMsgMode"][value="inline"]');
    var fileRadio = modal.querySelector('input[name="sysMsgMode"][value="file"]');
    var inlineSec = document.getElementById('smInlineSection');
    var fileSec = document.getElementById('smFileSection');
    if (cmd.systemMessageFile) {
      if (fileRadio) fileRadio.checked = true;
      if (inlineRadio) inlineRadio.checked = false;
      if (inlineSec) inlineSec.style.display = 'none';
      if (fileSec) fileSec.style.display = '';
      var fs = document.getElementById('smFileSelect');
      if (fs) fs.value = cmd.systemMessageFile;
    } else {
      if (inlineRadio) inlineRadio.checked = true;
      if (fileRadio) fileRadio.checked = false;
      if (inlineSec) inlineSec.style.display = '';
      if (fileSec) fileSec.style.display = 'none';
      var it = document.getElementById('smInlineText');
      if (it) it.value = cmd.systemMessage || '';
    }
    window._sysMsgTarget = { type: 'command', idx: idx };
    modal.classList.add('open');
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
    cmd.thinking = {type:d.getElementById('cmdThinkingType').value, level:d.getElementById('cmdThinkingLevel').value};
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
