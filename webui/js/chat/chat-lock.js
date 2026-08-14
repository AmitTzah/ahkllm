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
// threadId -> resolve callback for a pending getThreadLockInfo request.
var _lockInfoWaiters = {};
var _lockOverlayState = { threadId: '', salt: '', iterations: _lockIterations };
var _lockBusy = false;
var _lockEscapeHandler = null;
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

// ---------- Lock metadata ----------

function handleThreadLockInfo(data) {
  if (!data || !data.threadId) return;
  _lockInfo[data.threadId] = {
    salt: data.salt || '',
    iterations: data.iterations || _lockIterations
  };
  if (_lockInfoWaiters[data.threadId]) {
    _lockInfoWaiters[data.threadId](_lockInfo[data.threadId]);
    delete _lockInfoWaiters[data.threadId];
  }
}

// Resolve a thread's lock metadata, fetching it from AHK when this page has
// never seen it (e.g. the sidebar lock menu opens "Change password" on a chat
// that was never opened).
function requestLockInfo(threadId) {
  if (_lockInfo[threadId]) return Promise.resolve(_lockInfo[threadId]);
  return new Promise(function(resolve, reject) {
    _lockInfoWaiters[threadId] = resolve;
    setTimeout(function() {
      if (_lockInfoWaiters[threadId]) {
        delete _lockInfoWaiters[threadId];
        reject(new Error('Timed out loading lock information.'));
      }
    }, 10000);
    Ipc.postToHost('getThreadLockInfo', { threadId: threadId });
  });
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

function _showThreadLockOverlay() {
  var existing = document.getElementById('threadLockOverlay');
  if (existing) existing.remove();

  var overlay = document.createElement('div');
  overlay.id = 'threadLockOverlay';
  overlay.className = 'thread-lock-overlay';
  overlay.innerHTML =
    '<div class="thread-lock-box">' +
      '<button class="icon-btn thread-lock-close" id="lockOverlayClose" title="Close (Esc)"><i data-lucide="x"></i></button>' +
      '<div class="thread-lock-icon"><i data-lucide="lock" style="width:44px;height:44px;"></i></div>' +
      '<div class="thread-lock-title">This chat is locked</div>' +
      '<div class="thread-lock-sub">Enter the password to view it.</div>' +
      '<input class="thread-lock-input" id="lockPasswordInput" type="password" placeholder="Password" autocomplete="off">' +
      '<div class="thread-lock-error" id="lockError"></div>' +
      '<div class="thread-lock-row">' +
        '<button class="btn-ghost" id="lockOverlayCancel">Cancel</button>' +
        '<button class="btn-primary" id="lockUnlockBtn">Unlock</button>' +
      '</div>' +
    '</div>';
  document.body.appendChild(overlay);

  var input = document.getElementById('lockPasswordInput');
  input.addEventListener('keydown', function(e) {
    if (e.key === 'Enter') _submitUnlock();
    if (e.key === 'Escape') _dismissLockedOverlay();
  });
  document.getElementById('lockUnlockBtn').addEventListener('click', _submitUnlock);
  document.getElementById('lockOverlayCancel').addEventListener('click', _dismissLockedOverlay);
  document.getElementById('lockOverlayClose').addEventListener('click', _dismissLockedOverlay);

  // Escape anywhere dismisses the prompt (no remembered password = exit).
  if (!_lockEscapeHandler) {
    _lockEscapeHandler = function(e) {
      if (e.key === 'Escape') _dismissLockedOverlay();
    };
    document.addEventListener('keydown', _lockEscapeHandler);
  }

  setTimeout(function() { input.focus(); }, 0);
  if (typeof lucide !== 'undefined') lucide.createIcons();
}

function clearThreadLockOverlay() {
  var overlay = document.getElementById('threadLockOverlay');
  if (overlay) overlay.remove();
  _lockOverlayState = { threadId: '', salt: '', iterations: _lockIterations };
  _lockBusy = false;
  _restoreComposerForLock();
  if (_lockEscapeHandler) {
    document.removeEventListener('keydown', _lockEscapeHandler);
    _lockEscapeHandler = null;
  }
}

// Exit the lock prompt without opening the chat: tell AHK to drop the active
// thread and reset the local UI to the empty state.
function _dismissLockedOverlay() {
  if (_lockOverlayState.threadId)
    Ipc.postToHost('dismissLockedThread', {});
  clearThreadLockOverlay();
  activeThreadId = '';
  updateTopbarTitle();
  if (typeof updateScopedSearchState === 'function') updateScopedSearchState();
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

  var isSet = mode === 'set';
  var html =
    '<div class="modal-overlay open" id="threadLockModal" style="z-index:210;">' +
    '<div class="modal-box lock-modal-box">' +
      '<div class="modal-head">' +
        '<div class="modal-title">' + (isSet ? 'Protect this chat' : 'Change chat lock') + '</div>' +
        '<button class="icon-btn" id="lockModalClose"><i data-lucide="x"></i></button>' +
      '</div>' +
      '<div class="lock-modal-body">' +
        '<div class="lock-modal-hint">' +
          (isSet
            ? 'Only you can open this chat. A forgotten password cannot be recovered in-app.'
            : 'Enter your current password, then set a new one or remove the lock.') +
        '</div>' +
        (mode === 'change'
          ? '<div class="field"><label class="field-label" for="lockModalCurrent">Current password</label>' +
            '<input class="lock-input" id="lockModalCurrent" type="password" autocomplete="off"></div>'
          : '') +
        '<div class="field"><label class="field-label" for="lockModalNew">' +
          (isSet ? 'Password' : 'New password') + '</label>' +
          '<input class="lock-input" id="lockModalNew" type="password" autocomplete="new-password"></div>' +
        '<div class="field"><label class="field-label" for="lockModalConfirm">Confirm password</label>' +
          '<input class="lock-input" id="lockModalConfirm" type="password" autocomplete="new-password"></div>' +
        '<div class="thread-lock-error" id="lockModalError"></div>' +
      '</div>' +
      '<div class="modal-foot">' +
        (mode === 'change'
          ? '<button class="btn-ghost lock-remove-btn" id="lockModalRemove">Remove password</button>'
          : '') +
        '<span style="flex:1"></span>' +
        '<button class="btn-ghost" id="lockModalCancel">Cancel</button>' +
        '<button class="btn-primary" id="lockModalSave">' + (isSet ? 'Lock chat' : 'Save password') + '</button>' +
      '</div>' +
    '</div></div>';

  var wrap = document.createElement('div');
  wrap.innerHTML = html;
  document.body.appendChild(wrap.firstChild);

  _wireLockModal(threadId, mode);

  // Change/remove needs the CURRENT salt to derive the current-password hash;
  // keep the submit buttons disabled until the metadata arrives.
  if (!isSet && !_lockInfo[threadId]) {
    var saveBtn = document.getElementById('lockModalSave');
    var removeBtn = document.getElementById('lockModalRemove');
    if (saveBtn) saveBtn.disabled = true;
    if (removeBtn) removeBtn.disabled = true;
    requestLockInfo(threadId).then(function() {
      if (document.getElementById('threadLockModal') === null) return;
      if (saveBtn) saveBtn.disabled = false;
      if (removeBtn) removeBtn.disabled = false;
    }).catch(function(e) {
      var err = document.getElementById('lockModalError');
      if (err) err.textContent = e && e.message ? e.message : 'Failed to load lock information.';
    });
  }

  if (typeof lucide !== 'undefined') lucide.createIcons();
}

function _wireLockModal(threadId, mode) {
  var close = function() {
    var m = document.getElementById('threadLockModal');
    if (m) m.remove();
  };
  document.getElementById('lockModalClose').addEventListener('click', close);
  document.getElementById('lockModalCancel').addEventListener('click', close);
  document.getElementById('lockModalSave').addEventListener('click', function() {
    _submitLockModal(threadId, mode);
  });
  var removeBtn = document.getElementById('lockModalRemove');
  if (removeBtn) removeBtn.addEventListener('click', function() {
    _submitLockModal(threadId, 'remove');
  });
  ['lockModalCurrent', 'lockModalNew', 'lockModalConfirm'].forEach(function(id) {
    var el = document.getElementById(id);
    if (el) el.addEventListener('keydown', function(e) {
      if (e.key === 'Enter') _submitLockModal(threadId, mode);
    });
  });
}

async function _submitLockModal(threadId, mode) {
  if (_lockBusy) return;
  var err = document.getElementById('lockModalError');
  if (!err) return;
  err.textContent = '';

  var info = _lockInfo[threadId] || { salt: '', iterations: _lockIterations };
  if ((mode === 'change' || mode === 'remove') && !info.salt) {
    err.textContent = 'Lock information is still loading.';
    return;
  }

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
    // Keep the page's salt/iterations in sync so a follow-up change/remove
    // derives the CURRENT password hash with the CURRENT salt.
    if (mode === 'set' || mode === 'change') {
      _lockInfo[threadId] = { salt: payload.salt, iterations: payload.iterations };
    }
    var m = document.getElementById('threadLockModal');
    if (m) m.remove();
  } catch (e) {
    err.textContent = (e && e.message) ? e.message : 'Failed to update the lock.';
  } finally {
    _lockBusy = false;
    if (saveBtn) saveBtn.disabled = false;
  }
}

