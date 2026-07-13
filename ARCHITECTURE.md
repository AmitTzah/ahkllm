# LLM AutoHotkey Assistant — Architecture Guide

## Data Storage Locations

All persistent data lives under `%APPDATA%\LLM-AutoHotkey-Assistant\`:

| Path | What | Format |
|---|---|---|
| `chat_history.db` | Chat threads, messages, attachments, assistants, usage | SQLite (WAL mode) |
| `attachments\` | User-uploaded files (images, PDFs, DOCX) | SHA-256 hash filenames |
| `models_pricing.txt` (project dir) | Model pricing data | Key-value text |

All temporary data lives in `%TEMP%\`:

| Pattern | What | Lifetime |
|---|---|---|
| `ChatWindow_Req_*.json` | Chat API request payload | Per request |
| `ChatWindow_cURL_*.txt` | Generated cURL command | Per request |
| `ChatWindow_Out_*.json` | API response output | Per request |
| `ChatWindow_Err_*.txt` | cURL stderr | Per request |
| `ChatWindow_TitleGen_*.json` | Title generation payload | Per request |
| `chatHistoryJSONRequest_*.json` | Inline command request | Per request |
| `cURLCommand_*.txt` | Inline command cURL | Per request |
| `cURLOutput_*.json` | Inline command output | Per request |
| `cURLError_*.txt` | Inline command stderr | Per request |
| `LLM_Debug_Log.txt` | Rolling debug log (~500KB) | Across sessions |

User configuration: `UserConfig.ahk` (project root) — API keys, commands, hotkeys, theme.

## Layered Architecture (For Beginners)

### How This Project Is Different From Normal Web Apps

In a typical web app (React, Next.js, etc.), your JavaScript code can directly:
- Call APIs (`fetch("/api/chat")`)
- Talk to databases (`import { db } from "./db"`)
- Read/write files (`fs.readFile(...)`)
- Access the operating system

**This project can't do any of that from JavaScript.** The chat UI runs inside a WebView2 control — essentially an embedded Edge browser tab. Like any browser, it's sandboxed: no filesystem, no raw network, no native APIs.

Instead, every operation must round-trip through AutoHotkey, which acts as the backend server. But unlike a normal web app where the backend is a separate server process (often on a different machine), here the "backend" is running **on the same machine, in the same window** — just in a different layer.

### The Three Layers

```
┌──────────────────────────────────────────────────┐
│ LAYER 1: JavaScript (WebView2 — browser sandbox) │
│ • Renders chat bubbles, handles clicks            │
│ • Reads files into memory (FileReader API)        │
│ • Computes SHA-256 hashes, base64 encodes         │
│ • CANNOT: write files, call APIs, query SQLite    │
│ • Sends: chrome.webview.postMessage(json)         │
│ • Receives: window.addEventListener('message')    │
└──────────────────┬───────────────────────────────┘
                   │  in-process COM (not IPC!)
                   │  synchronous function call
                   ▼
┌──────────────────────────────────────────────────┐
│ LAYER 2: AutoHotkey (ChatWindow sub-process)     │
│ • Receives JS messages → routes to handlers       │
│ • Writes files (ImageUtils.SaveBase64ToFile)      │
│ • Queries SQLite (ChatDB.Attachment_Insert)       │
│ • Calls LLM APIs via cURL subprocess              │
│ • Reads files, encodes to base64 for API          │
│ • Sends results back to JS: postWebMessage()      │
│ • CANNOT: render HTML/CSS (that's Layer 1's job)  │
└──────────────────┬───────────────────────────────┘
                   │  WM_ messages (true IPC)
                   │  SendMessage() across processes
                   ▼
┌──────────────────────────────────────────────────┐
│ LAYER 3: AutoHotkey (Main process)               │
│ • Owns the tray icon and hotkeys                  │
│ • Shows command menu, captures text via UIA       │
│ • Spawns and manages ChatWindow sub-process       │
│ • Handles inline (non-chat) LLM requests          │
│ • Hosts API Logs Viewer and Usage Dashboard       │
│ • Reloads ChatWindow if it crashes                │
└──────────────────────────────────────────────────┘
```

### Why Three Layers Instead of One?

Layer 2 and Layer 3 run as **separate Windows processes** (two `AutoHotkey64.exe` in Task Manager). This isn't an accident:

| Reason | What It Prevents |
|--------|-----------------|
| **AHK is single-threaded** | If WebView2 and cURL polling shared the hotkey process, your `` ` `` menu would freeze during every LLM request |
| **Crash isolation** | WebView2 (Edge Chromium, ~200MB) can crash. Separate process means chat dies but hotkeys survive |
| **Pre-warming** | ChatWindow spawns hidden at startup. WebView2 takes ~2s to initialize — by the time you trigger a chat, it's ready to show instantly |

This is the same reason Chrome runs each tab in its own process, and Electron apps split into main + renderer processes.

### Concrete Example: Sending a Message With an Image Attachment

