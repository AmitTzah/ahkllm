# LLM AutoHotkey Assistant — Architecture Guide

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
│   ├── ModelParser.ahk              # Model ID parsing ("provider/model" → provider + name)
│   ├── TokenEstimation.ahk          # Character-based token estimation (~4 chars/token)
│   ├── AttachmentUtils.ahk          # Vision gate (HasVision), MIME-type classification, file size checks
│   ├── ImageUtils.ahk               # Base64 encode/decode (Crypt32), GDI+ screenshot capture, file I/O
│   └── DebugLog.ahk                 # Shared debug logging + safeDelete helper
│
├── app/                             # Application logic
│   ├── RequestProcessor.ahk         # Orchestrator: text capture → screenshot → LLM request dispatch
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
│   │   ├── Message.ahk              # Send + attachment delete callbacks
│   │   └── Sidebar.ahk              # Thread list, load, new, delete, trash, restore, rename, sidebar
│   ├── streaming/
│   │   ├── StreamHandler.ahk        # Streaming: cURL polling loop, SSE dispatch, finalization
│   │   ├── StreamCompletion.ahk     # Successful stream: DB persistence, API logging, title trigger
│   │   └── StreamError.ahk          # Error + cancellation: partial save, token estimation, logging
│   └── db/
│       ├── ChatDB.ahk               # Facade — static Open/Close + delegation to repos
│       ├── ThreadRepo.ahk           # Thread CRUD, settings get/set, soft-delete, restore, list
│       ├── MessageRepo.ahk          # Message CRUD, hard-delete with re-parenting
│       ├── TreeRepo.ahk             # Branch navigation, tree visualization, fork, stats, pricing
│       ├── AttachmentRepo.ahk       # Attachment CRUD, content-addressable storage, ref-counted delete
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
│   ├── SQLite/                      # SQLite3 database wrapper (WAL mode, SQLite.Escape helper)
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
│   ├── Bootstrap/                   # Bootstrap 5.3 (local, no CDN)
│   ├── css/
│   │   ├── chat.css                 # Chat layout
│   │   ├── custom.css               # Global custom styles
│   │   └── chat/                    # Chat-specific CSS modules
│   │       ├── chat-actions.css     # Message action buttons, dropdowns
│   │       ├── chat-attachments.css # Attachment bar, thumbnails, file badges
│   │       ├── chat-base.css        # Base chat layout
│   │       ├── chat-input.css       # Input area, textarea
│   │       ├── chat-messages.css    # Message bubbles, thinking animation
│   │       └── chat-sidebar.css     # Thread sidebar, nav bar
│   └── js/
│       ├── main.js                  # WebMessage dispatch, error display, nav toggle
│       ├── stream.js                # Streaming: SSE content rendering, cancel, persist
│       └── chat/                    # Chat JS modules
│           ├── chat-core.js         # initChatMode, renderMarkdown
│           ├── chat-render.js       # Message bubble creation, attachment rendering
│           ├── chat-input.js        # Send, loading, retry, paste handling
│           ├── chat-branching.js    # Edit, delete, fork, branch nav, tree modal
│           ├── chat-sidebar.js      # Thread list, trash, fork callback
│           ├── chat-actions.js      # Message action buttons (copy, edit, retry, feedback)
│           ├── chat-format.js       # Copy, cost formatting, token usage bar
│           ├── chat-quote.js        # Quote message in input
│           ├── chat-feedback.js     # Thumbs up/down feedback
│           ├── chat-undo.js         # Undo edit/delete operations
│           ├── attachments/         # Attachment subsystem
│           │   ├── chat-attachments.js        # State, render bar, add/remove, SHA-256 hash
│           │   ├── chat-attachments-extract.js # pdf.js + officeParser text extraction
│           │   └── chat-attachments-setup.js   # Drop zone, paste, browse, delete delegation
│           └── settings/            # Settings subsystem
│               ├── chat-settings.js         # Model/assistant/temperature/reasoning state
│               └── chat-settings-modal.js   # Settings modal UI
│
├── tests/                           # Unit + integration tests (~252 AHK + 11 JS)
│   ├── run_all_tests.bat            # PRIMARY ENTRY POINT — runs both AHK and JS
│   ├── run_ahk_tests.ahk            # AHK test runner (run_all_tests.bat calls this)
│   ├── test_config.ahk              # Test overrides (loaded after Config.ahk)
│   ├── js/                          # JavaScript unit tests (Node.js node:test, zero deps)
│   │   └── unit/
│   │       └── chat-attachments.test.js
│   ├── unit/
│   │   ├── TextCapture.test.ahk
│   │   ├── RequestProcessor.test.ahk
│   │   ├── ChatDB.test.ahk
│   │   ├── AttachmentRepo.test.ahk
│   │   ├── AttachmentUtils.test.ahk
│   │   ├── ImageUtils.test.ahk
│   │   ├── SQLiteEscape.test.ahk
│   │   ├── LLMRequestBuilder.test.ahk
│   │   ├── ChatUtils.test.ahk
│   │   ├── StreamHandler.test.ahk
│   │   ├── ChatRequestBuilder.test.ahk
│   │   ├── CustomMessages.test.ahk
│   │   ├── InlineRequestRunner.test.ahk
│   │   └── UserConfig.test.ahk
│   └── integration/
│       ├── ChatFlow.test.ahk
│       └── BranchFlow.test.ahk      # Branch nav, fork, sibling group, attachments
└── agent-workspace/                 # Feature development artifacts (transient)
    ├── feature/                     # Current feature plan, reference, state
    └── external-docs/               # Cached external API documentation
