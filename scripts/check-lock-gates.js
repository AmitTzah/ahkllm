// ======================================================
// check-lock-gates.js - Static guard for the locked-chats feature.
//
// Fails when a refactor removes a lock gate or a plaintext redaction, so a
// future handler can never silently bypass the password lock again. Run as
// part of `npm run test:fast` (test:lockgates).
// ======================================================
'use strict';
const fs = require('node:fs');
const path = require('node:path');

const ROOT = path.resolve(__dirname, '..');
const read = (p) => fs.readFileSync(path.join(ROOT, p), 'utf8');
let ok = true;
const fail = (msg) => { ok = false; console.error('FAIL: ' + msg); };

function sectionBetween(src, startMarker, endMarker) {
  const s = src.indexOf(startMarker);
  if (s < 0) return '';
  const e = src.indexOf(endMarker, s);
  return e > s ? src.slice(s, e) : src.slice(s);
}

// 1. Every thread-content action must be listed in the Dispatch gate, and the
//    gate must actually run against the active thread.
const EXPECTED_GATED_ACTIONS = [
  'chatSend', 'retry', 'editMessage', 'deleteMessage', 'deleteAttachment',
  'forkChat', 'switchBranch', 'updateModelSettings', 'switchAssistant',
  'updateFontSize', 'requestCurrentSettings'
];
const dispatch = read('chat/callbacks/Dispatch.ahk');
if (!/ThreadLockService\.RequireUnlocked\(activeThreadId\)/.test(dispatch))
  fail('Dispatch.ahk no longer calls ThreadLockService.RequireUnlocked(activeThreadId)');
const dispatchGate = sectionBetween(
  dispatch, '_IsLockedThreadContentAction(action, parsed)', 'return false\n}');
if (!dispatchGate)
  fail('Dispatch.ahk is missing _IsLockedThreadContentAction');
for (const a of EXPECTED_GATED_ACTIONS) {
  if (!new RegExp('case "' + a + '"').test(dispatchGate))
    fail('Dispatch gate is missing action "' + a + '"');
}
if (!/return parsed\.Has\("threadId"\)/.test(dispatchGate))
  fail('Dispatch gate must block scoped (threadId-carrying) searches');
if (!/return sub = "loadTree"/.test(dispatchGate))
  fail('Dispatch gate must block loadTree for a locked active thread');

// 2. The unified thread loader must refuse to load locked content.
const chatUtils = read('chat/ChatUtils.ahk');
if (!/ThreadLockService\.IsLocked\(threadId\) && !ThreadLockService\.IsUnlockedInSession\(threadId\)/.test(chatUtils))
  fail('_LoadThreadAndRefreshUI lock gate missing');
if (!/_postLockedThreadState\(threadId\)/.test(chatUtils))
  fail('_postLockedThreadState missing');

// 3. Sidebar must redact locked titles and report the lock flag.
const threadRepo = read('chat/db/ThreadRepo.ahk');
if (!/title: isLocked \? "Locked chat" : row\.title/.test(threadRepo))
  fail('Thread_List title redaction missing');
if (!/t\.is_locked/.test(threadRepo))
  fail('Thread_List does not select is_locked');

// 4. All three search phases (FTS5, LIKE, titles) must exclude locked threads.
const searchRepo = read('chat/db/SearchRepo.ahk');
const lockedFilters = (searchRepo.match(/t\.is_locked=0/g) || []).length;
if (lockedFilters < 3)
  fail('SearchRepo excludes locked threads in only ' + lockedFilters + '/3 queries');

// 5. In-flight streams must not paint into a locked chat, and API logs must
//    redact locked-chat request/response bodies.
const streamHandler = read('chat/streaming/StreamHandler.ahk');
if (!/ThreadLockService\.IsLocked\(requestParams\["_streamThreadId"\]\)/.test(streamHandler))
  fail('_shouldPostStreamToUI lock gate missing');
for (const f of ['chat/streaming/StreamCompletion.ahk', 'chat/streaming/StreamError.ahk']) {
  const src = read(f);
  if (!/"<hidden: locked chat>"/.test(src))
    fail(f + ' API-log redaction missing');
}

// 6. Deleting a locked chat requires the unlock.
const sidebar = read('chat/callbacks/Sidebar.ahk');
const deleteGates = (sidebar.match(/ThreadLockService\.RequireUnlocked\(threadId\)/g) || []).length;
if (deleteGates < 2)
  fail('Sidebar delete actions not gated (' + deleteGates + '/2)');

// 7. The IPC contract declares every lock message.
const contract = read('webui/js/shared/ipc-contract.js');
for (const msg of ['threadLocked', 'threadLockInfo', 'unlockThread', 'setThreadLock']) {
  if (!new RegExp("'" + msg + "'").test(contract))
    fail('IPC contract missing "' + msg + '"');
}

if (ok) {
  console.log('Lock gates OK: ' + EXPECTED_GATED_ACTIONS.length + ' gated actions, load/search/stream/log/sidebar guards present');
  process.exit(0);
}
process.exit(1);