Here's what actually happens when you paste an image and press Send — trace this to understand every layer:

```
[YOU] Paste image → click Send
  │
  ▼ LAYER 1 (JS)
  │  FileReader reads file into ArrayBuffer
  │  crypto.subtle.digest('SHA-256', buffer) → content hash
  │  btoa(binary) → base64 string
  │  chrome.webview.postMessage('{"action":"chatSend","attachments":[...]}')
  │
  ▼ LAYER 2 (AHK — same process, COM call)
  │  handleChatSend() deserializes JSON
  │  ImageUtils.SaveBase64ToFile(base64, msgId, filename, hash)
  │    → CryptStringToBinaryW (Win32 Crypto API) decodes base64
  │    → FileOpen + RawWrite to %APPDATA%/.../attachments/abc123.png
  │  ChatDB.Attachment_Insert(msgId, {type, file_path, ...})
  │    → SQLite INSERT via SQLite.dll
  │  BuildAndWriteRequestFiles()
  │    → ImageUtils.ReadAndEncode(filePath) re-reads file, re-encodes
  │    → Builds JSON: {model:"gpt-4o", messages:[..., {content:[{image_url:...}]}]}
  │  sendRequestToLLM()
  │    → Writes JSON to %TEMP% file
  │    → RunWait("cURL.exe ... @file.json") — separate process
  │
  ▼ LAYER 1 again (JS, via streaming callbacks)
  │  stream.js receives SSE chunks via postWebMessage
  │  Renders markdown in chat bubble
  │  Shows token usage bar
```

Every arrow crossing from Layer 1 to Layer 2 is `chrome.webview.postMessage()` → JSON serialization → AHK handler. There is no shortcut.

### How Normal Web Apps Do This (For Contrast)

```
[YOU] Paste image → click Send
  │
  ▼ Browser JS
  │  FormData.append('file', imageFile)
  │  fetch('/api/chat', {method:'POST', body: formData})
  │
  ▼ Server (Node.js/Express, separate machine or localhost)
  │  multer saves file to disk
  │  db.attachments.insert({...})  ← direct DB access
  │  fs.readFileSync(path)         ← direct filesystem
  │  fetch('https://api.openai.com/...', {body: ...})  ← direct HTTP
  │  res.json({reply: "..."})
  │
  ▼ Browser JS
     Renders response
```

In a normal web app, the JavaScript `fetch()` call goes directly to a server that has full system access. Here, `chrome.webview.postMessage()` goes to AHK in the same process, which then orchestrates everything. The architecture is the same pattern (UI → backend → response) but compressed into a single desktop application.

### Communication Mechanisms (Quick Reference)

| You Write | What Happens | Speed | Scope |
|-----------|-------------|-------|-------|
| `chrome.webview.postMessage(json)` (JS) | WebView2 COM → AHK `OnWebMessageReceived` | ~microseconds | Same process |
| `postWebMessage(target, data)` (AHK) | AHK → WebView2 COM → JS `message` event | ~microseconds | Same process |
| `SendMessage(WM_LOAD_THREAD, ...)` (AHK) | Win32 window message → other AHK process | ~milliseconds | Cross-process |

## Directory Structure

