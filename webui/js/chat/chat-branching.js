// ======================================================
// chat-branching.js — D1 Edit, D2 Delete, D3 Branch Nav, D4 Tree Viz
// ======================================================

// D1: Edit message — opens inline textarea, two save modes
var _editingMessageId = null;
var _removedAttachmentIds = [];

function editMessage(index) {
  var msg = chatMessages[index];
  _editingMessageId = msg.id;
  _removedAttachmentIds = [];
  if (!msg || isLoading) return;

  var bubble = document.querySelectorAll('.msg')[index];
  if (!bubble) return;

  // Use mock's pre-rendered .msg-edit-ui — just add .editing class
  bubble.classList.add('editing');
  var textarea = bubble.querySelector('.msg-edit-textarea');
  if (textarea) { textarea.value = msg.content || ''; textarea.focus(); }

  // Wire buttons (use onclick to replace any previous handler)
  var cancelBtn = bubble.querySelector('.cancel-edit');
  if (cancelBtn) cancelBtn.onclick = function() { bubble.classList.remove('editing'); };

  var overwriteBtn = bubble.querySelector('.save-overwrite');
  if (overwriteBtn) overwriteBtn.onclick = function() {
    var v = textarea.value.trim(); if (!v) return;
    commitEdit(index, msg.id, v, 'overwrite');
    bubble.classList.remove('editing');
  };

  var branchBtn = bubble.querySelector('.save-branch');
  if (branchBtn) branchBtn.onclick = function() {
    var v = textarea.value.trim(); if (!v) return;
    commitEdit(index, msg.id, v, 'branch');
    bubble.classList.remove('editing');
  };

}

// Module-level variables for edit attachments (kept for commitEdit compatibility)
var _editAttachments = [];
var _editExtractPromises = [];
var _editHashPromises = [];

function commitEdit(index, msgId, newContent, mode) {
  // Wait for any pending PDF/DOCX extractions AND SHA-256 hash computations to complete
  var allPromises = _editExtractPromises.concat(_editHashPromises);
  var doCommit = function() {
    var msg = chatMessages[index];
    if (msg && mode === 'overwrite') {
      recordUndo('edit', msgId, { content: msg.content }, { content: newContent });
    }
    var payload = { action: 'editMessage', id: msgId, content: newContent, mode: mode };
    if (_removedAttachmentIds.length > 0) {
      payload.removedAttachmentIds = _removedAttachmentIds.slice();
    }
    if (_editAttachments.length > 0) {
      // Include contentHash for content-addressable dedup
      payload.attachments = _editAttachments.map(function(a) {
        return { type: a.type, filename: a.filename, mimeType: a.mimeType, base64: a.base64, size: a.size, extractedText: a.extractedText || '', contentHash: a.contentHash || '' };
      });
      _editAttachments = [];
    }
    _editExtractPromises = [];
    _editHashPromises = [];
    _editingMessageId = null;
    _removedAttachmentIds = [];
    window.chrome.webview.postMessage(JSON.stringify(payload));
  };

  if (allPromises.length > 0) {
    Promise.all(allPromises).then(function() { doCommit(); }).catch(function() { doCommit(); });
  } else {
    doCommit();
  }
}

// Fork chat at a specific message — creates a copy thread up to that point
function forkChat(index) {
  var msg = chatMessages[index];
  if (!msg || isLoading) return;
  window.chrome.webview.postMessage(JSON.stringify({ action: 'forkChat', id: msg.id }));
}

// D2: Delete message
function deleteMessage(index) {
  var msg = chatMessages[index];
  if (!msg || isLoading) return;

  _showConfirm('Delete this message? This removes it from the current view but data is preserved.', function() {
    // Record undo state before deleting
    recordUndo('delete', msg.id, { content: msg.content, role: msg.role });
    window.chrome.webview.postMessage(JSON.stringify({ action: 'deleteMessage', id: msg.id }));
  });
}

// D3: Switch branch
function switchBranch(msgId, direction) {
  window.chrome.webview.postMessage(JSON.stringify({
    action: 'switchBranch',
    id: msgId,
    direction: direction
  }));
}

// D4: Chat tree visualization (modal)
var treeModalOpen = false;

function toggleTreeModal() {
  var overlay = document.getElementById('treeOverlay');
  if (!overlay) return;
  if (overlay.classList.contains('open')) {
    overlay.classList.remove('open');
  } else {
    overlay.classList.add('open');
    // Reset zoom/pan to default
    var layer = document.getElementById('treeZoomLayer');
    var pct = document.getElementById('zoomPct');
    if (layer) layer.style.transform = 'translate(0px,0px) scale(1)';
    if (pct) pct.textContent = '100%';
    // Request tree data — AHK will send renderChatTree message
    window.chrome.webview.postMessage(JSON.stringify({ action: 'sidebarAction', subAction: 'loadTree' }));
  }
}

// Wire tree close button, overlay click, and zoom/pan (guarded for test sandboxes)
if (typeof document !== 'undefined' && document.addEventListener) {
  document.addEventListener('DOMContentLoaded', function() {
    var treeClose = document.getElementById('treeClose');
    var treeOverlay = document.getElementById('treeOverlay');
    if (treeClose) treeClose.addEventListener('click', function() { treeOverlay.classList.remove('open'); });
    if (treeOverlay) treeOverlay.addEventListener('click', function(e) { if (e.target === treeOverlay) treeOverlay.classList.remove('open'); });

    // Tree modal pan & zoom (matches mock)
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
  });
}

