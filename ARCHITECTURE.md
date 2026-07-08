# LLM AutoHotkey Assistant — Architecture Guide

## Directory Structure

```
ai-automation/
├── Main.ahk                         # Entry point — run this file
├── UserConfig.ahk                   # User-facing configuration (API keys, prompts, theme, hotkeys)
├── lib/Config.ahk                   # Include chain — loads all vendor libs + application modules
├── ARCHITECTURE.md                  # This file
│
├── shared/                          # Shared application utilities
│   ├── ModelParser.ahk              # Model ID parsing ("provider/model" → provider + name)
│   ├── TokenEstimation.ahk          # Character-based token estimation (~4 chars/token)
│   └── DebugLog.ahk                 # Shared debug logging + safeDelete helper
│
├── app/                             # Application logic (loaded by Main.ahk)
│   ├── RequestProcessor.ahk         # Orchestrator: clipboard capture → LLM request dispatch
│   ├── ClipboardCapture.ahk         # Text capture via clipboard (FIM + non-FIM)
│   ├── InlineRequestRunner.ahk      # Non-chat cURL execution, response parsing, paste, cleanup
│   ├── InputWindow.ahk              # InputWindow class: GUI popup for custom prompts
│   ├── LoadingTracker.ahk           # Active request tracking, loading state, reload coordination
│   ├── LoadingUI.ahk                # Cursor changes, tooltip display, suspend banner toggle
│   └── menu/                        # Command menu system
│       ├── CommandMenu.ahk          # Menu building: command menu, tags, submenus, options
│       └── CommandState.ahk         # Command state management + custom input send action
│
├── chat/                            # Persistent chat window (sub-process)
│   ├── ChatWindow.ahk               # Window lifecycle: hotkeys, WebView2 creation, show/hide, pre-warm
│   ├── ChatIPC.ahk                  # IPC handlers: OnLoadThread, OnTriggerLLM + LoadThreadIntoUI
│   ├── ChatSettings.ahk             # Thread settings, assistant/model management, dropdown label
│   ├── ChatRequestBuilder.ahk       # buildRequest, sendRequestToLLM, _BuildAndFireRequest, handleCancelStream
│   ├── ChatUtils.ahk                # cURL management, WebView messaging, temp files, loading cursor, stats
│   ├── ThreadTitleGen.ahk           # Fire-and-forget thread title generation via cheap LLM call
│   ├── callbacks/
│   │   ├── Dispatch.ahk             # OnWebMessageReceived + callback includes
│   │   ├── Branch.ahk               # Branch nav, fork, feedback, Retry callbacks
│   │   ├── Edit.ahk                 # Edit and delete callbacks (hard-delete with re-parenting)
│   │   ├── Message.ahk              # Send + retry callbacks
│   │   └── Sidebar.ahk              # Thread list, load, new, delete, trash, restore, sidebar
│   ├── streaming/
│   │   └── StreamHandler.ahk        # Streaming: cURL polling, SSE parsing, DB persistence, API logging
│   └── db/
│       ├── ChatDB.ahk               # Facade — static Open/Close + delegation to repos
│       ├── ThreadRepo.ahk           # Thread CRUD operations
│       ├── MessageRepo.ahk          # Message CRUD operations
│       ├── TreeRepo.ahk             # Branch navigation, tree visualization, fork, stats
│       └── AssistantRepo.ahk        # Assistant CRUD operations
│
├── api/                             # API client
│   ├── LLMRequestBuilder.ahk        # JSON request building, FIM, chat history, thinking config
│   ├── SSEParser.ahk                # SSE streaming line parser (static)
│   ├── ApiLogger.ahk                # API request/response logging (static)
│   ├── CostCalculator.ahk           # Token cost calculation (static)
│   ├── CurlBuilder.ahk              # cURL command construction (static + instance)
│   ├── ProviderResolver.ahk         # Provider/endpoint resolution from model string
│   └── ResponseParser.ahk           # Response parsing (chat, FIM, streaming, error)
│
├── ipc/                             # Inter-process communication
│   └── CustomMessages.ahk           # CustomMessages class: WM_ message constants + helpers
│
├── lib/                             # Vendor/third-party libraries
│   ├── Config.ahk                   # Include chain (see below)
│   ├── SQLite/                      # SQLite3 database wrapper
│   ├── ApiLogsViewer.ahk            # Standalone API logs viewer
│   ├── Dark_Menu.ahk                # Dark theme for AHK menus
│   ├── Dark_MsgBox.ahk              # Dark mode MsgBox and InputBox
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
    ├── index.html                   # Main chat UI
    ├── api-logs.html                # API logs viewer UI
    ├── Bootstrap/                   # Bootstrap framework files
    ├── css/
    │   ├── custom.css               # Custom styles
    │   ├── vendor/                  # Third-party CSS (katex, texmath, highlight)
    │   └── chat/                    # Chat UI styles (split from chat.css)
    │       ├── chat-base.css        # Layout, containers, title bar
    │       ├── chat-messages.css    # Message bubbles, loading, streaming, thinking
    │       ├── chat-actions.css     # Action buttons, branch nav, more dropdown
    │       ├── chat-input.css       # Input area, buttons, token bar
    │       └── chat-sidebar.css     # Bootstrap helpers, utility classes
    └── js/
        ├── main.js                  # Message handler orchestrator + initialization
        ├── stream.js                # Streaming response rendering
        └── chat/                    # Chat feature modules
            ├── chat-core.js         # Core chat state, rendering
            ├── chat-settings.js     # Assistant selector dropdown
            ├── chat-settings-modal.js # Model settings modal functions
            ├── chat-format.js       # Clipboard, format helpers, token bar
            ├── chat-render.js       # Bubble creation, DOM rendering
            ├── chat-actions.js      # Message action buttons
            ├── chat-input.js        # Send, loading, keyboard, retry
            ├── chat-branching.js    # Edit, Delete, Branch Nav, Tree Viz
            ├── chat-sidebar.js      # Thread list sidebar + message nav bar
            ├── chat-quote.js        # Quote from chat
            ├── chat-feedback.js     # Thumbs up/down feedback
            └── chat-undo.js         # Undo/Redo (Ctrl+Z/Y)
```

