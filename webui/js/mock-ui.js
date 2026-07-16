// mock-ui.js — Panel resize, font size controls, tree zoom, composer resize
// Namespaced as window.MockUI to avoid global conflicts.
// Other mock behaviors (copy, edit, modals, popover, etc.) are handled by app modules.

window.MockUI = (function() {
  var exports = {};

  // Font Size Controls
  exports.initFontControls = function() {
    var currentFontSize = 17;
    var fontDisp = document.getElementById('font-size-display');
    var btnDec = document.getElementById('btn-font-dec');
    var btnInc = document.getElementById('btn-font-inc');

    if (!btnDec || !btnInc || !fontDisp) return;

    btnDec.addEventListener('click', function() {
      if (currentFontSize > 12) {
        currentFontSize -= 1;
        document.documentElement.style.setProperty('--chat-font-size', currentFontSize + 'px');
        fontDisp.textContent = currentFontSize + 'px';
      }
    });

    btnInc.addEventListener('click', function() {
      if (currentFontSize < 28) {
        currentFontSize += 1;
        document.documentElement.style.setProperty('--chat-font-size', currentFontSize + 'px');
        fontDisp.textContent = currentFontSize + 'px';
      }
    });
  };

  // Composer Auto-resize
  exports.initComposerResize = function() {
    var textarea = document.getElementById('chat-input');
    if (!textarea) return;

    textarea.addEventListener('input', function() {
      this.style.height = 'auto';
      this.style.height = (this.scrollHeight) + 'px';
    });
  };

  // Vertical Panel Resize
  function setupVerticalResize(seamId, topEl) {
    var seam = document.getElementById(seamId);
    if (!seam || !topEl) return;

    var dragging = false, startY = 0, startH = 0;

    seam.addEventListener('mousedown', function(e) {
      dragging = true;
      startY = e.clientY;
      startH = topEl.offsetHeight;
      document.body.style.userSelect = 'none';
      document.body.style.cursor = 'row-resize';
    });

    window.addEventListener('mousemove', function(e) {
      if (!dragging) return;
      var delta = e.clientY - startY;
      var newH = startH + delta;
      var parentH = topEl.parentElement.offsetHeight;
      newH = Math.max(150, Math.min(newH, parentH - 150));
      topEl.style.height = newH + 'px';
      topEl.style.flex = '0 0 auto';
    });

    function cancelDrag() {
      if (dragging) {
        dragging = false;
        document.body.style.userSelect = '';
        document.body.style.cursor = '';
      }
    }

    window.addEventListener('mouseup', cancelDrag);
    // WebView2 edge case: cancel drag if cursor leaves the WebView bounds
    document.documentElement.addEventListener('mouseleave', cancelDrag);
  }

  exports.setupVerticalResize = setupVerticalResize;

  // Horizontal Panel Resize
  function setupResize(seamId, notchId, railEl, side, min, max, start) {
    var seam = document.getElementById(seamId);
    var notch = document.getElementById(notchId);
    if (!seam || !notch || !railEl) return;

    var width = start, dragging = false, startX = 0, startW = 0, collapsed = false;

    function apply() {
      railEl.style.width = width + 'px';
      if (side === 'left') railEl.classList.toggle('mini', width <= 90 && width > 0);

      var isLeft = side === 'left';
      var icon = collapsed ? (isLeft ? 'chevron-right' : 'chevron-left') : (isLeft ? 'chevron-left' : 'chevron-right');
      notch.innerHTML = '<i data-lucide="' + icon + '" style="width:12px;height:12px;"></i>';
      if (typeof lucide !== 'undefined') lucide.createIcons();
    }

    seam.addEventListener('mousedown', function(e) {
      if (e.target.closest('.seam-notch')) return;
      dragging = true;
      startX = e.clientX;
      startW = width;
      document.body.style.userSelect = 'none';
      document.body.style.cursor = 'col-resize';
      // Disable CSS transition during drag for instant response
      railEl.style.transition = 'none';
    });

    window.addEventListener('mousemove', function(e) {
      if (!dragging) return;
      var delta = side === 'left' ? (e.clientX - startX) : (startX - e.clientX);
      width = Math.max(0, Math.min(max, startW + delta));
      collapsed = width < 40;
      if (width < 40) width = 0;
      apply();
    });

    function cancelDrag() {
      if (dragging && width > 0 && width < min) { width = min; apply(); }
      dragging = false;
      document.body.style.userSelect = '';
      document.body.style.cursor = '';
      // Re-enable CSS transition after drag
      railEl.style.transition = '';
    }

    window.addEventListener('mouseup', cancelDrag);
    // WebView2 edge case
    document.documentElement.addEventListener('mouseleave', function() {
      if (dragging) cancelDrag();
    });

    notch.addEventListener('click', function(e) {
      e.stopPropagation();
      if (collapsed) { width = startW > min ? startW : start; collapsed = false; }
      else { startW = width; width = 0; collapsed = true; }
      apply();
    });
  }

  exports.setupResize = setupResize;

  // Tree Modal Zoom & Pan
  exports.initTreeZoom = function() {
    var canvasWrap = document.getElementById('treeCanvasWrap');
    var layer = document.getElementById('treeZoomLayer');
    var pct = document.getElementById('zoomPct');
    var zoomIn = document.getElementById('zoomIn');
    var zoomOut = document.getElementById('zoomOut');
    var zoomFit = document.getElementById('zoomFit');

    if (!canvasWrap || !layer || !pct) return;

    var zoom = 1, panX = 0, panY = 0, panning = false;
    var panStart = { x: 0, y: 0 }, origPan = { x: 0, y: 0 };

    function applyZoom() {
      layer.style.transform = 'translate(' + panX + 'px,' + panY + 'px) scale(' + zoom + ')';
      pct.textContent = Math.round(zoom * 100) + '%';
    }

    if (zoomIn) zoomIn.addEventListener('click', function() { zoom = Math.min(2, zoom + 0.15); applyZoom(); });
    if (zoomOut) zoomOut.addEventListener('click', function() { zoom = Math.max(0.4, zoom - 0.15); applyZoom(); });
    if (zoomFit) zoomFit.addEventListener('click', function() { zoom = 1; panX = 0; panY = 0; applyZoom(); });

    canvasWrap.addEventListener('mousedown', function(e) {
      if (e.target.closest('.tree-node') || e.target.closest('button')) return;
      panning = true;
      canvasWrap.classList.add('panning');
      panStart = { x: e.clientX, y: e.clientY };
      origPan = { x: panX, y: panY };
    });

    window.addEventListener('mousemove', function(e) {
      if (!panning) return;
      panX = origPan.x + (e.clientX - panStart.x);
      panY = origPan.y + (e.clientY - panStart.y);
      applyZoom();
    });

    window.addEventListener('mouseup', function() { panning = false; canvasWrap.classList.remove('panning'); });

    canvasWrap.addEventListener('wheel', function(e) {
      e.preventDefault();
      zoom = Math.min(2, Math.max(0.4, zoom + (e.deltaY > 0 ? -0.05 : 0.05)));
      applyZoom();
    }, { passive: false });
  };

  // Auto-collapse side panels when window is small, expand when maximized
  exports.initAutoCollapse = function() {
    var railLeft = document.getElementById('railLeft');
    var railRight = document.getElementById('railRight');
    if (!railLeft || !railRight) return;

    function isMaximized() {
      // Heuristic: if window covers >90% of screen width, it's maximized
      return window.outerWidth / screen.availWidth > 0.9;
    }

    var wasMaximized = isMaximized();

    function onResize() {
      var nowMaximized = isMaximized();
      if (nowMaximized === wasMaximized) return;
      wasMaximized = nowMaximized;

      if (nowMaximized) {
        // Expand: restore default widths
        railLeft.style.width = '340px';
        railLeft.style.transition = '';
        railLeft.classList.remove('mini');
        railRight.style.width = '400px';
        railRight.style.transition = '';
        // Update notch icons
        document.getElementById('notchLeft').innerHTML = '<i data-lucide="chevron-left" style="width:12px;height:12px;"></i>';
        document.getElementById('notchRight').innerHTML = '<i data-lucide="chevron-right" style="width:12px;height:12px;"></i>';
        if (typeof lucide !== 'undefined') lucide.createIcons();
      } else {
        // Collapse: narrow panels
        railLeft.style.width = '0px';
        railLeft.style.transition = 'none';
        railRight.style.width = '0px';
        railRight.style.transition = 'none';
        document.getElementById('notchLeft').innerHTML = '<i data-lucide="chevron-right" style="width:12px;height:12px;"></i>';
        document.getElementById('notchRight').innerHTML = '<i data-lucide="chevron-left" style="width:12px;height:12px;"></i>';
        if (typeof lucide !== 'undefined') lucide.createIcons();
      }
    }

    window.addEventListener('resize', onResize);
    // Initial check — force apply after WebView2 is fully initialized
    setTimeout(function() {
      wasMaximized = !isMaximized(); // force mismatch
      onResize();
    }, 300);
  };

  return exports;
})();
