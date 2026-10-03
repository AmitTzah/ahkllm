/* Generic task controls; application-owned labels and explanations stay in the protocol. */
(function (root) {
  'use strict';
  var expandedByThread = {};

  function element(tag, className, text) {
    var node = document.createElement(tag);
    node.className = className;
    if (text) node.textContent = text;
    return node;
  }

  function actionButton(state, action, className) {
    var button = element('button', className, action.label);
    button.type = 'button';
    button.onclick = function () {
      if (action.confirm && !root.confirm(action.confirmation_message || action.description || action.label + '?')) return;
      button.disabled = true;
      root.Ipc.request(action.id === '__disconnect' ? 'applicationDisconnect' : 'applicationAction', {
        id: action.id, threadId: state.threadId, leafId: state.leafId
      }, 65000).catch(function () { button.disabled = false; });
    };
    return button;
  }

  function renderActions(body, state) {
    if (state.running) {
      body.appendChild(element('p', '', 'The model and its tools are working. You can hide this window or switch chats while they continue.'));
      return;
    }
    if (state.complete) body.appendChild(element('p', '', 'This task is finished. Your chat remains readable.'));
    if (state.awaitingFirstMessage) body.appendChild(element('p', '', 'Your context and tools are ready. Write your first message below, choose a model, and press Send. You can close this chat and return later.'));
    if (state.error) body.appendChild(element('p', '', state.error));
    if (state.notice) body.appendChild(element('p', '', state.notice));
    var actions = (state.actions || []).slice();
    if (state.pending && !state.complete && !state.error) actions.unshift({id:'__run',label:'Run prepared request',confirm:false});
    actions.forEach(function (action) {
      var row = element('div', 'chat-application-action');
      row.appendChild(actionButton(state, action, 'btn-sm'));
      if (action.description) row.appendChild(element('p', '', action.description));
      body.appendChild(row);
    });
    body.appendChild(actionButton(state, {
      id:'__disconnect', label:'Disconnect application', confirm:true,
      confirmation_message:'Disconnect this application? Saved chats stay readable, but its tools will be unavailable until you reconnect it.'
    }, 'chat-application-disconnect'));
  }

  root.showApplicationState = function (state) {
    if (state && state.threadId && root.activeThreadId && state.threadId !== root.activeThreadId) return;
    root._applicationState = state;
    var panel = document.getElementById('applicationPanel');
    if (!panel) {
      var input = document.getElementById('chat-input');
      var composer = input && input.closest('#chat-input-area');
      if (!composer) return;
      panel = element('details', 'chat-application-panel');
      panel.id = 'applicationPanel';
      composer.insertBefore(panel, composer.firstChild);
    }
    panel.replaceChildren();
    panel.style.display = state && state.connected ? '' : 'none';
    if (!state || !state.connected) return;
    var summary = element('summary', 'chat-application-summary');
    summary.appendChild(element('span', 'chat-application-title', state.label));
    var status = state.running ? 'Working…' : state.complete ? 'Finished' : state.error || state.blocked ? 'Needs attention' : state.awaitingFirstMessage ? 'Ready for your message' : state.pending ? 'Ready to start' : 'Active';
    summary.appendChild(element('span', 'chat-application-status', status));
    summary.onclick = function () { expandedByThread[state.threadId] = !panel.open; };
    panel.appendChild(summary);
    panel.open = state.blocked ? true : Object.prototype.hasOwnProperty.call(expandedByThread, state.threadId) ? expandedByThread[state.threadId] : !!(state.pending || state.awaitingFirstMessage || state.error);
    var body = element('div', 'chat-application-body');
    renderActions(body, state);
    panel.appendChild(body);
  };
})(typeof window !== 'undefined' ? window : globalThis);