## Architecture Overview

The application is an AutoHotkey v2 script that provides a hotkey-activated prompt menu, sends text to an LLM API (OpenAI-compatible) via cURL, and displays responses in a WebView2-based chat window.

### Key Design Decisions

- **Entry point**: `Main.ahk` — double-click to run.
- **User config**: `UserConfig.ahk` — all prompts, API keys, hotkeys, and theme settings in one file. Changes take effect on save (Ctrl+S in Notepad → auto-reload).
- **Persistent single-window model**: A single `ChatWindow.ahk` sub-process handles all chat sessions. Close = hide (not terminate). Re-opened via tray menu or command-line arg. No tray icon (managed by the main script).
- **SQLite persistence**: Chat history stored in `%APPDATA%\LLM-AutoHotkey-Assistant\chat_history.db` (WAL mode for concurrent access). Supports branching (parent-child tree + sibling groups), soft-delete, feedback, and reasoning content.
- **WebView2 frontend**: The chat UI is an HTML/JS page rendered by Microsoft Edge WebView2. AHK sends messages via `PostWebMessageAsJSON`; JS sends back via `chrome.webview.postMessage()`.
- **cURL for API calls**: The script writes JSON request files to `%TEMP%` and runs `cURL.exe` for API communication.

## Startup Flow

