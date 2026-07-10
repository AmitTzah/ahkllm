# LLM AutoHotkey Assistant — Architecture Guide

## Directory Structure

```
ai-automation/
├── Main.ahk                         # Entry point — run this file
├── UserConfig.ahk                   # User-facing configuration (API keys, commands, theme, hotkeys)
├── lib/Config.ahk                   # Include chain — loads all vendor libs + application modules
├── ARCHITECTURE.md                  # This file
│
├── shared/                          # Shared application utilities
│   ├── ModelParser.ahk              # Model ID parsing ("provider/model" → provider + name)
│   ├── TokenEstimation.ahk          # Character-based token estimation (~4 chars/token)
│   └── DebugLog.ahk                 # Shared debug logging + safeDelete helper
│
├── app/                             # Application logic
│   ├── RequestProcessor.ahk         # Orchestrator: text capture → LLM request dispatch
│   ├── TextCapture.ahk              # Text capture: UIA TextPattern (primary) + clipboard (fallback)
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
│   ├── UIA.ahk                      # UI Automation library (Descolada) — programmatic UI access
│   ├── SQLite/                      # SQLite3 database wrapper
│   ├── ApiLogsViewer.ahk            # API logs viewer (persistent WebView2, pre-created at startup)
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
├── system-messages/                 # System message text files for commands
│   ├── define.txt
│   ├── refine.txt
│   ├── summarize.txt
│   ├── translate-to-english.txt
│   └── rephrase-in-context.txt      # Uses {{fullText}} template variable
│
├── icons/                           # Provider icons
├── webui/                           # WebView2 frontend (chat UI + API logs viewer UI)
└── tests/                           # Unit + integration tests (166 tests)
```

## Architecture Overview

The application is an AutoHotkey v2 script that provides a hotkey-activated command menu, sends text to LLM APIs via cURL, and displays responses in a WebView2-based chat window.

### Key Design Decisions

- **Entry point**: `Main.ahk` — double-click to run.
- **User config**: `UserConfig.ahk` — all commands, API keys, hotkeys, and theme settings in one file.
- **Persistent single-window model**: A single `ChatWindow.ahk` sub-process handles all chat sessions. Close = hide (not terminate).
- **SQLite persistence**: Chat history stored in `%APPDATA%\LLM-AutoHotkey-Assistant\chat_history.db` (WAL mode). Supports branching, soft-delete, feedback, and reasoning content.
- **WebView2 frontend**: Chat UI rendered by Microsoft Edge WebView2. AHK ↔ JS via `PostWebMessageAsJSON` / `chrome.webview.postMessage()`.
- **cURL for API calls**: JSON request files written to `%TEMP%`, `cURL.exe` used for API communication.
- **UIA (UI Automation)**: Text is captured via Windows accessibility APIs (TextPattern) — zero scroll, no keystrokes. Clipboard capture retained as fallback.

## Command System

### Template Variables

Commands compose prompts using template variables, available in `systemMessage`, `systemMessageFile`, and `userMessage`:

| Variable | Source | Description |
|----------|--------|-------------|
| `{{selection}}` | UIA TextPattern / clipboard | User's highlighted text |
| `{{fullText}}` | UIA DocumentRange (lazy) | Entire document text (text editing controls only) |
| `{{input}}` | Input box (if `showInputBox: true`) | User-typed instruction |

### Command Fields

| Field | Purpose | Default |
|-------|---------|---------|
| `commandName`, `menuText`, `APIModels` | Required | — |
| `systemMessage` / `systemMessageFile` | System prompt (supports templates) | — |
| `userMessage` | User prompt template | *(none — explicit only)* |
| `showInputBox` | Open text input before sending | `false` |
| `inputBoxDefault` | Pre-filled text in input box | `""` |
| `pasteMode` | `"chat"`, `"replace"`, `"append"` | `"chat"` |
| `isFIM` | Use FIM endpoint (ignores prompt fields) | `false` |
| `expandNewlines` | Expand single `\n` → `\n\n` paragraph breaks | `false` |
| `stream`, `thinking`, `temperature`, `maxTokens`, `stop` | API parameters | — |

