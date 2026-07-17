// ======================================================
// chat-tree-modal.js — Tree visualization modal
//
// Renders the conversation
// tree as an interactive D3-style graph with zoom/pan.
// ======================================================

var treeModalOpen = false;

function toggleTreeModal() {
  var overlay = document.getElementById('treeOverlay');
  if (!overlay) return;
  if (overlay.classList.contains('open')) {
    overlay.classList.remove('open');
  } else {
    _resetTreeFullscreen();
    overlay.classList.add('open');
    var layer = document.getElementById('treeZoomLayer');
    var pct = document.getElementById('zoomPct');
    if (layer) layer.style.transform = 'translate(0px,0px) scale(1)';
    if (pct) pct.textContent = '100%';
    window.chrome.webview.postMessage(JSON.stringify({ action: 'sidebarAction', subAction: 'loadTree' }));
  }
}

var treeFullscreen = false;

function _resetTreeFullscreen() {
  treeFullscreen = false;
  var box = document.querySelector('.tree-modal');
  if (box) box.classList.remove('fullscreen');
  var icon = document.querySelector('#treeFullscreenBtn i');
  if (icon) icon.setAttribute('data-lucide', 'maximize2');
  if (typeof lucide !== 'undefined' && lucide.createIcons) lucide.createIcons();
}

function toggleTreeFullscreen() {
  var box = document.querySelector('.tree-modal');
  var btn = document.getElementById('treeFullscreenBtn');
  var icon = btn ? btn.querySelector('i') : null;
  if (!box) return;
  treeFullscreen = !treeFullscreen;
  if (treeFullscreen) {
    box.classList.add('fullscreen');
    if (icon) icon.setAttribute('data-lucide', 'minimize2');
  } else {
    box.classList.remove('fullscreen');
    if (icon) icon.setAttribute('data-lucide', 'maximize2');
  }
  if (typeof lucide !== 'undefined' && lucide.createIcons) lucide.createIcons();
  // Re-fit after transition
  var layer = document.getElementById('treeZoomLayer');
  var pct = document.getElementById('zoomPct');
  if (layer) layer.style.transform = 'translate(0px,0px) scale(1)';
  if (pct) pct.textContent = '100%';
}

function closeTreeModal() {
  var overlay = document.getElementById('treeOverlay');
  if (overlay) {
    overlay.classList.remove('open');
    _resetTreeFullscreen();
  }
}

// Wire tree close button, overlay click, and zoom/pan (guarded for test sandboxes)
if (typeof document !== 'undefined' && document.addEventListener) {
  document.addEventListener('DOMContentLoaded', function() {
    var treeClose = document.getElementById('treeClose');
    var treeOverlay = document.getElementById('treeOverlay');
    if (treeClose) treeClose.addEventListener('click', function() { closeTreeModal(); });
    if (treeOverlay) treeOverlay.addEventListener('click', function(e) { if (e.target === treeOverlay) closeTreeModal(); });

    initTreeZoom();
  });
}

// Initialize zoom/pan for the conversation tree modal.
function initTreeZoom() {
  var canvasWrap = document.getElementById('treeCanvasWrap');
  var layer = document.getElementById('treeZoomLayer');
  var pct = document.getElementById('zoomPct');
  if (!canvasWrap || !layer || !pct) return;

  var zoom = 1, panX = 0, panY = 0, panning = false, panStart = {x:0,y:0}, origPan = {x:0,y:0};

  function applyZoom() {
    layer.style.transform = 'translate(' + panX + 'px,' + panY + 'px) scale(' + zoom + ')';
    pct.textContent = Math.round(zoom * 100) + '%';
  }

  document.getElementById('zoomIn').addEventListener('click', function() { zoom = Math.min(2, zoom + 0.15); applyZoom(); });
  document.getElementById('zoomOut').addEventListener('click', function() { zoom = Math.max(0.4, zoom - 0.15); applyZoom(); });
  document.getElementById('zoomFit').addEventListener('click', function() { zoom = 1; panX = 0; panY = 0; applyZoom(); });

  canvasWrap.addEventListener('mousedown', function(e) {
    if (e.target.closest('.tree-node') || e.target.closest('button')) return;
    panning = true; canvasWrap.classList.add('panning');
    panStart = {x: e.clientX, y: e.clientY}; origPan = {x: panX, y: panY};
  });
  window.addEventListener('mousemove', function(e) {
    if (!panning) return;
    panX = origPan.x + (e.clientX - panStart.x); panY = origPan.y + (e.clientY - panStart.y);
    applyZoom();
  });
  window.addEventListener('mouseup', function() { panning = false; if (canvasWrap) canvasWrap.classList.remove('panning'); });
  canvasWrap.addEventListener('wheel', function(e) {
    e.preventDefault(); zoom = Math.min(2, Math.max(0.4, zoom + (e.deltaY > 0 ? -0.05 : 0.05))); applyZoom();
  }, {passive: false});
}

