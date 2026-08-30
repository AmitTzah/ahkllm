// menu-items.js — Menu Items settings section (Quick Access + Tray)
(function() {
  var sectionName = 'menu';
  var S = window.SettingsShared;
  function load(data) {
    if (!data || !data.menuItems) return;
    var mi = data.menuItems;
    renderTable('qaTableBody', mi.quickAccess || [], ['menuText', 'command']);
    renderTable('trayTableBody', mi.tray || [], ['menuText', 'action']);
  }
  function renderTable(tbodyId, items, fields) {
    var tbody = document.getElementById(tbodyId); if (!tbody) return;
    tbody.innerHTML = '';
    items.forEach(function(item) {
      var tr = document.createElement('tr');
      fields.forEach(function(f) {
        var td = document.createElement('td');
        if (f === 'action') {
          // Tray action: render a <select>
          var sel = document.createElement('select');
          sel.style.cssText = 'width:100%;border:1px solid transparent;border-radius:4px;padding:4px 8px;font-size:13px;background:transparent;';
          ['reload', 'exit'].forEach(function(v) {
            var opt = document.createElement('option');
            opt.value = v; opt.textContent = v;
            if (item[f] === v) opt.selected = true;
            sel.appendChild(opt);
          });
          sel.addEventListener('change', S.markDirty);
          td.appendChild(sel); tr.appendChild(td);
        } else {
          var inp = document.createElement('input');
          var rawValue = item[f] || '';
          if (tbodyId === 'trayTableBody' && f === 'menuText' && rawValue.indexOf('&') >= 0) {
            // AHK uses & inside menu labels to mark keyboard accelerators. Keep
            // that syntax in settings, but don't leak it into the editable UI.
            inp.value = rawValue.replace(/&(?=.)/g, '');
            inp._rawMenuText = rawValue;
            inp._displayMenuText = inp.value;
          } else {
            inp.value = rawValue;
          }
          inp.addEventListener('input', function() {
            inp._rawMenuText = undefined;
            inp._displayMenuText = undefined;
            S.markDirty();
          });
          td.appendChild(inp); tr.appendChild(td);
        }
      });
      var tdAct = document.createElement('td'); tdAct.className = 'actions';
      var delBtn = document.createElement('button'); delBtn.className = 'btn-sm danger'; delBtn.textContent = '✕';
      delBtn.addEventListener('click', function() { tr.remove(); S.markDirty(); });
      tdAct.appendChild(delBtn); tr.appendChild(tdAct); tbody.appendChild(tr);
    });
  }
  function readTable(tbodyId, fields) {
    var tbody = document.getElementById(tbodyId); if (!tbody) return [];
    var result = [];
    tbody.querySelectorAll('tr').forEach(function(tr) {
      var item = {};
      var inputs = tr.querySelectorAll('input, select');
      inputs.forEach(function(inp, i) {
        if (i >= fields.length) return;
        var value = inp.value;
        if (tbodyId === 'trayTableBody' && fields[i] === 'menuText' &&
            inp._rawMenuText !== undefined && value === inp._displayMenuText) {
          value = inp._rawMenuText;
        }
        item[fields[i]] = value;
      });
      result.push(item);
    });
    return result;
  }
  function addRow(tbodyId, fields) {
    var tbody = document.getElementById(tbodyId); if (!tbody) return;
    var tr = document.createElement('tr');
    fields.forEach(function(f) {
      var td = document.createElement('td');
      if (f === 'action') {
        var sel = document.createElement('select');
        sel.style.cssText = 'width:100%;border:1px solid transparent;border-radius:4px;padding:4px 8px;font-size:13px;background:transparent;';
        ['reload', 'exit'].forEach(function(v) { var opt = document.createElement('option'); opt.value = v; opt.textContent = v; sel.appendChild(opt); });
        sel.addEventListener('change', S.markDirty);
        td.appendChild(sel); tr.appendChild(td);
      } else {
        var inp = document.createElement('input');
        inp.addEventListener('input', S.markDirty);
        td.appendChild(inp); tr.appendChild(td);
      }
    });
    var tdAct = document.createElement('td'); tdAct.className = 'actions';
    var delBtn = document.createElement('button'); delBtn.className = 'btn-sm danger'; delBtn.textContent = '✕';
    delBtn.addEventListener('click', function() { tr.remove(); S.markDirty(); });
    tdAct.appendChild(delBtn); tr.appendChild(tdAct); tbody.appendChild(tr);
    S.markDirty();
  }
  function save() {
    var tray = readTable('trayTableBody', ['menuText', 'action']);
    // Bug #179: the tray menu is the app's only always-present close path, so
    // a saved tray config must always keep an Exit item - re-add the default
    // row if the user deleted every exit-action row (the backend also re-adds
    // an unconditional Exit item at rebuild time, so the app can always close).
    var hasExit = tray.some(function(item) { return item.action === 'exit'; });
    if (!hasExit) tray.push({ menuText: 'E&xit', action: 'exit' });
    return { menuItems: { quickAccess: readTable('qaTableBody', ['menuText', 'command']), tray: tray } };
  }
  function wire() {
    var addQA = document.getElementById('addQaRow'); if (addQA) addQA.addEventListener('click', function() { addRow('qaTableBody', ['menuText', 'command']); });
    var addTray = document.getElementById('addTrayRow'); if (addTray) addTray.addEventListener('click', function() { addRow('trayTableBody', ['menuText', 'action']); });
  }
  if (typeof document !== 'undefined') document.addEventListener('DOMContentLoaded', wire);
  S.registerSection(sectionName, {load: load, save: save});
})();
