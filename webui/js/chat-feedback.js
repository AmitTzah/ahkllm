// ======================================================
// chat-feedback.js — D8: Message feedback (thumbs up/down on assistant msgs)
// ======================================================

function addFeedbackButtons(actionsContainer, msg, index) {
  if (msg.role !== 'assistant') return;

  var feedbackGroup = document.createElement('span');
  feedbackGroup.className = 'feedback-group';
  feedbackGroup.style.cssText = 'display:inline-flex;align-items:center;margin-left:auto;gap:2px;';

  var upBtn = document.createElement('button');
  upBtn.style.cssText = 'background:none;border:1px solid var(--bs-border-color);border-radius:0.25rem;padding:1px 6px;cursor:pointer;font-size:0.75rem;';
  upBtn.textContent = '👍';
  upBtn.title = 'Thumbs up';
  if (msg.feedback === 1) upBtn.style.backgroundColor = 'rgba(25,135,84,0.2)';

  var downBtn = document.createElement('button');
  downBtn.style.cssText = 'background:none;border:1px solid var(--bs-border-color);border-radius:0.25rem;padding:1px 6px;cursor:pointer;font-size:0.75rem;';
  downBtn.textContent = '👎';
  downBtn.title = 'Thumbs down';
  if (msg.feedback === -1) downBtn.style.backgroundColor = 'rgba(220,53,69,0.2)';

  upBtn.addEventListener('click', function(e) {
    e.stopPropagation();
    var rating = msg.feedback === 1 ? 0 : 1;
    setFeedback(msg.id, rating, upBtn, downBtn, msg);
  });

  downBtn.addEventListener('click', function(e) {
    e.stopPropagation();
    var rating = msg.feedback === -1 ? 0 : -1;
    setFeedback(msg.id, rating, upBtn, downBtn, msg);
  });

  feedbackGroup.appendChild(upBtn);
  feedbackGroup.appendChild(downBtn);
  actionsContainer.appendChild(feedbackGroup);
}

function setFeedback(msgId, rating, upBtn, downBtn, msg) {
  window.chrome.webview.postMessage(JSON.stringify({
    action: 'setFeedback',
    id: msgId,
    rating: rating
  }));

  // Update local state
  msg.feedback = rating;

  // Update visual state
  if (rating === 1) {
    upBtn.style.backgroundColor = 'rgba(25,135,84,0.2)';
    downBtn.style.backgroundColor = 'transparent';
  } else if (rating === -1) {
    downBtn.style.backgroundColor = 'rgba(220,53,69,0.2)';
    upBtn.style.backgroundColor = 'transparent';
  } else {
    upBtn.style.backgroundColor = 'transparent';
    downBtn.style.backgroundColor = 'transparent';
  }
}