1. `Main.ahk` runs → `#Include <Config>` loads `lib/Config.ahk`
2. `Config.ahk` loads vendor libs + shared utilities + application classes
3. `Main.ahk` calls `ChatDB.Open()` to initialize SQLite, then `ChatDB.Thread_PurgeExpired()`
4. `Main.ahk` creates `llmClient := LLMRequestBuilder(APIKey)` and a `commandInputWindow` instance
5. `Main.ahk` spawns `ChatWindow.ahk` as hidden sub-process with "prewarm" flag
6. `Main.ahk` registers hotkeys (default: `` ` `` to open menu)
7. `Main.ahk` loads application modules (`app/*.ahk`)
8. Script ready — tray icon appears, hotkeys active

## Request Flow

### Chat Mode (pasteMode = "chat")

```
User presses hotkey → buildCommandMenu() → onCommandSelected()
    │
    ▼
processInitialRequest()                         # app/RequestProcessor.ahk
    │  ClipboardCapture.Capture() — text via clipboard
    │  Creates thread in ChatDB (system + user messages)
    │  Calls openChatWindow(threadId)
    ▼
chat/ChatWindow.ahk                             # Sub-process (persistent)
    │  Loads thread from DB → initChatMode → WebView
    │  If last message is from user: auto-triggers LLM
    ▼
buildRequest()                                  # Rebuilds API JSON from DB
    │  → writes to %TEMP% → cURL command
    ▼
sendRequestToLLM() → sendStreamingRequest()     # cURL → API → parse response
    │  (streaming or non-streaming)
    ▼
ChatDB.Msg_Insert()                             # Persist assistant response
    │  → postWebMessage("appendChatMessage")
    ▼
User types → handleChatSend()                   # callbacks/Message.ahk
    │  Inserts user message in DB → builds request → cURL → response
    ▼
ChatWindow stays open (hidden or visible)
```

### Non-Chat Mode (pasteMode = "replace"/"append")

```
processInitialRequest()
    │  ClipboardCapture.Capture()
    ▼
InlineRequestRunner.Run()                       # app/InlineRequestRunner.ahk
    │  Builds cURL command → Run(cURL) → wait → parse
    ▼
A_Clipboard := response → Send("^v")           # Pastes into active app
```

## Data Model (SQLite)

### `chat_threads`
| Column | Type | Description |
|--------|------|-------------|
| `id` | TEXT PRIMARY KEY | UUID |
| `title` | TEXT | Auto-generated by ThreadTitleGen |
| `is_deleted` | INTEGER | 0=active, 1=trashed (soft-delete, 30-day auto-purge) |
| `deleted_at` | TEXT | Timestamp when trashed |
| `created_at` | TEXT | ISO 8601 |
| `updated_at` | TEXT | ISO 8601 |
| `active_leaf_id` | TEXT | Current position in message tree |
| `active_path_tokens` | INTEGER | Context Used counter |
| `cumulative_*` | INTEGER/REAL | Persisted token counts and costs |

### `messages`
| Column | Type | Description |
|--------|------|-------------|
| `id` | TEXT PRIMARY KEY | UUID |
| `thread_id` | TEXT | FK to chat_threads |
| `role` | TEXT | "system", "user", or "assistant" |
| `content` | TEXT | Message body |
| `model` | TEXT | Model name (assistant only) |
| `parent_id` | TEXT | Previous message in path |
| `sibling_group` | TEXT | Group UUID for branch variants |
| `sibling_index` | INTEGER | Position within sibling group |
| `feedback` | INTEGER | 1 (up), -1 (down), NULL (none) |
| `reasoning` | TEXT | Thinking/reasoning content |
| `*_tokens` | INTEGER | Token counts from API response |

### Branching Model
Messages form a tree via `parent_id`. When edited or retried, a new sibling is created with the same `sibling_group`. `active_leaf_id` tracks current position. `TreeRepo` handles navigation, stats, and visualization.

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

### WebView → AHK (via postMessage)
Dispatched by `OnWebMessageReceived` in `callbacks/Dispatch.ahk`. Actions:
- `chatSend`, `retry`, `editMessage`, `deleteMessage`
- `switchBranch`, `forkChat`, `setFeedback`
- `sidebarAction`, `switchAssistant`, `updateModelSettings`
- `cancelStream`, `requestAssistantList`, `requestCurrentSettings`

## IPC (Inter-Process Communication)

| Message | Direction | Purpose |
|---------|-----------|---------|
| `WM_CHAT_WINDOW_OPENED` (0x500) | sub → main | Registers ChatWindow |
| `WM_LOADING_START` (0x400+123) | sub → main | Notifies loading started |
| `WM_LOADING_FINISH` (0x400+124) | sub → main | Notifies loading finished |
| `WM_LOAD_THREAD` (0x500+2) | main → sub | Load specific thread |
| `WM_NEW_CHAT` (0x500+3) | main → sub | Start new chat |
| `WM_TRIGGER_LLM` (0x500+4) | main → sub | Fire LLM for current thread |

## JavaScript Module Dependency Graph

Load order in `index.html` (bottom of `<body>`):
```
index.html
  └── vendor (markdown-it, katex, highlight, texmath)
       └── chat-core.js
            ├── chat-settings.js
            ├── chat-format.js
            ├── chat-render.js
            ├── chat-input.js
            ├── chat-branching.js
            ├── chat-sidebar.js
            ├── chat-quote.js
            ├── chat-feedback.js
            ├── chat-undo.js
            ├── stream.js
            └── main.js (orchestrator)
```

## Testing

### How to Run All Tests
```bash
"AutoHotkey64.exe" ai-automation/tests/run_tests.ahk
```

### Test Structure
```
ai-automation/tests/
├── test_config.ahk          # Test overrides (loaded after Config.ahk)
├── run_tests.ahk            # Entry point — discovers + runs all test classes
├── unit/                    # Isolated unit tests
└── integration/             # Cross-module integration tests
```

### Output Format
```
[PASS] ClassName.MethodName
[FAIL] ClassName.MethodName — Error message
---
N tests run | X passed | Y failed
```