```

## Architecture Overview

The application is an AutoHotkey v2 script that provides a hotkey-activated command menu, sends text to LLM APIs via cURL, and displays responses in a WebView2-based chat window.

### Key Design Decisions

- **Entry point**: `Main.ahk` — double-click to run.
- **User config**: `UserConfig.ahk` — all commands, API keys, hotkeys, and theme settings in one file.
- **Persistent single-window model**: A single `ChatWindow.ahk` sub-process handles all chat sessions. Close = hide (not terminate).
- **SQLite persistence**: Chat history stored in `%APPDATA%\LLM-AutoHotkey-Assistant\chat_history.db` (WAL mode). Supports branching, soft-delete, feedback, reasoning, and file/image attachments.
- **Content-addressable attachment storage**: Files stored by SHA-256 hash filename in `attachments/`. O(1) FileExist() dedup. Reference-counted deletion prevents orphaned files.
- **WebView2 frontend**: Chat UI rendered by Microsoft Edge WebView2. AHK ↔ JS via `PostWebMessageAsJSON` / `chrome.webview.postMessage()`.
- **cURL for API calls**: JSON request files written to `%TEMP%`, `cURL.exe` used for API communication.
- **UIA (UI Automation)**: Text is captured via Windows accessibility APIs (TextPattern) — zero scroll, no keystrokes. Clipboard capture retained as fallback.
- **All vendor libraries local**: Bootstrap, pdf.js, officeParser, highlight.js, katex, markdown-it — all bundled locally, no CDN dependencies.

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
    │  [if includeImageContext] GDI+ screenshot capture + vision gate
    │  Creates thread in ChatDB (system + user messages + attachment)
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

### `chat_threads`
| Column | Type | Description |
|--------|------|-------------|
| `id` | TEXT PRIMARY KEY | UUID |
| `title` | TEXT | Auto-generated by ThreadTitleGen |
| `is_deleted` | INTEGER | 0=active, 1=trashed (soft-delete) |
| `deleted_at` | TEXT | Timestamp when trashed |
| `created_at` | TEXT | ISO 8601 |
| `updated_at` | TEXT | ISO 8601 |
| `active_leaf_id` | TEXT | Current position in message tree |
| `active_path_tokens` | INTEGER | Context Used counter |
| `model_override` | TEXT | Per-thread model override |
| `system_override` | TEXT | Per-thread system message override |
| `reasoning_override` | TEXT | Per-thread reasoning setting |
| `temperature_override` | REAL | Per-thread temperature |
| `assistant_id` | TEXT | Per-thread assistant (pre-defined config) |
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
| `prompt_tokens` | INTEGER | Prompt token count from API |
| `completion_tokens` | INTEGER | Completion token count |
| `total_tokens` | INTEGER | Total tokens |
| `cached_tokens` | INTEGER | Cache hit tokens |

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
| `extracted_text` | TEXT | Text extracted from PDF/office files |
| `created_at` | TEXT | ISO 8601 |

### Branching Model
Messages form a tree via `parent_id`. When edited or retried, a new sibling is created with the same `sibling_group` and incremented `sibling_index`. `active_leaf_id` tracks current position. `TreeRepo` handles navigation, stats, fork, and visualization. `GetSiblings()` is scoped per `thread_id` to prevent cross-thread contamination.

### Fork Design
`TreeRepo.ForkThread()` creates a complete copy of the conversation up to a fork point:
1. Copies the active path with fresh message UUIDs
2. Generates new `sibling_group` UUIDs mapped from originals (no cross-thread sharing)
3. Second pass copies ALL siblings in each group (not just active path) so branch nav works
4. Copies thread-level settings (model, temperature, reasoning, assistant)
5. Copies attachments via `AttachmentRepo.CopyForMessage()` (shares content-addressable files)
6. Title: "Copy - [original title]"

### Attachment Storage
Files are stored with SHA-256 content hashes as filenames (e.g., `abc123...png`). `SaveBase64ToFile()` checks `FileExist()` before writing — O(1) dedup. `AttachmentRepo._DeleteFileIfOrphaned()` uses reference counting: only deletes the physical file when no remaining `message_attachments` rows reference it.

## WebView ↔ AHK Communication

### AHK → WebView (postWebMessage)
```javascript
postWebMessage("target", data) → JSON: {"target": "target", "data": data}
```
Key targets: `initChatMode`, `appendChatMessage`, `streamContent`, `streamReasoning`, `streamDone`, `streamCancelled`, `setChatButtonsEnabled`, `updateTokenUsage`, `updateBranchInfo`, `renderChatTree`, `threadList`, `trashList`, `loadThread`, `threadForked`, `showError`.

### WebView → AHK (via postMessage)
Dispatched by `OnWebMessageReceived` in `callbacks/Dispatch.ahk`. Actions: `chatSend`, `deleteAttachment`, `retry`, `editMessage`, `deleteMessage`, `switchBranch`, `forkChat`, `setFeedback`, `sidebarAction`, `switchAssistant`, `updateModelSettings`, `cancelStream`, `requestAssistantList`, `requestCurrentSettings`.

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
  └── vendor (markdown-it, katex, highlight, texmath, pdf.js, pdf.worker, officeParser)
       └── chat/chat-core.js
            ├── chat/chat-format.js
            ├── chat/chat-render.js
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
    ▼
chat/ChatRequestBuilder.ahk: buildRequest()
    │  ImageUtils.ReadAndEncode(filePath) → base64 for API
    │  AttachmentUtils.HasVision(model) → vision gate
    │  Includes images as vision content blocks in API request
    ▼
cURL → LLM API
```

