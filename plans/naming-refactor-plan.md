# Naming & Structure Refactor Plan — Round 2

## Function Size Ranking (Application Code, >15 lines)

### Top 10 Largest Functions
| # | Function | Lines | File | Action |
|---|----------|-------|------|--------|
| 1 | `BuildAndWriteRequestFiles()` | 108 | chat/ChatRequestBuilder.ahk | Split into 4 helpers |
| 2 | `generateThreadTitle()` | 96 | chat/ChatUtils.ahk | Extract to own file + split |
| 3 | `sidebarActionFromWebView()` | 82 | chat/ChatCallbacks_Sidebar.ahk | Each subAction → own function |
| 4 | `saveStreamResponse()` | 69 | chat/StreamHandler.ahk | Split into persist + log |
| 5 | `_handleStreamError()` | 58 | chat/StreamHandler.ahk | Extract error parsing |
| 6 | `retryAction()` | 50 | chat/ChatCallbacks_Branch.ahk | Split setup + fire |
| 7 | `buildCommandMenu()` | 49 | app/CommandMenu.ahk | Borderline, leave |
| 8 | `switchAssistantFromWebView()` | 48 | chat/ChatSettings.ahk | Borderline, leave |
| 9 | `_handleStreamCancelled()` | 47 | chat/StreamHandler.ahk | Borderline, leave |
| 10 | `sendStreamingRequest()` | 46 | chat/StreamHandler.ahk | Borderline, leave |

---

## Phase 1: Split Top 3 Largest Functions

### 1a: `BuildAndWriteRequestFiles()` (108 lines) → 4 helpers
```
BuildAndWriteRequestFiles() → orchestrator (~15 lines)
  ├── _validateProvider(providerInfo) → checks API key
  ├── _buildMessagesArray() → constructs messages from DB
  ├── _applyOverrides(requestObj, providerInfo) → system/reasoning/temp/Google
  └── _writeRequestFiles(payload) → temp file creation
```

### 1b: `generateThreadTitle()` (96 lines) → 3 helpers  
Already being extracted to `ThreadTitleGen.ahk`. Further split:
```
generateThreadTitle(threadId) → orchestrator (~15 lines)
  ├── _buildTitleRequest() → prompt + JSON
  ├── _executeTitleGen() → cURL + wait
  └── _parseTitleResponse() → extract title from response
```

### 1c: `sidebarActionFromWebView()` (82 lines) → per-action functions
```
handleSidebarAction(params) → dispatch (~10 lines)
  ├── _loadThreadList()
  ├── _loadTrashList()
  ├── _loadThread(threadId)
  ├── _navigateToMessage(messageId)
  ├── _newChat()
  ├── _softDeleteThread(threadId)
  ├── _restoreThread(threadId)
  ├── _hardDeleteThread(threadId)
  ├── _emptyTrash()
  └── _renameThread(threadId, title)
```

---

## Phase 2: Fix Generic Function Names

### Drop "FromWebView" suffix (all callbacks)
| Current | New |
|---------|-----|
| `chatSendFromWebView()` | `handleChatSend()` |
| `retryFromWebView()` | `handleRetry()` |
| `editMessageFromWebView()` | `handleEdit()` |
| `deleteMessageFromWebView()` | `handleDelete()` |
| `switchBranchFromWebView()` | `handleBranchSwitch()` |
| `forkChatFromWebView()` | `handleFork()` |
| `setFeedbackFromWebView()` | `handleFeedback()` |
| `cancelStreamFromWebView()` | `handleCancelStream()` |
| `sidebarActionFromWebView()` | `handleSidebarAction()` |
| `switchAssistantFromWebView()` | `handleSwitchAssistant()` |
| `updateModelSettingsFromWebView()` | `handleModelSettingsUpdate()` |

### Other function renames
| Current | New | Why |
|---------|-----|-----|
| `manageCursorAndToolTip(action)` | `updateLoadingUI(action)` | Generic "manage" → specific |
| `mainScriptHotkeyActions(action)` | `handleHotkey(action)` | Redundant prefix |
| `commandMenuHandler(index)` | `onCommandSelected(index)` | Event-driven |
| `customCommandSendButtonAction()` | `onCommandInputSend()` | Shorter, event-driven |
| `OpenOrSpawnChatWindow()` | `openChatWindow()` | Simplify |
| `KillChatWindow()` | `closeChatWindow()` | Not killing, closing |
| `OnChatWindowOpened()` | `onChatWindowOpened()` | Consistent casing |
| `BuildAndWriteRequestFiles()` | `buildRequest()` | Shorter, implementation-neutral |
| `ToggleSuspend()` | Keep, clear enough |
| `postAssistantsToWebView()` | Keep, clear |

