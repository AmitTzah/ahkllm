# LLM AutoHotkey Assistant — Architecture Guide

## Directory Structure

```
ai-automation/
├── Main.ahk                         # Entry point — run this file
├── UserConfig.ahk                   # User-facing configuration (API keys, prompts, theme, hotkeys)
├── lib/Config.ahk                   # Include chain — loads all vendor libs + application modules
├── ARCHITECTURE.md                  # This file
│
├── app/                             # Application logic (loaded by Main.ahk)
│   ├── CommandMenu.ahk              # Menu building: command menu, tags, submenus, options
│   ├── CommandManager.ahk           # Command state management, window operations, send-to handlers
│   ├── RequestProcessor.ahk         # Clipboard capture (FIM/chat), model spawning, cURL request building
│   ├── ModelTracker.ahk             # Active model tracking, loading state, reload coordination
│   └── UiHelpers.ahk                # Cursor changes, tooltip display, suspend banner toggle
│
├── chat/                            # Persistent chat window (sub-process)
│   ├── ChatWindow.ahk               # Orchestrator: hotkeys, WebView creation, cURL runner, message dispatch
│   ├── ChatDB.ahk                   # SQLite wrapper: thread/message CRUD, branching, fork
│   ├── ChatUtils.ahk                # postWebMessage, cURL PID management, title generation, debugLog
│   ├── ChatCallbacks_Message.ahk    # Send + retry callbacks, buildStructuredMessagesFromPath
│   ├── ChatCallbacks_Edit.ahk       # Edit and delete callbacks (hard-delete with re-parenting)
│   ├── ChatCallbacks_Branch.ahk     # Branch nav, fork, feedback, Retry button callbacks
│   ├── ChatCallbacks_Sidebar.ahk    # Thread list, load, new, delete, trash, restore, sidebar
│   └── StreamHandler.ahk            # Streaming: cURL polling, SSE parsing, DB persistence, API logging, title gen trigger
│
├── api/                             # API client (split into 4 files)
│   ├── LLMClient.ahk                # Core: cURL templates, JSON building, FIM, response extraction
│   ├── SSEParser.ahk                # SSE streaming line parser (static)
│   ├── ApiLogger.ahk                # API request/response logging (static)
│   └── CostCalculator.ahk           # Token cost calculation (static)
│
├── ui/                              # UI components
│   ├── InputWindow.ahk              # InputWindow class: GUI popup for custom prompts
│   └── CustomMessages.ahk           # CustomMessages class: inter-process WM_ messaging
│
├── lib/                             # Vendor/third-party libraries
│   ├── Config.ahk                   # Include chain (see below)
│   ├── SQLite/                      # SQLite3 database wrapper
│   ├── ApiLogsViewer.ahk            # Standalone API logs viewer
│   ├── Dark_Menu.ahk                # Dark theme for AHK menus
│   ├── Dark_MsgBox.ahk              # Dark theme for MsgBox/InputBox
│   ├── WebViewToo.ahk               # WebView2 Framework
│   ├── WebView2.ahk                 # WebView2 Core
│   ├── jsongo.v2.ahk                # JSON parsing/serialization
│   ├── AutoXYWH.ahk                 # GUI auto-resizing
│   ├── ToolTipEx.ahk                # Enhanced tooltips
│   ├── SystemThemeAwareToolTip.ahk  # Dark theme tooltips
│   ├── Promise.ahk                  # Promise/A+ implementation
│   ├── ComVar.ahk                   # COM utility
│   ├── 32bit/                       # 32-bit native binaries
│   └── 64bit/                       # 64-bit native binaries
│
├── icons/                           # Provider icons
│   ├── IconOn.ico                   # Tray icon when active
│   ├── IconOff.ico                  # Tray icon when suspended
│   └── ... (provider icons)
│
└── webui/                           # WebView2 frontend
    ├── index.html                   # Main chat UI (see JS dependency graph below)
    ├── api-logs.html                # API logs viewer UI
    ├── Bootstrap/                   # Bootstrap framework files
    ├── css/
    │   ├── custom.css               # Custom styles
    │   └── vendor/                  # Third-party CSS (katex, texmath, highlight)
    └── js/
        ├── chat-core.js             # Core chat state, rendering, shared action buttons
        ├── chat-branching.js        # D1-D4: Edit, Delete, Branch Nav, Tree Viz
        ├── chat-sidebar.js          # D6: Thread list sidebar + message nav bar
        ├── chat-quote.js            # D5: Quote from chat (button + selection popup)
        ├── chat-feedback.js         # D8: Thumbs up/down feedback
        ├── chat-undo.js             # D9: Undo/Redo (Ctrl+Z/Y)
        ├── stream.js                # Streaming response rendering
        ├── main.js                  # Message handler orchestrator + initialization
        └── vendor/                  # Third-party JS (markdown-it, katex, highlight, texmath)
```

