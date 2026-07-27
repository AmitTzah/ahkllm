// menu-items.js — Menu Items settings section (Quick Access + Tray)
(function() {
  var sectionName = 'menu';
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
        var inp = document.createElement('input');
        inp.value = item[f] || ''; inp.addEventListener('input', function() { if (window.SettingsPanel) window.SettingsPanel.markDirty(); });
        td.appendChild(inp); tr.appendChild(td);
      });
      var tdAct = document.createElement('td'); tdAct.className = 'actions';
      var delBtn = document.createElement('button'); delBtn.className = 'btn-sm danger'; delBtn.textContent = '✕';
      delBtn.addEventListener('click', function() { tr.remove(); if (window.SettingsPanel) window.SettingsPanel.markDirty(); });
      tdAct.appendChild(delBtn); tr.appendChild(tdAct); tbody.appendChild(tr);
    });
  }
  function readTable(tbodyId, fields) {
    var tbody = document.getElementById(tbodyId); if (!tbody) return [];
    var result = [];
    tbody.querySelectorAll('tr').forEach(function(tr) {
      var item = {}; var inputs = tr.querySelectorAll('input');
      inputs.forEach(function(inp, i) { if (i < fields.length) item[fields[i]] = inp.value; });
      result.push(item);
    });
    return result;
  }
  function addRow(tbodyId, fields) {
    var tbody = document.getElementById(tbodyId); if (!tbody) return;
    var tr = document.createElement('tr');
    fields.forEach(function() {
      var td = document.createElement('td'); var inp = document.createElement('input');
      inp.addEventListener('input', function() { if (window.SettingsPanel) window.SettingsPanel.markDirty(); });
      td.appendChild(inp); tr.appendChild(td);
    });
    var tdAct = document.createElement('td'); tdAct.className = 'actions';
    var delBtn = document.createElement('button'); delBtn.className = 'btn-sm danger'; delBtn.textContent = '✕';
    delBtn.addEventListener('click', function() { tr.remove(); if (window.SettingsPanel) window.SettingsPanel.markDirty(); });
    tdAct.appendChild(delBtn); tr.appendChild(tdAct); tbody.appendChild(tr);
    if (window.SettingsPanel) window.SettingsPanel.markDirty();
  }
  function save() {
    return { menuItems: { quickAccess: readTable('qaTableBody', ['menuText', 'command']), tray: readTable('trayTableBody', ['menuText', 'action']) } };
  }
  function wire() {
    var addQA = document.getElementById('addQaRow'); if (addQA) addQA.addEventListener('click', function() { addRow('qaTableBody', ['menuText', 'command']); });
    var addTray = document.getElementById('addTrayRow'); if (addTray) addTray.addEventListener('click', function() { addRow('trayTableBody', ['menuText', 'action']); });
  }
  if (typeof document !== 'undefined') document.addEventListener('DOMContentLoaded', wire);
  (function reg() { if (window.SettingsPanel) window.SettingsPanel.registerSection(sectionName, {load:load, save:save}); else setTimeout(reg, 50); })();
})();