### Variable renames
| Current | New | Location |
|---------|-----|----------|
| `router` | `llmClient` | Main.ahk, ChatWindow.ahk |
| `requestParams["responseWindowTitle"]` | `requestParams["windowTitle"]` | ChatWindow.ahk |
| `customCommandInputWindow` | `commandInputWindow` | Main.ahk |
| `scriptSuspendStatus` | `suspendBanner` | Main.ahk |
| `mainScriptHiddenhWnd` | `mainHwnd` | Main.ahk, ChatWindow |

---

## Phase 3: Fix Generic File Names

| Current | New | Reason |
|---------|-----|--------|
| `app/CommandManager.ahk` | `app/CommandState.ahk` | Holds state, not a "manager" |
| `app/ModelTracker.ahk` | `app/LoadingTracker.ahk` | Tracks loading, not models |
| `app/UiHelpers.ahk` | `app/LoadingUI.ahk` | Cursor + tooltip + suspend = loading UI |
| `chat/ChatUtils.ahk` | Split into 3 (see Phase 4) | "Utils" is a code smell |

---

## Phase 4: Split Generic Files + Oversized Files

### `chat/ChatUtils.ahk` → 3 files
| New File | Contents |
|----------|----------|
| `chat/WebViewMessaging.ahk` | `postWebMessage()`, `startLoadingCursor()`, `buildStructuredMessagesFromPath()`, `postThreadStats()`, `_LoadThreadAndRefreshUI()` |
| `chat/ThreadTitleGen.ahk` | `generateThreadTitle()` + its 3 helper functions |
| `chat/CurlState.ahk` | `cURLState()`, `deleteTempFiles()` |

### `chat/StreamHandler.ahk` (441) → split into streaming/ dir
| New File | Contents |
|----------|----------|
| `chat/streaming/StreamHandler.ahk` | `sendStreamingRequest()`, `_pollStreamTimer()`, `_readStreamChunkFromParams()`, `_finalizeStreaming()`, `_cleanupStreamState()`, `readStreamChunk()` |
| `chat/streaming/StreamCompletion.ahk` | `_handleStreamComplete()`, `saveStreamResponse()`, `_maybeGenerateTitle()`, `_getProviderEndpoint()` |
| `chat/streaming/StreamError.ahk` | `_handleStreamError()`, `_handleStreamCancelled()`, `_logCancelledRequest()` |

### `chat/db/MessageRepo.ahk` (336) → split
| New File | Contents |
|----------|----------|
| `chat/db/TreeRepo.ahk` | `GetActivePath()`, `GetSiblings()`, `GetTree()`, `ForkThread()`, `SetActiveLeaf()`, `SwitchBranch()`, `GetThreadStats()`, `_WalkToLeaf()`, `_SyncActivePathTokens()` |
| Keep MessageRepo.ahk | `Insert()`, `HardDelete()`, `Edit()`, `SetFeedback()`, `_TouchThreadByMsg()` |

### `webui/js/main.js` (369) → extract init
| New File | Contents |
|----------|----------|
| `webui/js/chat-init.js` | `DOMContentLoaded`, `setTheme()`, `setFontFace()`, `toggleNavBar()`, `markdown-it init` |
| Keep main.js | `handleWebMessage()`, `showError()` |

### `webui/js/chat-render.js` (307) → extract actions
| New File | Contents |
|----------|----------|
| `webui/js/chat-actions.js` | `addMessageActions()`, `createBranchBadge()`, `updateBranchBadges()` |
| Keep chat-render.js | Render functions |

---

## Phase 5: Directory Restructuring

### Before (flat chat/ with 14 files)
```
chat/  ← flat, mixed concerns
```

### After
```
chat/
├── callbacks/
│   ├── Branch.ahk       ← ChatCallbacks_Branch.ahk
│   ├── Dispatch.ahk     ← ChatDispatch.ahk
│   ├── Edit.ahk         ← ChatCallbacks_Edit.ahk
│   ├── Message.ahk      ← ChatCallbacks_Message.ahk
│   └── Sidebar.ahk      ← ChatCallbacks_Sidebar.ahk
├── db/
│   ├── ChatDB.ahk       ← moved from chat/
│   ├── ThreadRepo.ahk
│   ├── MessageRepo.ahk
│   ├── TreeRepo.ahk     ← NEW
│   └── AssistantRepo.ahk
├── streaming/
│   ├── StreamHandler.ahk
│   ├── StreamCompletion.ahk ← NEW
│   └── StreamError.ahk      ← NEW
├── ChatIPC.ahk
├── ChatRequestBuilder.ahk
├── ChatSettings.ahk
├── ChatWindow.ahk
├── CurlState.ahk
├── ThreadTitleGen.ahk
└── WebViewMessaging.ahk

ipc/                       ← NEW directory
└── CustomMessages.ahk     ← moved from ui/
```

---

## Phase 6: Fix All Tests + Includes

- Update all `#Include` paths for moved/renamed files
- Fix `tests/run_tests.ahk`  
- Fix ModelId include ordering issue (test_config.ahk)
- Update `OnWebMessageReceived` dispatch for renamed callback functions
- Target: 111/111 tests passing