## Testing

### How to Run All Tests

**Primary entry point (runs both AHK and JS tests):**
```bash
tests\run_all_tests.bat
```

**AHK tests only:**
```bash
"AutoHotkey64.exe" tests\run_ahk_tests.ahk
```

**JS tests only:**
```bash
node --test tests/js/unit/*.test.js
```

### Test Structure
```
ai-automation/tests/
├── run_all_tests.bat              # PRIMARY ENTRY POINT — runs both AHK + JS
├── run_ahk_tests.ahk              # AHK test runner (called by run_all_tests.bat)
├── test_config.ahk                # Test overrides (loaded after Config.ahk)
├── js/                            # JavaScript unit tests (Node.js node:test, zero npm deps)
│   └── unit/
│       └── chat-attachments.test.js    # MIME classification, extension allow-list
├── unit/                          # AHK unit tests (14 files, ~200 tests)
│   ├── AttachmentRepo.test.ahk         # Content-addressable storage, ref-count delete
│   ├── AttachmentUtils.test.ahk        # HasVision, MIME classification
│   ├── ChatDB.test.ahk                 # Core DB operations
│   ├── ChatRequestBuilder.test.ahk
│   ├── ChatUtils.test.ahk
│   ├── CustomMessages.test.ahk
│   ├── ImageUtils.test.ahk             # Base64 encode/decode, roundtrip
│   ├── InlineRequestRunner.test.ahk
│   ├── LLMRequestBuilder.test.ahk
│   ├── RequestProcessor.test.ahk       # Paste block, apilogs handler
│   ├── SQLiteEscape.test.ahk           # Escape correctness, SQL roundtrip
│   ├── StreamHandler.test.ahk
│   ├── TextCapture.test.ahk            # ExpandTemplate, NormalizeLineEndings
│   └── UserConfig.test.ahk
└── integration/                    # AHK integration tests (2 files, ~50 tests)
    ├── BranchFlow.test.ahk             # Branch nav, fork (title, settings, siblings, UUIDs)
    └── ChatFlow.test.ahk
```

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
  ✔ identifies PDF from MIME type
✔ getAttachmentTypeFromMime
ℹ tests 11 | pass 11 | fail 0
```

Tests: ~252 AHK + 11 JS (growing). Run on every commit via `run_all_tests.bat`.
