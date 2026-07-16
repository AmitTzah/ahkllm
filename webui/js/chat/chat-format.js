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
    var originalHTML = btn.innerHTML;
    btn.innerHTML = '<i data-lucide="check" style="width:20px;height:20px;"></i>';
    if (typeof lucide !== 'undefined') lucide.createIcons();
    setTimeout(function() {
      btn.innerHTML = originalHTML;
      if (typeof lucide !== 'undefined') lucide.createIcons();
    }, 2000);
  }).catch(function(err) {
    console.error('Failed to copy chat: ', err);
  });
}

// Show checkmark feedback on a message's copy button
function showCopiedFeedback(index) {
  var container = document.getElementById('chat-messages');
  if (!container) return;
  var bubbles = container.querySelectorAll('.msg');
  if (bubbles[index]) {
    var copyBtn = bubbles[index].querySelector('.msg-action-btn[title="Copy"]');
    if (copyBtn) {
      var originalHTML = copyBtn.innerHTML;
      copyBtn.innerHTML = '<i data-lucide="check"></i>';
      if (typeof lucide !== 'undefined') lucide.createIcons();
      setTimeout(function() {
        copyBtn.innerHTML = originalHTML;
        if (typeof lucide !== 'undefined') lucide.createIcons();
      }, 2000);
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
  var bar = document.getElementById('tokenBar');
  if (!bar) return;

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
  var bar = document.getElementById('tokenBar');
  if (!bar) return;

  var cu = data.activePathTokens || 0;
  var cw = data.contextWindow || 0;
  var pt = data.cumulativeInputTokens || 0;
  var ct = data.cumulativeOutputTokens || 0;
  var ckt = data.cumulativeCachedTokens || 0;
  var cost = Number(data.cumulativeCost || 0).toFixed(2);

  // Cost gets dynamic breakdown; others get field explanation
  var costTip = 'Input: $' + (Number(data.cumulativeInputCost) || 0).toFixed(4) +
    '  |  Cached: $' + (Number(data.cumulativeCachedInputCost) || 0).toFixed(4) +
    '  |  Output: $' + (Number(data.cumulativeOutputCost) || 0).toFixed(4);

  bar.innerHTML =
    '<div class="tu-item" title="Context used from the active conversation path">' +
      '<i data-lucide="hash" class="tu-icon"></i>' +
      '<span class="tu-val">' + formatCompact(cu) + (cw ? ' / ' + formatCompact(cw) : '') + '</span>' +
    '</div>' +
    '<div class="tu-item" title="Culminative Input/output token usage across all conversation branches">' +
      '<i data-lucide="activity" class="tu-icon"></i>' +
      '<span class="tu-val">\u2191 ' + formatCompact(pt) + ' &nbsp;\u2193 ' + formatCompact(ct) + '</span>' +
    '</div>' +
    '<div class="tu-item" title="Input tokens that were cache hits">' +
      '<i data-lucide="database" class="tu-icon"></i>' +
      '<span class="tu-val">' + formatCompact(ckt) + '</span>' +
    '</div>' +
    '<div class="tu-item" title="' + costTip + '">' +
      '<i data-lucide="dollar-sign" class="tu-icon"></i>' +
      '<span class="tu-val">$' + cost + '</span>' +
    '</div>';

  if (typeof lucide !== 'undefined') lucide.createIcons();
}