```
ai-automation/
├── Main.ahk                         # Entry point — run this file
├── UserConfig.ahk                   # User-facing configuration (API keys, commands, theme, hotkeys)
├── lib/Config.ahk                   # Include chain — loads all vendor libs + application modules
├── ARCHITECTURE.md                  # This file
├── models_pricing.txt               # Model pricing data (refreshed via Refresh-ModelPricing.ps1)
│
├── shared/                          # Shared application utilities
│   ├── ModelParser.ahk              # Model ID parsing ("provider/model" → provider + name), version suffix stripping
│   ├── AttachmentUtils.ahk          # Vision gate (HasVision), MIME-type classification, file size checks
│   ├── ImageUtils.ahk               # Base64 encode/decode (Crypt32), GDI+ screenshot capture, file I/O
│   └── DebugLog.ahk                 # Shared debug logging (rolling ~500KB in %TEMP%) + safeDelete helper
│
├── app/                             # Application logic
│   ├── RequestProcessor.ahk         # Orchestrator: text capture → screenshot → LLM request dispatch
│   ├── TextCapture.ahk              # Text capture: UIA TextPattern (primary) + clipboard (fallback)
│   ├── InlineRequestRunner.ahk      # Non-chat cURL execution, response parsing, paste, cleanup, usage tracking
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
│   ├── ChatUtils.ahk                # Structured message building, cURL management, WebView messaging
│   ├── ThreadTitleGen.ahk           # Fire-and-forget thread title generation via cheap LLM call
│   ├── callbacks/
│   │   ├── Dispatch.ahk             # OnWebMessageReceived + callback includes
│   │   ├── Branch.ahk               # Branch nav, fork, feedback, Retry callbacks
│   │   ├── Edit.ahk                 # Edit and delete callbacks (hard-delete with re-parenting)
│   │   ├── Message.ahk              # Send + attachment delete callbacks
│   │   └── Sidebar.ahk              # Thread list, load, new, delete, trash, restore, rename, sidebar
│   ├── streaming/
│   │   ├── StreamHandler.ahk        # Streaming: cURL polling loop, SSE dispatch, finalization
│   │   ├── StreamCompletion.ahk     # Successful stream: DB persistence, API logging, title trigger
│   │   └── StreamError.ahk          # Error + cancellation: partial save, logging
│   └── db/
│       ├── ChatDB.ahk               # Facade — Open/Close, usage queries, chat_usage/command_usage UPSERT
│       ├── ThreadRepo.ahk           # Thread CRUD, settings get/set, soft-delete, restore, list
│       ├── MessageRepo.ahk          # Message CRUD, per-message token attribution, hard-delete with re-parenting
│       ├── TreeRepo.ahk             # Branch navigation, tree visualization, fork, stats, pricing lookup
│       ├── AttachmentRepo.ahk       # Attachment CRUD, content-addressable storage, ref-counted delete
│       └── AssistantRepo.ahk        # Assistant CRUD operations
│
├── api/                             # API client
│   ├── LLMRequestBuilder.ahk        # JSON request building, FIM, chat history, thinking config
│   ├── SSEParser.ahk                # SSE streaming line parser (static), thinking token extraction
│   ├── ApiLogger.ahk                # API request/response logging (static)
│   ├── CostCalculator.ahk           # Token cost calculation — cached input cost, version-stripped pricing
│   ├── CurlBuilder.ahk              # cURL command construction (static + instance)
│   ├── ProviderResolver.ahk         # Provider/endpoint resolution from model string
│   └── ResponseParser.ahk           # Response parsing (chat, FIM, streaming, error), usage extraction
│
├── ipc/                             # Inter-process communication
│   └── CustomMessages.ahk           # CustomMessages class: WM_ message constants + helpers
│
├── lib/                             # Vendor/third-party libraries
│   ├── Config.ahk                   # Include chain (see below)
│   ├── UIA.ahk                      # UI Automation library (Descolada) — programmatic UI access
│   ├── SQLite/                      # SQLite3 database wrapper (WAL mode, SQLite.Escape helper)
│   ├── ApiLogsViewer.ahk            # API logs viewer (persistent WebView2, pre-created at startup)
│   ├── UsageDashboard.ahk           # Usage dashboard (persistent WebView2, Chart.js graphs)
│   ├── Dark_Menu.ahk                # Dark theme for AHK menus
│   ├── Dark_MsgBox.ahk              # Dark mode MsgBox and InputBox
│   ├── WebViewToo.ahk               # WebView2 Framework
│   ├── WebView2.ahk                 # WebView2 Core
│   ├── jsongo.v2.ahk                # JSON parsing/serialization (returns AHK Map objects)
│   ├── AutoXYWH.ahk                 # GUI auto-resizing
│   ├── ToolTipEx.ahk                # Enhanced tooltips
│   ├── SystemThemeAwareToolTip.ahk  # Dark theme tooltips
│   ├── Promise.ahk                  # Promise/A+ implementation
│   ├── ComVar.ahk                   # COM utility
│   ├── RuntimeResolver.ahk          # Runtime path resolution
│   ├── 32bit/                       # 32-bit WebView2Loader.dll
│   └── 64bit/                       # 64-bit WebView2Loader.dll
│
├── system-messages/                 # System message text files for commands
│   ├── brutal-critic.txt
│   ├── natural-conversationalist.txt
│   ├── refine.txt
│   ├── rephrase-in-context.txt      # Uses {{fullText}} template variable
│   ├── summarize.txt
│   ├── translate-to-english.txt
│   └── violet.txt
│
├── icons/                           # Provider icons (.ico)
├── webui/                           # WebView2 frontend
│   ├── index.html                   # Chat UI (charset=utf-8, Bootstrap 5 dark mode)
│   ├── api-logs.html                # API logs viewer UI
│   ├── usage-dashboard.html         # Usage dashboard (Chart.js graphs, filtering)
│   ├── Bootstrap/                   # Bootstrap 5.3 + Chart.js (local, no CDN)
│   │   └── chart.umd.min.js         # Chart.js for usage dashboard
│   ├── css/
│   │   ├── chat.css                 # Chat layout
│   │   ├── custom.css               # Global custom styles
│   │   └── chat/                    # Chat-specific CSS modules
│   │       ├── chat-actions.css     # Message action buttons, dropdowns
│   │       ├── chat-attachments.css # Attachment bar, thumbnails, file badges
│   │       ├── chat-base.css        # Base chat layout
│   │       ├── chat-input.css       # Input area, textarea
│   │       ├── chat-messages.css    # Message bubbles, thinking animation, token tooltip
│   │       └── chat-sidebar.css     # Thread sidebar, nav bar
│   └── js/
│       ├── main.js                  # WebMessage dispatch, error display, nav toggle
│       ├── stream.js                # Streaming: SSE content rendering, cancel, persist
│       ├── usage-dashboard.js       # Usage dashboard: Chart.js graphs, filtering, CSV export
│       └── chat/                    # Chat JS modules
│           ├── chat-core.js         # initChatMode, renderMarkdown
│           ├── chat-render.js       # Message bubble creation, attachment rendering, timestamps
│           ├── chat-input.js        # Send, loading, retry, paste handling
│           ├── chat-branching.js    # Edit, delete, fork, branch nav, tree modal
│           ├── chat-sidebar.js      # Thread list, trash, fork callback
│           ├── chat-actions.js      # Message action buttons (copy, edit, retry, feedback)
│           ├── chat-format.js       # Copy, cost formatting, token usage bar
│           ├── chat-quote.js        # Quote message in input
│           ├── chat-feedback.js     # Thumbs up/down feedback
│           ├── chat-undo.js         # Undo edit/delete operations
│           ├── chat-token-tooltip.js # Per-message token info tooltip (📊 icon hover)
│           ├── attachments/         # Attachment subsystem
│           │   ├── chat-attachments.js        # State, render bar, add/remove, SHA-256 hash
│           │   ├── chat-attachments-extract.js # pdf.js + officeParser text extraction
│           │   └── chat-attachments-setup.js   # Drop zone, paste, browse, delete delegation
│           └── settings/            # Settings subsystem
│               ├── chat-settings.js         # Model/assistant/temperature/reasoning state
│               └── chat-settings-modal.js   # Settings modal UI
│
├── tests/                           # Unit + integration tests (211 AHK + 89 JS + 4 SQLite = 304)
│   ├── run_all_tests.bat            # PRIMARY ENTRY POINT — runs both AHK and JS
│   ├── run_ahk_tests.ahk            # AHK test runner (called by run_all_tests.bat)
│   ├── run_js_tests.bat             # JS test runner (called by run_all_tests.bat)
│   ├── test_config.ahk              # Test overrides (loaded after Config.ahk)
│   ├── unit/                        # Unit tests — AHK (.test.ahk) and JS (.test.js) side by side
│   │   ├── AttachmentRepo.test.ahk       # Content-addressable storage, ref-count delete
│   │   ├── AttachmentUtils.test.ahk      # HasVision, MIME classification
│   │   ├── chat-attachments.test.js      # MIME, extensions, icons, constants (36 tests)
│   │   ├── chat-format.test.js           # getMessageText, formatCost, formatCompact (22 tests)
│   │   ├── chat-input.test.js            # onChatSend payload, retry logic (5 tests)
│   │   ├── ChatDB.test.ahk               # Core DB operations, chat_usage, command_usage
│   │   ├── ChatRequestBuilder.test.ahk
│   │   ├── ChatUtils.test.ahk            # Structured messages with token fields + createdAt
│   │   ├── CostCalculator.test.ahk       # Cached input cost, pricing lookup, version stripping
│   │   ├── CustomMessages.test.ahk
│   │   ├── edit-removed-attachments.test.js # _removedAttachmentIds, commitEdit payload (7 tests)
│   │   ├── fork-function.test.js         # forkChat() definition, payload, guards (4 tests)
│   │   ├── ImageUtils.test.ahk           # Base64 encode/decode, roundtrip
│   │   ├── InlineRequestRunner.test.ahk  # FIM, command usage tracking
│   │   ├── LLMRequestBuilder.test.ahk
│   │   ├── ModelParser.test.ahk          # StripProvider, StripVersion parsing
│   │   ├── RequestProcessor.test.ahk     # Paste block, apilogs handler
│   │   ├── SQLiteEscape.test.ahk         # Escape correctness, SQL roundtrip
│   │   ├── stream-state.test.js          # streamState, _persistStreamedMessage, cancel (10 tests)
│   │   ├── StreamError.test.ahk          # Cancel-retry sibling_group preservation (2 tests)
│   │   ├── StreamHandler.test.ahk
│   │   ├── TextCapture.test.ahk          # ExpandTemplate, NormalizeLineEndings
│   │   ├── UsageDashboard.test.ahk       # Dashboard lifecycle, CloseUsageDashboard
│   │   ├── UsageTracking.test.ahk        # Per-message attribution, backfill, multi-turn, commands
│   │   └── UserConfig.test.ahk
│   └── integration/                  # Integration tests — AHK and JS side by side
│       ├── BranchFlow.test.ahk           # Branch nav, fork (title, settings, siblings, UUIDs)
│       ├── ChatFlow.test.ahk
│       ├── UsageFlow.test.ahk            # Full pipeline, multi-model, time range
│       └── edit-send-flow.test.js        # Cross-module: edit commit, attachment send, stream (5 tests)
└── agent-workspace/                 # Feature development artifacts (transient)
    ├── feature/                     # Current feature plan, reference, state
    │   └── archive/                 # Completed feature records
    └── external-docs/               # Cached external API documentation
```

