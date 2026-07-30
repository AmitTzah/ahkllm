// commands-drag.js — custom drag-drop with solid ghost + FLIP animation
(function() {
  var C = window.Cmds;
  var _floatingGhost = null, _dragOffsetX = 0, _dragOffsetY = 0;

  function _onItemDragStart(e) {
    var item = e.currentTarget;
    e.dataTransfer.setData('text/item', item.dataset.index);
    e.dataTransfer.effectAllowed = 'move';
    var img = new Image();
    img.src = 'data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7';
    e.dataTransfer.setDragImage(img, 0, 0);
    _floatingGhost = item.cloneNode(true);
    _floatingGhost.style.position = 'fixed';
    _floatingGhost.style.pointerEvents = 'none';
    _floatingGhost.style.zIndex = '9999';
    _floatingGhost.style.opacity = '1';
    _floatingGhost.style.width = item.offsetWidth + 'px';
    _floatingGhost.style.boxShadow = '0 5px 15px rgba(0,0,0,0.2)';
    _floatingGhost.style.backgroundColor = getComputedStyle(item).backgroundColor || 'var(--bg-panel)';
    _floatingGhost.classList.remove('active','is-dragging','drag-over','drop-above');
    var rect = item.getBoundingClientRect();
    _dragOffsetX = e.clientX - rect.left;
    _dragOffsetY = e.clientY - rect.top;
    _floatingGhost.style.left = (e.clientX - _dragOffsetX) + 'px';
    _floatingGhost.style.top = (e.clientY - _dragOffsetY) + 'px';
    document.body.appendChild(_floatingGhost);
    setTimeout(function() { item.style.visibility = 'hidden'; item.classList.add('is-dragging'); }, 0);
  }

  function _onItemDrag(e) {
    if (_floatingGhost && e.clientX !== 0 && e.clientY !== 0) {
      _floatingGhost.style.left = (e.clientX - _dragOffsetX) + 'px';
      _floatingGhost.style.top = (e.clientY - _dragOffsetY) + 'px';
    }
  }

  function _onItemDragEnd(e) {
    if (_floatingGhost) { _floatingGhost.remove(); _floatingGhost = null; }
    var item = e.currentTarget;
    item.style.visibility = '';
    item.classList.remove('is-dragging');
    document.querySelectorAll('.cmd-item.is-dragging').forEach(function(el) { el.style.visibility = ''; el.classList.remove('is-dragging'); });
    _syncGroupOrderFromDOM();
    C.mark();
  }

  function _onGroupBodyDragOver(e, body) {
    e.preventDefault();
    var draggingItem = body.querySelector('.is-dragging');
    if (!draggingItem) return;
    var siblings = [];
    body.querySelectorAll('.cmd-item:not(.is-dragging)').forEach(function(s) { siblings.push(s); });
    var nextSibling = null;
    for (var i = 0; i < siblings.length; i++) {
      var box = siblings[i].getBoundingClientRect();
      if (e.clientY - box.top - box.height / 2 < 0) { nextSibling = siblings[i]; break; }
    }
    if (nextSibling !== (draggingItem.nextElementSibling || null)) {
      var oldPositions = new Map();
      body.querySelectorAll('.cmd-item').forEach(function(child) { oldPositions.set(child, child.getBoundingClientRect()); });
      body.insertBefore(draggingItem, nextSibling);
      body.querySelectorAll('.cmd-item').forEach(function(child) {
        var oldPos = oldPositions.get(child);
        if (!oldPos) return;
        var newPos = child.getBoundingClientRect();
        if (oldPos.top !== newPos.top) {
          var deltaY = oldPos.top - newPos.top;
          child.style.transition = 'none';
          child.style.transform = 'translateY(' + deltaY + 'px)';
          child.offsetHeight;
          child.style.transition = 'transform 0.2s ease';
          child.style.transform = '';
        }
      });
    }
  }

  function _syncGroupOrderFromDOM() {
    var orders = C.groupOrders();
    document.querySelectorAll('#commandsListBody .cmd-group-body').forEach(function(body) {
      var tag = body.dataset.group || '__main__';
      var indices = [];
      body.querySelectorAll('.cmd-item').forEach(function(item) {
        indices.push(parseInt(item.dataset.index));
      });
      if (tag === '__main__' || orders[tag]) orders[tag] = indices;
    });
  }

  function _onGroupDragStart(e) {
    var group = e.currentTarget.closest('.cmd-group');
    if (!group || group.dataset.tag === '' || !group.dataset.tag) { e.preventDefault(); return; }
    e.dataTransfer.setData('text/group', group.dataset.tag);
    e.dataTransfer.effectAllowed = 'move';
    var img = new Image();
    img.src = 'data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7';
    e.dataTransfer.setDragImage(img, 0, 0);
    _floatingGhost = group.cloneNode(true);
    _floatingGhost.style.position = 'fixed';
    _floatingGhost.style.pointerEvents = 'none';
    _floatingGhost.style.zIndex = '9999';
    _floatingGhost.style.opacity = '1';
    _floatingGhost.style.width = group.offsetWidth + 'px';
    _floatingGhost.style.boxShadow = '0 5px 15px rgba(0,0,0,0.2)';
    _floatingGhost.style.backgroundColor = getComputedStyle(group).backgroundColor || 'var(--bg-panel)';
    _floatingGhost.classList.remove('is-dragging','drag-over');
    var rect = group.getBoundingClientRect();
    _dragOffsetX = e.clientX - rect.left;
    _dragOffsetY = e.clientY - rect.top;
    _floatingGhost.style.left = (e.clientX - _dragOffsetX) + 'px';
    _floatingGhost.style.top = (e.clientY - _dragOffsetY) + 'px';
    document.body.appendChild(_floatingGhost);
    setTimeout(function() { group.style.visibility = 'hidden'; group.classList.add('is-dragging'); }, 0);
  }

  function _onGroupDrag(e) {
    if (_floatingGhost && e.clientX !== 0 && e.clientY !== 0) {
      _floatingGhost.style.left = (e.clientX - _dragOffsetX) + 'px';
      _floatingGhost.style.top = (e.clientY - _dragOffsetY) + 'px';
    }
  }

  function _onGroupDragEnd(e) {
    if (_floatingGhost) { _floatingGhost.remove(); _floatingGhost = null; }
    var group = e.currentTarget.closest('.cmd-group');
    if (group) { group.style.visibility = ''; group.classList.remove('is-dragging'); }
    _collectSubmenuOrderFromDOM();
    C.mark();
  }

  function _onListDragOver(e) {
    e.preventDefault();
    var draggingGroup = document.querySelector('#commandsListBody .cmd-group.is-dragging');
    if (!draggingGroup) return;
    var list = document.getElementById('commandsListBody');
    var groups = [];
    list.querySelectorAll('.cmd-group:not(.is-dragging)').forEach(function(g) { groups.push(g); });
    var nextGroup = null;
    for (var i = 0; i < groups.length; i++) {
      var box = groups[i].getBoundingClientRect();
      if (e.clientY - box.top - box.height / 2 < 0) { nextGroup = groups[i]; break; }
    }
    if (nextGroup !== (draggingGroup.nextElementSibling || null)) {
      list.insertBefore(draggingGroup, nextGroup);
    }
  }

  function _collectSubmenuOrderFromDOM() {
    var tags = [];
    document.querySelectorAll('#commandsListBody .cmd-group').forEach(function(g) {
      if (g.dataset.tag) tags.push(g.dataset.tag);
    });
    C.setSubmenuOrder(tags);
  }

  C._wireItemDrag = function(list) {
    list.querySelectorAll('.cmd-item').forEach(function(item) {
      item.addEventListener('dragstart', _onItemDragStart);
      item.addEventListener('drag', _onItemDrag);
      item.addEventListener('dragend', _onItemDragEnd);
    });
    list.querySelectorAll('.cmd-group-body').forEach(function(body) {
      body.addEventListener('dragover', function(e) { _onGroupBodyDragOver(e, body); });
      body.addEventListener('drop', function(e) { e.preventDefault(); });
    });
  };

  C._wireGroupDrag = function(list) {
    list.querySelectorAll('.cmd-group-header').forEach(function(hdr) {
      hdr.addEventListener('dragstart', _onGroupDragStart);
      hdr.addEventListener('drag', _onGroupDrag);
      hdr.addEventListener('dragend', _onGroupDragEnd);
    });
    list.addEventListener('dragover', _onListDragOver);
    list.addEventListener('drop', function(e) { e.preventDefault(); });
  };
})();