### Line Ending Normalization

`TextCapture.NormalizeLineEndings()` runs on all captured text:
- Always: `\r\n` / `\r` → `\n` (lossless, free)
- Optional (`expandNewlines: true`): single `\n` → `\n\n` (paragraph breaks for LLM training data)

### FIM (Fill In the Middle)

FIM commands use a separate API endpoint (`fimEndpoint`). Prompt template fields are ignored. FIM Fill works with or without a text selection (cursor = zero-width gap). UIA TextPattern used for capture (zero scroll); paste uses `^v` (preserves undo history).

## Startup Flow

1. `Main.ahk` runs → `#Include <Config>` loads `lib/Config.ahk`
2. `Config.ahk` loads vendor libs (including `UIA.ahk`) + shared utilities + application classes
3. `Main.ahk` calls `ChatDB.Open()` to initialize SQLite
4. `Main.ahk` creates `llmClient := LLMRequestBuilder(APIKey)` and a `commandInputWindow` instance
5. `Main.ahk` spawns `ChatWindow.ahk` as hidden sub-process with "prewarm" flag
6. `Main.ahk` registers hotkeys (default: `` ` `` to open menu)
7. `Main.ahk` pre-creates API Logs Viewer (hidden, deferred 2s)
8. Script ready — tray icon appears, hotkeys active

## Request Flow

### Chat Mode (pasteMode = "chat")

```
User presses hotkey → buildCommandMenu() → onCommandSelected()
    │
    ▼
processInitialRequest()                         # app/RequestProcessor.ahk
    │  TextCapture.Capture() — UIA TextPattern → clipboard fallback
    │  Template expansion: {{selection}}, {{fullText}}, {{input}}
    │  Creates thread in ChatDB (system + user messages)
    │  Calls openChatWindow(threadId)
    ▼
chat/ChatWindow.ahk                             # Sub-process (persistent)
    │  Loads thread from DB → initChatMode → WebView
    │  If last message is from user: auto-triggers LLM
    ▼
buildRequest() → sendRequestToLLM() → ChatDB.Msg_Insert()
```

### Non-Chat Mode (pasteMode = "replace"/"append")

```
processInitialRequest()
    │  TextCapture.Capture() — UIA TextPattern → clipboard fallback
    │  Template expansion
    ▼
InlineRequestRunner.Run()                       # app/InlineRequestRunner.ahk
    │  Builds cURL command → Run(cURL) → wait → parse
    │  Normalizes API response line endings
    ▼
Send("^v") → highlights inserted text (UIA TextPattern for FIM)
```

## Data Model (SQLite)

[unchanged — see commit history for full schema]

## WebView ↔ AHK Communication

[unchanged — see commit history]

## IPC (Inter-Process Communication)

[unchanged — see commit history]

## JavaScript Module Dependency Graph

[unchanged — see commit history for load order]

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
│   ├── TextCapture.test.ahk      # ExpandTemplate, NormalizeLineEndings, structural guards
│   ├── RequestProcessor.test.ahk # Paste block structure, apilogs handler
│   ├── ChatDB.test.ahk
│   ├── LLMRequestBuilder.test.ahk
│   ├── ChatUtils.test.ahk
│   ├── StreamHandler.test.ahk
│   ├── ChatRequestBuilder.test.ahk
│   ├── CustomMessages.test.ahk
│   ├── InlineRequestRunner.test.ahk
│   └── UserConfig.test.ahk
└── integration/
    ├── ChatFlow.test.ahk
    └── BranchFlow.test.ahk
```

### Output Format
```
[PASS] ClassName.MethodName
[FAIL] ClassName.MethodName — Error message
---
N tests run | X passed | Y failed
```
