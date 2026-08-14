// ======================================================
// chat-lock.js — Tier-1 chat password locks
//
// The password is NEVER sent to AHK or stored anywhere.
// This module derives a PBKDF2-SHA-256 hash (Web Crypto,
// same API already used for attachment content hashes) and
// only the derived hash crosses the IPC boundary. AHK
// compares it constant-time against the stored hash and
// keeps the session unlock set.
//
// This is access control, not encryption at rest: the chat
// DB still holds plaintext content (Tier-2 encryption is a
// separate follow-up).
// ======================================================

var _lockIterations = 600000;
// threadId -> { salt, iterations } known to this page (from threadLocked /
// threadLockInfo). Used to derive the CURRENT password hash for
// change/remove flows.
var _lockInfo = {};
var _lockOverlayState = { threadId: '', salt: '', iterations: _lockIterations };
var _lockBusy = false;
var _lockComposerState = { inputDisabled: null, sendDisabled: null, scopedDisabled: null };

// ---------- KDF helpers (Web Crypto) ----------

function _bytesToHex(bytes) {
  var out = '';
  for (var i = 0; i < bytes.length; i++)
    out += (bytes[i] < 16 ? '0' : '') + bytes[i].toString(16);
  return out;
}

function _hexToBytes(hex) {
  var out = new Uint8Array(hex.length / 2);
  for (var i = 0; i < out.length; i++)
    out[i] = parseInt(hex.substr(i * 2, 2), 16);
  return out;
}

function _randomSaltHex() {
  var salt = new Uint8Array(16);
  crypto.getRandomValues(salt);
  return _bytesToHex(salt);
}

// PBKDF2-SHA-256, 256-bit output. Returns a Promise of a lowercase hex string.
function derivePasswordHash(password, saltHex, iterations) {
  var enc = new TextEncoder();
  return crypto.subtle.importKey('raw', enc.encode(password), 'PBKDF2', false, ['deriveBits'])
    .then(function(keyMaterial) {
      return crypto.subtle.deriveBits(
        { name: 'PBKDF2', hash: 'SHA-256', salt: _hexToBytes(saltHex), iterations: iterations },
        keyMaterial, 256
      );
    })
    .then(function(bits) {
      return _bytesToHex(new Uint8Array(bits));
    });
}

// Length-stable comparison: XOR every character so timing does not leak the
// position of the first differing byte.
function _constantTimeEquals(a, b) {
  var len = Math.max(a.length, b.length);
  var diff = 0;
  for (var i = 0; i < len; i++) {
    var ca = i < a.length ? a.charCodeAt(i) : 0;
    var cb = i < b.length ? b.charCodeAt(i) : 0;
    diff |= ca ^ cb;
  }
  return diff === 0;
}

// ---------- Locked-thread overlay ----------

function handleThreadLocked(data) {
  var threadId = data && data.threadId;
  if (!threadId) return;

  _lockOverlayState = {
    threadId: threadId,
    salt: data.salt || '',
    iterations: data.iterations || _lockIterations
  };
  _lockInfo[threadId] = { salt: _lockOverlayState.salt, iterations: _lockOverlayState.iterations };

  // Wipe any previous chat content from memory and DOM — a locked thread must
  // never sit on top of another thread's rendered messages.
  chatMessages = [];
  var pane = document.getElementById('chat-messages');
  if (pane) pane.innerHTML = '';

  activeThreadId = threadId;
  if (!_threadMeta[threadId]) _threadMeta[threadId] = {};
  _threadMeta[threadId].title = 'Locked chat';
  updateTopbarTitle();
  if (typeof _setActiveHighlight === 'function') _setActiveHighlight(threadId);
  if (typeof updateScopedSearchState === 'function') updateScopedSearchState();

  _disableComposerForLock();
  _showThreadLockOverlay();
}

function handleThreadLockInfo(data) {
  if (!data || !data.threadId) return;
  _lockInfo[data.threadId] = {
    salt: data.salt || '',
    iterations: data.iterations || _lockIterations
  };
}

