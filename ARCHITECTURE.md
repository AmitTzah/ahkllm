# LLM AutoHotkey Assistant — Architecture Guide

## Contents

- [Data Storage Locations](#data-storage-locations)
- [Layered Architecture (For Beginners)](#layered-architecture-for-beginners)
- [Directory Structure](#directory-structure)
- [Architecture Overview](#architecture-overview)
- [Command System](#command-system)
- [Startup Flow](#startup-flow)
- [Request Flow](#request-flow)
- [Data Model (SQLite)](#data-model-sqlite)
- [WebView ↔ AHK Communication](#webview--ahk-communication)
- [IPC (Inter-Process Communication)](#ipc-inter-process-communication)
- [JavaScript Module Dependency Graph](#javascript-module-dependency-graph)
- [Usage Dashboard](#usage-dashboard)
- [Debug Logging](#debug-logging)
- [Testing](#testing)

---

## Data Storage Locations

All persistent data lives under `%APPDATA%\LLM-AutoHotkey-Assistant\`:

| Path | What | Format |
|---|---|---|
| `chat_history.db` | Chat threads, messages, attachments, assistants, folders, usage, FTS5 search index | SQLite (WAL mode) |
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

User configuration: `UserConfig.ahk` (project root) — API keys, commands, hotkeys, theme (light only).

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
│ • Hosts inline dashboard + API logs viewer        │
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
│ • Hosts API Logs Viewer (pre-created at startup)  │
│ • Provides ShowApiLogs() + ShowUsageDashboard()   │
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
├── UserConfig.ahk                   # User-facing configuration (API keys, commands, hotkeys)
├── lib/Config.ahk                   # Include chain — loads all vendor libs + application modules
├── ARCHITECTURE.md                  # This file
├── models_pricing.txt               # Model pricing data (refreshed via Refresh-ModelPricing.ps1)
│
├── shared/                          # Shared application utilities
│   ├── ModelParser.ahk              # Model ID parsing ("provider/model" → provider + name)
│   ├── AttachmentUtils.ahk          # Vision gate, MIME-type classification, file size checks
│   ├── ImageUtils.ahk               # Base64 encode/decode, GDI+ screenshot capture, file I/O
│   ├── DebugLog.ahk                 # Rolling debug log (~500KB in %TEMP%) + safeDelete helper
│   └── RuntimeResolver.ahk          # API key check, provider resolution, default assistant
│
├── app/                             # Application logic
│   ├── RequestProcessor.ahk         # Orchestrator: text capture → LLM request dispatch
│   ├── TextCapture.ahk              # UIA TextPattern (primary) + clipboard (fallback)
│   ├── InlineRequestRunner.ahk      # Non-chat cURL execution, response parsing, paste
│   ├── InputWindow.ahk              # GUI popup for custom prompts (light mode only)
│   ├── LoadingTracker.ahk           # Active request tracking, loading state, IPC handler
│   ├── LoadingUI.ahk                # Cursor changes, tooltip display, suspend banner toggle
│   ├── menu/                        # Command menu system
│   │   ├── CommandMenu.ahk          # Menu building: command menu, tags, submenus
│   │   └── CommandState.ahk         # Command state management
│   └── viewers/                     # Persistent WebView2 viewer windows
│       ├── ApiLogsViewer.ahk        # API logs viewer (persistent WebView2)
│       └── UsageDashboard.ahk       # IPC relay — sends showDashboard to ChatWindow
│
├── chat/                            # Persistent chat window (sub-process)
│   ├── ChatWindow.ahk               # Window lifecycle, WebView2 creation, show/hide, pre-warm,
│   │                                #   Dashboard host object, WM_SHOW_DASHBOARD handler
│   ├── ChatIPC.ahk                  # IPC handlers: OnLoadThread, OnTriggerLLM
│   ├── ChatSettings.ahk             # Thread settings, assistant/model management, dropdown label
│   ├── ChatRequestBuilder.ahk       # buildRequest, sendRequestToLLM, cancel stream
│   ├── ChatUtils.ahk                # Structured message building, cURL state, postWebMessage
│   ├── ThreadTitleGen.ahk           # Fire-and-forget thread title generation
│   ├── callbacks/
│   │   ├── Dispatch.ahk             # OnWebMessageReceived + callback includes
│   │   │                            #   Includes showApiLogs IPC handler
│   │   ├── Branch.ahk               # Branch navigation, fork, retry
│   │   ├── Edit.ahk                 # Edit and delete callbacks
│   │   ├── Message.ahk              # Send + attachment delete callbacks
│   │   └── Sidebar.ahk              # Thread list, folders, trash, rename, navigation
│   ├── streaming/
│   │   ├── StreamHandler.ahk        # Streaming: cURL polling, SSE dispatch, finalization
│   │   ├── StreamCompletion.ahk     # Successful stream: DB persistence, API logging
│   │   └── StreamError.ahk          # Error + cancellation: partial save, logging,
│   │                                #   handleCancelStream (moved from ChatRequestBuilder)
│   └── db/
│       ├── ChatDB.ahk               # Facade — Open/Close, usage queries, schema
│       ├── ThreadRepo.ahk           # Thread CRUD, settings, soft-delete, restore
│       ├── MessageRepo.ahk          # Message CRUD, token attribution, hard-delete
│       ├── TreeRepo.ahk             # Branch navigation, tree viz, fork, stats, pricing
│       ├── AttachmentRepo.ahk       # Content-addressable storage, ref-counted delete
│       ├── AssistantRepo.ahk        # Assistant CRUD (includes description field)
│       └── UsageRepo.ahk            # Daily usage aggregation + dashboard queries
│
├── api/                             # API client
│   ├── LLMRequestBuilder.ahk        # JSON request building, FIM, thinking config
│   ├── SSEParser.ahk                # SSE streaming line parser
│   ├── ApiLogger.ahk                # API request/response logging
│   ├── CostCalculator.ahk           # Token cost calculation
│   ├── CurlBuilder.ahk              # cURL command construction
│   ├── ProviderResolver.ahk         # Provider/endpoint resolution
│   └── ResponseParser.ahk           # Response parsing, usage extraction
│
├── ipc/                             # Inter-process communication
│   └── CustomMessages.ahk           # WM_ message constants + helpers
│                                    #   WM_SHOW_DASHBOARD, WM_SHOW_API_LOGS, WM_LOAD_THREAD
│
├── lib/                             # Vendor/third-party libraries
│   ├── Config.ahk                   # Include chain
│   ├── UIA.ahk                      # UI Automation library (Descolada)
│   ├── SQLite/                      # SQLite3 wrapper (WAL mode)
│   ├── WebViewToo.ahk               # WebView2 Framework
│   ├── WebView2.ahk                 # WebView2 Core
│   ├── jsongo.v2.ahk                # JSON parsing/serialization
│   ├── AutoXYWH.ahk                 # GUI auto-resizing
│   ├── ToolTipEx.ahk                # Enhanced tooltips
│   ├── Promise.ahk                  # Promise/A+ implementation
│   ├── ComVar.ahk                   # COM utility
│   ├── 32bit/                       # 32-bit WebView2Loader.dll
│   └── 64bit/                       # 64-bit WebView2Loader.dll
│
├── system-messages/                 # System message text files for commands/assistants
│   ├── brutal-critic.txt
│   ├── natural-conversationalist.txt
│   ├── refine.txt
│   ├── rephrase-in-context.txt
│   ├── summarize.txt
│   ├── translate-to-english.txt
│   └── violet.txt
│
├── icons/                           # Provider icons (.ico) + tray icons
│   ├── anthropic.ico, deepseek.ico, google.ico, openai.ico, openrouter.ico, perplexity.ico
│   └── IconOn.ico, IconOff.ico, Scribblemate.ico
│
├── webui/                           # WebView2 frontend (light mode only)
│   ├── index.html                   # Main chat UI — 4-column SaaS layout
│   │                                #   Includes inline Usage Dashboard panel
│   ├── api-logs.html                # API logs viewer UI (light mode only)
│   ├── fonts/                       # Local fonts (Inter + JetBrains Mono, no CDN)
│   │   ├── fonts.css                # Imports inter.css + jetbrains-mono.css
│   │   ├── inter.css                # @font-face declarations (400,500,600,700)
│   │   ├── inter-latin-*.ttf
│   │   ├── jetbrains-mono.css       # @font-face declarations (400,500,600)
│   │   └── jetbrains-mono-latin-*.ttf
│   ├── css/                         # Modular CSS (10 files, no Bootstrap)
│   │   ├── theme.css                # CSS variables, reset, font-face
│   │   ├── layout.css               # App layout, panels, seams, resizers
│   │   ├── left-panel.css           # Folders, chat items, trash
│   │   ├── center.css               # Topbar, thread, composer
│   │   ├── messages.css             # Message bubbles, thinking block, edit UI
│   │   ├── actions.css              # Action buttons, branch nav, stat popover
│   │   ├── right-panel.css          # Config fields, model card, thread map
│   │   ├── modals.css               # Tree modal, sysmsg modal
│   │   ├── popover.css              # Model/assistant popover
│   │   ├── components.css           # Buttons, switches, scrollbars, tooltips
│   │   └── vendor/                  # Katex, texmath, highlight themes
│   └── js/
│       ├── main.js                  # WebMessage dispatch, dashboard toggle, sidebar toggle
│       ├── ui-controls.js           # Panel resize, font controls, composer resize, auto-collapse
│       ├── usage-dashboard.js       # Inline dashboard: Chart.js graphs, filtering, CSV export
│       ├── vendor/                  # Local JS libraries (no CDN)
│       │   ├── lucide.min.js        # Icon library (replaces emoji)
│       │   ├── chart.umd.min.js     # Chart.js for usage dashboard
│       │   ├── markdown-it.min.js, katex.min.js, mhchem.min.js
│       │   ├── texmath.min.js, highlight.min.js
│       │   ├── pdf.min.js, pdf.worker.min.js, officeparser.iife.js
│       └── chat/                    # Chat JS modules (all stateful)
│           ├── chat-core.js         # State, initChatMode, escHtml, shared _showConfirm/_makeInlineEditor
│           ├── chat-render.js       # Message bubble HTML generation (extracted helpers)
│           │                        #   _buildMetaText, _buildReasoningHtml, _buildAttachmentHtml, _buildEditUiHtml
│           ├── chat-input.js        # Send, loading indicator, retry
│           ├── chat-branching.js    # Edit, delete, fork, branch nav, tree modal
│           ├── chat-tree-modal.js   # Conversation tree visualization with zoom/pan
│           ├── chat-sidebar.js      # Thread list, folders, thread switching, topbar title
│           ├── chat-threadmap.js    # Right-panel thread map nav, scrollToMessage
│           ├── chat-trash.js        # Trash list sidebar
│           ├── chat-actions.js      # Message action buttons (Lucide icons)
│           ├── chat-format.js       # Copy, cost formatting, token usage bar
│           ├── chat-quote.js        # Quote message
│           ├── chat-token-tooltip.js # Per-message token info popover
│           ├── chat-search.js       # Real-time message search
│           ├── stream.js            # SSE streaming: content rendering, cancel, persist
│           ├── attachments/         # Attachment subsystem
│           │   ├── chat-attachments.js        # State, render bar, add/remove, SHA-256
│           │   ├── chat-attachments-extract.js # pdf.js + officeParser text extraction
│           │   └── chat-attachments-setup.js   # Drop zone, paste, browse, delete
│           └── settings/            # Settings subsystem
│               ├── chat-settings.js         # Model/assistant popover, provider icons
│               │                            #   Split: _populateAssistantsTab, _populateModelsTab
│               └── chat-settings-modal.js   # Right panel config: system prompt, temperature, thinking
│
├── tests/                           # Unit + integration tests
│   ├── run_all_tests.bat            # PRIMARY ENTRY POINT
│   ├── run_ahk_tests.ahk            # AHK test runner
│   ├── run_js_tests.bat             # JS test runner (node:test)
│   ├── test_config.ahk              # Test overrides (loaded after Config.ahk)
│   ├── unit/                        # Unit tests — AHK (.test.ahk) and JS (.test.js)
│   │   └── [19 AHK + 13 JS test files]
│   └── integration/                 # Integration tests
│       ├── BranchFlow.test.ahk
│       ├── ChatFlow.test.ahk
│       ├── UsageFlow.test.ahk
│       ├── chat-folders.test.js     # Folder-aware thread list
│       └── edit-send-flow.test.js
└── agent-workspace/                 # Feature development artifacts (transient)
    ├── feature/
    │   └── archive/                 # Completed feature records
    └── external-docs/               # Cached external API documentation
```

## Architecture Overview

The application is an AutoHotkey v2 script that provides a hotkey-activated command menu, sends text to LLM APIs via cURL, and displays responses in a WebView2-based chat window.

### Key Design Decisions

- **Entry point**: `Main.ahk` — double-click to run.
- **User config**: `UserConfig.ahk` — all commands, API keys, hotkeys, and theme in one file.
- **Persistent single-window model**: A single `ChatWindow.ahk` sub-process handles all chat sessions. Close = hide (not terminate).
- **SQLite persistence**: Chat history stored in `%APPDATA%\LLM-AutoHotkey-Assistant\chat_history.db` (WAL mode). Supports branching, soft-delete, reasoning, file/image attachments, folders, and usage tracking.
- **Content-addressable attachment storage**: Files stored by SHA-256 hash. O(1) FileExist() dedup. Reference-counted deletion.
- **WebView2 frontend**: Chat UI rendered by Microsoft Edge WebView2. AHK ↔ JS via `PostWebMessageAsJSON` / `chrome.webview.postMessage()`.
- **cURL for API calls**: JSON request files written to `%TEMP%`, `cURL.exe` used for API communication.
- **UIA (UI Automation)**: Text captured via Windows accessibility APIs (TextPattern) — zero scroll, no keystrokes.
- **All vendor libraries local**: Lucide, Chart.js, pdf.js, officeParser, highlight.js, katex, markdown-it — all bundled locally, no CDN dependencies.
- **Light mode only**: Dark mode removed. CSS variable system supports future dark mode addition.
- **Inline dashboard**: Usage dashboard embedded in main GUI (toggled via icon rail). No separate window.
- **Folder persistence**: `chat_folders` SQLite table with `folder_id` FK on `chat_threads`. Full CRUD via sidebar.

### UI Design System

The chat UI uses a custom 4-column SaaS-style layout with CSS custom properties:

```
┌──────┬────────────────┬──────────────────────┬──────────┐
│ Icon │  Left Panel    │  Center (Chat/        │  Right   │
│ Rail │  (340px)       │   Dashboard)          │  Panel   │
│ 80px │  ┌──────────┐  │  flex: 1              │ (400px)  │
│      │  │ Folders  │  │  ┌────────────────┐  │ ┌──────┐ │
│  💬   │  │ Chats    │  │  │ Topbar / Dash  │  │ │Config│ │
│  📊   │  │ Search   │  │  │ Thread Area    │  │ │Model │ │
│  ⚙    │  │ Trash    │  │  │ Composer       │  │ │Temp  │ │
│      │  └──────────┘  │  └────────────────┘  │ │Think │ │
└──────┴────────────────┴──────────────────────┴──────────┘
        ↕ resizable        ↕ resizable          ↕ resizable
```

- **Icon Rail**: Brand mark, Chats (active), Dashboard, Settings icons
- **Left Panel**: Folder-based chat list with inline rename, move-to-folder dropdown, collapsible trash
- **Center**: Chat thread OR inline Usage Dashboard (toggled via icon rail)
- **Right Panel**: Configuration (model card, system prompt, temperature, thinking), Thread Map
- **Modals**: Conversation Tree (zoomable/pannable), System Prompt editor, Model/Assistant popover

Fonts: Inter (UI) + JetBrains Mono (code), loaded locally. Icons: Lucide (replaces emoji).

## Command System

### Template Variables

| Variable | Source | Description |
|----------|--------|-------------|
| `{{selection}}` | UIA TextPattern / clipboard | User's highlighted text |
| `{{fullText}}` | UIA DocumentRange (lazy) | Entire document text |
| `{{input}}` | Input box (if `showInputBox: true`) | User-typed instruction |

### Command Fields

| Field | Purpose | Default |
|-------|---------|---------|
| `commandName`, `menuText`, `APIModels` | Required | — |
| `systemMessage` / `systemMessageFile` | System prompt (supports templates) | — |
| `userMessage` | User prompt template | *(none)* |
| `showInputBox` | Open text input before sending | `false` |
| `pasteMode` | `"chat"`, `"replace"`, `"append"` | `"chat"` |
| `includeImageContext` | Capture screenshot + attach to chat | `false` |
| `isFIM` | Use FIM endpoint | `false` |
| `expandNewlines` | Expand `\n` → `\n\n` paragraph breaks | `false` |
| `stream`, `thinking`, `temperature`, `maxTokens`, `stop` | API parameters | — |

## Startup Flow

1. `Main.ahk` runs → `#Include <Config>` loads `lib/Config.ahk`
2. `Config.ahk` loads vendor libs + shared utilities + application classes
3. `Main.ahk` clears debug log, logs `[APP] Started`
4. `Main.ahk` calls `ChatDB.Open()` to initialize SQLite
5. `Main.ahk` spawns `ChatWindow.ahk` as hidden sub-process with "prewarm" flag
6. `Main.ahk` registers hotkeys (default: `` ` `` to open menu)
7. `Main.ahk` pre-creates API Logs Viewer (deferred 2s)
8. Script ready — tray icon appears ("LLM AutoHotkey Assistant"), hotkeys active

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

## Data Model (SQLite)

### `chat_folders`
| Column | Type | Description |
|--------|------|-------------|
| `id` | TEXT PRIMARY KEY | UUID |
| `name` | TEXT NOT NULL | Folder display name |
| `created_at` | TEXT | ISO 8601 |

### `chat_threads`
| Column | Type | Description |
|--------|------|-------------|
| `id` | TEXT PRIMARY KEY | UUID |
| `title` | TEXT | Auto-generated by ThreadTitleGen |
| `folder_id` | TEXT | FK to chat_folders (NULL = unfiled) |
| `is_deleted` | INTEGER | 0=active, 1=trashed (soft-delete) |
| `deleted_at` | TEXT | Timestamp when trashed |
| `created_at` | TEXT | ISO 8601 |
| `updated_at` | TEXT | ISO 8601 |
| `active_leaf_id` | TEXT | Current leaf in message tree |
| `model_override` | TEXT | Per-thread model override |
| `system_override` | TEXT | Per-thread system message override |
| `reasoning_override` | TEXT | Per-thread reasoning setting |
| `temperature_override` | REAL | Per-thread temperature |
| `assistant_id` | TEXT | Per-thread assistant |
| `cumulative_input_tokens` | INTEGER | Sum of prompt_tokens |
| `cumulative_output_tokens` | INTEGER | Sum of completion_tokens |
| `cumulative_cached_tokens` | INTEGER | Sum of cached_tokens |
| `cumulative_cost` | REAL | Total cost in USD |

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
| `reasoning` | TEXT | Thinking/reasoning content |
| `token_count` | INTEGER | Context contribution (visible tokens) |
| `thinking_tokens` | INTEGER | Reasoning tokens (billed, not in context) |
| `cached_tokens` | INTEGER | Cache hit tokens |
| `response_time_ms` | INTEGER | Total response time in ms |
| `ttft_ms` | INTEGER | Time to first token in ms |
| `active_path_tokens` | INTEGER | Total context from root to this message |
| `created_at` | TEXT | ISO 8601 |

### `assistants`
| Column | Type | Description |
|--------|------|-------------|
| `id` | TEXT PRIMARY KEY | UUID |
| `name` | TEXT | Display name |
| `base_model` | TEXT | Model ID |
| `system_prompt` | TEXT | System message |
| `description` | TEXT | Short description (shown in model card) |
| `reasoning` | TEXT | Reasoning setting |
| `temperature` | REAL | Temperature |
| `is_default` | INTEGER | 1 if default assistant |

### Branching Model
Messages form a tree via `parent_id`. When edited or retried, a new sibling is created with the same `sibling_group` and incremented `sibling_index`. `active_leaf_id` tracks current position. `TreeRepo` handles navigation, stats, fork, and visualization.

### Fork Design
`TreeRepo.ForkThread()` creates a complete copy of the conversation up to a fork point: copies active path with fresh UUIDs, generates new `sibling_group` UUIDs, copies all siblings (not just active path), copies thread-level settings, copies attachments via content-addressable storage. Title: "Copy - [original title]".

### `messages_fts` (FTS5 Virtual Table)
| Column | Type | Description |
|--------|------|-------------|
| `msg_id` | TEXT | FK to messages.id — kept in sync by MessageRepo Insert/Edit/HardDelete |
| `content` | TEXT | Indexed message content (tokenized by FTS5 default tokenizer) |

FTS5 full-text search index for real-time message search. Created as `CREATE VIRTUAL TABLE IF NOT EXISTS` — SQLite manages it internally. Sync is explicit (no triggers): `ChatDB.FTS_Sync()` on Insert/Edit, `ChatDB.FTS_Remove()` on HardDelete. Existing messages are backfilled on first run if the FTS table is empty.

### Message Search
Two search inputs in the UI:
- **"Search chats..."** (left panel): searches all messages across all non-deleted threads + matches thread titles
- **"Search in chat..."** (right panel): searches messages within the active thread only

**Search engine**: Two-phase query in `ChatDB.SearchMessages()`:
1. **FTS5** (primary): two-step — query `messages_fts MATCH 'term1 AND term2'` for matching msg_ids, then `SELECT ... FROM messages WHERE id IN (...)`. Word-level, case-insensitive, ranked by relevance.
2. **LIKE** (fallback): `content LIKE '%term%'` — catches substrings FTS5 tokenization misses (e.g., "err" in "error"). Only runs if FTS5 returns 0 results.

**Frontend**: `chat-search.js` manages debounced input (250ms), dropdown with `<mark>`-highlighted previews, keyboard navigation (Arrow/Enter/Escape), stale response guard via `queryId` counter, and click-to-navigate reusing `scrollToMessageById()`.

## WebView ↔ AHK Communication

### AHK → WebView (postWebMessage)
Key targets: `initChatMode`, `appendChatMessage`, `streamContent`, `streamReasoning`, `streamDone`, `streamCancelled`, `setChatButtonsEnabled`, `updateTokenUsage`, `renderChatTree`, `threadList`, `trashList`, `loadThread`, `threadForked`, `showError`, `showDashboard`, `currentSettings`, `dropdownLabel`, `assistantList`, `modelList`, `updateTopbarTitle`, `searchResults`.

### WebView → AHK (via postMessage)
Dispatched by `OnWebMessageReceived` in `callbacks/Dispatch.ahk`. Actions: `chatSend`, `deleteAttachment`, `retry`, `editMessage`, `deleteMessage`, `switchBranch`, `forkChat`, `sidebarAction`, `searchMessages`, `hideWindow`, `switchAssistant`, `updateModelSettings`, `cancelStream`, `requestAssistantList`, `requestCurrentSettings`, `showApiLogs`.

## IPC (Inter-Process Communication)

| Message | Direction | Purpose |
|---------|-----------|---------|
| `WM_CHAT_WINDOW_OPENED` (0x500+0) | sub → main | Registers ChatWindow hWnd |
| `WM_LOADING_START` (0x400+123) | sub → main | Notifies loading started |
| `WM_LOADING_FINISH` (0x400+124) | sub → main | Notifies loading finished |
| `WM_LOAD_THREAD` (0x500+2) | main → sub | Load specific thread |
| `WM_TRIGGER_LLM` (0x500+4) | main → sub | Fire LLM for current thread |
| `WM_SHOW_DASHBOARD` (0x500+6) | main → sub | Show inline dashboard |
| `WM_SHOW_API_LOGS` (0x500+7) | sub → main | Open API logs viewer |

## JavaScript Module Dependency Graph

Load order in `index.html` (bottom of `<body>`):
```
vendor (lucide, highlight, chart.js, markdown-it, katex, mhchem, texmath, pdf, officeParser)
  └── usage-dashboard.js            # Inline dashboard (Chart.js graphs)
  └── chat/chat-core.js             # State, escHtml, _showConfirm, _makeInlineEditor (shared)
       ├── chat/settings/chat-settings.js        # Model/assistant popover
       ├── chat/chat-format.js                   # Token bar, copy
       ├── chat/chat-render.js                   # Message bubbles
       ├── chat/chat-token-tooltip.js            # Token popover
       ├── chat/chat-actions.js                  # Lucide icon buttons
       ├── chat/attachments/chat-attachments.js  # Attachment state
       │    ├── chat-attachments-extract.js      # pdf.js text extraction
       │    └── chat-attachments-setup.js        # Drop/paste/browse
       ├── chat/chat-input.js                    # Send, loading, retry
       ├── chat/chat-branching.js                # Edit, delete, tree modal
       ├── chat/chat-tree-modal.js               # Conversation tree visualization
       ├── chat/chat-sidebar.js                  # Folders, threads, thread switching
       ├── chat/chat-threadmap.js                # Right-panel thread map nav
       ├── chat/chat-trash.js                    # Trash list
       ├── chat/chat-search.js                   # Real-time search dropdown
       ├── chat/chat-quote.js                    # Quote in input
       ├── chat/stream.js                        # SSE streaming
       ├── chat/settings/chat-settings-modal.js  # Right panel config
       ├── main.js                               # WebMessage dispatch, dashboard toggle
       └── ui-controls.js                        # Panel resize, font, auto-collapse
```

## Usage Dashboard

Embedded inline in the main ChatWindow GUI (toggled via 📊 icon in the left rail). Rendered with Chart.js:

- **Summary cards**: Total Cost (with breakdown tooltip), API Requests, Total Tokens, Speed, Latency
- **Main chart**: Stacked bar chart of costs over time (toggle: Model/Provider grouping)
- **Per-model sections**: Line chart for requests + stacked bar for tokens per model
- **Filters**: Time range, type (All/Chat/Commands), provider, model
- **CSV export**: Full data export
- Data sourced from `chat_usage` and `command_usage` tables via `ChatDB.Usage_Query()`
- Quick Access menu item sends IPC to ChatWindow to show inline dashboard

## Debug Logging

Rolling log at `%TEMP%\LLM_Debug_Log.txt` (~500KB kept when file exceeds 1MB):

| Prefix | When | Example |
|--------|------|---------|
| `[APP]` | Startup/shutdown | `[APP] Started` |
| `[DB]` | Database open | `[DB] Opened — path=...` |
| `[API]` | LLM requests | `[API] Chat done — prompt=1500 completion=300` |
| `[STREAM]` | Stream lifecycle | `[STREAM] Started/Done/Cancelled` |
| `[THREAD]` | Thread operations | `[THREAD] Created/Deleted/Forked` |
| `[BRANCH]` | Branch switches | `[BRANCH] Switch — thread=42 leaf=abc` |
| `[EDIT]` / `[DELETE]` | Message edits | `[EDIT] Message — id=...` |
| `[ATTACH]` | Attachments | `[ATTACH] Sent — 3 files` |
| `[SETTINGS]` | Thread settings | `[SETTINGS] Saved — model=gpt-4.1` |
| `[MODEL]` | Model switches | `[MODEL] Switched to assistant: Coder` |
| `[USAGE]` | Token attribution | `[USAGE] Chat — prompt=1500 completion=300` |
| `[COST]` | Cost calculation | `[COST] Chat — total=$0.0152` |
| `[DASHBOARD]` | Dashboard | `[DASHBOARD] Query/Sent` |
| `[DISPATCH]` | WebMessage dispatch | `[DISPATCH] showApiLogs received` |
| `[APILOGS]` | API logs viewer | `[APILOGS] ShowApiLogs called` |
| `[SEARCH]` | Message search | `[SEARCH] Error: ...` |

## Testing

### How to Run
```
tests\run_all_tests.bat              # All tests
tests\run_js_tests.bat               # JS only (235 tests)
tests\run_ahk_tests.ahk              # AHK only
```

### Test Structure
AHK (`.test.ahk`) and JS (`.test.js`) tests live side by side:

| Directory | AHK Files | JS Files | Total Tests |
|-----------|----------|----------|-------------|
| `unit/` | 19 | 14 | ~275 |
| `integration/` | 3 | 2 | ~50 |

Tests run via `node:test` (JS) and custom runner (AHK). **235 JS tests pass.**