## Architecture Overview

The application is an AutoHotkey v2 script that provides a hotkey-activated command menu, sends text to LLM APIs via cURL, and displays responses in a WebView2-based chat window.

### Key Design Decisions

- **Entry point**: `Main.ahk` — double-click to run.
- **User config**: `UserConfig.ahk` — all commands, API keys, hotkeys, and theme settings in one file.
- **Persistent single-window model**: A single `ChatWindow.ahk` sub-process handles all chat sessions. Close = hide (not terminate).
- **SQLite persistence**: Chat history stored in `%APPDATA%\LLM-AutoHotkey-Assistant\chat_history.db` (WAL mode). Supports branching, soft-delete, feedback, reasoning, file/image attachments, and usage tracking.
- **Content-addressable attachment storage**: Files stored by SHA-256 hash filename in `attachments/`. O(1) FileExist() dedup. Reference-counted deletion prevents orphaned files.
- **WebView2 frontend**: Chat UI rendered by Microsoft Edge WebView2. AHK ↔ JS via `PostWebMessageAsJSON` / `chrome.webview.postMessage()`.
- **cURL for API calls**: JSON request files written to `%TEMP%`, `cURL.exe` used for API communication.
- **UIA (UI Automation)**: Text is captured via Windows accessibility APIs (TextPattern) — zero scroll, no keystrokes. Clipboard capture retained as fallback.
- **All vendor libraries local**: Bootstrap, Chart.js, pdf.js, officeParser, highlight.js, katex, markdown-it — all bundled locally, no CDN dependencies.

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
| `includeImageContext` | Capture screenshot + attach to chat message | `false` |
| `isFIM` | Use FIM endpoint (ignores prompt fields) | `false` |
| `expandNewlines` | Expand single `\n` → `\n\n` paragraph breaks | `false` |
| `stream`, `thinking`, `temperature`, `maxTokens`, `stop` | API parameters | — |
| `maxContextWords` | Truncate captured text to word limit | `0` (unlimited) |

