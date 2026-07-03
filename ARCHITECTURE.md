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
│   ├── PromptMenu.ahk               # Menu building: prompt menu, tags, submenus, options
│   ├── PromptManager.ahk            # Prompt state management, window operations, send-to handlers
│   ├── RequestProcessor.ahk         # Clipboard capture (FIM/chat), model spawning, cURL request building
│   ├── ModelTracker.ahk             # Active model tracking, loading state, reload coordination
│   └── UiHelpers.ahk                # Cursor changes, tooltip display, suspend banner toggle
│
├── chat/                            # Chat/Response Window (spawned as sub-process)
│   ├── ResponseWindow.ahk           # Orchestrator: hotkeys, WebView creation, cURL runner, message display
│   ├── ChatCallbacks.ahk            # HostObject callbacks: chatSendFromWebView, retryFromWebView, buttonClickAction
│   └── ChatUtils.ahk                # State management, postWebMessage, temp file cleanup, loading cursor
│
├── api/                             # API client
│   └── LLMClient.ahk                # LLMClient class: JSON request building, cURL, FIM, response extraction, logging
│
├── ui/                              # UI components
│   ├── InputWindow.ahk              # InputWindow class: GUI popup for custom prompts
│   └── CustomMessages.ahk           # CustomMessages class: inter-process WM_ messaging
│
├── lib/                             # Vendor/third-party libraries (unchanged)
│   ├── Config.ahk                   # Include chain (see above)
│   ├── ApiLogsViewer.ahk            # Standalone API logs viewer (Options > API Logs)
│   ├── Dark_Menu.ahk                # Dark theme for AHK menus
│   ├── Dark_MsgBox.ahk              # Dark theme for MsgBox/InputBox
│   ├── WebViewToo.ahk               # WebView2 Framework
│   ├── WebView2.ahk                 # WebView2 Core
│   ├── jsongo.v2.ahk                # JSON parsing
│   ├── AutoXYWH.ahk                 # GUI auto-resizing
│   ├── ToolTipEx.ahk                # Enhanced tooltips
│   ├── SystemThemeAwareToolTip.ahk  # Dark theme tooltips
│   ├── Promise.ahk                  # Promise/A+ implementation
│   ├── ComVar.ahk                   # COM utility
│   ├── 32bit/                       # 32-bit native binaries
│   └── 64bit/                       # 64-bit native binaries
│
├── icons/                           # Provider icons (unchanged)
│   ├── IconOn.ico
│   ├── IconOff.ico
│   ├── deepseek.ico
│   ├── openai.ico
│   └── ... (other provider icons)
│
└── webui/                           # WebView frontend
    ├── index.html                   # Main chat UI
    ├── api-logs.html                # API logs viewer UI
    ├── Bootstrap/                   # Bootstrap framework
    ├── css/                         # Stylesheets
    │   ├── custom.css               # Our custom styles
    │   └── vendor/                  # Third-party CSS
    │       ├── katex.min.css
    │       ├── texmath.min.css
    │       └── highlight/
    │           └── atom-one-dark.min.css
    └── js/                          # JavaScript
        ├── main.js                  # Our chat logic
        └── vendor/                  # Third-party JS
            ├── highlight.min.js
            ├── katex.min.js
            ├── markdown-it.min.js
            ├── mhchem.min.js
            └── texmath.min.js
