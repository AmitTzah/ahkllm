// ======================================================
// ipc.js - Typed WebView -> AHK sender.
//
// Every outgoing message goes through Ipc.postToHost,
// which validates the action + payload against the shared
// IPC contract (ipc-contract.js) and then posts it. This
// is the single choke point the WebView uses to talk to
// AHK, so the correlation-id/ack layer (step 2 of the IPC
// refactor) can be added here without touching call sites.
// ======================================================
(function(root, factory) {
  if (typeof module === 'object' && module.exports) module.exports = factory(require('./ipc-contract'));
  else root.Ipc = factory(root.IPCMessages);
})(typeof self !== 'undefined' ? self : this, function(IPCMessages) {
  'use strict';

  function postToHost(action, payload) {
    var msg = { action: action };
    if (payload && typeof payload === 'object') {
      for (var k in payload) msg[k] = payload[k];
    }
    if (IPCMessages) {
      var problems = IPCMessages.validate(action, payload, 'web->ahk');
      if (problems.length) {
        console.error('[IPC] invalid outgoing message "' + action + '": ' + problems.join('; '));
      }
    }
    if (window.chrome && window.chrome.webview) {
      window.chrome.webview.postMessage(JSON.stringify(msg));
    }
  }

  return { postToHost: postToHost };
});