// Called by AHK with tree data.
function renderChatTree(tree) {
  var container = document.querySelector('.tree-canvas');
  if (!container) return;

  container.innerHTML = '';

  if (!tree || tree.length === 0) {
    container.innerHTML = '<p style="color:var(--text-tertiary);padding:2rem;text-align:center;">No messages yet.</p>';
    var sub2 = document.querySelector('.tree-modal-sub');
    if (sub2) sub2.textContent = 'Viewing active path · 0 nodes';
    return;
  }

  _inheritModels(tree, '');

  var sub = document.querySelector('.tree-modal-sub');
  if (sub) {
    var total = _countTreeNodes(tree);
    sub.textContent = 'Viewing active path · ' + total + ' node' + (total !== 1 ? 's' : '');
  }

  var activeIds = {};
  _collectActivePath(activeIds);

  var svgPaths = [];
  var allNodes = [];
  _layoutTreeNodes(tree, 0, 60, activeIds, svgPaths, allNodes);

  var maxBottom = 60;
  for (var i = 0; i < allNodes.length; i++) {
    // 100 = layout NODE_H (90) + slack, since real rendered nodes can exceed NODE_H.
    if (allNodes[i].top + 100 > maxBottom) maxBottom = allNodes[i].top + 100;
  }
  var maxRight = 40;
  for (var i2 = 0; i2 < allNodes.length; i2++) {
    if (allNodes[i2].left + 280 > maxRight) maxRight = allNodes[i2].left + 280;
  }
  container.style.width = Math.max(1200, maxRight + 40) + 'px';
  container.style.height = Math.max(800, maxBottom + 40) + 'px';

  var svgEl = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
  svgEl.setAttribute('width', container.style.width);
  svgEl.setAttribute('height', container.style.height);
  svgEl.setAttribute('style', 'position:absolute;top:0;left:0;pointer-events:none;');
  for (var si = 0; si < svgPaths.length; si++) {
    var p = svgPaths[si];
    var path = document.createElementNS('http://www.w3.org/2000/svg', 'path');
    path.setAttribute('d', 'M ' + p.x1 + ' ' + p.y1 + ' C ' + (p.x1 + 50) + ' ' + p.y1 + ' ' + (p.x2 - 50) + ' ' + p.y2 + ' ' + p.x2 + ' ' + p.y2);
    path.setAttribute('stroke', p.active ? 'var(--accent-primary)' : 'var(--border-main)');
    path.setAttribute('stroke-width', p.active ? '2.5' : '2');
    path.setAttribute('fill', 'none');
    svgEl.appendChild(path);
  }
  container.appendChild(svgEl);

  for (var ni = 0; ni < allNodes.length; ni++) {
    var nd = allNodes[ni];
    var el = document.createElement('div');
    el.className = 'tree-node' + (nd.active ? ' active-path' : '');
    el.setAttribute('data-target', nd.id);
    el.style.cssText = 'position:absolute;left:' + nd.left + 'px;top:' + nd.top + 'px;' + (nd.active ? '' : 'opacity:0.7;');
    el.innerHTML =
      '<div class="tree-node-role"' + (nd.isLastAssistant ? ' style="color:var(--accent-primary);"' : '') + '>' +
        escHtml(nd.roleLabel) + (nd.isLastAssistant ? ' (Current)' : '') +
      '</div>' +
      '<div class="tree-node-text">' + escHtml(nd.preview) + '</div>';
    el.addEventListener('click', function(targetId) {
      return function(e) {
        e.stopPropagation();
        var leafId = _findDefaultLeaf(targetId, window._treeData);
        var resolvedId = leafId || targetId;
        window.chrome.webview.postMessage(JSON.stringify({ action: 'sidebarAction', subAction: 'navigateToMessage', messageId: resolvedId }));
        closeTreeModal();
        setTimeout(function() {
          for (var i = 0; i < chatMessages.length; i++) {
            if (chatMessages[i].id === targetId) { scrollToMessage(i); break; }
          }
        }, 150);
      };
    }(nd.id));
    container.appendChild(el);
  }
}

// Recursively fill in missing model names (branched messages may lack them)
function _inheritModels(nodes, parentModel) {
  if (!nodes) return;
  for (var i = 0; i < nodes.length; i++) {
    if (!nodes[i].model && nodes[i].role === 'assistant') {
      nodes[i].model = parentModel || 'Assistant';
    }
    _inheritModels(nodes[i].children || [], nodes[i].model || parentModel);
  }
}