### `includeImageContext`
When `true`, `RequestProcessor` captures a screenshot via GDI+ `BitBlt` (no PrintScreen key, no clipboard) before building the request. The screenshot is saved as a PNG attachment and linked to the user message. A vision-gate check (`AttachmentUtils.HasVision()`) blocks non-vision models with a tooltip error.

### Line Ending Normalization

`TextCapture.NormalizeLineEndings()` runs on all captured text:
- Always: `\r\n` / `\r` → `\n` (lossless, free)
- Optional (`expandNewlines: true`): single `\n` → `\n\n` (paragraph breaks for LLM training data)

### FIM (Fill In the Middle)

FIM commands use a separate API endpoint (`fimEndpoint`). Prompt template fields are ignored. FIM Fill works with or without a text selection (cursor = zero-width gap). UIA TextPattern used for capture (zero scroll); paste uses `^v` (preserves undo history).

## Startup Flow

1. `Main.ahk` runs → `#Include <Config>` loads `lib/Config.ahk`
2. `Config.ahk` loads vendor libs (including `UIA.ahk`) + shared utilities + application classes
3. `Main.ahk` clears previous debug log, logs `[APP] Started`
4. `Main.ahk` calls `ChatDB.Open()` to initialize SQLite, logs `[DB] Opened`
5. `Main.ahk` creates `llmClient := LLMRequestBuilder(APIKey)` and a `commandInputWindow` instance
6. `Main.ahk` spawns `ChatWindow.ahk` as hidden sub-process with "prewarm" flag
7. `Main.ahk` registers hotkeys (default: `` ` `` to open menu)
8. `Main.ahk` pre-creates API Logs Viewer (hidden, deferred 2s) and Usage Dashboard (deferred 2.5s)
9. Script ready — tray icon appears, hotkeys active

## Request Flow

### Chat Mode (pasteMode = "chat")

```
User presses hotkey → buildCommandMenu() → onCommandSelected()
    │
    ▼
processInitialRequest()                         # app/RequestProcessor.ahk
    │  TextCapture.Capture() — UIA TextPattern → clipboard fallback
    │  Template expansion: {{selection}}, {{fullText}}, {{input}}
    │  [if includeImageContext] GDI+ screenshot capture + vision gate
    │  Creates thread in ChatDB (system + user messages + attachment)
    │  Calls openChatWindow(threadId)
    ▼
chat/ChatWindow.ahk                             # Sub-process (persistent)
    │  Loads thread from DB → initChatMode → WebView
    │  If last message is from user: auto-triggers LLM
    ▼
buildRequest() → sendRequestToLLM() → ChatDB.Msg_Insert()
    │  Per-message token attribution via subtraction
    │  Cost calculation via CostCalculator
    │  chat_usage daily aggregation UPSERT
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
    │  Extracts usage, computes costs, upserts command_usage
    ▼
Send("^v") → highlights inserted text (UIA TextPattern for FIM)
```

## Data Model (SQLite)

### `chat_threads`
| Column | Type | Description |
|--------|------|-------------|
| `id` | TEXT PRIMARY KEY | UUID |
| `title` | TEXT | Auto-generated by ThreadTitleGen |
| `is_deleted` | INTEGER | 0=active, 1=trashed (soft-delete) |
| `deleted_at` | TEXT | Timestamp when trashed |
| `created_at` | TEXT | ISO 8601 |
| `updated_at` | TEXT | ISO 8601 |
| `active_leaf_id` | TEXT | Current leaf in message tree. GetThreadStats() reads this message's active_path_tokens for the token bar. |
| `model_override` | TEXT | Per-thread model override |
| `system_override` | TEXT | Per-thread system message override |
| `reasoning_override` | TEXT | Per-thread reasoning setting |
| `temperature_override` | REAL | Per-thread temperature |
| `assistant_id` | TEXT | Per-thread assistant (pre-defined config) |
| `cumulative_input_tokens` | INTEGER | Sum of all prompt_tokens across all API calls in this thread |
| `cumulative_output_tokens` | INTEGER | Sum of all completion_tokens across all API calls |
| `cumulative_cached_tokens` | INTEGER | Sum of all cached_tokens across all API calls |
| `cumulative_cost` | REAL | Total cost in USD |
| `cumulative_input_cost` | REAL | Input token cost |
| `cumulative_cached_input_cost` | REAL | Cached input token cost |
| `cumulative_output_cost` | REAL | Output token cost |

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
| `token_count` | INTEGER | This message's context contribution (visible tokens; thinking excluded) |
| `thinking_tokens` | INTEGER | Reasoning tokens (billed, not in context) |
| `cached_tokens` | INTEGER | Cache hit tokens for the API call |
| `response_time_ms` | INTEGER | Total response time in ms |
| `ttft_ms` | INTEGER | Time to first token in ms |
| `active_path_tokens` | INTEGER | Total context tokens from root to this message. For assistants: API prompt_tokens + token_count (ground truth). For user/system: parent + token_count (prefix sum). Read by GetThreadStats() from leaf message — O(1). |
| `created_at` | TEXT | ISO 8601 |

### `message_attachments`
| Column | Type | Description |
|--------|------|-------------|
| `id` | TEXT PRIMARY KEY | UUID |
| `message_id` | TEXT | FK to messages |
| `attachment_type` | TEXT | "image", "pdf", "docx", "text_file", etc. |
| `file_path` | TEXT | Relative path in attachments/ dir |
| `mime_type` | TEXT | MIME type |
| `original_filename` | TEXT | User-visible filename |
| `file_size` | INTEGER | File size in bytes |
| `extracted_text` | TEXT | Text extracted from PDF/office files (base64 encoded) |
| `created_at` | TEXT | ISO 8601 |

### `assistants`
| Column | Type | Description |
|--------|------|-------------|
| `id` | TEXT PRIMARY KEY | UUID |
| `name` | TEXT | Display name |
| `base_model` | TEXT | Model ID (e.g. "openai/gpt-4.1") |
| `system_prompt` | TEXT | System message |
| `reasoning` | TEXT | Reasoning setting |
| `temperature` | REAL | Temperature |
| `is_default` | INTEGER | 1 if default assistant |
| `created_at` | TEXT | ISO 8601 |

### `chat_usage` — Chat API usage (daily aggregation)
| Column | Type | Description |
|--------|------|-------------|
| `date` | TEXT | 'YYYY-MM-DD' |
| `model` | TEXT | Model name |
| `provider` | TEXT | Provider (openai, deepseek, etc.) |
| `call_count` | INTEGER | Number of API calls |
| `prompt_tokens` | INTEGER | Total prompt tokens |
| `completion_tokens` | INTEGER | Total completion tokens |
| `thinking_tokens` | INTEGER | Total reasoning tokens |
| `cached_tokens` | INTEGER | Total cache hit tokens |
| `input_cost` | REAL | Input token cost |
| `cached_input_cost` | REAL | Cached input token cost |
| `output_cost` | REAL | Output token cost |
| `total_cost` | REAL | Total cost |
| `total_response_time_ms` | INTEGER | Sum of response times |
| `total_ttft_ms` | INTEGER | Sum of time-to-first-token |
| PRIMARY KEY | (date, model, provider) | |

### `command_usage` — Command API usage (daily aggregation)
| Column | Type | Description |
|--------|------|-------------|
| `date` | TEXT | 'YYYY-MM-DD' |
| `model` | TEXT | Model name |
| `provider` | TEXT | Provider |
| `command_name` | TEXT | Command name (Refine, FIM, etc.) |
| `call_count` | INTEGER | Number of calls |
| `prompt_tokens` | INTEGER | Total prompt tokens |
| `completion_tokens` | INTEGER | Total completion tokens |
| `thinking_tokens` | INTEGER | Total reasoning tokens |
| `cached_tokens` | INTEGER | Total cache hit tokens |
| `input_cost` | REAL | Input token cost |
| `cached_input_cost` | REAL | Cached input token cost |
| `output_cost` | REAL | Output token cost |
| `total_cost` | REAL | Total cost |
| `total_response_time_ms` | INTEGER | Sum of response times |
| `total_ttft_ms` | INTEGER | Sum of time-to-first-token |
| PRIMARY KEY | (date, model, provider, command_name) | |

### Branching Model
Messages form a tree via `parent_id`. When edited or retried, a new sibling is created with the same `sibling_group` and incremented `sibling_index`. `active_leaf_id` tracks current position. `TreeRepo` handles navigation, stats, fork, and visualization. `GetSiblings()` is scoped per `thread_id` to prevent cross-thread contamination.

### Per-Message Token Attribution
When an assistant message is inserted with API usage data:
1. `existing_sum = SUM(token_count)` of all messages in active path
2. `new_input = Max(0, prompt_tokens - existing_sum)` — clamped, never negative
3. Last user message's `token_count` is backfilled to `new_input`
4. Assistant gets `token_count = completion_tokens - thinking_tokens` (visible output only)
5. `active_path_tokens = existing_sum + new_input + token_count` (thinking excluded from context)

### Fork Design
`TreeRepo.ForkThread()` creates a complete copy of the conversation up to a fork point:
1. Copies the active path with fresh message UUIDs
2. Generates new `sibling_group` UUIDs mapped from originals (no cross-thread sharing)
3. Second pass copies ALL siblings in each group (not just active path) so branch nav works
4. Copies thread-level settings (model, temperature, reasoning, assistant)
5. Copies attachments via `AttachmentRepo.CopyForMessage()` (shares content-addressable files)
6. Title: "Copy - [original title]"

### Attachment Storage
Files are stored with SHA-256 content hashes as filenames (e.g., `abc123...png`) under `%APPDATA%\LLM-AutoHotkey-Assistant\attachments\`. `SaveBase64ToFile()` checks `FileExist()` before writing — O(1) dedup. `AttachmentRepo._DeleteFileIfOrphaned()` uses reference counting: only deletes the physical file when no remaining `message_attachments` rows reference it.

## WebView ↔ AHK Communication

### AHK → WebView (postWebMessage)
```javascript
postWebMessage("target", data) → JSON: {"target": "target", "data": data}
```
Key targets: `initChatMode`, `appendChatMessage`, `streamContent`, `streamReasoning`, `streamDone`, `streamCancelled`, `setChatButtonsEnabled`, `updateTokenUsage`, `updateBranchInfo`, `renderChatTree`, `threadList`, `trashList`, `loadThread`, `threadForked`, `showError`.

### WebView → AHK (via postMessage)
Dispatched by `OnWebMessageReceived` in `callbacks/Dispatch.ahk`. Actions: `chatSend`, `deleteAttachment`, `retry`, `editMessage`, `deleteMessage`, `switchBranch`, `forkChat`, `setFeedback`, `sidebarAction`, `switchAssistant`, `updateModelSettings`, `cancelStream`, `requestAssistantList`, `requestCurrentSettings`, `openUsageDashboard`.

## IPC (Inter-Process Communication)

| Message | Direction | Purpose |
|---------|-----------|---------|
| `WM_CHAT_WINDOW_OPENED` (0x500+0) | sub → main | Registers ChatWindow |
| `WM_LOADING_START` (0x400+123) | sub → main | Notifies loading started |
| `WM_LOADING_FINISH` (0x400+124) | sub → main | Notifies loading finished |
| `WM_LOAD_THREAD` (0x500+2) | main → sub | Load specific thread |
| `WM_TRIGGER_LLM` (0x500+4) | main → sub | Fire LLM for current thread |
| `WM_OPEN_USAGE_DASHBOARD` (0x500+5) | main → sub | Open usage dashboard from command menu |

## JavaScript Module Dependency Graph

Load order in `index.html` (bottom of `<body>`):
```
index.html
  └── vendor (markdown-it, katex, highlight, texmath, pdf.js, pdf.worker, officeParser)
       └── chat/chat-core.js
            ├── chat/chat-format.js
            ├── chat/chat-render.js
            ├── chat/chat-token-tooltip.js
            ├── chat/attachments/chat-attachments.js
            │    ├── chat/attachments/chat-attachments-extract.js
            │    └── chat/attachments/chat-attachments-setup.js
            ├── chat/settings/chat-settings.js
            │    └── chat/settings/chat-settings-modal.js
            ├── chat/chat-input.js
            ├── chat/chat-branching.js
            ├── chat/chat-sidebar.js
            ├── chat/chat-quote.js
            ├── chat/chat-feedback.js
            ├── chat/chat-undo.js
            ├── chat/chat-actions.js
            ├── stream.js
            └── main.js (orchestrator + WebMessage dispatch)
```

## Usage Dashboard

A separate WebView2 window accessed from the tray menu or chat UI. Charts rendered with Chart.js (bundled locally):

- **Summary cards**: Total tokens, total cost (with ⓘ cost breakdown tooltip), total API calls
- **Main chart**: Stacked bar chart of costs over time (toggle: cost/tokens)
- **Per-model sections**: Line/area chart for requests + stacked bar chart for tokens per model
- **Filters**: Time range (All Time, Last 30 Days, This Month, Last Month, Last 24 Hours), type (All/Chat/Commands), provider, model
- **CSV export**: Full data export with all token and cost columns
- Data sourced from `chat_usage` and `command_usage` tables via `ChatDB.Usage_Query()`

## Debug Logging

Rolling log at `%TEMP%\LLM_Debug_Log.txt` (~500KB kept when file exceeds 1MB). Structured prefixes for grep-ability:

| Prefix | When | Example |
|--------|------|---------|
| `[APP]` | Startup/shutdown/ChatWindow | `[APP] Started` |
| `[DB]` | Database open | `[DB] Opened — path=...` |
| `[API]` | LLM requests | `[API] Chat done — prompt=1500 completion=300 cached=50 response_time=1200ms model=gpt-4.1` |
| `[STREAM]` | Stream lifecycle | `[STREAM] Started/Done/Cancelled/Error` |
| `[THREAD]` | Thread operations | `[THREAD] Created/Deleted/Forked` |
| `[BRANCH]` | Branch switches | `[BRANCH] Switch — thread=42 leaf=abc` |
| `[EDIT]` / `[DELETE]` | Message edits/deletes | `[EDIT] Message — id=...` |
| `[ATTACH]` | Attachment operations | `[ATTACH] Sent — 3 files (image=1 doc=2)` |
| `[SETTINGS]` | Thread settings | `[SETTINGS] Saved — thread=42 model=gpt-4.1 systemMsg=0chars` |
| `[MODEL]` | Model/assistant switches | `[MODEL] Switched to assistant: Coder (gpt-4.1)` |
| `[USAGE]` | Token attribution | `[USAGE] Chat — prompt=1500 completion=300 cached=50` |
| `[COST]` | Cost calculation | `[COST] Chat — input=$0.0030 cached=$0.0002 output=$0.0120 total=$0.0152` |
| `[DASHBOARD]` | Usage dashboard | `[DASHBOARD] Opened / Query — chat=5 rows cmd=3 rows` |

## Attachment Pipeline (JS → AHK → DB → API)

```
User drags/pastes/browses file
    │  chat-attachments-setup.js: event → addAttachment()
    ▼
chat-attachments.js: FileReader → base64 + SHA-256 hash
    │  pdf.js / officeParser: text extraction (async)
    │  renderAttachmentBar(): thumbnail or file badge with ×
    ▼
chat-input.js: onChatSend() → getAttachmentsForSend()
    │  Payload: { action: "chatSend", content, attachments: [{type, filename, base64, contentHash, ...}] }
    ▼
chat/callbacks/Message.ahk: handleChatSend()
    │  ImageUtils.SaveBase64ToFile(base64, msgId, filename, contentHash)
    │  → content-addressable: SHA-256 hash as filename, FileExist() dedup
    │  ChatDB.Attachment_Insert(msgId, {type, file_path, mime_type, ...})
    │  Logs: [ATTACH] Sent — N files (image=X doc=Y)
    ▼
chat/ChatRequestBuilder.ahk: buildRequest()
    │  ImageUtils.ReadAndEncode(filePath) → base64 for API
    │  AttachmentUtils.HasVision(model) → vision gate
    │  Includes images as vision content blocks in API request
    │  Logs: [API] Chat send — model=... thread=... pathLen=...
    ▼
cURL → LLM API
```

## Testing

### How to Run All Tests

Copy and paste into terminal from the project root:

```
tests\run_all_tests.bat
```

This runs AHK tests (211) then JS tests (89) and SQLite tests (4) — 304 total. Alternatively:

```
tests\run_ahk_tests.ahk          # AHK only
tests\run_js_tests.bat           # JS only
```

### Test Structure

AHK (`.test.ahk`) and JS (`.test.js`) tests live side by side in the same directories, distinguished by file extension. See the directory tree above for the full listing. Summary:

| Directory | AHK Files | JS Files | Total Tests |
|-----------|----------|----------|-------------|
| `unit/` | 19 | 6 | ~254 |
| `integration/` | 3 | 1 | ~50 |
| **Total** | **22** | **7** | **~304** |

### Output Format

**AHK tests:**
```
[PASS] ClassName.MethodName
[FAIL] ClassName.MethodName — Error message
---
N tests run | X passed | Y failed
```

**JS tests (node:test TAP output):**
```
▶ getAttachmentTypeFromMime
  ✔ identifies images from MIME type
✔ getAttachmentTypeFromMime
ℹ tests 89 | pass 89 | fail 0
```

Tests: 211 AHK + 89 JS + 4 SQLite = 304 total. Run on every commit via `run_all_tests.bat`.
