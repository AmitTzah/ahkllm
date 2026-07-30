// ui-controls.js — Panel resize, font size controls, composer resize
// Namespaced as window.UiControls to avoid global conflicts.

window.UiControls = (function() {
  var exports = {};

  // Font Size Controls
  exports.initFontControls = function() {
    var currentFontSize = 17;
    if (typeof getComputedStyle !== 'undefined') {
      var cssVal = getComputedStyle(document.documentElement).getPropertyValue('--chat-font-size').trim();
      if (cssVal) currentFontSize = parseInt(cssVal) || 17;
    }
    var fontDisp = document.getElementById('font-size-display');
    var btnDec = document.getElementById('btn-font-dec');
    var btnInc = document.getElementById('btn-font-inc');

    if (!btnDec || !btnInc || !fontDisp) return;

    function applyFontSize(size) {
      document.documentElement.style.setProperty('--chat-font-size', size + 'px');
      fontDisp.textContent = size + 'px';
      // Persist per-chat font size to AHK/DB
      if (window.chrome && window.chrome.webview) {
        window.chrome.webview.postMessage(JSON.stringify({
          action: 'updateFontSize',
          fontSize: size
        }));
      }
    }

    btnDec.addEventListener('click', function() {
      if (currentFontSize > 12) {
        currentFontSize -= 1;
        applyFontSize(currentFontSize);
      }
    });

    btnInc.addEventListener('click', function() {
      if (currentFontSize < 28) {
        currentFontSize += 1;
        applyFontSize(currentFontSize);
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
  // railRef: an element, or a function returning the currently-visible panel element
  // (allows one seam to resize whichever panel occupies the slot, e.g. chat sidebar vs settings nav)
  function setupResize(seamId, notchId, railRef, side, min, max, start) {
    var seam = document.getElementById(seamId);
    var notch = document.getElementById(notchId);
    var getRail = typeof railRef === 'function' ? railRef : function() { return railRef; };
    if (!seam || !notch || !getRail()) return;

    var dragging = false, startX = 0, startW = 0, dragWidth = 0;

    function isCollapsed(el) { return el.offsetWidth < 40; }

    function apply(el, width) {
      el.style.width = width + 'px';
      if (side === 'left') el.classList.toggle('mini', width <= 90 && width > 0);

      var isLeft = side === 'left';
      var icon = isCollapsed(el) ? (isLeft ? 'chevron-right' : 'chevron-left') : (isLeft ? 'chevron-left' : 'chevron-right');
      notch.innerHTML = '<i data-lucide="' + icon + '" style="width:12px;height:12px;"></i>';
      if (typeof lucide !== 'undefined') lucide.createIcons();
    }

    seam.addEventListener('mousedown', function(e) {
      if (e.target.closest('.seam-notch')) return;
      var el = getRail();
      if (!el) return;
      dragging = true;
      startX = e.clientX;
      startW = el.offsetWidth;
      dragWidth = startW;
      document.body.style.userSelect = 'none';
      document.body.style.cursor = 'col-resize';
      // Disable CSS transition during drag for instant response
      el.style.transition = 'none';
    });

    window.addEventListener('mousemove', function(e) {
      if (!dragging) return;
      var el = getRail();
      if (!el) return;
      var delta = side === 'left' ? (e.clientX - startX) : (startX - e.clientX);
      dragWidth = Math.max(0, Math.min(max, startW + delta));
      if (dragWidth < 40) dragWidth = 0;
      apply(el, dragWidth);
    });

    function cancelDrag() {
      var el = getRail();
      if (dragging && el && dragWidth > 0 && dragWidth < min) { dragWidth = min; apply(el, dragWidth); }
      dragging = false;
      document.body.style.userSelect = '';
      document.body.style.cursor = '';
      // Re-enable CSS transition after drag
      if (el) el.style.transition = '';
    }

    window.addEventListener('mouseup', cancelDrag);
    // WebView2 edge case
    document.documentElement.addEventListener('mouseleave', function() {
      if (dragging) cancelDrag();
    });

    notch.addEventListener('click', function(e) {
      e.stopPropagation();
      var el = getRail();
      if (!el) return;
      if (isCollapsed(el)) {
        var prev = parseInt(el.dataset.prevWidth, 10);
        apply(el, prev > min ? prev : start);
      } else {
        el.dataset.prevWidth = el.offsetWidth;
        apply(el, 0);
      }
    });
  }

  exports.setupResize = setupResize;

  // Auto-collapse side panels when window is small, expand when maximized
  exports.initAutoCollapse = function() {
    var railLeft = document.getElementById('railLeft');
    var railRight = document.getElementById('railRight');
    var settingsNav = document.getElementById('settingsNav');
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
        if (settingsNav) {
          settingsNav.style.width = '340px';
          settingsNav.style.transition = '';
          settingsNav.classList.remove('mini');
        }
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
        if (settingsNav) {
          settingsNav.style.width = '0px';
          settingsNav.style.transition = 'none';
        }
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