function _countTreeNodes(tree) {
  var count = 0;
  for (var i = 0; i < tree.length; i++) {
    count += 1 + _countTreeNodes(tree[i].children || []);
  }
  return count;
}

function _findDefaultLeaf(nodeId, tree) {
  function _walk(nodes) {
    if (!nodes || nodes.length === 0) return null;
    for (var i = 0; i < nodes.length; i++) {
      if (nodes[i].id === nodeId) {
        var current = nodes[i];
        var children = current.children || [];
        while (children.length > 0) {
          current = children[children.length - 1];
          children = current.children || [];
        }
        return current.id;
      }
      var found = _walk(nodes[i].children || []);
      if (found) return found;
    }
    return null;
  }
  return _walk(tree || []);
}

function _collectActivePath(activeIds) {
  for (var i = 0; i < (typeof chatMessages !== 'undefined' ? chatMessages.length : 0); i++) {
    if (chatMessages[i].id) activeIds[chatMessages[i].id] = true;
  }
}

// Layout nodes bottom-up: children first, parent centered between them.
// Siblings at the same level stack vertically (newest on top via TreeRepo sorting).
// Root-level branches (multiple nodes in the `nodes` array) get the same
// SIBLING_GAP cushion as child subtrees so adjacent subtrees never touch/overlap.
function _layoutTreeNodes(nodes, depth, startY, activeIds, svgPaths, allNodes) {
  if (!nodes || nodes.length === 0) return startY;
  var x = 40 + depth * 340;
  // NODE_H is the layout-math node height. Real rendered height is ~81-126px
  // (.tree-node in modals.css: padding + role line + up to 3 clamped text lines),
  // so the effective visual gap is (SIBLING_GAP - NODE_H) minus the overflow.
  var NODE_H = 90;
  var SIBLING_GAP = 160;

  var childInfo = [];
  var currentY = startY;
  for (var i = 0; i < nodes.length; i++) {
    // Cushion between consecutive subtrees in this array (root-level branches;
    // mirrors the inner loop's child-subtree gap below).
    if (i > 0) currentY += SIBLING_GAP - NODE_H;
    var node = nodes[i];
    var children = node.children || [];
    var childTops = [];
    var childY = currentY;
    for (var ci = 0; ci < children.length; ci++) {
      childTops.push(childY);
      childY = _layoutTreeNodes([children[ci]], depth + 1, childY, activeIds, svgPaths, allNodes);
      childY += SIBLING_GAP - NODE_H;
    }
    if (children.length > 0) childY -= (SIBLING_GAP - NODE_H);

    childInfo.push({ node: node, childTops: childTops, bottomY: childY });
    currentY = Math.max(childY, currentY + NODE_H);
  }

  for (var i2 = 0; i2 < childInfo.length; i2++) {
    var info = childInfo[i2];
    var nd = info.node;
    var ctops = info.childTops;
    var isActive = !!activeIds[nd.id];
    var roleLabel = nd.role === 'user' ? 'You' : (nd.role === 'assistant' ? (nd.model || 'Assistant') : 'System');
    var preview = (nd.content_preview || '(empty)');
    if (preview.length > 55) preview = preview.substring(0, 55) + '...';
    var children = nd.children || [];
    var isLastAssistant = isActive && nd.role === 'assistant' && (!children.length || !activeIds[children[0].id]);

    var nodeTop;
    if (ctops.length > 0) {
      var firstChildCenter = ctops[0] + NODE_H / 2;
      var lastChildCenter = ctops[ctops.length - 1] + NODE_H / 2;
      nodeTop = (firstChildCenter + lastChildCenter) / 2 - NODE_H / 2;
    } else {
      nodeTop = info.bottomY;
      info.bottomY = nodeTop + NODE_H;
    }

    allNodes.push({ id: nd.id, left: x, top: Math.round(nodeTop), active: isActive, roleLabel: roleLabel, preview: preview, isLastAssistant: isLastAssistant });

    var childX = 40 + (depth + 1) * 340;
    var parentCenterX = x + 260;
    var parentCenterY = Math.round(nodeTop) + NODE_H / 2;
    for (var ci2 = 0; ci2 < ctops.length; ci2++) {
      var childCenterY = ctops[ci2] + NODE_H / 2;
      var childActive = isActive && !!activeIds[(children[ci2] || {}).id];
      svgPaths.push({
        x1: parentCenterX, y1: parentCenterY,
        x2: childX, y2: Math.round(childCenterY),
        active: childActive
      });
    }
  }

  var maxBottom = startY;
  for (var i3 = 0; i3 < childInfo.length; i3++) {
    if (childInfo[i3].bottomY > maxBottom) maxBottom = childInfo[i3].bottomY;
  }
  return maxBottom;
}