## Architecture Overview

The application is an AutoHotkey v2 script that provides a hotkey-activated prompt menu, sends text to an LLM API (OpenAI-compatible) via cURL, and displays responses in a WebView2-based chat window.

### Key Design Decisions

- **Entry point**: `Main.ahk` — double-click to run.
- **User config**: `UserConfig.ahk` — all prompts, API keys, hotkeys, and theme settings in one file. Changes take effect on save (Ctrl+S in Notepad → auto-reload).
- **Persistent single-window model**: A single `ChatWindow.ahk` sub-process handles all chat sessions. Close = hide (not terminate). Re-opened via tray menu or command-line arg. No tray icon (managed by the main script).
- **SQLite persistence**: Chat history is stored in `%APPDATA%\LLM-AutoHotkey-Assistant\chat_history.db` (WAL mode for concurrent access). Supports branching (parent-child tree + sibling groups), soft-delete, feedback, and reasoning content.
- **WebView2 frontend**: The chat UI is an HTML/JS page rendered by Microsoft Edge WebView2. AHK sends messages via `PostWebMessageAsJSON`; the JS side sends messages back via `chrome.webview.postMessage()`.
- **cURL for API calls**: The script writes JSON request files to `%TEMP%` and runs `cURL.exe` as a hidden process to communicate with the LLM API.

## Startup Flow