function _showThreadLockOverlay() {
  var existing = document.getElementById('threadLockOverlay');
  if (existing) existing.remove();

  var overlay = document.createElement('div');
  overlay.id = 'threadLockOverlay';
  overlay.className = 'thread-lock-overlay';
  overlay.innerHTML =
    '<div class="thread-lock-box">' +
      '<div class="thread-lock-icon"><i data-lucide="lock" style="width:44px;height:44px;"></i></div>' +
      '<div class="thread-lock-title">This chat is locked</div>' +
      '<div class="thread-lock-sub">Enter the password to view it.</div>' +
      '<input class="thread-lock-input" id="lockPasswordInput" type="password" placeholder="Password" autocomplete="off">' +
      '<div class="thread-lock-error" id="lockError"></div>' +
      '<div class="thread-lock-row">' +
        '<button class="btn-primary" id="lockUnlockBtn">Unlock</button>' +
      '</div>' +
    '</div>';
  document.body.appendChild(overlay);

  var input = document.getElementById('lockPasswordInput');
  input.addEventListener('keydown', function(e) {
    if (e.key === 'Enter') _submitUnlock();
  });
  document.getElementById('lockUnlockBtn').addEventListener('click', _submitUnlock);
  setTimeout(function() { input.focus(); }, 0);
  if (typeof lucide !== 'undefined') lucide.createIcons();
}

function clearThreadLockOverlay() {
  var overlay = document.getElementById('threadLockOverlay');
  if (overlay) overlay.remove();
  _lockOverlayState = { threadId: '', salt: '', iterations: _lockIterations };
  _lockBusy = false;
  _restoreComposerForLock();
}

function _disableComposerForLock() {
  var input = document.getElementById('chat-input');
  var send = document.getElementById('chat-send-btn');
  var scoped = document.querySelector('.search-wrap.in-panel .search-input');
  _lockComposerState = {
    inputDisabled: input ? input.disabled : null,
    sendDisabled: send ? send.disabled : null,
    scopedDisabled: scoped ? scoped.disabled : null
  };
  if (input) input.disabled = true;
  if (send) send.disabled = true;
  if (scoped) scoped.disabled = true;
}

function _restoreComposerForLock() {
  var input = document.getElementById('chat-input');
  var send = document.getElementById('chat-send-btn');
  var scoped = document.querySelector('.search-wrap.in-panel .search-input');
  if (input) input.disabled = !!_lockComposerState.inputDisabled;
  if (send) send.disabled = !!_lockComposerState.sendDisabled;
  if (scoped) scoped.disabled = !!_lockComposerState.scopedDisabled;
}

async function _submitUnlock() {
  if (_lockBusy) return;
  var input = document.getElementById('lockPasswordInput');
  var err = document.getElementById('lockError');
  if (!input || !err) return;
  var password = input.value;
  if (!password) {
    err.textContent = 'Enter a password.';
    return;
  }
  if (!_lockOverlayState.salt) {
    err.textContent = 'No lock data for this chat.';
    return;
  }

  _lockBusy = true;
  var btn = document.getElementById('lockUnlockBtn');
  if (btn) btn.disabled = true;
  try {
    var hash = await derivePasswordHash(password, _lockOverlayState.salt, _lockOverlayState.iterations);
    await Ipc.request('unlockThread', { threadId: _lockOverlayState.threadId, passwordHash: hash });
    // Success: AHK responds by loading the thread normally (initChatMode),
    // which clears the overlay via main.js.
    input.value = '';
  } catch (e) {
    err.textContent = (e && e.message) ? e.message : 'Incorrect password.';
    input.value = '';
    input.focus();
  } finally {
    _lockBusy = false;
    if (btn) btn.disabled = false;
  }
}

// ---------- Lock modal (set / change / remove) ----------

