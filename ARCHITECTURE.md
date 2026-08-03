# LLM AutoHotkey Assistant — Architecture Guide

## Contents

- [Overview](#overview)
- [Data Storage Locations](#data-storage-locations)
- [Layered Architecture](#layered-architecture)
- [Directory Structure](#directory-structure)
- [Key Design Decisions](#key-design-decisions)
- [Settings System](#settings-system)
- [Model Metadata Pipeline](#model-metadata-pipeline)
- [Thinking / Reasoning Configuration](#thinking--reasoning-configuration)
- [Command System](#command-system)
- [Startup Flow](#startup-flow)
- [Request Flow](#request-flow)
- [Streaming](#streaming)
- [Data Model (SQLite)](#data-model-sqlite)
- [WebView ↔ AHK Communication](#webview--ahk-communication)
- [Settings Panel (WebUI)](#settings-panel-webui)
- [IPC (Inter-Process Communication)](#ipc-inter-process-communication)
- [JavaScript Module Dependency Graph](#javascript-module-dependency-graph)
- [Usage Dashboard](#usage-dashboard)
- [Debug Logging](#debug-logging)
- [Testing](#testing)

---

## Overview

The LLM AutoHotkey Assistant is an AutoHotkey v2 application that:

- Binds global hotkeys to an LLM **command menu** (`backtick` by default).
- Captures selected text via **UIA (UI Automation)** and sends it to LLM providers through **cURL**.
- Renders conversations in a persistent **WebView2** chat window with branching, attachments, folders, search, and per-thread usage tracking.
- Manages all settings through an in-app **Settings panel** backed by a JSON file, with a **model metadata pipeline** (models.dev → corrections → `DefaultSettings.ahk`).

It talks to multiple providers through OpenAI-compatible endpoints plus provider-specific shims (DeepSeek's `thinking` toggle, Google's `thinking_config`), driven entirely by per-model metadata.

## Data Storage Locations

All persistent data lives under `%APPDATA%\LLM-AutoHotkey-Assistant\`:

| Path | What | Format |
|---|---|---|
| `settings.json` | User settings (merged defaults + saved values) | JSON |
| `chat_history.db` | Chat threads, messages, attachments, assistants, folders, usage, FTS5 search index | SQLite (WAL mode) |
| `attachments\` | Uploaded files + rendered scanned PDF pages | SHA-256 hash filenames |
| `system-messages\` | User-created system message text files | Text |

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

## Layered Architecture

### How This Project Is Different From Normal Web Apps

In a typical web app, JavaScript can directly call APIs, query databases, and read files. **This project can't do any of that from JavaScript.** The chat UI runs inside a WebView2 control — an embedded browser tab that is sandboxed: no filesystem, no raw network, no native APIs.

Every operation round-trips through AutoHotkey, which acts as the backend. Unlike a normal web app, the "backend" runs on the same machine, in the same window — just in a different layer.

```
┌──────────────────────────────────────────────────┐
│ LAYER 1: JavaScript (WebView2 — browser sandbox) │
│ • Renders chat bubbles, handles clicks            │
│ • Reads files into memory (FileReader API)        │
│ • Computes SHA-256 hashes, base64 encodes         │
│ • Renders the Settings panel (sections/load/save) │
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
│ • Hosts the WebView2 chat UI + settings IPC       │
│ • Writes files (ImageUtils.SaveBase64ToFile)      │
│ • Queries SQLite (ChatDB.*, Repos)                │
│ • Calls LLM APIs via cURL subprocess              │
│ • Sends results back to JS: postWebMessage()      │
│ • CANNOT: render HTML/CSS (that's Layer 1's job)  │
└──────────────────┬───────────────────────────────┘
                   │  WM_ messages (true IPC)
                   │  PostMessage() across processes
                   ▼
┌──────────────────────────────────────────────────┐
│ LAYER 3: AutoHotkey (Main process)               │
│ • Owns the tray icon and hotkeys                  │
│ • Shows command menu, captures text via UIA       │
│ • Spawns and manages ChatWindow sub-process       │
│ • Handles inline (non-chat) LLM requests          │
│ • Reloads settings globals on WM_SETTINGS_UPDATED │
│ • Pre-creates the API Logs Viewer                 │
└──────────────────────────────────────────────────┘
```

### Why Two AHK Processes?

Layer 2 and Layer 3 run as **separate Windows processes** (two `AutoHotkey64.exe` in Task Manager):

| Reason | What It Prevents |
|--------|-----------------|
| **AHK is single-threaded** | If WebView2 and cURL polling shared the hotkey process, the `` ` `` menu would freeze during every LLM request |
| **Crash isolation** | WebView2 (Edge Chromium, ~200MB) can crash. Separate process means chat dies but hotkeys survive |
| **Pre-warming** | ChatWindow spawns hidden at startup. WebView2 takes ~2s to initialize — by the time you trigger a chat, it's ready instantly |

This is the same reason Chrome runs each tab in its own process, and Electron splits main + renderer.

### Communication Mechanisms (Quick Reference)

| You Write | What Happens | Speed | Scope |
|-----------|-------------|-------|-------|
| `chrome.webview.postMessage(json)` (JS) | WebView2 COM → AHK `OnWebMessageReceived` | ~microseconds | Same process |
| `postWebMessage(target, data)` (AHK) | AHK → WebView2 COM → JS `message` event | ~microseconds | Same process |
| `PostMessage(WM_*, ...)` (AHK) | Win32 window message → other AHK process | ~milliseconds | Cross-process |

## Directory Structure

```
autohotkey-llm-client/
├── Main.ahk                     # Main process entry point (hotkeys, tray, inline requests)
├── DefaultSettings.ahk          # Default settings as top-level globals (commands, hotkeys, ...)
├── DefaultModels.ahk            # Auto-generated model metadata (pricing, thinking, compat)
├── README.md, ARCHITECTURE.md, LICENSE
│
├── api/                         # API client layer
│   ├── LLMRequestBuilder.ahk    # JSON request building, FIM, thinking config, cost, response parse
│   ├── ProviderResolver.ahk     # "provider/model" → endpoint + API key resolution
│   ├── CurlBuilder.ahk          # cURL command construction
│   ├── CurlExecutor.ahk         # Sync cURL run: spawn, wait, read output file
│   ├── SSEParser.ahk            # SSE streaming line parser
│   ├── ResponseParser.ahk       # Response parsing, usage extraction
│   ├── CostCalculator.ahk       # Token cost calculation
│   ├── ApiLogger.ahk            # API request/response logging
│   └── handlers/                # Per-provider thinking/request shims
│       ├── OpenAIChatCompletions.ahk   # ApplyThinking dispatcher: deepseek/openai formats
│       └── GoogleChatCompletions.ahk   # Google thinking_config (budget / level / disabled)
│
├── app/                         # Main-process application logic
│   ├── settings/                # Settings subsystem (see Settings System)
│   │   ├── SettingsPersistence.ahk # settings.json read/write + Map conversion
│   │   ├── SettingsDefaults.ahk    # pristine defaults snapshot
│   │   ├── SettingsMerge.ahk       # deep-merge loaded settings with defaults
│   │   ├── SettingsApply.ahk       # apply a settings Map to the globals
│   │   └── SettingsHandler.ahk     # facade over the above (stable public API)
│   ├── HotkeyRegistrar.ahk      # Dynamic hotkey registration (turn off + re-register on settings update)
│   ├── RequestProcessor.ahk     # Orchestrator: text capture → LLM request dispatch
│   ├── TextCapture.ahk          # UIA TextPattern (primary) + clipboard (fallback)
│   ├── InlineRequestRunner.ahk  # Non-chat cURL execution, response parsing, paste
│   ├── InputWindow.ahk          # GUI popup for custom prompts
│   ├── LoadingTracker.ahk       # Active request tracking, loading state, IPC
│   ├── LoadingUI.ahk            # Cursor changes, tooltip, suspend banner
│   ├── SuspendBanner.ahk        # Suspended-state banner GUI (rebuilt on settings updates)
│   ├── menu/                    # Command menu system
│   │   ├── CommandMenu.ahk      # Menu building: command menu, tags, submenus
│   │   └── CommandState.ahk     # Command state management
│   └── viewers/                 # Persistent WebView2 viewer windows
│       ├── ApiLogsViewer.ahk    # API logs viewer (persistent WebView2)
│       └── UsageDashboard.ahk   # IPC relay → ChatWindow inline dashboard
│
├── chat/                        # ChatWindow sub-process
│   ├── ChatWindow.ahk           # Window lifecycle, WebView2, show/hide, pre-warm
│   ├── ChatHotkeys.ahk          # Chat-window hotkeys (configured close-windows key)
│   ├── ChatIconResolver.ahk     # Resolve the configured chat-window icon path
│   ├── ChatIPC.ahk              # IPC handlers: OnLoadThread, OnTriggerLLM
│   ├── ChatSettings.ahk         # Chat sidebar settings, postCurrentSettingsToWebView, assistant/model mgmt
│   ├── ChatRequestBuilder.ahk   # buildRequest (chat payload + per-model thinking), sendRequestToLLM
│   ├── ChatUtils.ahk            # Structured messages, cURL state, postWebMessage
│   ├── ThreadTitleGen.ahk       # Fire-and-forget thread title generation (thinking always disabled)
│   ├── callbacks/               # WebMessage handlers (OnWebMessageReceived → Dispatch)
│   │   ├── Dispatch.ahk         # Router + settings save/reset/all-settings handlers
│   │   ├── Branch.ahk           # Branch navigation, fork, retry
│   │   ├── Edit.ahk             # Edit and delete callbacks
│   │   ├── Message.ahk          # Send + attachment delete callbacks
│   │   ├── Search.ahk           # Message search queries
│   │   └── Sidebar.ahk          # Thread list, folders, trash, rename, navigation
│   ├── streaming/
│   │   ├── StreamHandler.ahk    # cURL polling, SSE dispatch, finalization
│   │   ├── StreamCompletion.ahk # Successful stream: DB persistence, API logging, title gen
│   │   └── StreamError.ahk      # Error + cancellation: partial save, logging
│   └── db/                      # SQLite repositories
│       ├── ChatDB.ahk           # Facade — Open/Close, schema, usage queries
│       ├── ThreadRepo.ahk       # Thread CRUD, settings, soft-delete, restore
│       ├── MessageRepo.ahk      # Message CRUD, token attribution, hard-delete, FTS sync
│       ├── TreeRepo.ahk         # Branch navigation, tree viz, fork, stats
│       ├── AttachmentRepo.ahk   # Content-addressable storage, ref-counted delete
│       ├── AssistantRepo.ahk    # Assistant CRUD
│       ├── SearchRepo.ahk       # FTS5 search queries
│       └── UsageRepo.ahk        # Daily usage aggregation + dashboard queries
│
├── shared/                      # Shared application utilities
│   ├── ModelParser.ahk          # Model ID parsing ("provider/model" → provider + name)
│   ├── AttachmentUtils.ahk      # Vision gate, MIME classification, file size checks
│   ├── ImageUtils.ahk           # Base64 encode/decode, GDI+ screenshot, file I/O
│   ├── DebugLog.ahk             # Rolling debug log (~500KB in %TEMP%)
│   └── RuntimeResolver.ahk      # API key check, primary provider, default assistant
│
├── ipc/
│   └── CustomMessages.ahk       # WM_ message constants + notify helpers
│                                #   WM_SETTINGS_UPDATED, WM_RELOAD_MAIN, WM_LOAD_THREAD, ...
│
├── lib/                         # Vendor/third-party libraries
│   ├── Config.ahk               # Include chain
│   ├── UIA.ahk                  # UI Automation library (Descolada)
│   ├── SQLite/                  # SQLite3 wrapper (WAL mode)
│   ├── WebViewToo.ahk           # WebView2 Framework
│   ├── WebView2.ahk             # WebView2 Core
│   ├── jsongo.v2.ahk            # JSON parse/serialize
│   ├── AutoXYWH.ahk, ToolTipEx.ahk, Promise.ahk
│
├── scripts/                     # Model metadata pipeline
│   ├── Refresh-Models.ps1 / .bat# Main: models.dev + corrections → DefaultModels.ahk
│   ├── Fetch-Models.ps1         # Dumb fetcher: raw models.dev JSON
│   ├── Sync-Pi-Corrections.ps1  # Dev tool: sync corrections from the pi repo
│   ├── models-corrections.json  # Manual overrides (source of truth for corrections)
│   ├── models_metadata.txt      # Timestamped backup of DefaultModels.ahk (gitignored)
│   ├── models_pricing.txt       # Legacy flat pricing export (gitignored)
│   ├── run-js-coverage.ps1      # JS test coverage runner (v8 coverage)
│   ├── js-coverage-preload.js   # Coverage preload hook for node --test
│   ├── js-coverage-report.js    # Coverage report generator
│   └── README.md                # Pipeline documentation
│
├── system-messages/             # Default system message text files
├── icons/                       # Provider icons + tray icons (IconOn/IconOff)
│
├── webui/                       # WebView2 frontend (chat + settings + api logs)
│   ├── index.html               # Main chat UI — 4-column layout + Settings panel
│   ├── api-logs.html            # API logs viewer UI
│   ├── css/                     # Modular CSS (theme, layout, panels, messages, settings, ...)
│   ├── fonts/                   # Local fonts (Inter + JetBrains Mono, no CDN)
│   ├── icons/filetypes/         # 35+ branded SVG file-type icons (no CDN)
│   └── js/
│       ├── main.js              # WebMessage dispatch (routes to chat modules + SettingsPanel)
│       ├── settings/
│       │   ├── settings-panel.js       # Settings panel: section registry, save/load, dirty, reset
│       │   └── sections/               # One module per settings tab
│       │       ├── general.js          # Thread titles, API logs, trash, chat shortcut
│       │       ├── icons.js, ui-theme.js, hotkeys.js, menu-items.js
│       │       ├── providers.js, models.js, sysmsg-modal.js
│       │       ├── assistants.js       # Chat profiles (single model-scoped reasoning dropdown)
│       │       └── commands/           # Command editor (commands-core, -render, -actions, -drag)
│       ├── shared/
│       │   ├── settings-shared.js      # Shared section helpers (escaping, select fill, registration)
│       │   └── reasoning-levels.js     # Shared reasoning-level labels/ordering/options builder
│       ├── chat/                       # Chat JS modules
│       │   ├── chat-core.js, chat-render.js, chat-input.js, chat-branching.js
│       │   ├── chat-sidebar.js, chat-search.js, chat-threadmap.js, chat-trash.js
│       │   ├── chat-actions.js, chat-format.js, chat-quote.js, chat-token-tooltip.js
│       │   ├── chat-tree-modal.js, stream.js
│       │   ├── attachments/            # Attachment subsystem (state, extraction, setup)
│       │   └── model-picker/           # Chat sidebar settings
│       │       ├── model-picker.js    # Model/assistant popover
│       │       └── model-picker-config.js  # Right panel config (uses ReasoningLevels)
│       └── vendor/                     # Local JS libs (lucide, chart.js, pdf.js, markdown-it, ...)
│
├── tests/
│   ├── run_all_tests.bat        # PRIMARY ENTRY POINT (AHK + JS)
│   ├── run_ahk_tests.ahk        # AHK test runner
│   ├── run_js_tests.bat         # JS test runner (node:test)
│   ├── test_config.ahk          # Test overrides (mock models/providers for unit tests)
│   ├── unit/                    # Unit tests — AHK (.test.ahk) + JS (.test.js)
│   ├── integration/             # Integration tests (BranchFlow, ChatFlow, UsageFlow, ...)
│   └── headless/                # Headless e2e harness: verify-bugs.js + BUG_HUNT_REPORT.md
```

## Key Design Decisions

- **Entry point**: `Main.ahk` — double-click to run. It includes `lib/Config.ahk` (the include chain) which loads `DefaultSettings.ahk`, `shared/`, `api/`, `app/`, `chat/`, `ipc/`.
- **Settings are JSON**: `app/settings/SettingsHandler.ahk` loads/saves `%APPDATA%\LLM-AutoHotkey-Assistant\settings.json`, merging saved values with `DefaultSettings.ahk` defaults. See [Settings System](#settings-system).
- **DefaultSettings.ahk is the source of defaults**: it declares every default as a **top-level global** (`providers`, `assistants`, `commands`, hotkeys, `chatShortcut`, ...). `SettingsHandler.GetDefaults()` snapshots these; model metadata is generated into `DefaultModels.ahk` by `scripts/Refresh-Models.ps1`.
- **Persistent single-window model**: one `ChatWindow.ahk` sub-process handles all chat sessions. Close = hide (not terminate).
- **SQLite persistence**: chat history in `%APPDATA%\LLM-AutoHotkey-Assistant\chat_history.db` (WAL mode). Branching, soft-delete, reasoning, attachments, folders, usage tracking.
- **Content-addressable attachments**: files stored by SHA-256 hash; O(1) dedup; reference-counted deletion. Scanned PDF pages rendered as images via pdf.js canvas.
- **Virtual host mapping**: WebView2 loads from `https://ahk.localhost/` (not `file://`) — gives a proper origin for workers/fetch, eliminating pdf.js "fake worker" warnings.
- **cURL for API calls**: JSON payloads written to `%TEMP%`, `cURL.exe` performs the request (streaming via `-N`).
- **UIA text capture**: Windows accessibility TextPattern — zero scroll, no keystrokes.
- **All vendor libraries local**: Lucide, Chart.js, pdf.js, officeParser, highlight.js, katex, markdown-it — no CDN.
- **Metadata-driven provider support**: per-model `compat.thinkingFormat` + `thinkingLevelMap` + `thinkingOff` drive request shaping per provider. See [Thinking / Reasoning Configuration](#thinking--reasoning-configuration).

## Settings System

Settings are the combination of **defaults** (`DefaultSettings.ahk` globals) and **saved overrides** (`settings.json`).

### The Defaults Snapshot Problem (important)

`DefaultSettings.ahk` is a script that runs once at startup, assigning **mutable global variables** (`chatShortcut := "1"`, `appDefaultModel := "..."`, `mainHotkey := "``"`, ...). When settings are applied, `SettingsHandler.ApplyToGlobals()` **overwrites those same globals** with the saved values:

```ahk
global chatShortcut
if settings.Has("chatShortcut")
    chatShortcut := settings["chatShortcut"]
```

So after loading a customized `settings.json`, the globals no longer hold the defaults. If `GetDefaults()` simply re-read the globals it would return **applied** values, which broke "Reset to Defaults" (e.g. `chatShortcut` stayed `"b"` instead of reverting to `"1"`).

The solution is [`CacheInitialDefaults()`](app/settings/SettingsDefaults.ahk:15): called **before** `ApplyToGlobals` at startup (in `Main.ahk` and `ChatWindow.ahk`), it snapshots the pristine defaults into a static `_initialDefaults` Map that nothing ever reassigns. `GetDefaults()` returns that snapshot (shallow-cloned) so the true defaults are always available.

### Key Functions (`app/settings/`)

| Function | Purpose |
|----------|---------|
| `CacheInitialDefaults()` | Snapshot pristine `DefaultSettings.ahk` globals at startup (before `ApplyToGlobals`) |
| `GetDefaults()` | Return the pristine defaults Map (snapshot once captured) |
| `Load()` | Read `settings.json` (empty Map if missing) |
| `Save(settings)` | Delete `settings.json` + write the given Map fresh (no merge) |
| `Merge(existing, defaults)` | Fill missing keys from defaults, keep existing values |
| `ApplyToGlobals(settings)` | Write settings into the section globals (providers, models, assistants, commands, hotkeys, chatShortcut, ...) |
| `_Defaults*()` | Build each section's default Map from `DefaultSettings.ahk` globals |
| `_Apply*()` | Apply each section's saved values to globals |

### Reset to Defaults

`chat/callbacks/Dispatch.ahk` — `_HandleRequestDefaultSettings()`:

1. `defaults := SettingsHandler.GetDefaults()` → pristine defaults from `DefaultSettings.ahk`.
2. `SettingsHandler.Save(defaults)` → **deletes** `settings.json` and writes a fresh file containing only the defaults.
3. `ApplyToGlobals(defaults)`, notify Main to reload, and send `defaultSettings` to the WebUI (`reloadWithDefaults` repopulates every settings section).

### Settings Persistence

`Save()` is destructive (delete + rewrite), so all merging happens at call sites: `_HandleSaveSettings` merges the incoming UI data over `(saved file + defaults)` before saving. API keys normally live in environment variables per provider (`authEnvVar`), but a provider can also store a direct key in `settings.json` (`authMode: "direct"` + `apiKey`) — the UI warns that direct entry persists the key in the file.

## Model Metadata Pipeline

Model metadata (pricing, context, thinking levels, compat flags) is generated rather than hand-maintained:

```
models.dev (API)
     │
     ▼
Fetch-Models.ps1 ──► models-dev-raw.json   (dumb fetcher, gitignored)
     │
     ▼
Refresh-Models.ps1 ──► DefaultModels.ahk
     │  1. Reads scripts/models-corrections.json (manual overrides win)
     │  2. Fetches models.dev
     │  3. Applies family/provider fallbacks
     │  4. Generates models := Map(...) into DefaultModels.ahk
     ▼
Sync-Pi-Corrections.ps1   (dev tool: extracts corrections from the pi repo)
```

- `scripts/models-corrections.json` is the single, version-controlled override file (e.g. fixing deepseek-v4-flash's effort values to `["none","low","high","max"]`).
- `scripts/Refresh-Models.ps1` writes `DefaultModels.ahk` (the committed generated model metadata) and keeps a timestamped backup at `scripts/models_metadata.txt`.
- Each model entry carries: `provider`, `api`, `compat` (`thinkingFormat`, `supportsReasoningEffort`, `supportsUsageInStreaming`, `maxTokensField`), `thinkingLevelMap`, `thinkingOff`, pricing (`input`/`cachedInput`/`output`), `context`, `reasoning`, `vision`.
- See `scripts/README.md` for the full pipeline explanation.

## Thinking / Reasoning Configuration

Thinking is **metadata-driven** and **provider-specific**. Each model declares:

- `compat.thinkingFormat` — `"deepseek"`, `"openai"`, or `"google"`.
- `thinkingLevelMap` — the selectable levels (e.g. `Map("none","none","low","low","high","high","max","max")`). Keys are what the UI offers; values are the wire values.
- `thinkingOff` — the provider's "off" representation (DeepSeek `"disabled"`, OpenAI `"none"`, Google `"0"`/`"MINIMAL"`).

### Request shaping (`api/handlers/`)

`OpenAIChatCompletions.ApplyThinking()` dispatches by `thinkingFormat`:

| Provider format | Enabled (level) | Disabled ("none"/"") |
|---|---|---|
| `deepseek` | `{"thinking":{"type":"enabled"}}` + `reasoning_effort` | `{"thinking":{"type":"disabled"}}` |
| `openai` | `reasoning_effort: <level>` | `reasoning_effort: "none"` |
| `google` | `extra_body.google.thinking_config` (`thinking_level` / `thinking_budget`) | `thinking_budget: 0` (2.x) or `MINIMAL`/`LOW` (3.x/Gemma) |

### "Model Default" = no thinking config

Both request paths only send a thinking config when the reasoning value is a level the model actually offers:

- **Chat path** (`chat/ChatRequestBuilder.ahk`): `thinkingLevelMap.Has(reasoning)` gate — empty ("Model Default") or any unselectable value sends **no** thinking config.
- **Command path** (`api/LLMRequestBuilder.ahk`): empty type = no config; `enabled`+level uses the level; `disabled` maps to `"none"` so it reaches the disabled branch.

### One model-scoped dropdown everywhere

The chat sidebar, assistant settings, and command settings each use a **single dropdown**: "Model Default" + the model's supported levels, sorted least→most thinking by the shared frontend helper [`webui/js/shared/reasoning-levels.js`](webui/js/shared/reasoning-levels.js) (`ReasoningLevels` — the single source for labels/order). The backend sends raw level values for the chat sidebar; assistants and commands build options from `data.models` metadata.

**Thread title generation** has no UI control — it always passes `"disabled"` so the cheap utility call never thinks.

## Command System

Commands are user-configurable hotkey actions in the `` ` `` menu, defined in the **Commands** settings tab (persisted in `settings.json`).

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
| `isFIM` | Use DeepSeek FIM endpoint | `false` |
| `expandNewlines` | Expand `\n` → `\n\n` | `false` |
| `stream`, `temperature`, `maxTokens`, `stop` | API parameters | — |
| `thinking` | Single model-scoped level (`""` = Model Default, or `{type:"enabled", level}`) | `""` |

## Startup Flow

1. `Main.ahk` runs → `#Include <Config>` loads `lib/Config.ahk` (vendor libs + shared utils + app modules).
2. `SettingsHandler.CacheInitialDefaults()` snapshots pristine defaults **before** any `ApplyToGlobals`.
3. `defaults := SettingsHandler.GetDefaults()`; `settings := SettingsHandler.Load()`; `merged := Merge(settings, defaults)`; `ApplyToGlobals(merged)`.
4. `Main.ahk` opens `ChatDB` (SQLite), spawns `ChatWindow.ahk` hidden with a "prewarm" flag, registers hotkeys via `HotkeyRegistrar._registerAllHotkeys()`, and pre-creates the API Logs Viewer (deferred 2s).
5. `ChatWindow.ahk` also calls `CacheInitialDefaults()` + merges settings (it's a separate process with its own globals), then builds the WebView2 UI.

## Request Flow

### Chat Mode (pasteMode = "chat")

```
User presses hotkey → buildCommandMenu() → onCommandSelected()
    │
    ▼
processInitialRequest()                     # app/RequestProcessor.ahk
    │  TextCapture.Capture() — UIA TextPattern → clipboard fallback
    │  Template expansion: {{selection}}, {{fullText}}, {{input}}
    │  [if includeImageContext] GDI+ screenshot + vision gate
    │  Creates thread in ChatDB (system + user messages + attachment)
    │  openChatWindow(threadId) → WM_LOAD_THREAD
    ▼
chat/ChatWindow.ahk                        # Sub-process (persistent)
    │  Loads thread from DB → initChatMode → WebView
    │  If last message is from user: auto-triggers LLM
    ▼
ChatRequestBuilder.buildRequest() → sendRequestToLLM() → ChatDB.Msg_Insert()
    │  Per-message token attribution via subtraction
    │  Cost via CostCalculator; chat_usage daily aggregation UPSERT
```

### Inline Mode (pasteMode = "replace" / "append")

```
onCommandSelected() → InlineRequestRunner.Run(...)
    │  Builds request via api/LLMRequestBuilder.createJSONRequest()
    │  Writes JSON + cURL to %TEMP%, RunWait(cURL)
    │  Parses response, tracks usage (command_usage), pastes result
```

### Thread Title Generation

After the first exchange in a thread (`StreamCompletion`), `ThreadTitleGen.generateThreadTitle()` makes a separate cheap call (`titleGenModel`, max tokens, `"disabled"` thinking) and updates the thread title.

## Streaming

Requests with `stream: true` are executed via cURL `-N`; `chat/streaming/StreamHandler.ahk` polls the output file in a loop, parses SSE lines (`SSEParser`), and posts incremental updates to the WebUI (`streamContent`, `streamReasoning`, `streamModelName`). On completion, `StreamCompletion` persists the message, attributes tokens, logs the API call, and triggers title generation. `StreamError` handles failures/cancellation, saving partial content.

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
| `title` | TEXT | Default "New Chat"; auto-titled after the first exchange |
| `folder_id` | TEXT | FK to chat_folders (NULL = unfiled) |
| `is_deleted` | INTEGER | 0=active, 1=trashed (soft-delete) |
| `deleted_at` | TEXT | Timestamp when trashed |
| `created_at` / `updated_at` | TEXT | UTC `YYYY-MM-DD HH:MM:SS` (`datetime('now')`) |
| `active_leaf_id` | TEXT | Current leaf in message tree |
| `model_override` / `system_override` | TEXT | Per-thread overrides |
| `reasoning_override` / `temperature_override` | TEXT / REAL | Per-thread reasoning / temperature |
| `assistant_id` | TEXT | Per-thread assistant |
| `cumulative_input_tokens` / `cumulative_output_tokens` / `cumulative_cached_tokens` | INTEGER | Token sums |
| `cumulative_cost` | REAL | Total cost USD |
| `cumulative_input_cost` / `cumulative_cached_input_cost` / `cumulative_output_cost` | REAL | Cost breakdown (input / cached-input / output) |
| `font_size` | INTEGER | Per-thread chat font size (default 17) |
| `advanced_toggles` | TEXT | JSON `{"codeExecution":..., "webSearch":...}` right-rail toggles |

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
| `token_count` | INTEGER | Context contribution |
| `thinking_tokens` | INTEGER | Reasoning tokens (billed, not in context) |
| `cached_tokens` | INTEGER | Cache hit tokens |
| `response_time_ms` / `ttft_ms` | INTEGER | Timing |
| `active_path_tokens` | INTEGER | Total context from root |
| `created_at` | TEXT | ISO 8601 |

### `assistants`
| Column | Type | Description |
|--------|------|-------------|
| `id` | TEXT PRIMARY KEY | UUID |
| `name` / `base_model` | TEXT | Identity |
| `system_prompt` / `description` | TEXT | System message / short description |
| `reasoning` | TEXT | Reasoning setting (level or "" = Model Default) |
| `temperature` | REAL | Temperature |
| `is_default` | INTEGER | 1 if default assistant |

### Branching Model

Messages form a tree via `parent_id`. Edits/retries create a sibling with the same `sibling_group` and incremented `sibling_index`. `active_leaf_id` tracks the current position. `TreeRepo` handles navigation, stats, fork, and visualization. `ForkThread` copies the active path with fresh UUIDs, new sibling groups, all siblings, thread settings, and attachments (content-addressed).

### `messages_fts` (FTS5 Virtual Table)

Full-text search index over `messages.content`, kept in sync explicitly by `MessageRepo` (Insert/Edit → `FTS_Sync`, HardDelete → `FTS_Remove`). Search is two-phase: FTS5 `MATCH` for word-level ranking, with a `LIKE '%term%'` fallback for substrings the tokenizer misses. Frontend: `chat-search.js` (debounced, `<mark>` previews, keyboard nav, stale-response guard).

## WebView ↔ AHK Communication

### AHK → WebView (`postWebMessage`)

Key targets: `initChatMode`, `appendChatMessage`, `streamContent`, `streamReasoning`, `streamDone`, `streamCancelled`, `setChatButtonsEnabled`, `updateTokenUsage`, `renderChatTree`, `threadList`, `trashList`, `loadThread`, `threadForked`, `showError`, `showDashboard`, `currentSettings`, `defaultSettings`, `settingsSaved`, `dropdownLabel`, `assistantList`, `modelList`, `updateTopbarTitle`, `searchResults`.

### ⚠ `currentSettings` carries two different payloads

The `currentSettings` action is used by **two different senders**:

1. **Chat sidebar** (`chat/ChatSettings.ahk` → `postCurrentSettingsToWebView`): partial payload — `model`, `reasoning`, `temperature`, `thinkingLevels` (raw level values), assistant metadata. **No `commands`/`assistants`/`models`.**
2. **Full settings** (`chat/callbacks/Dispatch.ahk` → `_HandleRequestAllSettings`): the complete merged settings Map (includes `commands`, `assistants`, `models`, `providers`, ...).

`main.js` always calls `populateCurrentSettings(data)` (chat sidebar dropdowns), but only calls `SettingsPanel.onSettingsReceived(data)` when the payload carries the full settings structure (`Array.isArray(data.commands)`). Feeding the chat-sidebar payload into the settings panel would reload every section with empty data and blank the Commands tab — this was a real bug.

### WebView → AHK (`postMessage`)

Dispatched by `OnWebMessageReceived` in `chat/callbacks/Dispatch.ahk`. Actions include: `chatSend`, `deleteAttachment`, `retry`, `editMessage`, `deleteMessage`, `switchBranch`, `forkChat`, `sidebarAction`, `searchMessages`, `hideWindow`, `switchAssistant`, `updateModelSettings`, `cancelStream`, `requestAssistantList`, `requestCurrentSettings`, `requestAllSettings`, `requestDefaultSettings`, `saveSettings`, `refreshModelPricing`, `showApiLogs`, `debugLog` (JS→AHK log bridge), `webViewReady`.

## Settings Panel (WebUI)

The Settings panel is a set of sections rendered in `webui/index.html`, orchestrated by `webui/js/settings/settings-panel.js`:

- **Registry**: each `sections/*.js` module registers `{ load(data), save() }` with `SettingsPanel.registerSection()`.
- **Load**: `SettingsPanel.onSettingsReceived(data)` (full settings only — see the `currentSettings` caveat) and `reloadWithDefaults(defaults)` (after Reset) call every section's `load`.
- **Save**: `saveSettings()` calls every section's `save()`, collects the results, and posts `{action:'saveSettings', data}` to AHK; `Dispatch._HandleSaveSettings` merges and persists.
- **Sections**: General (thread titles, API logs, trash, chat shortcut), Icons, UI/Theme, Hotkeys, Menu Items, Providers, Models (pricing/metadata), Assistants, Commands, plus the system-message modal.
- **Dirty tracking**: `markDirty()/clearDirty()/isDirty()` guard navigation away from unsaved changes.
- **Reset**: `resetToDefaults()` posts `requestDefaultSettings`; the backend saves pristine defaults and the panel reloads them.

## IPC (Inter-Process Communication)

`ipc/CustomMessages.ahk` (uses the `0x500+` range — WebView2 owns `0x400–0x4FF`):

| Message | Value | Direction | Purpose |
|---------|-------|-----------|---------|
| `WM_CHAT_WINDOW_OPENED` | `0x500+0` | sub → main | Registers ChatWindow hWnd |
| `WM_LOAD_THREAD` | `0x500+2` | main → sub | Load a specific thread |
| `WM_TRIGGER_LLM` | `0x500+4` | main → sub | Fire LLM for current thread |
| `WM_SHOW_DASHBOARD` | `0x500+6` | main → sub | Show inline dashboard |
| `WM_SHOW_API_LOGS` | `0x500+7` | sub → main | Open API logs viewer |
| `WM_SETTINGS_UPDATED` | `0x500+8` | sub → main | Reload settings globals + hotkeys |
| `WM_RELOAD_MAIN` | `0x500+9` | sub → main | Restart the Main process |
| `WM_LOADING_START` / `WM_LOADING_FINISH` | `0x400+123/124` | sub → main | Loading cursor state |

## JavaScript Module Dependency Graph

Load order in `index.html` (bottom of `<body>`):

```
vendor (lucide, highlight, chart.js, markdown-it, katex, mhchem, texmath, pdf, officeParser)
  └── chat/chat-core.js             # State, escHtml, _showChatConfirm, _makeInlineEditor
       ├── chat/model-picker/model-picker.js    # Model/assistant popover
       ├── chat/chat-format.js                  # Token bar, copy
       ├── chat/chat-render.js                  # Message bubbles
       ├── chat/chat-token-tooltip.js, chat-actions.js
       ├── chat/attachments/*                   # State, extraction, setup
       ├── chat/chat-input.js, chat-branching.js, chat-tree-modal.js
       ├── chat/chat-sidebar.js, chat-threadmap.js, chat-trash.js
       ├── chat/chat-search.js, chat-quote.js, stream.js
       ├── chat/model-picker/model-picker-config.js # Right panel config
       ├── settings/settings-panel.js           # Settings panel orchestrator
       │    ├── shared/reasoning-levels.js      # Shared level labels/ordering
       │    └── settings/sections/*             # One module per tab (incl. commands/*)
       ├── main.js               # WebMessage dispatch
       └── (ui controls / usage dashboard are loaded alongside)
```

## Usage Dashboard

Embedded inline in the ChatWindow GUI (toggled via the rail icon). Rendered with Chart.js:

- **Summary cards**: Total Cost, API Requests, Total Tokens, Speed, Latency.
- **Main chart**: stacked cost over time (Model/Provider grouping toggle).
- **Per-model sections**: requests line + tokens stacked bar.
- **Filters**: time range, type (All/Chat/Commands), provider, model; CSV export.
- Data from `chat_usage` + `command_usage` via `ChatDB.Usage_Query()`; the Quick Access menu sends IPC to show it.

## Debug Logging

Rolling log at `%TEMP%\LLM_Debug_Log.txt` (~500KB kept when the file exceeds 1MB), written via `shared/DebugLog.ahk`. Prefixes include `[APP]`, `[SETTINGS]`, `[DB]`, `[API]`, `[STREAM]`, `[THREAD]`, `[BRANCH]`, `[EDIT]`, `[ATTACH]`, `[MODEL]`, `[USAGE]`, `[COST]`, `[DASHBOARD]`, `[DISPATCH]`, `[APILOGS]`, `[SEARCH]`, `[WebUI]` (JS→AHK bridge). The **API Logs Viewer** (`webui/api-logs.html` + `ApiLogsViewer.ahk`) provides a GUI over request/response history.

## Testing

### How to Run

```
tests\run_all_tests.bat              # All tests (AHK + JS) — primary entry
tests\run_js_tests.bat               # JS only (node:test)
tests\run_ahk_tests.ahk              # AHK only (custom runner)
```

Headless end-to-end (GUI bug harness — launches the real app; needs an interactive
session + elevated permissions; deliberately not part of `run_all_tests.bat`):

```
node tests\headless\verify-bugs.js --all          # every scenario against the real app
```

The harness also supports targeted re-runs (`--scenarios=...`), report/scenario sync
checks (`--check-sync`), and PID-targeted cleanup after aborted runs (`--cleanup`) — see
`tests/headless/README.md` for the manual and `tests/headless/BUG_HUNT_REPORT.md` for the
live bug list and workflow.

### Structure

AHK (`.test.ahk`) and JS (`.test.js`) tests live side by side under `tests/unit/` and `tests/integration/`:

- **Unit**: request builders (chat + command, Model Default = no config, per-provider thinking), settings (defaults merge, pristine snapshot, apply-to-globals), DB repositories, parsing, cost, model metadata integrity, WebUI modules (chat render, search, attachments, settings sections, reasoning-levels helper, main.js message routing).
- **Integration**: branch flow, chat flow, usage flow (AHK); chat folders, edit-send flow (JS).

Run `tests\run_all_tests.bat` for the current pass/fail counts (do not hard-code them here —
they drift as tests are added).

## Bug-Hunt Workflow (Headless Harness)

`tests/headless/` contains a headless verification harness for GUI bugs plus a **living bug
report** — this is the workflow to point an agent at when auditing or fixing the app:

- `tests/headless/BUG_HUNT_REPORT.md` — the authoritative list of **open, headlessly
  verified** bugs. Every entry has a Status
  (`reported → verified → fix in progress → fix applied → awaiting user commit → removed`),
  the scenario id that reproduces it, and Repro / Expected / Actual / Evidence. It also
  defines the full lifecycle (intake + fix cycle) with the exact file to touch at each step.
- `tests/headless/README.md` — harness manual: how to run scenarios, add one, write AHK
  probes, and the environment quirks to avoid.
- `tests/headless/verify-bugs.js` — the scenario runner. `--check-sync` enforces that the
  report and the scenario list stay in sync (no stale/dangling ids), and `--all` re-verifies
  every scenario against the real app.

**Lifecycle:** the full lifecycle (intake → `reported` → headless verification → `verified`
→ fix cycle → History) is defined in `tests/headless/BUG_HUNT_REPORT.md` — that file is the
authoritative source and must be read first. In short: suspected bugs are written into the
report as `reported`, reproduced headlessly (scenario PASS = `verified`, then ranked), and
fixed one at a time in rank order — each fix flips its scenario to assert the **fixed**
behavior, turning it into a permanent regression check. Every status change is written before
the work it describes, so a task closed midway resumes from "Where we left off".

**How a developer points an agent at it:** "fix bug #5", "add more bugs to the bug hunt",
"verify this repro: …", "continue", or "re-verify everything" — all are handled by the
report's lifecycle rules (see `tests/headless/README.md → How a developer uses this`).