```

## Architecture Overview

The application is an AutoHotkey v2 script that provides a hotkey-activated prompt menu, sends text to an LLM API (OpenAI-compatible) via cURL, and displays responses in a WebView2-based chat window.

### Key Design Decisions

- **Entry point**: `Main.ahk` — double-click to run.
- **User config**: `UserConfig.ahk` — all prompts, API keys, hotkeys, and theme settings in one file. Changes take effect on save (Ctrl+S in Notepad).
- **Sub-process model**: Each Response Window runs as a separate AHK process (`chat/ResponseWindow.ahk`). The main script communicates with them via Windows messages (`WM_`).
- **WebView2 frontend**: The chat UI is an HTML/JS page rendered by Microsoft Edge WebView2. AHK sends messages via `PostWebMessageAsJSON`; the JS side calls back to AHK via registered `HostObject` methods.
- **cURL for API calls**: The script writes JSON request files to `%TEMP%` and runs `cURL.exe` as a hidden process to communicate with the LLM API.

## Startup Flow

1. `Main.ahk` runs → `#Include <Config>` loads `lib/Config.ahk`
2. `Config.ahk` loads all vendor libs + application classes (`api/LLMClient.ahk`, `ui/InputWindow.ahk`, `ui/CustomMessages.ahk`)
3. `Main.ahk` creates `router := LLMClient(APIKey)` and three InputWindow instances
4. `Main.ahk` registers hotkeys (default: `` ` `` to open menu)
5. `Main.ahk` loads application modules (`app/*.ahk`)
6. Script is ready — tray icon appears, hotkeys active

## Request Flow

When a user selects a prompt from the menu (`` ` `` → select prompt):

```
User presses hotkey
    │
    ▼
buildPromptMenu()                    # app/PromptMenu.ahk
    │  Displays the prompt menu with tags, send-to options, etc.
    ▼
promptMenuHandler(index)             # app/PromptMenu.ahk
    │  For non-custom prompts: calls processInitialRequest()
    │  For custom prompts: shows InputWindow → user types → customPromptSendButtonAction()
    ▼
processInitialRequest()              # app/RequestProcessor.ahk
    │  STEP 1: Capture text via clipboard (Ctrl+C / FIM selection)
    │  STEP 2: Build JSON request, write to %TEMP%, build cURL command
    │  STEP 3: Spawn ResponseWindow.ahk as sub-process
    ▼
chat/ResponseWindow.ahk              # chat/ResponseWindow.ahk (sub-process)
    │  Reads request params from temp JSON file
    │  Creates WebView2 window, loads resources/index.html
    │  Runs cURL → reads response → sends to WebView
    │
    ├── pasteMode "chat":            # Sends structured messages → chat UI
    │   postWebMessage("initChatMode", messagesArray)
    │   postWebMessage("appendChatMessage", newMessage)
    │
    ├── pasteMode "replace"/"append": # Direct clipboard paste
    │   A_Clipboard := response
    │   Send("^v")  ← pastes into active app
    │   Closes window
    │
    └── pasteMode "chat" + user types message:
        JS → hostObjects.ChatSend.Func(message) → chatSendFromWebView()
            → appends to JSON → repeats cURL flow → appendChatMessage()
```

## pasteMode Values

| Value | Behavior | Use Case |
|-------|----------|----------|
| `"chat"` | Opens a full chat interface in the Response Window. Messages displayed as bubbles with copy/retry buttons. Inline input box at bottom. | Chat prompts (General assistant, Quick ask, Council) |
| `"replace"` | Pastes the LLM response directly into the active app, replacing the selected text. Closes window immediately. | Rephrase, Summarize, Translate, FIM Fill |
| `"append"` | Pastes the LLM response after the cursor position. Closes window immediately. | FIM Continue |

## Multi-Model (Council) Mode

When `APIModels` contains multiple comma-separated models (e.g. `"deepseek-v4-pro, deepseek-v4-flash"`):

1. `processInitialRequest()` creates a separate `ResponseWindow.ahk` process for each model
2. Each window gets its own JSON file, cURL command, and output file
3. Windows are arranged side-by-side (2 models) or in a row (3+ models)
4. Each window is an independent chat session
5. The "Send message to all" feature appends a user message to ALL active model JSON files and triggers re-requests

## WebView ↔ AHK Communication

### AHK → WebView (postWebMessage)
```
postWebMessage("target", data)  →  JSON: {"target": "target", "data": data}
```
Handled by `handleWebMessage()` in `main.js`:
- `setTheme` — sets dark/light mode
- `initChatMode` — initializes chat with message array
- `appendChatMessage` — appends a new message bubble
- `removeLastAssistantMessage` — removes last assistant bubble (for retry)
- `renderMarkdown` — renders markdown in non-chat mode (FIM fallback)
- `setChatButtonsEnabled` — enables/disables chat input during loading

### WebView → AHK (HostObjects)
```
window.chrome.webview.hostObjects.ChatSend.Func(message)
window.chrome.webview.hostObjects.RetryAction.Func()
```
Registered in `chat/ResponseWindow.ahk`:
- `ChatSend` → `chatSendFromWebView()` — appends user message, re-sends
- `RetryAction` → `retryFromWebView()` — removes last assistant, re-sends
- `ButtonClick` → `buttonClickAction()` — handles "Retry" and "Close"

## How to Add a New Prompt

Edit `UserConfig.ahk` and add an entry to the `prompts` array:

```autohotkey
{
    promptName: "My New Prompt",
    menuText: "&9 - My Menu Label",
    systemPrompt: "You are a helpful assistant...",
    APIModels: "deepseek-v4-flash",
    pasteMode: "chat",
    isCustomPrompt: true,
    customPromptInitialMessage: "",
    skipConfirmation: false,
    tags: ["&My tag"]
}
```

Then save the file (Ctrl+S in Notepad) — the script auto-reloads.

## Configuration System

`UserConfig.ahk` is a standard AHK file directly `#Include`d into the script. There is no config file parser — all settings are plain AHK variables and arrays. This means:

- String values use quotes
- Arrays use `[item1, item2]`
- Maps use `Map("key", "value")`
- Booleans use `true`/`false`
- The `prompts` array is an AHK array of objects

## Inter-Process Communication

The main script and Response Windows use Windows messages (`WM_`) for IPC:

| Message | Direction | Purpose |
|---------|-----------|---------|
| `WM_RESPONSE_WINDOW_OPENED` | sub → main | Registers a new Response Window |
| `WM_RESPONSE_WINDOW_CLOSED` | sub → main | Unregisters a closed Response Window |
| `WM_SEND_TO_ALL_MODELS` | main → sub | Triggers re-request with new user message |
| `WM_RESPONSE_WINDOW_LOADING_START` | sub → main | Notifies loading started |
| `WM_RESPONSE_WINDOW_LOADING_FINISH` | sub → main | Notifies loading finished |

These are handled by the `CustomMessages` class in `ui/CustomMessages.ahk`.

## Data Storage & Persistence

The script writes data in three different storage locations, each with different lifetimes.

### 1. WebView sessionStorage (Browser Storage)

**Scope:** Per Response Window (WebView2 instance). Persists across page reloads within the same window (e.g., system sleep/wake), but is **automatically cleared** when the window closes. Unlike `localStorage`, data does NOT bleed between different chat sessions.

| Key | Type | Content | Purpose |
|-----|------|---------|---------|
| `isChatMode` | string `"true"` | Whether the current WebView is in chat mode | Restores the chat UI layout if the WebView reloads |
| `chatMessages` | JSON string | Array of `{role, content, model?}` objects | Restores all chat bubbles after a reload (e.g. system sleep/wake) |
| `preMarkdownText` | string | Raw markdown text for FIM/non-chat modes | Restores rendered content for the fallback `#content` div on reload |

**Important:** `sessionStorage` is scoped to each WebView2 instance. When the window closes, the data is automatically purged — no stale chat from a previous prompt will appear.

### 2. Temp Files (`%TEMP%\*`)

**Scope:** Session-only. Created per prompt, deleted when the Response Window closes.

| Pattern | Encoding | Content | Lifecycle |
|---------|----------|---------|-----------|
| `chatHistoryJSONRequest_*.json` | UTF-8 | Full chat conversation as JSON `{model, messages: [{role, content}]}` | Created on prompt start. Appended on each user/assistant message exchange. **Deleted** on window close. |
| `cURLCommand_*.txt` | UTF-8 | The raw cURL command string (with API key, paths, model, etc.) | Created per request. **Deleted** on window close. |
| `cURLOutput_*.json` | UTF-8 | Raw response from LLM API (full JSON returned by the endpoint) | Created per request. Overwritten on retry. **Deleted** on window close. |
| `responseWindowData_*.json` | UTF-8 | Request params passed from main script to sub-process (prompt name, model, pasteMode, skipConfirmation, etc.) | Created on prompt start. **Deleted** on window close. |

**All temp file names are sanitized** with `RegExReplace(..., "[\/\\:*?\"<>|]", "")` to avoid illegal filesystem characters.

### 3. API Log File (Persistent)

| Location | Format | Content | Lifecycle |
|----------|--------|---------|-----------|
| `%TEMP%\LLM_API_Log.json` | JSON array | Array of log entries, each containing `{timestamp, promptName, provider, model, isFIM, endpoint, pasteMode, request, response, status}` | **Never deleted by the script.** Capped at `apiLogMaxEntries` (default: 20). Viewable via Options → API Logs. |

The API log is the only persistent storage. Each entry stores:
- **`request`** — The JSON payload sent to the API (system + user messages only, NOT including the response — see `requestBeforeAppend` in `chat/ResponseWindow.ahk`)
- **`response`** — The raw JSON response from the API (includes the assistant's reply and metadata)
- Cleared manually via the "Clear Logs" button in the API Logs Viewer

### 4. Debug Log File (Temporary Diagnostics)

| Location | Format | Content | Lifecycle |
|----------|--------|---------|-----------|
| `%TEMP%\LLM_Debug_Log.txt` | Plain text, one line per entry | Timestamped diagnostic messages from `RequestProcessor.ahk`, `ResponseWindow.ahk`, and `StreamHandler.ahk` | Cleared on each script startup. Grows during the session. Used only for debugging — not a persistent feature. |

The `debugLog()` helper is defined in two places:
- `chat/ChatUtils.ahk` — used by `ResponseWindow.ahk` and `StreamHandler.ahk` (sub-process context). Tags lines with the model name from `requestParams["singleAPIModelName"]`.
- `app/RequestProcessor.ahk` — standalone copy for the main script context. Tags lines with `[RequestProcessor]`.

Each entry records a key decision or state during the request lifecycle:
- **RequestProcessor**: which cURL command type was selected (streaming vs non-streaming vs FIM), file paths written, the `stream` field value passed to ResponseWindow
- **ResponseWindow** (non-streaming): entry into `sendRequestToLLM`, cURL command length/contents, PID of spawned cURL process, while-loop exit reason (did the process end or was it cancelled?), output file existence check
- **StreamHandler** (streaming): entry into `sendStreamingRequest`, PID, whether the output file exists at start, poll iteration count, total content length accumulated after the stream ends

To view the log at any time, open `%TEMP%\LLM_Debug_Log.txt` in a text editor. The log is automatically cleared each time the script starts (see `Main.ahk` — startup block).

### Summary

| Storage | Lifetime | Data |
|---------|----------|------|
| WebView sessionStorage | Per window session | Chat bubble state (for reload recovery) |
| `%TEMP%\*.json/txt` | Per prompt | Request payloads, cURL commands, API responses |
| `%TEMP%\LLM_API_Log.json` | Persistent | API interaction history (capped) |
| `%TEMP%\LLM_Debug_Log.txt` | Per session | Diagnostic trace (cleared on startup) |

**There is NO on-disk chat history.** Once a Response Window closes, the conversation is gone. This is intentional — the script is designed for ad-hoc queries, not as a permanent chat record.
