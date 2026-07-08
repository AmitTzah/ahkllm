// ======================================================
// chat-feedback.js — D8: Message feedback (thumbs up/down on assistant msgs)
// ======================================================

function setFeedback(msgId, rating, upBtn, downBtn, msg) {
  window.chrome.webview.postMessage(JSON.stringify({
    action: 'setFeedback',
    id: msgId,
    rating: rating
  }));

  // Update local state
  msg.feedback = rating;

  // Update visual state using CSS classes
  upBtn.classList.remove('feedback-active-up');
  downBtn.classList.remove('feedback-active-down');

  if (rating === 1) {
    upBtn.classList.add('feedback-active-up');
  } else if (rating === -1) {
    downBtn.classList.add('feedback-active-down');
  }
}
