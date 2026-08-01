// commands-actions.js — Mutating command actions (delete, tag management).
// Split out of commands-render.js so the renderer only renders.
(function() {
  var C = window.Cmds;

  C.createTagBadge = function(tag) {
    var b = document.createElement('span'); b.className = 'badge'; b.textContent = tag;
    var x = document.createElement('span'); x.textContent = '\u00D7'; x.style.cssText = 'cursor:pointer;margin-left:4px;';
    x.addEventListener('click', function(e) { e.stopPropagation(); b.remove(); C.mark(); });
    b.appendChild(x); return b;
  };

  C.addTagToSelected = function() {
    var td = document.getElementById('cmdTags'); if (!td) return;
    var tn = prompt('Tag name (submenu name):'); if (!tn || !tn.trim()) return;
    td.appendChild(C.createTagBadge(tn.trim())); C.mark();
  };

  C.deleteSelected = function() {
    if (C.selectedIdx() < 0 || C.selectedIdx() >= C.commands().length) return;
    var idx = C.selectedIdx();
    C.commands().splice(idx, 1);
    C.setSelectedIdx(-1);
    // Remove from all group orders and adjust indices above the deleted one.
    var orders = C.groupOrders();
    Object.keys(orders).forEach(function(tag) {
      var arr = orders[tag];
      var pos = arr.indexOf(idx);
      if (pos >= 0) arr.splice(pos, 1);
      for (var k = 0; k < arr.length; k++) { if (arr[k] > idx) arr[k]--; }
    });
    C.ensureGroupOrders();
    C.renderList(0);
    if (C.commands().length > 0) C.selectCommand(0); else C.showPlaceholder();
    C.mark();
  };
})();