// ---------- Sidebar lock menu (Lock / Unlock / Change password) ----------

function _makeLockMenuItem(action, icon, label, disabled, stateLabel) {
  var btn = document.createElement('button');
  btn.className = 'lock-menu-item';
  btn.setAttribute('data-action', action);
  if (disabled) btn.disabled = true;
  btn.innerHTML =
    '<i data-lucide="' + icon + '"></i>' +
    '<span class="lock-menu-label">' + escHtml(label) + '</span>' +
    (stateLabel ? '<span class="lock-menu-state">' + escHtml(stateLabel) + '</span>' : '');
  return btn;
}

// t is the sidebar thread row ({ id, title, is_locked }). A locked chat whose
// title is still the redacted placeholder has not been unlocked this session.
function openLockMenu(threadId, anchorEl, t) {
  var existing = document.getElementById('lockMenuDropdown');
  if (existing) existing.remove();

  var locked = !!t.is_locked;
  var hidden = locked && t.title === 'Locked chat';

  var dd = document.createElement('div');
  dd.id = 'lockMenuDropdown';
  dd.className = 'lock-menu-dropdown';
  dd.appendChild(_makeLockMenuItem('lock', 'lock', 'Lock Chat', hidden, hidden ? 'already locked' : ''));
  dd.appendChild(_makeLockMenuItem('unlock', 'unlock', 'Unlock Chat', !hidden, ''));
  var sep = document.createElement('div');
  sep.className = 'lock-menu-sep';
  dd.appendChild(sep);
  dd.appendChild(_makeLockMenuItem('change', 'key-round', 'Change password / remove lock', !locked, ''));

  var rect = anchorEl.getBoundingClientRect();
  dd.style.left = Math.max(8, rect.left - 190) + 'px';
  dd.style.top = (rect.bottom + 6) + 'px';
  document.body.appendChild(dd);

  dd.addEventListener('click', function(e) {
    var btn = e.target.closest('.lock-menu-item');
    if (!btn || btn.disabled) return;
    var action = btn.getAttribute('data-action');
    dd.remove();
    if (action === 'lock') {
      if (locked) Ipc.postToHost('lockChatNow', { threadId: threadId });
      else openThreadLockModal(threadId, 'set');
    } else if (action === 'unlock') {
      if (typeof loadThread === 'function') loadThread(threadId);
    } else if (action === 'change') {
      openThreadLockModal(threadId, 'change');
    }
  });

  var closeMenu = function(ev2) {
    if (!dd.contains(ev2.target) && ev2.target !== anchorEl) {
      dd.remove();
      document.removeEventListener('click', closeMenu);
      document.removeEventListener('keydown', closeMenu);
    }
  };
  setTimeout(function() {
    document.addEventListener('click', closeMenu);
    document.addEventListener('keydown', function escMenu(e2) {
      if (e2.key === 'Escape') {
        dd.remove();
        document.removeEventListener('click', closeMenu);
        document.removeEventListener('keydown', escMenu);
      }
    });
  }, 0);

  if (typeof lucide !== 'undefined') lucide.createIcons();
}
