// ipc.js — typed WebView -> AHK messaging.
// Outgoing messages are validated against ipc-contract.js and carry a reqId.
// Ipc.request() resolves or rejects from the matching host acknowledgement.
(function(root, factory) {
  if (typeof module === 'object' && module.exports) module.exports = factory(require('./ipc-contract'));
  else root.Ipc = factory(root.IPCMessages);
})(typeof self !== 'undefined' ? self : this, function(IPCMessages) {
  'use strict';

  var nextReqId = 1;
  var pending = {}; // reqId -> { action, resolve, reject, timer }
  var DEFAULT_TIMEOUT_MS = 10000;

  function postToHost(action, payload) {
    var msg = { action: action };
    if (payload && typeof payload === 'object') {
      for (var k in payload) msg[k] = payload[k];
    }
    msg.reqId = 'r' + (nextReqId++);
    if (IPCMessages) {
      var problems = IPCMessages.validate(action, payload, 'web->ahk');
      if (problems.length) {
        console.error('[IPC] invalid outgoing message "' + action + '": ' + problems.join('; '));
      }
    }
    if (window.chrome && window.chrome.webview) {
      window.chrome.webview.postMessage(JSON.stringify(msg));
    }
    return msg.reqId;
  }

  // Send an action and resolve when AHK acknowledges it (or reject on ack
  // failure / timeout). The ack means "request received and handled", not
  // necessarily "long-running operation finished" (e.g. chatSend acks when
  // the stream starts).
  function request(action, payload, timeoutMs) {
    var reqId = postToHost(action, payload);
    return new Promise(function(resolve, reject) {
      var timer = setTimeout(function() {
        delete pending[reqId];
        reject(new Error('IPC timeout: "' + action + '" was not acknowledged within ' + (timeoutMs || DEFAULT_TIMEOUT_MS) + 'ms'));
      }, timeoutMs || DEFAULT_TIMEOUT_MS);
      // Keep node test processes from hanging on unacknowledged requests.
      if (timer && typeof timer.unref === 'function') timer.unref();
      pending[reqId] = { action: action, resolve: resolve, reject: reject, timer: timer };
    });
  }

  // Route an incoming "ack" message to its pending request.
  function handleAck(message) {
    if (!message || !message.data) return;
    var entry = pending[message.data.reqId];
    if (!entry) return;
    clearTimeout(entry.timer);
    delete pending[message.data.reqId];
    if (message.data.ok) {
      entry.resolve(message.data);
    } else {
      entry.reject(new Error(message.data.error || ('IPC error: "' + entry.action + '"')));
    }
  }

  return { postToHost: postToHost, request: request, handleAck: handleAck, pending: pending };
});
