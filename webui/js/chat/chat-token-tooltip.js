// ======================================================
// chat-token-tooltip.js — Per-message token info popover
// Renders the stat toggle / stat popover in the token bar
// ======================================================

function createTokenInfoIcon(msg, index) {
  var wrapper = document.createElement('div');
  wrapper.className = 'stat-toggle';

  var btn = document.createElement('button');
  btn.className = 'msg-action-btn stat-btn';
  btn.title = 'Token Usage';
  btn.innerHTML = '<i data-lucide="bar-chart-2"></i>';

  var popover = document.createElement('div');
  popover.className = 'stat-popover';
  wrapper.appendChild(popover);

  btn.addEventListener('click', function(e) {
    e.stopPropagation();
    var wasOpen = wrapper.classList.contains('pop-open');
    // Close all other popovers
    document.querySelectorAll('.stat-toggle.pop-open').forEach(function(p) { p.classList.remove('pop-open'); });
    if (!wasOpen) {
      // Always read from chatMessages (not closure) to get latest token data
      var currentMsg = (typeof chatMessages !== 'undefined' && index < chatMessages.length) ? chatMessages[index] : msg;
      showTokenTooltip(popover, currentMsg);
      wrapper.classList.add('pop-open');
    }
  });

  wrapper.appendChild(btn);
  return wrapper;
}

function showTokenTooltip(popover, msg) {
  if (msg.role === 'assistant') {
    var visibleTokens = msg.tokenCount || 0;
    var thinkingTokens = msg.thinkingTokens || 0;
    var cachedTokens = msg.cachedTokens || 0;
    var responseTimeMs = msg.responseTimeMs || 0;
    var ttftMs = msg.ttftMs || 0;
    var totalOutput = visibleTokens + thinkingTokens;
    var tokPerSec = responseTimeMs > 0 && totalOutput > 0 ? Math.round(totalOutput / (responseTimeMs / 1000)) : 0;
    var totalTime = (responseTimeMs / 1000).toFixed(1);

    popover.innerHTML =
      '<div style="font-weight:600; font-size:15px; margin-bottom:14px; display:flex; align-items:center; gap:8px; color:var(--accent-primary);">' +
        '<i data-lucide="bar-chart-2" style="width:18px;height:18px;"></i> Token Usage' +
      '</div>' +
      '<div style="font-size:14px; line-height:1.6; color:var(--text-secondary);">' +
        '<div>Output: <span style="font-weight:600;color:var(--text-primary);">' + formatNumber(totalOutput) + ' tokens</span></div>' +
        '<div style="padding-left:16px; border-left:2px solid var(--border-main); margin-left:8px; margin-top:4px;">' +
          '<div>Visible: ' + formatNumber(visibleTokens) + ' tokens</div>' +
          '<div>Thinking: ' + formatNumber(thinkingTokens) + ' tokens</div>' +
        '</div>' +
        '<div style="margin-top:8px;">Cache: <span style="font-weight:600;color:var(--text-primary);">' + formatNumber(cachedTokens) + ' tokens</span></div>' +
        (tokPerSec > 0 ? '<div style="margin-top:4px;">Speed: <span style="font-weight:600;color:var(--text-primary);">' + formatNumber(tokPerSec) + ' tok/sec</span></div>' : '') +
        (ttftMs > 0 ? '<div style="margin-top:4px;">TTFT: <span style="font-weight:600;color:var(--text-primary);">' + (ttftMs / 1000).toFixed(2) + 's</span></div>' : '') +
        '<div style="margin-top:6px; padding-top:6px; border-top:1px solid var(--border-light);">Total time: <span style="font-weight:600;color:var(--text-primary);">' + totalTime + 's</span></div>' +
      '</div>';
  } else if (msg.role === 'user') {
    var inputTokens = msg.tokenCount || 0;
    popover.innerHTML =
      '<div style="font-weight:600; font-size:15px; margin-bottom:14px; display:flex; align-items:center; gap:8px; color:var(--accent-primary);">' +
        '<i data-lucide="bar-chart-2" style="width:18px;height:18px;"></i> Token Usage' +
      '</div>' +
      '<div style="font-size:14px; line-height:1.6; color:var(--text-secondary);">' +
        '<div>Input: <span style="font-weight:600;color:var(--text-primary);">' + formatNumber(inputTokens) + ' tokens</span></div>' +
        '<div style="padding-left:16px; border-left:2px solid var(--border-main); margin-left:8px; margin-top:4px;">(contribution to context)</div>' +
      '</div>';
  }

  if (typeof lucide !== 'undefined') lucide.createIcons();
}

function closeAllTokenTooltips() {
  document.querySelectorAll('.stat-toggle.pop-open').forEach(function(p) { p.classList.remove('pop-open'); });
}

// Close popovers when clicking outside
document.addEventListener('click', function(e) {
  if (!e.target.closest('.stat-toggle')) {
    closeAllTokenTooltips();
  }
});