1. `Main.ahk` runs → `#Include <Config>` loads `lib/Config.ahk`
2. `Config.ahk` loads vendor libs + application classes (`LLMClient.ahk`, `SSEParser.ahk`, `ApiLogger.ahk`, `CostCalculator.ahk`, `InputWindow.ahk`, `CustomMessages.ahk`, `ChatDB.ahk`)
3. `Main.ahk` calls `ChatDB.Open()` to initialize the SQLite database, then `ChatDB.Thread_PurgeExpired()` to clean up expired trash
4. `Main.ahk` creates `router := LLMClient(APIKey)` and a single `customCommandInputWindow` instance
5. `Main.ahk` spawns `ChatWindow.ahk` as a hidden sub-process with "prewarm" flag — WebView2 initializes in the background to avoid black flash on first open
6. `Main.ahk` registers hotkeys (default: `` ` `` to open menu)
7. `Main.ahk` loads application modules (`app/*.ahk`)
8. Script is ready — tray icon appears, hotkeys active

## Request Flow

### Chat Mode (pasteMode = "chat")

```
User presses hotkey → buildCommandMenu() → commandMenuHandler()
    │
    ▼
processInitialRequest()                         # app/RequestProcessor.ahk
    │  Captures text via clipboard (Ctrl+C)
    │  Creates thread in ChatDB (system prompt + user message)
    │  Calls OpenOrSpawnChatWindow(threadId)
    ▼
chat/ChatWindow.ahk                             # Sub-process (persistent)
    │  Loads thread from DB → initChatMode → WebView
    │  If last message is from user: auto-triggers LLM
    ▼
BuildAndWriteRequestFiles()                     # Rebuilds API JSON from DB
    │  → writes to %TEMP% → cURL command
    ▼
sendRequestToLLM()                              # cURL → API → parse response
    │  (streaming or non-streaming)
    ▼
ChatDB.Msg_Insert()                             # Persist assistant response
    │  → postWebMessage("appendChatMessage")
    ▼
User types → chatSendFromWebView()              # ChatCallbacks.ahk
    │  Inserts user message in DB
    │  Builds request from DB → cURL → response
    │  Inserts assistant message in DB
    ▼
ChatWindow stays open (hidden or visible)
```

### Non-Chat Mode (pasteMode = "replace"/"append")

```
processInitialRequest()
    │  Captures text
    │  Builds cURL command inline (no ChatWindow)
    ▼
Run(cURLCommand) → wait → parse response
    │  Sets A_Clipboard := response
    ▼
Send("^v")                                     # Pastes into active app
    │  Cleans up temp files
    ▼
Done
```

## Data Model (SQLite)

### `chat_threads`
| Column | Type | Description |
|--------|------|-------------|
| `id` | TEXT PRIMARY KEY | UUID (timestamp-random) |
| `title` | TEXT | User-visible thread title (auto-generated by LLM) |
| `is_deleted` | INTEGER | 0=active, 1=trashed (soft-delete, 30-day auto-purge) |
| `deleted_at` | TEXT | Timestamp when trashed (for auto-purge) |
| `created_at` | TEXT | ISO 8601 datetime |
| `updated_at` | TEXT | ISO 8601 datetime |
| `active_leaf_id` | TEXT | Current position in message tree |
| `active_path_tokens` | INTEGER | Context Used counter (API total_tokens on insert, estimated subtraction on edit/delete) |
| `cumulative_prompt_tokens` | INTEGER | Persisted across deletes — tokens already paid for |
| `cumulative_completion_tokens` | INTEGER | Persisted across deletes |
| `cumulative_cached_tokens` | INTEGER | Persisted across deletes |
| `cumulative_total_tokens` | INTEGER | Persisted across deletes |
| `cumulative_cost` | REAL | Total API cost (persisted across deletes) |
| `cumulative_input_cost` | REAL | Input cost component |
| `cumulative_cached_input_cost` | REAL | Cached input cost component |
| `cumulative_output_cost` | REAL | Output cost component |

### `messages`
| Column | Type | Description |
|--------|------|-------------|
| `id` | TEXT PRIMARY KEY | UUID (timestamp-random) |
| `thread_id` | TEXT | FK to chat_threads |
| `role` | TEXT | "system", "user", or "assistant" |
| `content` | TEXT | Message body |
| `model` | TEXT | Model name (assistant only) |
| `parent_id` | TEXT | Previous message in path (NULL for root) |
| `sibling_group` | TEXT | Group UUID for branch variants |
| `sibling_index` | INTEGER | Position within sibling group |
| `feedback` | INTEGER | 1 (up), -1 (down), NULL (none) |
| `reasoning` | TEXT | Thinking/reasoning content (DeepSeek) |
| `prompt_tokens` | INTEGER | Actual prompt tokens from API response |
| `completion_tokens` | INTEGER | Actual completion tokens from API response |
| `cached_tokens` | INTEGER | Cached prompt tokens from API response |
| `total_tokens` | INTEGER | Actual total tokens from API response |
| `created_at` | TEXT | ISO 8601 datetime |

### Deletion Model
- **Messages**: Hard-delete (`DELETE FROM`). Children are re-parented to the deleted message's parent.
- **Threads**: Soft-delete (`is_deleted=1`). Moves to trash with `deleted_at` timestamp. Auto-purged after `trashRetentionDays` (configurable, default 30). Trash visible in sidebar with restore/delete forever.
- **Cumulative counters**: Token counts and costs are stored at the thread level and persist across message deletes — these represent already-paid API usage.

### Branching Model
Messages form a tree via `parent_id`. When a message is edited or retried, a new sibling is created with the same `sibling_group`. `active_leaf_id` tracks the user's current position in the tree. Branch navigation walks backward to root and forward through `_WalkToLeaf`.

## WebView ↔ AHK Communication

### AHK → WebView (postWebMessage)
```javascript
postWebMessage("target", data) → JSON: {"target": "target", "data": data}
```
Handled by `handleWebMessage()` in `main.js`. Key targets:
- `initChatMode` — initialize chat with message array
- `appendChatMessage` — append a new message bubble
- `streamContent` / `streamReasoning` / `streamDone` — streaming updates
- `setChatButtonsEnabled` — enable/disable input during loading
- `updateTokenUsage` — cost/token display
- `updateBranchInfo` — branch navigation badge
- `renderChatTree` — tree modal data
- `threadList` / `loadThread` — sidebar thread operations
- `threadForked` — fork confirmation
- `setTheme` / `setFontFace` — UI configuration

### WebView → AHK (via postMessage)
```javascript
window.chrome.webview.postMessage(JSON.stringify({ action: 'chatSend', message: '...' }));
```
Dispatched by `OnWebMessageReceived` in `ChatWindow.ahk`. Actions:
- `chatSend` — send user message
- `retry` — retry last assistant message
- `editMessage` — edit (overwrite or branch)
- `deleteMessage` — hard-delete with re-parenting
- `switchBranch` — navigate siblings
- `forkChat` — duplicate thread from point
- `setFeedback` — thumbs up/down
- `sidebarAction` — thread list, load, new, delete, navigate

## IPC (Inter-Process Communication)

The main script (`Main.ahk`) and ChatWindow sub-process communicate via Windows messages (`WM_`):

| Message | Direction | Purpose |
|---------|-----------|---------|
| `WM_RESPONSE_WINDOW_OPENED` (0x400+125) | sub → main | Registers Response Window for model tracking |
| `WM_RESPONSE_WINDOW_CLOSED` (0x400+126) | sub → main | Unregisters Response Window |
| `WM_CHAT_WINDOW_OPENED` (0x500) | sub → main | Registers ChatWindow for model tracking |
| `WM_CHAT_WINDOW_CLOSED` (0x501) | sub → main | Unregisters ChatWindow |
| `WM_RESPONSE_WINDOW_LOADING_START` (0x400+123) | sub → main | Notifies loading started |
| `WM_RESPONSE_WINDOW_LOADING_FINISH` (0x400+124) | sub → main | Notifies loading finished |
| `WM_SEND_TO_ALL_MODELS` (0x400+127) | main → sub | Triggers re-request with new user message |
| `WM_LOAD_THREAD` (0x500+2) | main → sub | Load a specific thread in ChatWindow |
| `WM_NEW_CHAT` (0x500+3) | main → sub | Start a new chat in ChatWindow |

**Important:** WebView2 uses the 0x400–0x4FF range internally. ChatWindow messages use 0x500+ to avoid access-violation crashes.

## JavaScript Module Dependency Graph

Load order in `index.html` (bottom of `<body>`) is critical:

```
index.html
  └── markdown-it / katex / highlight / texmath  (vendor — no deps)
       └── chat-core.js                           (defines: chatMessages, initChatMode, addMessageActions)
            ├── chat-branching.js                 (depends on: chatMessages, postMessage, addMessageActions)
            ├── chat-sidebar.js                   (depends on: chatMessages, postMessage, activeThreadId)
            ├── chat-quote.js                     (depends on: autoResizeChatInput)
            ├── chat-feedback.js                  (standalone — no deps)
            ├── chat-undo.js                      (depends on: postMessage, editMessage, deleteMessage)
            ├── stream.js                         (depends on: chat-core addMessageActions, chat-core createBranchBadge)
            └── main.js                           (depends on: ALL of the above — orchestrator)
```

**Key cross-module calls:**
- `chat-core.js` calls `quoteMessage()` from `chat-quote.js`, `editMessage()`/`deleteMessage()` from `chat-branching.js`, `addFeedbackButtons()` from `chat-feedback.js`, `forkChat()` from `chat-sidebar.js`
- `stream.js` calls `createBranchBadge()` from `chat-core.js` and `addMessageActions()` from `chat-core.js`

## Data Storage

| Storage | Lifetime | Data |
|---------|----------|------|
| `%APPDATA%\LLM-AutoHotkey-Assistant\chat_history.db` | Persistent (SQLite) | All threads, messages, branches, feedback |
| `%TEMP%\ChatWindow_Req_*.json` | Per request | cURL request payload (rebuilt from DB each time) |
| `%TEMP%\ChatWindow_Out_*.json` | Per request | Raw API response |
| `%TEMP%\LLM_API_Log.json` | Persistent (capped) | API interaction history |
| `%TEMP%\LLM_Debug_Log.txt` | Per session | Diagnostic trace (cleared on startup) |

## Configuration System

`UserConfig.ahk` is a standard AHK file directly `#Include`d into the script. There is no config file parser — all settings are plain AHK variables and arrays.

## How to Add a New Command

Edit `UserConfig.ahk` and add an entry to the `commands` array. See the template at the top of the file for all available fields.

## pasteMode Values

| Value | Behavior |
|-------|----------|
| `"chat"` | Opens the persistent ChatWindow. Messages displayed as bubbles with edit/delete/fork/retry/quote/copy/feedback buttons. Inline input box at bottom. SQLite-persisted. |
| `"replace"` | Pastes the LLM response directly into the active app, replacing the selected text. No window. |
| `"append"` | Pastes the LLM response after the cursor position. No window. |

## Multi-Model (Council) Mode

When `APIModels` contains multiple comma-separated models and `pasteMode != "chat"`, the script spawns a separate inline cURL request for each model. Results are pasted independently.

**For `pasteMode = "chat"`, multi-model is not supported.** Only the first model is used. The script logs a warning to the debug log when multiple models are configured with chat mode.

## File Size Warnings

No modified files exceed 300 lines. Largest is [`chat/ChatCallbacks_Edit.ahk`](ai-automation/chat/ChatCallbacks_Edit.ahk) at ~95 lines.
[`webui/index.html`](ai-automation/webui/index.html) reduced from 652 to 127 lines by extracting CSS to [`webui/css/chat.css`](ai-automation/webui/css/chat.css).

## Testing

### How to Run All Tests (No GUI Popups)

```bash
"AutoHotkey64.exe" ai-automation/tests/run_tests.ahk
```

No flags needed. No piping to echo. Run directly.

### Why No Popups

Tests use a 3-layer defense to suppress all AHK GUI:

| Layer | Mechanism | What It Catches |
|-------|-----------|----------------|
| `#ErrorStdOut` in script | AHK v2 directive | Load-time parse/syntax errors |
| `OnError` handler in `run_tests.ahk` | Global error hook | All runtime errors (unassigned vars, type errors) |
| `test_config.ahk` overrides | `MsgBox()` + `ExitApp()` functions | Production code calling `MsgBox` or `ExitApp` |

`test_config.ahk` also provides mock config globals (`APIKey`, `modelPricing`, `APIEndpoint`), so `UserConfig.ahk` is **never loaded** in test mode — preventing the "no API key" `ExitApp` call.

### Test Structure

```
ai-automation/tests/
├── test_config.ahk          # Mock configs + popup suppression (included FIRST)
├── run_tests.ahk            # Entry point — discovers + runs all test classes
├── unit/                    # Tests isolated from I/O, DB, network
│   ├── ChatDB.test.ahk      # DB CRUD, branching, token stats
│   └── LLMClient.test.ahk   # JSON building, SSE parsing, cost computation
└── integration/             # Tests across multiple modules (future)
```

### How Tests Work

Test files define classes with methods. Each method is a single test case. The runner discovers all classes via `RegisterTestClass()` (called in `static __New()`), instantiates each class, and iterates its prototype methods.

A test **passes** if it completes without throwing. A test **fails** if it throws any `Error` object:

```ahk
class MyTest {
    static __New() {
        RegisterTestClass("MyTest")
    }

    Addition_Works() {
        result := 2 + 2
        if result != 4
            throw Error("Expected 4, got " result)
    }
}
```

### Output Format

```
[PASS] MyTest.Addition_Works
[FAIL] MyTest.OtherTest — Expected 4, got 5
---
3 tests run | 2 passed | 1 failed
```

### How New Tests Are Discovered

1. Create a `*.test.ahk` file in `unit/` or `integration/`
2. Define a class with `static __New()` calling `RegisterTestClass("ClassName")`
3. Add methods starting with capital letter (methods starting with `_` are treated as helpers)
4. Add a `#Include` line in [`tests/run_tests.ahk`](ai-automation/tests/run_tests.ahk)
