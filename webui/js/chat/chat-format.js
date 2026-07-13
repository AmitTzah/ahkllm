// ======================================================
// chat-format.js — Clipboard, number formatting, token usage bar
// ======================================================

// Format a single message as text (role label + content + attachment extracted text)
function getMessageText(msg) {
  var text = '';
  switch (msg.role) {
    case 'user': text = 'You:\n' + msg.content; break;
    case 'assistant': text = (msg.model || 'Assistant') + ':\n' + msg.content; break;
    case 'system': text = 'System Prompt:\n' + msg.content; break;
  }
  if (msg.attachments && msg.attachments.length) {
    for (var a = 0; a < msg.attachments.length; a++) {
      var att = msg.attachments[a];
      if (att.extracted_text && att.extracted_text !== '__SCANNED_PDF__' && att.extracted_text !== '__LIBRARY_UNAVAILABLE__' && att.extracted_text !== '(no text extracted)') {
        var label = 'File';
        if (att.attachment_type === 'pdf') label = 'PDF';
        else if (att.attachment_type === 'docx') label = 'DOCX';
        text += '\n\n[Attached ' + label + ': ' + (att.original_filename || 'file') + ']\n' + att.extracted_text;
      }
    }
  }
  return text;
}

// Copy a single message's content to clipboard
function copySingleMessage(index) {
  var msg = chatMessages[index];
  if (!msg) return;
  navigator.clipboard.writeText(getMessageText(msg)).then(function() {
    showCopiedFeedback(index);
  }).catch(function(err) {
    console.error('Failed to copy: ', err);
  });
}

// Copy entire chat to clipboard
function copyEntireChat() {
  var parts = [];
  for (var i = 0; i < chatMessages.length; i++) {
    parts.push(getMessageText(chatMessages[i]));
  }

  var fullText = parts.join('\n\n---\n\n');

  navigator.clipboard.writeText(fullText).then(function() {
    var btn = document.getElementById('copy-entire-chat-btn');
    if (!btn) return;
    var originalText = btn.innerHTML;
    btn.innerHTML = '✅ Copied!';
    btn.disabled = true;
    setTimeout(function() {
      btn.innerHTML = originalText;
      btn.disabled = false;
    }, 2000);
  }).catch(function(err) {
    console.error('Failed to copy chat: ', err);
  });
}

// Show "Copied!" feedback on a message button
function showCopiedFeedback(index) {
  var container = document.getElementById('chat-messages');
  if (!container) return;
  var bubbles = container.querySelectorAll('.chat-message');
  if (bubbles[index]) {
    var copyBtn = bubbles[index].querySelector('[data-action="copy"]');
    if (copyBtn) {
      var originalHTML = copyBtn.innerHTML;
      copyBtn.innerHTML = '✅';
      setTimeout(function() { copyBtn.innerHTML = originalHTML; }, 2000);
    }
  }
}

// Format helpers
function formatNumber(n) {
  return n.toString().replace(/\B(?=(\d{3})+(?!\d))/g, ",");
}

// Compact number format: 1234567 -> "1.2m", 1234 -> "1.2k"
function formatCompact(n) {
  if (n >= 1000000) return (n / 1000000).toFixed(1).replace(/\.0$/, '') + 'm';
  if (n >= 1000) return (n / 1000).toFixed(1).replace(/\.0$/, '') + 'k';
  return String(n);
}

// Token usage bar
function showTokenUsageBar() {
  var bar = document.getElementById('token-usage-bar');
  var content = document.getElementById('token-usage-content');
  if (!bar || !content) return;

  // Always show zeros — updated by postThreadStats when data is available
  updateTokenUsage({
    activePathTokens: 0,
    contextWindow: 0,
    cumulativePromptTokens: 0,
    cumulativeCompletionTokens: 0,
    cumulativeCachedTokens: 0,
    cumulativeCost: 0,
    cumulativeInputCost: 0,
    cumulativeCachedInputCost: 0,
    cumulativeOutputCost: 0
  });
}

function updateTokenUsage(data) {
  var bar = document.getElementById('token-usage-bar');
  var content = document.getElementById('token-usage-content');
  if (!bar || !content) return;

  var cu = data.activePathTokens || 0;
  var cw = data.contextWindow || 0;
  var pt = data.cumulativeInputTokens || 0;
  var ct = data.cumulativeOutputTokens || 0;
  var ckt = data.cumulativeCachedTokens || 0;

  // Build pricing tooltip (per 1M tokens from UserConfig modelPricing)
  var pricingTip = '';
  if (data.pricingUnit && data.pricingUnit.input > 0) {
    var p = data.pricingUnit;
    pricingTip = '\n$' + p.input + '/1M input · $' + p.cachedInput + '/1M cached · $' + p.output + '/1M output';
  }

  var html = '';

  // Row 1: Context Used (current conversation tree)
  html += '<div class="tu-row" title="Context usage for the current conversation tree. Shows how much of the model\u2019s context window is filled by messages in this branch.">';
  html += '<span><span class="tu-label">🔢 Context Used:</span> ' +
    formatNumber(cu) + (cw ? ' / ' + formatNumber(cw) : '') +
    '</span></div>';

  // Row 2: Tokens ↑↓ (all branches)
  html += '<div class="tu-row" title="Input/output tokens across ALL conversation branches. Input includes cumulative prompt from each API request (context re-sent and billed per-request). Output is completion tokens only. Values come directly from API usage data.">';
  html += '<span><span class="tu-label">📊 Tokens</span> \u2191 ' + formatCompact(pt) +
    '  \u2193 ' + formatCompact(ct) +
    '</span></div>';

  // Row 3: Cache (all branches)
  html += '<div class="tu-row" title="Input tokens that were cache hits across ALL branches.">';
  html += '<span><span class="tu-label">💾 Cache</span> ' + formatCompact(ckt) + '</span></div>';

  // Row 4: API Cost (all branches, with pricing tooltip)
  var costTip = 'Total cost across all conversation branches.' + pricingTip;
  html += '<div class="tu-row tu-cost" title="' + costTip + '">';
  html += '<span><span class="tu-label">💲 API Cost</span>';
  html += ' $' + Number(data.cumulativeCost).toFixed(2);
  html += '  |  Input: $' + (Number(data.cumulativeInputCost) || 0).toFixed(4);
  html += '  |  Cached: $' + (Number(data.cumulativeCachedInputCost) || 0).toFixed(4);
  html += '  |  Output: $' + (Number(data.cumulativeOutputCost) || 0).toFixed(4);
  html += '</span></div>';

  content.innerHTML = html;
  bar.style.display = 'block';
}