function openThreadLockModal(threadId, mode) {
  if (!threadId) return;
  mode = mode === 'change' ? 'change' : 'set';
  var existing = document.getElementById('threadLockModal');
  if (existing) existing.remove();

  var info = _lockInfo[threadId] || { salt: '', iterations: _lockIterations };
  var html =
    '<div class="modal-overlay open" id="threadLockModal">' +
    '<div class="modal-box" style="max-width:420px;">' +
      '<div class="modal-head"><div class="modal-title">' +
        (mode === 'set' ? 'Protect this chat' : 'Change chat lock') +
      '</div><button class="icon-btn" id="lockModalClose"><i data-lucide="x"></i></button></div>' +
      '<div class="modal-body">';

  if (mode === 'change') {
    html +=
      '<div class="field"><label class="field-label">Current Password</label>' +
      '<input class="thread-lock-input" id="lockModalCurrent" type="password" autocomplete="off"></div>';
  }

  if (mode === 'set') {
    html +=
      '<div class="thread-lock-sub">Only you can open this chat. A forgotten password cannot be recovered in-app.</div>';
  } else {
    html += '<div class="thread-lock-sub">Leave the new fields empty and press "Remove password" to unlock this chat for good.</div>';
  }

  html +=
    '<div class="field"><label class="field-label">' + (mode === 'set' ? 'Password' : 'New Password') + '</label>' +
    '<input class="thread-lock-input" id="lockModalNew" type="password" autocomplete="new-password"></div>' +
    '<div class="field"><label class="field-label">Confirm Password</label>' +
    '<input class="thread-lock-input" id="lockModalConfirm" type="password" autocomplete="new-password"></div>' +
    '<div class="thread-lock-error" id="lockModalError"></div>' +
    '</div>' +
    '<div class="modal-foot">' +
      (mode === 'change'
        ? '<button class="btn-ghost" id="lockModalRemove">Remove password</button>'
        : '') +
      '<span style="flex:1"></span>' +
      '<button class="btn-ghost" id="lockModalCancel">Cancel</button>' +
      '<button class="btn-primary" id="lockModalSave">' + (mode === 'set' ? 'Lock chat' : 'Save new password') + '</button>' +
    '</div>' +
  '</div></div>';

  var wrap = document.createElement('div');
  wrap.innerHTML = html;
  document.body.appendChild(wrap.firstChild);

  _wireLockModal(threadId, mode, info);
  if (typeof lucide !== 'undefined') lucide.createIcons();
}

function _wireLockModal(threadId, mode, info) {
  var close = function() {
    var m = document.getElementById('threadLockModal');
    if (m) m.remove();
  };
  document.getElementById('lockModalClose').addEventListener('click', close);
  document.getElementById('lockModalCancel').addEventListener('click', close);
  document.getElementById('lockModalSave').addEventListener('click', function() {
    _submitLockModal(threadId, mode, info);
  });
  var removeBtn = document.getElementById('lockModalRemove');
  if (removeBtn) removeBtn.addEventListener('click', function() {
    _submitLockModal(threadId, 'remove', info);
  });
  ['lockModalCurrent', 'lockModalNew', 'lockModalConfirm'].forEach(function(id) {
    var el = document.getElementById(id);
    if (el) el.addEventListener('keydown', function(e) {
      if (e.key === 'Enter') _submitLockModal(threadId, mode, info);
    });
  });
}

async function _submitLockModal(threadId, mode, info) {
  if (_lockBusy) return;
  var err = document.getElementById('lockModalError');
  if (!err) return;
  err.textContent = '';

  var current = (document.getElementById('lockModalCurrent') || {}).value || '';
  var next = (document.getElementById('lockModalNew') || {}).value || '';
  var confirm = (document.getElementById('lockModalConfirm') || {}).value || '';

  if (mode === 'remove' && !current) {
    err.textContent = 'Enter your current password.';
    return;
  }
  if ((mode === 'set' || mode === 'change') && (!next || next !== confirm)) {
    err.textContent = 'Passwords do not match.';
    return;
  }
  if ((mode === 'set' || mode === 'change') && next.length < 4) {
    err.textContent = 'Use at least 4 characters.';
    return;
  }

  _lockBusy = true;
  var saveBtn = document.getElementById('lockModalSave');
  if (saveBtn) saveBtn.disabled = true;
  try {
    var payload = {
      threadId: threadId,
      mode: mode,
      passwordHash: '',
      salt: '',
      iterations: info.iterations || _lockIterations,
      currentPasswordHash: ''
    };
    if (mode === 'remove') {
      payload.currentPasswordHash = await derivePasswordHash(current, info.salt, info.iterations);
    } else {
      payload.salt = _randomSaltHex();
      payload.iterations = _lockIterations;
      payload.passwordHash = await derivePasswordHash(next, payload.salt, payload.iterations);
      if (mode === 'change')
        payload.currentPasswordHash = await derivePasswordHash(current, info.salt, info.iterations);
    }
    await Ipc.request('setThreadLock', payload);
    var m = document.getElementById('threadLockModal');
    if (m) m.remove();
  } catch (e) {
    err.textContent = (e && e.message) ? e.message : 'Failed to update the lock.';
  } finally {
    _lockBusy = false;
    if (saveBtn) saveBtn.disabled = false;
  }
}