// Called by AHK with tree data.
// Matches mock design: absolute-positioned nodes, SVG connectors, active-path highlighting.
function renderChatTree(tree) {
  var container = document.querySelector('.tree-canvas');
  if (!container) return;

  // Clear previous nodes and SVG
  container.innerHTML = '';

  if (!tree || tree.length === 0) {
    container.innerHTML = '<p style="color:var(--text-tertiary);padding:2rem;text-align:center;">No messages yet.</p>';
    var sub2 = document.querySelector('.tree-modal-sub');
    if (sub2) sub2.textContent = 'Viewing active path · 0 nodes';
    return;
  }

  // Fill in missing models (branched messages may lack model) — inherit from parent
  _inheritModels(tree, '');

  // Update subtitle
  var sub = document.querySelector('.tree-modal-sub');
  if (sub) {
    var total = _countTreeNodes(tree);
    sub.textContent = 'Viewing active path · ' + total + ' node' + (total !== 1 ? 's' : '');
  }

  // Collect active-path IDs (first child at each level)
  var activeIds = {};
  _collectActivePath(activeIds);

  // Layout: bottom-up — children first, parent centered between them
  var svgPaths = [];
  var allNodes = [];
  _layoutTreeNodes(tree, 0, 60, activeIds, svgPaths, allNodes);

  // Auto-size canvas
  var maxBottom = 60;
  for (var i = 0; i < allNodes.length; i++) {
    if (allNodes[i].top + 100 > maxBottom) maxBottom = allNodes[i].top + 100;
  }
  var maxRight = 40;
  for (var i2 = 0; i2 < allNodes.length; i2++) {
    if (allNodes[i2].left + 280 > maxRight) maxRight = allNodes[i2].left + 280;
  }
  container.style.width = Math.max(1200, maxRight + 40) + 'px';
  container.style.height = Math.max(800, maxBottom + 40) + 'px';

  // Render SVG connectors
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

  // Render nodes
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
        // Set active leaf to the branch's end (preserves full path),
        // but scroll to the specific clicked node for visual targeting.
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

function closeTreeModal() {
  var overlay = document.getElementById('treeOverlay');
  if (overlay) overlay.classList.remove('open');
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

// Count total nodes in tree (recursive)
function _countTreeNodes(tree) {
  var count = 0;
  for (var i = 0; i < tree.length; i++) {
    count += 1 + _countTreeNodes(tree[i].children || []);
  }
  return count;
}

// Walk the first-child chain from a node to find the default leaf ID
function _findDefaultLeaf(nodeId, tree) {
  function _walk(nodes) {
    if (!nodes || nodes.length === 0) return null;
    for (var i = 0; i < nodes.length; i++) {
      if (nodes[i].id === nodeId) {
        // Found the node — now walk its last-child chain to the bottom (final version)
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

// Collect active-path node IDs from the actually-loaded chat messages
function _collectActivePath(activeIds) {
  // Use chatMessages (the active path) as the source of truth
  for (var i = 0; i < (typeof chatMessages !== 'undefined' ? chatMessages.length : 0); i++) {
    if (chatMessages[i].id) activeIds[chatMessages[i].id] = true;
  }
}

// Layout nodes bottom-up: children first, then center parent between them.
// Matches mock: parent positioned between siblings, connectors to ALL children.
// Returns the bottommost Y used by this subtree.
function _layoutTreeNodes(nodes, depth, startY, activeIds, svgPaths, allNodes) {
  if (!nodes || nodes.length === 0) return startY;
  var x = 40 + depth * 340;
  var NODE_H = 90;   // approximate node height
  var SIBLING_GAP = 160; // vertical gap between siblings

  // First pass: recursively layout children of each node, collecting child positions.
  // Each sibling's subtree starts below the previous sibling's subtree.
  var childInfo = []; // [{ node, childTops: [y1, y2, ...] }]
  var currentY = startY;
  for (var i = 0; i < nodes.length; i++) {
    var node = nodes[i];
    var children = node.children || [];
    // Layout children: they get positioned sequentially
    var childTops = [];
    var childY = currentY;
    for (var ci = 0; ci < children.length; ci++) {
      childTops.push(childY);
      childY = _layoutTreeNodes([children[ci]], depth + 1, childY, activeIds, svgPaths, allNodes);
      childY += SIBLING_GAP - NODE_H; // gap between siblings
    }
    // Adjust last sibling gap (remove extra)
    if (children.length > 0) childY -= (SIBLING_GAP - NODE_H);

    childInfo.push({ node: node, childTops: childTops, bottomY: childY });
    // Next sibling's subtree starts below this one.
    // If this node has children, childY already accounts for their height.
    // If leaf, just advance by one node height.
    currentY = Math.max(childY, currentY + NODE_H);
  }

  // Second pass: position each node centered among its children, collect all nodes
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

    // Position node: center between children, or at bottom of previous
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

    // Draw connectors from this node to ALL children
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

  // Return bottommost Y
  var maxBottom = startY;
  for (var i3 = 0; i3 < childInfo.length; i3++) {
    if (childInfo[i3].bottomY > maxBottom) maxBottom = childInfo[i3].bottomY;
  }
  return maxBottom;
}
