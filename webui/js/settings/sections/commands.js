// commands.js — Commands settings section (master-detail)
(function() {
  var sectionName = 'commands';
  var _commands = [];

  function load(data) {
    _commands = (data && data.commands) ? data.commands : [];
    renderList();
    if (_commands.length > 0) selectCommand(0);
  }

  function renderList() {
    var list = document.getElementById('commandsListBody');
    if (!list) return;
    list.innerHTML = '';
    _commands.forEach(function(cmd, idx) {
      var item = document.createElement('div');
      item.className = 'command-item' + (idx === 0 ? ' active' : '');
      item.dataset.index = idx;
      item.innerHTML = '<span class="drag-handle">⋮⋮</span><div style="flex:1;"><strong>' + escHtml(cmd.commandName || cmd.menuText || 'Unnamed') + '</strong><div class="tag">' + escHtml((cmd.tags || []).join(', ') || 'no tag') + '</div></div>' +
        '<div class="order-arrows"><button class="btn-sm" style="font-size:10px;padding:1px 4px;">↑</button><button class="btn-sm" style="font-size:10px;padding:1px 4px;">↓</button></div>';
      item.addEventListener('click', function(e) {
        if (e.target.closest('.order-arrows')) return;
        list.querySelectorAll('.command-item').forEach(function(i) { i.classList.remove('active'); });
        this.classList.add('active');
        selectCommand(parseInt(this.dataset.index));
      });
      // Arrow buttons
      item.querySelector('.order-arrows').addEventListener('click', function(e) {
        e.stopPropagation();
        var isUp = e.target.textContent.trim() === '↑';
        var newIdx = isUp ? idx - 1 : idx + 1;
        if (newIdx >= 0 && newIdx < _commands.length) {
          var tmp = _commands[idx]; _commands[idx] = _commands[newIdx]; _commands[newIdx] = tmp;
          renderList(); selectCommand(newIdx); mark();
        }
      });
      list.appendChild(item);
    });
  }

  function selectCommand(idx) {
    if (idx < 0 || idx >= _commands.length) return;
    var cmd = _commands[idx];
    var detail = document.getElementById('cmdDetail');
    if (!detail) return;
    detail.style.display = '';
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
  }

  function createTagBadge(text) {
    var span = document.createElement('span'); span.className = 'badge';
    span.innerHTML = escHtml(text) + ' <span class="remove">×</span>';
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
    var detail = document.getElementById('cmdDetail');
    return {
      commands: _commands,
      submenuOrder: [] // populated from badge list if present
    };
  }

  function addCommand() {
    _commands.push({ commandName: 'New Command', menuText: 'New Command', APIModels: '', pasteMode: 'chat', stream: false, isFIM: false, showInputBox: false, userMessage: '', tags: [] });
    renderList(); selectCommand(_commands.length - 1); mark();
  }

  function escHtml(s) { return String(s).replace(/&/g,'&').replace(/</g,'<').replace(/>/g,'>').replace(/"/g,'"'); }

  if (typeof document !== 'undefined') {
    document.addEventListener('DOMContentLoaded', function() {
      var addBtn = document.getElementById('addCommandBtn');
      if (addBtn) addBtn.addEventListener('click', addCommand);
      var addTagBtn = document.getElementById('addCmdTagBtn');
      if (addTagBtn) addTagBtn.addEventListener('click', addTag);
      // Wire detail form inputs
      var detail = document.getElementById('cmdDetail');
      if (detail) {
        detail.querySelectorAll('input, select, textarea').forEach(function(el) { el.addEventListener('change', mark); el.addEventListener('input', mark); });
        detail.querySelectorAll('.switch').forEach(function(sw) { sw.addEventListener('click', function() { sw.classList.toggle('on'); mark(); }); });
      }
    });
  }
  (function reg() { if (window.SettingsPanel) window.SettingsPanel.registerSection(sectionName, {load:load, save:save}); else setTimeout(reg, 50); })();
})();
