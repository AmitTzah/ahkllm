// ======================================================
// chat-token-tooltip.js — Per-message token info tooltip
// Click to toggle, click elsewhere to dismiss
// ======================================================

function createTokenInfoIcon(msg) {
  var btn = document.createElement('button');
  btn.className = 'msg-action-btn token-info-btn';
  btn.textContent = '\uD83D\uDCCA';
  btn.title = 'Click for token usage info';

  btn.addEventListener('click', function(e) {
    e.stopPropagation();
    var existing = btn.querySelector('.token-tooltip');
    if (existing) {
      existing.remove();
    } else {
      closeAllTokenTooltips();
      showTokenTooltip(btn, msg);
    }
  });

  return btn;
}

function showTokenTooltip(btn, msg) {
  var tooltip = document.createElement('div');
  tooltip.className = 'token-tooltip';

  if (msg.role === 'assistant') {
    var visibleTokens = msg.tokenCount || 0;
    var thinkingTokens = msg.thinkingTokens || 0;
    var cachedTokens = msg.cachedTokens || 0;
    var responseTimeMs = msg.responseTimeMs || 0;
    var ttftMs = msg.ttftMs || 0;
    var totalOutput = visibleTokens + thinkingTokens;

    var tokPerSec = '';
    if (responseTimeMs > 0 && totalOutput > 0) {
      tokPerSec = Math.round(totalOutput / (responseTimeMs / 1000));
    }

    var lines = [];
    lines.push('<div class="token-tooltip-title">\uD83D\uDCCA Token Usage</div>');
    lines.push('<div class="token-tooltip-row">Output: <span>' + formatNumber(totalOutput) + ' tokens</span></div>');
    lines.push('<div class="token-tooltip-sub">  \u251C Visible: <span>' + formatNumber(visibleTokens) + ' tokens</span></div>');
    lines.push('<div class="token-tooltip-sub">  \u2514 Thinking: <span>' + formatNumber(thinkingTokens) + ' tokens</span></div>');
    lines.push('<div class="token-tooltip-row">Cache: <span>' + formatNumber(cachedTokens) + ' tokens</span></div>');
    if (tokPerSec) {
      lines.push('<div class="token-tooltip-row">Speed: <span>' + formatNumber(tokPerSec) + ' tok/sec</span></div>');
    }
    if (responseTimeMs > 0) {
      if (ttftMs > 0) {
        lines.push('<div class="token-tooltip-row">TTFT: <span>' + (ttftMs / 1000).toFixed(2) + 's</span></div>');
      }
      lines.push('<div class="token-tooltip-row">Total time: <span>' + (responseTimeMs / 1000).toFixed(1) + 's</span></div>');
    }
    tooltip.innerHTML = lines.join('');
  } else if (msg.role === 'user') {
    var inputTokens = msg.tokenCount || 0;
    tooltip.innerHTML =
      '<div class="token-tooltip-title">\uD83D\uDCCA Token Usage</div>' +
      '<div class="token-tooltip-row">Input: <span>' + formatNumber(inputTokens) + ' tokens</span></div>' +
      '<div class="token-tooltip-sub">(contribution to context)</div>';
  }

  btn.appendChild(tooltip);
}

function closeAllTokenTooltips() {
  var tooltips = document.querySelectorAll('.token-tooltip');
  for (var i = 0; i < tooltips.length; i++) {
    tooltips[i].remove();
  }
}

// Close any open tooltip when clicking elsewhere
document.addEventListener('click', function(e) {
  if (!e.target.closest('.token-info-btn')) {
    closeAllTokenTooltips();
  }
});
