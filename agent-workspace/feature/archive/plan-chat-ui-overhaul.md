# Implementation Plan: Chat UI Overhaul

## §1 Overall Project

The LLM AutoHotkey Assistant is a Windows desktop application (AutoHotkey v2) that provides hotkey-activated LLM interactions. The chat UI runs inside a WebView2 control (embedded Edge browser) — HTML/CSS/JS frontend communicating with AutoHotkey backend via `chrome.webview.postMessage()` / `postWebMessage()`. Current chat UI uses Bootstrap 5.3 dark/light mode with emoji-based icons, a toggle sidebar, and a basic toolbar. The JS layer is ~18 modules handling streaming, branching, attachments, settings, and undo. AHK backend (15+ modules) handles SQLite persistence, cURL API calls, and IPC — none of this changes.

## §2 This Feature

Complete visual overhaul of the chat WebView UI. Replace the Bootstrap-based design with a custom 4-column SaaS-style layout defined in [`agent-workspace/feature/chat-ui-mock.html`](agent-workspace/feature/chat-ui-mock.html). The mock is a self-contained 1544-line HTML file with inline CSS and JS. This feature:

1. Modularizes the mock into focused CSS/HTML/JS files
2. Downloads all CDN resources (Google Fonts, Lucide icons) to local
3. Replaces the existing `webui/` with the new design
4. Removes Bootstrap entirely
5. Adapts all existing JS modules to work with the new DOM structure
6. Preserves all existing functionality (streaming, branching, attachments, settings, undo, etc.)

**Out of scope:** New features not present in the mock, API changes. **In scope:** Minimal AHK changes for folder persistence — a `chat_folders` SQLite table, `folder_id` column on `chat_threads`, and folder CRUD `sidebarAction` subActions (createFolder, renameFolder, deleteFolder, moveToFolder).

**Deferred:** Dark mode — the CSS variable system supports it trivially (`[data-theme="dark"]` overrides), but the mock only defines light mode. Dark mode will be added in Step 7 as a `[data-theme="dark"]` selector block. Custom font configuration (`setFontFace`) is dropped — the new design uses Inter/JetBrains Mono exclusively. The Export button in the topbar is a visual stub for a future feature.

## §3 End State Upon Feature Completion

### Layout Structure

```
┌──────┬────────────────┬──────────────────────┬──────────┐
│ Icon │  Left Panel    │  Center (Chat)       │  Right   │
│ Rail │  (340px)       │  (flex: 1)           │  Panel   │
│ 80px │  ┌──────────┐  │  ┌────────────────┐  │ (400px)  │
│      │  │ Chats    │  │  │ Topbar          │  │ ┌──────┐ │
│  🔷   │  │ ┌──────┐ │  │  │ Title · Stats  │  │ │Config│ │
│  💬   │  │ │Search│ │  │  │ Font Controls  │  │ │Model │ │
│  📊   │  │ └──────┘ │  │  └────────────────┘  │ │System│ │
│  ⚙    │  │ ┌──────┐ │  │  ┌────────────────┐  │ │Temp  │ │
│      │  │ │Folder│ │  │  │ Thread          │  │ │Think │ │
│      │  │ │ Chat │ │  │  │ ┌────────────┐  │  │ │Adv.  │ │
│      │  │ │ Chat │ │  │  │ │ Messages   │  │  │ └──────┘ │
│      │  │ └──────┘ │  │  │ │            │  │  │ ──────── │
│      │  │ ┌──────┐ │  │  │ │            │  │  │ Thread   │
│      │  │ │Unfiled│ │  │  │ └────────────┘  │  │ Map      │
│      │  │ │ Chat  │ │  │  └────────────────┘  │ ┌──────┐ │
│      │  │ └──────┘ │  │  ┌────────────────┐  │ │Search│ │
│      │  │          │  │  │ Composer       │  │ │Items │ │
│  👤   │  │ Trash    │  │  │ [tools] [inp] │  │ └──────┘ │
│      │  └──────────┘  │  │ [mic] [send]   │  │          │
│      │                │  └────────────────┘  │          │
└──────┴────────────────┴──────────────────────┴──────────┘
         ↕ resizable      ↕ resizable           ↕ resizable
```

### Panel Details

**Icon Rail** (80px fixed):
- Brand mark (layers icon, indigo bg)
- Nav icons: Chats (active), Dashboard, Settings — with active indicator bar
- Spacer
- User avatar circle (initials "JD", clickable)

**Left Panel** (340px default, resizable 64-600px, collapsible to 0):
- Header: "Chats" title + New Folder + New Chat icon buttons
- Global search input with search icon
- Scrollable area:
  - Folders (collapsible): Greetings (4), Research (1) — with chevron, rename, delete buttons
  - Unfiled section label
  - Chat items: icon + name + date + hover-reveal action buttons (rename, move, delete)
  - Active chat: indigo left border + indigo bg
- Bottom: Collapsible Trash section with restore/permanent-delete

**Center** (flex: 1):
- **Topbar** (76px min-height):
  - Left: Chat title (editable via pencil icon) + folder badge pill
  - Center: Token stats row — Context Used, Tokens ↑↓, Cache, API Cost ($)
  - Right: Font size controls (type icon, minus, 17px display, plus) + Copy All + Export buttons
- **Thread** (scrollable): Message area, max-width 1080px centered, 40px padding
  - User messages: author "You" + timestamp, light gray bubble, bottom-left radius 4px
  - Bot messages: author "Violet" (indigo) + model · timestamp, no bubble, full-width
  - Thinking block: collapsible details with brain icon, monospace content, left border
  - Edit UI: textarea with indigo focus ring, Cancel / Save as Branch / Overwrite buttons
  - Message actions (hover-reveal): branch nav (◀ 2/2 ▶), copy, edit, regenerate (bot only), quote, fork, delete, stats popover
  - Stat popover: token usage details (output/thinking/cache/speed/TTFT/time)
  - Flash animation on tree-node click (indigo glow → fade)
- **Composer**:
  - Rounded container with shadow, indigo focus ring
  - Left tools: paperclip + tools dropdown (Web Search, Code Execution, Calculator toggles)
  - Center: auto-resizing textarea, placeholder "Type a message... (Shift+Enter for newline)"
  - Right: mic + send (indigo arrow) buttons

**Right Panel** (400px default, resizable 260-800px, collapsible to 0):
- **Configuration** (top half, vertically resizable):
  - "CONFIGURATION" section title
  - Model card: Violet name, deepseek-v4-flash ID, description, "Change →" button
  - System prompt: mini textarea + "Expand" link → full modal editor
  - Temperature: label + current value + range slider (0-2, step 0.1)
  - Thinking Level: dropdown (Off/Low/Medium/High)
  - Advanced: collapsible section with Structured Outputs, Code Execution, Web Search toggles
- **Vertical Resizer** (drag handle)
- **Thread Map** (bottom half):
  - "THREAD MAP" section title + "View Tree" button
  - Search-in-thread input
  - Thread items: role badge (You/Violet) + content snippet, 2-line clamp
  - Left border color: user = dark, bot = indigo
  - Click scrolls to + flashes target message

### Modals & Overlays

**Tree Modal** (900×700px, zoomable/pannable):
- Header: "Conversation Tree" + "Viewing active path · N nodes"
- Controls: zoom in/out/fit + close
- Canvas: dot-grid background, grab-to-pan cursor
- Nodes: positioned cards with role label + text preview, active-path = indigo border
- SVG connector lines between nodes
- Click node → close modal + scroll to + flash message

**System Prompt Modal** (720×600px):
- Header: "Edit System Prompt" + close
- Body: full monospace textarea
- Footer: character count + Cancel + Save Changes

**Model/Assistant Popover** (400px, positioned near model card):
- Tabs: Assistants | Models
- Assistants tab: Violet (purple avatar), Nova (green), Atlas (amber) — each with name, description, radio
- Models tab: grouped by provider (Deepseek, Google, OpenAI) — each with box icon + name + description + radio
- Click overlay to close

### Design System (CSS Variables)

All styling uses CSS custom properties on `:root`:
- Colors: `--bg-main: #FAFAFA`, `--bg-panel: #FFFFFF`, `--bg-hover: #F3F4F6`, `--bg-active: #EEF2FF`
- Text: `--text-primary: #111827`, `--text-secondary: #4B5563`, `--text-tertiary: #9CA3AF`
- Accent: `--accent-primary: #4F46E5`, `--accent-hover: #4338CA`, `--accent-light: #E0E7FF`
- Borders: `--border-light: #F3F4F6`, `--border-main: #E5E7EB`, `--border-focus: #C7D2FE`
- User messages: `--user-msg-bg: #F3F4F6`, `--user-msg-text: #111827`
- Radii: `--radius-sm: 6px`, `--radius-md: 10px`, `--radius-lg: 14px`, `--radius-full: 9999px`
- Fonts: `--font-ui: 'Inter', system-ui, sans-serif`, `--font-mono: 'JetBrains Mono', monospace`
- Shadows: sm/md/lg/modal
- Dynamic: `--chat-font-size: 17px` (adjustable 12-28px)

### External Resources (All Downloaded Locally)

| Resource | Local Path |
|----------|-----------|
| Inter 400,500,600,700 (latin) | `webui/fonts/inter-latin-*.woff2` |
| JetBrains Mono 400,500,600 (latin) | `webui/fonts/jetbrains-mono-latin-*.woff2` |
| Lucide icons | `webui/js/vendor/lucide.min.js` |

### Removed

- `webui/Bootstrap/` — entire directory (bootstrap.min.css, bootstrap.bundle.min.js, sidebars.css, sidebars.js, fonts/)
- `webui/css/chat.css` — Bootstrap-dependent chat layout
- `webui/css/custom.css` — Bootstrap-dependent custom styles
- All old CSS in `webui/css/chat/` (6 files) — replaced by new modular CSS

## §4 Implementation Steps

---

### [x] Step 0: Write JS Test Safety Net

**Goal:** Encode current JS module behavior in unit tests so wiring steps can verify nothing breaks.

**Actions:**
- Create `tests/unit/chat-render.test.js` — test `createMessageBubble()` DOM output for user/assistant/system roles, attachment rendering, reasoning block, action buttons presence, `renderChatMessages()` container population, `appendChatMessage()`, `removeLastAssistantMessage()`, `replaceMessagesAfter()`, `updateChatMessages()`
- Create `tests/unit/chat-actions.test.js` — test `addMessageActions()` produces correct buttons for user vs assistant, branch nav only when siblings>1, `_iconBtn()` factory, `_createMoreDropdown()` structure
- Create `tests/unit/chat-sidebar.test.js` — test `loadThreadList()` DOM output, `loadTrashList()` DOM output, `modelEmoji()` mapping
- Create `tests/unit/chat-branching.test.js` — test `renderChatTree()` / `renderTreeNode()` DOM output with children, `updateBranchInfo()` label update
- Create `tests/unit/stream.test.js` — test `createStreamingBubble()` DOM structure, `createThinkingBlock()` nesting, `_persistStreamedMessage()` dedup logic, `cancelStreaming()` partial save, `onStreamDone()` finalization
- Create `tests/unit/chat-settings.test.js` — test `populateAssistantDropdown()` DOM output, `updateDropdownLabel()` selector state, `populateCurrentSettings()` field population
- Create `tests/unit/chat-format.test.js` (extend existing) — add `updateTokenUsage()` DOM output tests with various data inputs (zero state, full data, missing fields)
- Create `tests/unit/chat-input.test.js` (extend existing) — add `setChatButtonsEnabled()` state transitions (enabled→disabled→enabled), button text/onclick
- Create `tests/unit/main.test.js` — test `handleWebMessage()` routes to correct handlers for all targets (setTheme, initChatMode, appendChatMessage, streamContent, streamDone, streamCancelled, threadList, loadThread, etc.)

**Unit Tests to Write/Update:**
- `tests/unit/chat-render.test.js` — ~18 tests (createMessageBubble × 3 roles + attachments + reasoning + actions, renderChatMessages, appendChatMessage, removeLastAssistantMessage, replaceMessagesAfter, updateChatMessages)
- `tests/unit/chat-actions.test.js` — ~8 tests (addMessageActions user/assistant, branch nav show/hide, iconBtn factory, moreDropdown structure)
- `tests/unit/chat-sidebar.test.js` — ~10 tests (loadThreadList empty/with data/active, loadTrashList empty/with data/expand, modelEmoji, renderNavList, scrollToMessage)
- `tests/unit/chat-branching.test.js` — ~6 tests (renderChatTree empty/with data, renderTreeNode with/without children/with sibling badge, updateBranchInfo)
- `tests/unit/stream.test.js` — ~12 tests (createStreamingBubble, createThinkingBlock collapsed/expanded, persistStreamedMessage dedup by id/by content/no dup, cancelStreaming with/without dbMsg, onStreamDone finalization)
- `tests/unit/chat-settings.test.js` — ~5 tests (populateAssistantDropdown, updateDropdownLabel assistant/non-assistant, populateCurrentSettings, onSettingsProviderChange)
- `tests/unit/chat-format.test.js` — extend with ~4 tests (updateTokenUsage zero/full/missing fields, showTokenUsageBar)
- `tests/unit/chat-input.test.js` — extend with ~4 tests (setChatButtonsEnabled enabled/disabled, onStopStreaming, handleChatInputKeydown Enter/Shift+Enter)
- `tests/unit/main.test.js` — ~10 tests (handleWebMessage routing for all targets)

**Integration Tests to Write/Update:**
None — infrastructure unchanged.

**Live Smoke Test:**
Run `tests\run_js_tests.bat` — verify all 89 existing + ~77 new = ~166 JS tests pass. Then run `tests\run_all_tests.bat` — verify 211 AHK + 166 JS = 377 total tests pass.

**Smoke Test Classification:** Model

**Suggested Commit Message:** test(js): add comprehensive unit test safety net for chat UI modules

---

### [ ] Step 1: Modularize Mock + Download External Resources

**Goal:** Split the 1544-line mock into focused CSS/HTML/JS files. Download fonts and Lucide locally. The modularized version must look pixel-identical to the original mock. **Note:** This step may involve multiple design iteration rounds — the user may refine the mock during verification.

**Actions:**

**1a. Download External Resources:**
- Download Inter font (400,500,600,700 latin) as `.woff2` files. Use the Google Fonts CSS API URL (`https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&display=swap`) — parse the returned CSS to get the `.woff2` URLs, download each, save to `webui/fonts/inter-latin-400.woff2` through `inter-latin-700.woff2`
- Write `webui/fonts/inter.css` with `@font-face` declarations for each weight, pointing to local `.woff2` files, with `font-display: swap`
- Download JetBrains Mono font (400,500,600 latin) similarly → save as `webui/fonts/jetbrains-mono-latin-400.woff2` through `600.woff2`
- Write `webui/fonts/jetbrains-mono.css` with `@font-face` declarations
- Download `lucide.min.js` from `https://unpkg.com/lucide@latest` → save as `webui/js/vendor/lucide.min.js`
- Write `webui/fonts/fonts.css` that `@import`s both `inter.css` and `jetbrains-mono.css`

**1b. Extract CSS into 10 Modular Files:**
Split the mock's 547-line `<style>` block (lines 12-659) into these files. Copy rules verbatim — do not refactor or change selectors. The goal is pixel-identical output:
- `webui/css/theme.css` — `:root { ... }` (lines 13-53), `* { box-sizing }` (line 55), `html, body` (lines 57-66), `button, input, textarea, select` (lines 68-69), button transitions (lines 70-73)
- `webui/css/layout.css` — `.app` (line 75), `.icon-rail` (lines 78-81), `.brand-mark` (lines 83-88), `.nav-icon` (lines 90-101), `.icon-rail-spacer` (line 103), `.nav-avatar` (lines 105-110), `.rail-left`/`.rail-right` (lines 113-116), `.seam` (lines 118-134), mini rail state (lines 137-145)
- `webui/css/left-panel.css` — `.rail-left-head` (line 148-149), `.rail-title` (line 149), `.rail-head-actions` (line 151), `.icon-btn`/`.ghost-btn` (lines 152-158), `.btn-primary` (lines 159-163), `.icon-btn:hover`/`.ghost-btn:hover` (line 165), `.search-wrap` (lines 168-169), `.search-input` (lines 170-178), `.search-icon` (lines 177-178), `.rail-left-scroll` (line 180), `.folder`/`.folder-head`/`.folder-chevron`/`.folder-name`/`.folder-count` (lines 182-192), `.folder-actions`/`.folder-action-btn` (lines 195-202), `.folder-chats` (lines 204-205), `.unfiled-label` (line 207), `.chat-item`/`.chat-icon`/`.chat-meta`/`.chat-name`/`.chat-item-bottom`/`.chat-date` (lines 209-227), `.chat-actions`/`.chat-action-btn` (lines 229-246), `.trash-wrap`/`.trash-head`/`.trash-items`/`.trash-item`/`.trash-item-acts` (lines 248-261)
- `webui/css/center.css` — `.center` (line 264), `.topbar` (lines 267-271), `.topbar-left` (line 272), `.chat-title-topbar`/`.title-text` (lines 273-277), `.rename-chat-btn` (lines 279-283), `.chat-title-topbar .fold` (lines 286-289), `.token-bar`/`.tu-item`/`.tu-icon`/`.tu-val` (lines 292-298), `.topbar-right` (line 300), `.font-size-ctrl` (lines 303-316), `.thread` (line 319), `.thread-inner` (line 321), `.composer` (line 412), `.composer-inner` (lines 413-418), `.composer-tools` (lines 420-423), `.tools-dropdown`/`.tools-menu` (lines 425-436), `.composer-inner textarea` (lines 437-440), `.composer-actions`/`.send-btn` (lines 443-455)
- `webui/css/messages.css` — `.msg`/`.msg-body`/`.msg-head`/`.msg-author`/`.msg-meta` (lines 324-332), `.msg-content` (line 334), `.msg.you .msg-content` (lines 336-339), `.msg.bot .msg-content` (line 340), `.thinking-block` (lines 343-353), `.msg-edit-ui`/`.msg-edit-textarea`/`.msg-edit-actions` (lines 356-366), `.msg.editing` states (lines 357-358), flash animation (lines 385-389)
- `webui/css/actions.css` — `.msg-actions` (line 369), `.msg-action-btn` (lines 372-379), `.branch-nav`/`.branch-label` (lines 381-383), `.stat-toggle`/`.stat-popover`/`::after`/`::before` (lines 392-409)
- `webui/css/right-panel.css` — `.rr-panel`/`.rr-panel-head`/`.rr-panel-body` (lines 458-476), `.model-card`/`.change-btn` (lines 479-495), `.field`/`.field-label`/`.expand-link` (lines 498-504), `textarea.sysinput` (lines 506-511), `input[type=range]` (lines 513-518), `select.dropdown` (lines 520-526), `.advanced-wrap`/`.advanced-toggle`/`.advanced-body`/`.toggle-row` (lines 529-538), `.switch` (lines 540-543), `.tree-launch` (lines 546-548), `.thread-item` (lines 550-555)
- `webui/css/modals.css` — `.modal-overlay`/`.modal-box`/`.modal-head`/`.modal-title` (lines 558-563), `.tree-modal`/`.tree-modal-sub`/`.tree-controls`/`.zoom-controls` (lines 565-576), `.tree-canvas-wrap`/`.tree-zoom-layer`/`.tree-canvas` (lines 574-577), `.tree-node` (lines 579-586), `.sysmsg-modal`/`.sysmsg-body`/`.sysmsg-foot` (lines 588-596)
- `webui/css/popover.css` — `.popover-overlay` (line 599), `.model-popover` (lines 601-607), `.popover-header`/`.popover-tab` (lines 609-615), `.popover-content`/`.popover-pane` (lines 617-619), `.si-group-label` (line 621), `.selector-item`/`.si-avatar`/`.si-icon`/`.si-text`/`.si-name`/`.si-desc`/`.si-radio` (lines 623-652)
- `webui/css/components.css` — scrollbar styles (lines 655-658); button active press effect is already in theme.css

CSS load order in `<head>`: theme → layout → left-panel → center → messages → actions → right-panel → modals → popover → components

**1c. Extract HTML Skeleton:**
Remove all hardcoded sample data while preserving structural containers:
- **Remove**: ALL `.chat-item` elements inside `.folder-chats`, the unfiled `.chat-item`, ALL `.msg` elements inside `.thread-inner`, ALL `.thread-item` elements inside `.rr-panel-body`, ALL `.tree-node` elements inside `.tree-canvas`, the SVG connector lines, ALL `.selector-item` elements inside `.popover-pane`, ALL `.trash-item` elements
- **Keep**: The `.folder` wrapper divs (with `data-folder` attributes), the `.folder-head` structure, the `.unfiled-label`, the `.trash-wrap` skeleton, the `.thread-inner` container, the `.composer-inner` structure, the popover skeleton (`.popover-header` + `.popover-content` with empty panes), the modal skeletons, the tree canvas skeleton, the config panel skeleton
- **Add** these IDs to structural elements (they don't exist in the mock):
  - `id="chat-sidebar"` on `#railLeft`
  - `id="chat-messages"` on `.thread` (NOT `.thread-inner` — scroll operations target `.thread`)
  - `id="thread-list"` on `.rail-left-scroll`
  - `id="nav-message-list"` as a new `<div>` inside `.rr-panel-body`, BELOW the search input
  - `id="sidebar-toggle"` on the Chats nav icon button
  - `id="new-chat-btn"` on the "New chat" icon button in `.rail-head-actions`
  - `id="chat-input-area"` on `.composer`
  - `id="attachment-bar"` as a new `<div>` above `.composer-inner` (hidden by default)
  - `id="attachment-file-input"` as a hidden `<input type="file">` inside `.composer`
  - `id="attachment-browse-btn"` on the paperclip button in `.composer-tools`
  - `id="copy-entire-chat-btn"` on the copy icon button in `.topbar-right`
  - `id="chat-input"` on the composer `<textarea>`
  - `id="chat-send-btn"` on the send button (`.send-btn`)
  - `id="usage-dashboard-btn"` as a new icon button in `.topbar-right`
  - `id="fim-notice"` as a new `<div>` at the top of `.thread` (hidden by default)
  - `id="token-usage-bar"` on `.token-bar` (`#tokenBar`)
  - `id="token-usage-content"` on a child div inside `.token-bar`

**Scroll Container Note (Critical):** In the mock, `.thread` is the scrollable element (`overflow-y: auto`), while `.thread-inner` is a centered max-width wrapper. All existing JS scroll logic operates on `#chat-messages`. Therefore, `id="chat-messages"` MUST be on `.thread`, NOT on `.thread-inner`. Messages render as direct children of `.thread`. Apply `.thread-inner`'s max-width/padding to `.thread` directly (or use CSS `> *` selector).

**1d. Extract mock-ui.js (Limited Scope):**
Extract ONLY these behaviors from the mock's `<script>` block into `webui/js/mock-ui.js`:
- Panel resize: `setupResize()` (horizontal) and `setupVerticalResize()` (vertical)
- Font size controls: `#btn-font-dec` / `#btn-font-inc` click handlers
- Tree modal zoom/pan: zoom in/out/fit buttons, canvas pan, wheel zoom
- Composer auto-resize: textarea height adjustment

**Explicitly REMOVE (do NOT extract)** — these behaviors are replaced by app modules:
- Copy button feedback → `chat-format.js`
- Folder collapse → `chat-sidebar.js`
- Chat item selection → `chat-sidebar.js`
- Tools menu toggle → Step 7
- Stat popover → `chat-token-tooltip.js`
- Inline message editing → `chat-branching.js`
- Flash animation → `chat-branching.js`
- Config toggles/switches → `chat-settings-modal.js`
- Model popover → `chat-settings.js`
- Modals setup → `chat-settings-modal.js` + `chat-branching.js`
- System prompt modal sync → `chat-settings-modal.js`

**Important:** Wrap `mock-ui.js` functions in a namespace to avoid global conflicts: `window.MockUI = { setupResize, setupVerticalResize, initFontControls, initTreeZoom, initComposerResize }`. Call from `main.js` DOMContentLoaded.

**Unit Tests to Write/Update:**
None — pure structural extraction.

**Integration Tests to Write/Update:**
None.

**Live Smoke Test:**
1. Open `agent-workspace/feature/chat-ui-mock.html` in a browser (left window)
2. Open the new modularized `webui/index.html` in a browser (right window)
3. Compare side-by-side at 100% zoom:
   - Icon rail: brand mark, nav icons, avatar — identical size, spacing, colors
   - Left panel: "Chats" header, search input, folders (Greetings/Research), chat items, trash — identical
   - Center: topbar (title, stats, font controls), thread messages (user + bot with thinking), composer — identical
   - Right panel: model card, system prompt, temperature slider, thinking dropdown, advanced toggles, thread map — identical
   - Seams/resizers: drag handles visible, notch visible on hover
4. Click interactions on modularized version:
   - Folders collapse/expand with chevron animation
   - Chat items highlight on click
   - Font size +/- adjust chat font size and update display
   - Copy buttons show checkmark for 2 seconds
   - Tools dropdown opens/closes
   - Stat popover opens/closes
   - Edit button shows inline edit UI, Cancel/Save work
   - Thread map items click → flash target message
   - Panel resize: drag seams, click notch to collapse/expand
   - Vertical resize: drag h-seam
   - Model card click → popover opens, tabs switch, items select
   - Expand system prompt → modal opens, edit, save reflects in mini textarea
   - Tree modal: opens, zoom in/out/fit, pan, node click → close + flash
   - Advanced toggles expand/collapse, switches toggle
   - Temperature slider updates value display
5. Verify NO 404 errors in browser console
6. Verify all Lucide icons render (no missing icons)

**Smoke Test Classification:** Human — visual pixel comparison required. Note: design iteration rounds expected.

**Suggested Commit Message:** refactor(webui): modularize chat UI mock into focused CSS/HTML/JS files with local fonts and icons

---

### [x] Step 2: Replace webui/ with Modularized Skeleton + Remove Bootstrap

**Goal:** Swap the existing `webui/index.html` and CSS files for the new modularized versions. Remove Bootstrap. The webview loads without errors (no data yet — just the skeleton).

**Actions:**
- Delete `webui/Bootstrap/` directory entirely
- Delete `webui/css/chat.css`
- Delete `webui/css/custom.css`
- Delete `webui/css/chat/` directory (6 old CSS files)
- Replace `webui/index.html` with the new skeleton HTML (from Step 1c) that:
  - References all new modular CSS files in order: theme → layout → left-panel → center → messages → actions → right-panel → modals → popover → components
  - References `webui/fonts/fonts.css`
  - References vendor JS: `lucide.min.js`, `markdown-it.min.js`, `katex.min.js`, `mhchem.min.js`, `texmath.min.js`, `highlight.min.js`, `pdf.min.js`, `officeparser.iife.js`
  - References `mock-ui.js` (wrapped in `window.MockUI` namespace)
  - References app JS in dependency order: chat-core → chat-settings → chat-format → chat-render → chat-token-tooltip → chat-actions → chat-attachments* → chat-input → chat-branching → chat-sidebar → chat-quote → chat-undo → stream → chat-settings-modal → main
  - **Do NOT remove `chat-settings-modal.js`.** Instead, update it with guard clauses: every function checks if its target DOM elements exist before operating. `populateCurrentSettings()` stores values in `window._pendingSettings` if the right panel doesn't exist yet. `openModelSettings()` becomes a no-op. `updateDropdownLabel()` stores in `window._dropdownLabel`. This prevents ReferenceErrors in `handleWebMessage` between Steps 2-6.
  - Includes all IDs added in Step 1c
  - Calls `lucide.createIcons()` after DOM ready
  - Includes a helper: `function refreshIcons() { if (typeof lucide !== 'undefined') lucide.createIcons(); }` — to be called after dynamic DOM updates in later steps
- Preserve `webui/api-logs.html` and `webui/usage-dashboard.html` unchanged
- Keep all vendor JS files in `webui/js/vendor/` unchanged

**Bootstrap CSS Variable Cleanup (Do NOW, Not Step 7):**
These files reference `var(--bs-*)` and break as soon as Bootstrap CSS is removed:
- `webui/js/chat/chat-undo.js` line 130: Replace `var(--bs-tertiary-bg)`, `var(--bs-body-color)`, `var(--bs-border-color)` with new design tokens: `var(--bg-panel)`, `var(--text-primary)`, `var(--border-main)`
- `webui/js/main.js` line 266 (`showError`): Replace `var(--bs-danger)` and `var(--bs-light)` with `var(--danger)` and `var(--bg-panel)`
- `webui/js/chat/chat-quote.js` line 62: Replace `var(--bs-primary)` with `var(--accent-primary)`
- `webui/js/stream.js` line 161: Replace `var(--bs-text-muted,#9ca3af)` with `var(--text-tertiary)`
- Remove `setTheme()` function from `main.js` (dark mode added back in Step 7). Replace with stub that sets `data-theme` attribute.
- Remove `setFontFace()` function from `main.js` (font is now fixed to Inter/JetBrains Mono). **Also remove the `setFontFace` case from `handleWebMessage` switch** to prevent ReferenceError.
- Remove `data-bs-theme` attribute references throughout

**Guard Clauses in handleWebMessage (Prevent ReferenceErrors):**
Wrap these `handleWebMessage` cases with `typeof === 'function'` guards:
- `currentSettings`: `if (typeof populateCurrentSettings === 'function') populateCurrentSettings(data);`
- `dropdownLabel`: `if (typeof updateDropdownLabel === 'function') updateDropdownLabel(data);`
- `assistantList`: store in `window.assistantList = data;` BEFORE calling `populateAssistantDropdown(data)` (which targets a now-removed `<select>`). Add guard: `if (typeof populateAssistantDropdown === 'function') populateAssistantDropdown(data);`

**chat-settings-modal.js Guard Clauses:**
- `populateCurrentSettings()`: check `if (!document.getElementById('model-settings-modal')) { window._pendingSettings = settings; return; }` — stores for later retrieval when config panel is wired in Step 6
- `openModelSettings()`: check `if (!document.getElementById('model-settings-modal')) return;`
- `saveModelSettings()`: check `if (!document.getElementById('model-settings-modal')) return;`
- `updateDropdownLabel()`: check `if (!document.getElementById('assistant-selector')) { window._dropdownLabel = data; return; }`
- `onSettingsProviderChange()`: check `if (!document.getElementById('settings-provider')) return;`
- `closeModelSettings()`: check `if (!document.getElementById('model-settings-modal')) return;`

**Unit Tests to Write/Update:**
Update all Step 0 test expectations where Bootstrap CSS variables were changed. Remove tests for `setTheme()` and `setFontFace()` (functions deleted). Tests for `chat-settings-modal.js` functions should be skipped (module temporarily removed from load list).

**Integration Tests to Write/Update:**
None.

**Live Smoke Test:**
1. Run `tests\run_js_tests.bat` — all tests pass (adjusted expectations)
2. Run `tests\run_all_tests.bat` — all 211 AHK + JS tests pass
3. Verify `webui/index.html` references all CSS/JS files with correct paths (no 404s will appear at runtime)
4. Verify Bootstrap directory is deleted

**Smoke Test Classification:** Model

**Suggested Commit Message:** feat(webui): replace Bootstrap UI with modularized chat design skeleton

---

### [x] Step 3: Adapt Core Chat Modules (render, input, stream, core)

**Goal:** Update `chat-core.js`, `chat-render.js`, `chat-input.js`, `stream.js`, and `chat-quote.js` to work with the new DOM structure. Messages render in the new bubble style. Sending and streaming work.

**Actions:**
- Update `chat-core.js`:
  - `initChatMode()`: remove `#chat-layout`/`#content` show/hide logic (chat always visible now). Still call `renderChatMessages()`, `showTokenUsageBar()`.
  - `renderMarkdown()`: update container references. For FIM mode, render into `#chat-messages` with a FIM banner (or keep `#content` as a fallback div inside `.thread`).
  - Scroll tracking in `DOMContentLoaded`: track `#chat-messages` (which is `.thread` — the scrollable element)
- Update `chat-render.js`:
  - `createMessageBubble()`: change class names — `.chat-message` → `.msg`, `.{role}` → `.you`/`.bot`/`.system`
  - Label row: `.message-label` → `.msg-author` (use `<span class="msg-author">` + `<span class="msg-meta">` for timestamp in `.msg-head`)
  - Content div: `.message-content` → `.msg-content`
  - Wrap entire label+content in `.msg-body` div (matches mock structure)
  - Actions div: `.message-actions` → `.msg-actions` (append to `.msg-body`, not directly to `.msg`)
  - User message: `.msg.you .msg-content` gets user-bubble styling automatically from CSS
  - Bot message: render without bubble background (CSS handles `.msg.bot .msg-content`)
  - Reasoning: `.thinking-block` stays the same (class names match mock)
  - Attachments: `.msg-attachment-image`/`.msg-attachment-file` stay the same
  - After each bubble creation: call `refreshIcons()` to render Lucide icons in action buttons (Step 5 adds icon attributes; this ensures they render)
- Update `chat-input.js`:
  - `onChatSend()`: `#chat-input` preserved, `#chat-send-btn` preserved — no structural changes
  - `showLoadingIndicator()`: append loading dots to `#chat-messages`. Loading dots CSS (`.loading-indicator`, `.dot`, `@keyframes bounce`) must be added to `webui/css/messages.css`
  - `setChatButtonsEnabled()`: update button text/onclick for send/stop (same pattern)
- Update `stream.js`:
  - `createStreamingBubble()`: use `.msg.bot` class. Create structure: `.msg.bot` > `.msg-body` > `.msg-head` (`.msg-author`: "Streaming...") + `.msg-content` (empty, for content). Return the `.msg.bot` element as `streamState.bubble`.
  - `createThinkingBlock()`: insert `.thinking-block` into `streamState.bubble.querySelector('.msg-body')`, BEFORE `.msg-content`. Use `streamState.bubble.querySelector('.msg-body').insertBefore(details, streamState.contentDiv)`.
  - `onStreamDone()`: finalize with new class names, call `addStreamingActions()`, call `refreshIcons()`. Actions div appends to `.msg-body` (not `.msg.bot` directly) so hover CSS (`.msg:hover .msg-actions`) works.
  - `addStreamingActions()`: change `bubble.appendChild(actions)` to `bubble.querySelector('.msg-body').appendChild(actions)`.
  - `cancelStreaming()`: same pattern, updated selectors.
  - Fix `var(--bs-text-muted,#9ca3af)` at line 161 → `var(--text-tertiary)`. (Already done in Step 2 cleanup, but verify here.)
  - **Standardization rule**: ALL `.msg-actions` divs must be children of `.msg-body`, not `.msg`. This ensures `.msg:hover .msg-actions { opacity: 1 }` always works.
- Update `chat-quote.js`:
  - Line 45: `.closest('.chat-message')` → `.closest('.msg')`
  - Line 50: `.classList.contains('chat-message')` → `.classList.contains('msg')`

**Unit Tests to Write/Update:**
- Update `tests/unit/chat-render.test.js` — change expected class names from `.chat-message` → `.msg`, `.message-label` → `.msg-author`, etc.
- Update `tests/unit/stream.test.js` — change expected class names in `createStreamingBubble`
- Update `tests/unit/chat-input.test.js` — minimal changes

**Integration Tests to Write/Update:**
None.

**Live Smoke Test:**
1. Start the AHK app, trigger a chat
2. Verify messages render with new bubble style:
   - User: "You" label + timestamp, light gray rounded bubble (bottom-left sharp corner)
   - Assistant: colored author name (indigo) + model · timestamp, full-width plain text
3. Type a message and press Enter → loading dots appear → streamed response renders token-by-token
4. Verify thinking/reasoning block renders with brain icon, collapsible, monospace content
5. Press Stop during streaming → partial content preserved, action buttons appear
6. Verify send button toggles to "Stop" during streaming and back to "Send" after
7. Run `tests\run_js_tests.bat` — all ~166 tests pass with updated expectations

**Smoke Test Classification:** Human

**Suggested Commit Message:** feat(webui): adapt core chat modules for new message bubble design

---

### [x] Step 4: Adapt Sidebar (folders, trash, thread map)

**Goal:** Rewrite `chat-sidebar.js` to render the new folder-based chat list, collapsible trash, and inline thread map in the right panel. Folders are persisted in SQLite via new AHK subActions.

**DB Schema (added to existing SQLite):**
```sql
CREATE TABLE IF NOT EXISTS chat_folders (
    id TEXT PRIMARY KEY,        -- UUID
    name TEXT NOT NULL,         -- folder display name
    sort_order INTEGER DEFAULT 0,
    created_at TEXT DEFAULT (datetime('now'))
);

ALTER TABLE chat_threads ADD COLUMN folder_id TEXT REFERENCES chat_folders(id) ON DELETE SET NULL;
```

**New AHK `sidebarAction` subActions:**
- `createFolder` → `{ name }` → returns `{ folders: [...] }` (full folder list)
- `renameFolder` → `{ folderId, name }` → returns `{ folders: [...] }`
- `deleteFolder` → `{ folderId }` → returns `{ folders: [...] }` (threads in folder become `folder_id = NULL`)
- `moveToFolder` → `{ threadId, folderId }` → returns updated thread list
- `loadThreadList` response now includes `folders` array: `{ threads: [...], folders: [{ id, name, sort_order }] }`
- Each thread in `loadThreadList` response now includes `folder_id` field (null = unfiled)

**AHK Implementation (new file: [`chat/db/FolderRepo.ahk`](chat/db/FolderRepo.ahk)):**
- `FolderRepo.Create(name)` — INSERT, return folder object
- `FolderRepo.Rename(id, name)` — UPDATE
- `FolderRepo.Delete(id)` — DELETE, SET NULL thread folder_ids
- `FolderRepo.ListAll()` — SELECT all folders ordered by sort_order
- `FolderRepo.MoveThread(threadId, folderId)` — UPDATE chat_threads SET folder_id

**JS Changes:**
- Rewrite `loadThreadList(threads, folders)`:
  - Group threads by `folder_id`. Threads with `folder_id = null` appear under "Unfiled".
  - Render folder sections from `folders` array: each folder gets `.folder` wrapper with `.folder-head` (chevron, name, count badge, rename icon button, delete icon button) and `.folder-chats` container
  - Folder rename: click pencil icon → inline input → send `sidebarAction.renameFolder`
  - Folder delete: confirmation → send `sidebarAction.deleteFolder` (threads auto-unfile via `ON DELETE SET NULL`)
  - Render chat items in correct folder: icon, name, date, hover-reveal action buttons (rename, move-to-folder dropdown, delete)
  - Active chat gets `.active` class
  - "New Folder" button in `.rail-head-actions` → prompt for name → send `sidebarAction.createFolder`
  - Move-to-folder: dropdown lists existing folders + "New Folder..." → send `sidebarAction.moveToFolder`
  - After any folder mutation: AHK sends back updated `threadList` + `folders` → re-render
- Rewrite `loadTrashList()`:
  - Render in `.trash-wrap` > `.trash-items`
  - Trash items: strikethrough name + restore (rotate-ccw icon) + delete-forever (x icon) buttons
  - Wire up collapse toggle on `.trash-head` (chevron rotation, `.trash-wrap.collapsed` class)
  - All trash operations go through existing `sidebarAction` subActions (no change)
- Rewrite `renderNavList()` (now thread map in right panel):
  - Render into `#nav-message-list` (the new `<div>` added inside `.rr-panel-body` BELOW the search input in Step 1c)
  - Each item: `.thread-item.you-row` or `.thread-item.bot-row` with `.who` + `.snippet`
  - Click scrolls to + flashes target message (reuse existing `scrollToMessage` + flash animation)
  - Call `refreshIcons()` after rendering thread items
- Update `toggleSidebar()`: toggle `.rail-left` visibility using mock's collapse mechanism (integrate with `MockUI.setupResize` notch click)
- Update `openSidebar()`: request thread list + trash list from AHK (existing `sidebarAction` pattern)
- Update `closeSidebar()`: hide via collapse
- Update `newChat()`: wire to `#new-chat-btn` in `.rail-head-actions`
- Update `modelEmoji()`: return Lucide icon names (e.g., `'hash'`, `'message-square'`, `'microscope'`) — render via `data-lucide` attribute
- After all dynamic DOM creation: call `refreshIcons()`

**Unit Tests to Write/Update:**
- Update `tests/unit/chat-sidebar.test.js` — expect new folder structure, new class names
- Add tests for `loadThreadList()` with folders
- Add tests for `loadTrashList()` with new trash structure
- Add tests for `renderNavList()` (thread map items)

**Integration Tests to Write/Update:**
None.

**Live Smoke Test:**
1. Open the app with existing chat history
2. Verify left panel shows folders with correct chat counts
3. Click a folder — chevron rotates, chats collapse/expand
4. Click a chat — it becomes active (indigo border + bg), thread loads in center
5. Hover over chat item — action buttons appear (rename, move, delete)
6. Click trash section — expands to show trashed chats
7. Click restore on a trashed chat — it reappears in main list
8. Click delete forever — chat removed after confirmation
9. Right panel thread map shows message list
10. Click a thread map item — scrolls to and flashes that message in center
11. Run `tests\run_js_tests.bat` — all tests pass

**Smoke Test Classification:** Human

**Suggested Commit Message:** feat(webui): adapt sidebar for folder-based chat list and inline thread map

---

### [ ] Step 5: Adapt Branching, Actions, Format, and Token Tooltip

**Goal:** Update message action buttons to use Lucide icons. Wire up the rich tree modal with algorithmic layout. Move token stats to topbar. Update stat popover. Fix `.chat-message` selectors in branching.

**Actions:**

**5a. Update chat-actions.js:**
- `_iconBtn()`: create button with `<i data-lucide="icon-name">` child element instead of emoji text. Call `refreshIcons()` after adding buttons.
- `addMessageActions()` for user: copy (`copy`), edit (`edit-2`), branch nav, token stat (`bar-chart-2`), more dropdown (quote, fork, delete)
- `addMessageActions()` for assistant: copy, retry (`refresh-cw`), edit, branch nav, token stat, more dropdown (quote, fork, delete)
- `_addBranchNav()`: use Lucide `chevron-left`/`chevron-right` icons
- Replace `_createMoreDropdown()`: adapt to use Lucide icons. Keep the existing dropdown pattern (`.more-dropdown`/`.more-menu`) but use Lucide `ellipsis-vertical` icon for the toggle

**5b. Update chat-branching.js — Edit UI:**
- `editMessage()`: rewrite to use mock's `.msg-edit-ui` structure. Instead of inline `createElement` calls with `style.cssText`, add class `.editing` to the `.msg` element. CSS handles showing `.msg-edit-ui` and hiding `.msg-content` + `.msg-actions` + `.thinking-block`. The edit UI structure (`.msg-edit-textarea`, `.msg-edit-actions` with Cancel/Save as Branch/Overwrite) is pre-rendered in each bubble by `createMessageBubble()`.
- **Selector updates**: Replace ALL `.chat-message` selectors with `.msg`:
  - Line 17: `container.querySelectorAll('.chat-message')[index]` → `.msg`
  - Line 52: same
  - Line 84: same
  - Line 368: `container.querySelector('.chat-message[data-msg-id="..."]')` → `.msg`
- Remove inline Bootstrap CSS variables from edit textarea styling (line 29) — replaced by `.msg-edit-textarea` CSS class

**5c. Update chat-branching.js — Tree Modal (Algorithmic Layout):**
This is a complete rewrite of `renderChatTree()`. Algorithm:

1. **Data flow change**: In `handleWebMessage` (main.js), the `renderChatTree` case currently checks for `#tree-container` which doesn't exist in new HTML. **Change**: Always store tree data in `window._treeData = data`. When `toggleTreeModal()` opens the modal, call `renderChatTree(window._treeData)` into `.tree-canvas`. The `handleWebMessage` case becomes: `window._treeData = data; if (document.getElementById('treeOverlay').classList.contains('open')) renderChatTree(data);`

2. **Post-order traversal** — compute subtree height for each node:
   ```
   function computeHeights(node):
       if node.children.length == 0: node._subtreeHeight = 1; return 1
       total = 0
       for child in node.children: total += computeHeights(child)
       node._subtreeHeight = max(1, total)
       return node._subtreeHeight
   ```

3. **Pre-order layout** — assign (x, y) positions:
   - Node dimensions: 260px wide, ~80px tall, gap between nodes: 40px vertical, 80px horizontal
   - x = depth × 340 (260 + 80)
   - y = running counter that advances by each subtree's height × 120
   - Root at (40, 40), children cascade: first child at same y as parent, subsequent children offset by previous sibling's subtree height

4. **SVG connector lines** — for each parent→child edge:
   - Parent right-center: (parent.x + 260, parent.y + 40)
   - Child left-center: (child.x, child.y + 40)
   - Cubic bezier: `M ${px+260} ${py+40} C ${px+300} ${py+40}, ${cx-40} ${cy+40}, ${cx} ${cy+40}`
   - Insert into `<svg>` element inside `.tree-canvas`, update SVG `width`/`height` to cover all nodes
   - Non-active-path edges: `stroke="#E5E7EB"`, active-path edges: `stroke="#4F46E5"`

5. **Active path**: Walk from root following `children` where `node.id` matches next entry in `activePath` (derived from `activeLeafId`). Mark nodes with `.active-path` class.

6. Wire zoom/pan/close (from `MockUI.initTreeZoom()` called in Step 7)

**5d. Update chat-format.js:**
- `updateTokenUsage()`: render into `#token-usage-content` (inside `#token-usage-bar` which is now `.token-bar`). Use mock's `.tu-item` structure: each stat is a `<div class="tu-item">` with icon + label + value. Map: contextUsed → hash icon, tokens → activity icon, cache → database icon, cost → dollar-sign icon
- `showTokenUsageBar()`: show `#token-usage-bar` (no change to ID)
- `copyEntireChat()`: wire to `#copy-entire-chat-btn`. On success: swap copy icon for check icon for 2 seconds using `refreshIcons()`

**5e. Update chat-token-tooltip.js:**
- `createTokenInfoIcon()`: use Lucide `bar-chart-2` icon button. Wire click to toggle mock's `.stat-popover` (add `.pop-open` class to parent `.stat-toggle`)
- `showTokenTooltip()`: render popover content into `.stat-popover` child div. Match mock structure: title row with icon + "Token Usage", then data rows (Output: visible+thinking, Cache, Speed, TTFT, Total time)
- `closeAllTokenTooltips()`: remove `.pop-open` from all `.stat-toggle` elements
- Document click handler: close popovers when clicking outside (existing pattern)
- Call `refreshIcons()` after creating popover content

**Unit Tests to Write/Update:**
- Update `tests/unit/chat-actions.test.js` — expect Lucide icon attributes instead of emoji
- Update `tests/unit/chat-branching.test.js` — expect new edit UI structure, new tree modal structure
- Update `tests/unit/chat-format.test.js` — expect new token bar structure
- Update token tooltip tests — expect stat popover structure

**Integration Tests to Write/Update:**
None.

**Live Smoke Test:**
1. Hover over a message — action buttons appear with Lucide icons (not emoji)
2. Click Copy — icon changes to checkmark for 2 seconds
3. Click Edit — inline edit UI opens with textarea + Cancel/Save as Branch/Overwrite buttons
4. Edit text, click Overwrite — message updates in place
5. Click Retry on assistant message — regenerates response
6. Click branch nav arrows — switches between sibling branches
7. Click stat icon — popover opens with token details (output/thinking/cache/speed/TTFT/time)
8. Click "View Tree" in right panel — tree modal opens with zoomable/pannable canvas
9. Zoom in/out/fit — canvas transforms
10. Click a tree node — modal closes, scrolls to + flashes message
11. Verify token stats in topbar show: Context Used, Tokens ↑↓, Cache, API Cost
12. Click Copy All in topbar — icon changes to checkmark
13. Run `tests\run_js_tests.bat` — all tests pass

**Smoke Test Classification:** Human

**Suggested Commit Message:** feat(webui): adapt branching, actions, format for new UI with Lucide icons and tree modal

---

### [ ] Step 6: Adapt Settings (model popover, config panel)

**Goal:** Replace the old modal-based settings with the mock's inline right panel configuration and model/assistant popover. Re-add `chat-settings-modal.js` to the script load list.

**Actions:**
- **Re-add `chat-settings-modal.js`** to the script load list in `webui/index.html` (was removed in Step 2). It loads after `chat-settings.js` and before `main.js`.
- Rewrite `chat-settings.js`:
  - Remove `onAssistantSelect()` dropdown handler (no `<select>` element exists)
  - Wire `#modelCardTrigger` click → position and open `#modelPopover` (position to the left of the card using `getBoundingClientRect()`)
  - Wire `#popoverOverlay` click → close popover
  - Wire popover tabs (`.popover-tab[data-target="tab-assistants"]` / `data-target="tab-models"`) — switch active pane
  - Populate assistants tab: for each assistant in `window.assistantList`, create `.selector-item` with avatar (`.si-avatar`), name (`.si-name`), description (`.si-desc`), radio (`.si-radio`)
  - Populate models tab: group `window.modelList` by provider, create `.si-group-label` + `.selector-item` per model with `.si-icon` + name + description + radio
  - Wire `.selector-item` click → add `.active` class, remove from siblings, send `switchAssistant` or `updateModelSettings` to AHK, close popover
  - Call `refreshIcons()` after populating popover content
  - On popover close: update model card display to reflect current selection
- Rewrite `chat-settings-modal.js`:
  - `openModelSettings()`: no longer opens a modal → settings are always visible in right panel. Guard clause from Step 2 already handles this.
  - `populateCurrentSettings(settings)`: update `#modelCardTrigger` content (`.name`, `.id`, `.desc`), `#sysMsgMini` textarea value, `#tempSlider` value + `#tempVal` display, `select.dropdown` thinking level, `.advanced-wrap` toggle states. **Also store all values**: `window._currentSettings = { model: settings.model || '', systemMessage: settings.systemMessage || '', reasoning: settings.reasoning || '', temperature: settings.temperature || '' }`.
  - **CRITICAL — Send ALL fields on every change**: The AHK handler at [`chat/ChatSettings.ahk:136`](chat/ChatSettings.ahk:136) reads all four fields unconditionally. If `model` is empty, it resets to `chatDefaultModel`. So every `updateModelSettings` message MUST include all four fields:
    ```javascript
    function _sendAllSettings() {
      var s = window._currentSettings || {};
      window.chrome.webview.postMessage(JSON.stringify({
        action: 'updateModelSettings',
        model: s.model || '',
        systemMessage: s.systemMessage || '',
        reasoning: s.reasoning || '',
        temperature: s.temperature || ''
      }));
    }
    ```
    Call `_sendAllSettings()` (debounced 300ms) after ANY individual field change.
  - **System prompt modal**: wire `#expandSysMsg` click → open `#sysMsgOverlay`, copy `#sysMsgMini` value to `#sysMsgFull`, update char count. `#sysMsgSave` → copy `#sysMsgFull` back to `#sysMsgMini`, update `window._currentSettings.systemMessage`, call `_sendAllSettings()`, close overlay. `#sysMsgClose`/`#sysMsgCancel` → close overlay without saving.
  - Wire `#tempSlider` input → update `#tempVal` display. On `change`: update `window._currentSettings.temperature`, call `_sendAllSettings()`.
  - Wire thinking dropdown `change` → update `window._currentSettings.reasoning`, call `_sendAllSettings()`.
  - Wire `#advancedToggle` click → toggle `.open` on `#advancedWrap`
  - Wire `.switch` clicks → toggle `.on`, update `window._currentSettings`, call `_sendAllSettings()`
  - On model/assistant switch (from `chat-settings.js` popover): update `window._currentSettings.model`, call `_sendAllSettings()`
- Update `main.js`:
  - Remove old `assistant-selector` change handler
  - In `handleWebMessage()`: `assistantList` target → store in `window.assistantList` and call `populateAssistantDropdown` (guarded). `dropdownLabel` → store in `window._dropdownLabel` and update `#modelCardTrigger` if it exists. `currentSettings` → call `populateCurrentSettings` (guarded).
  - Add `renderChatTree` case update: `window._treeData = data; if (document.getElementById('treeOverlay') && document.getElementById('treeOverlay').classList.contains('open')) renderChatTree(data);`
- Call `refreshIcons()` after populating popover and updating model card

**Unit Tests to Write/Update:**
- Update `tests/unit/chat-settings.test.js` — test popover population, model card update, system prompt sync

**Integration Tests to Write/Update:**
None.

**Live Smoke Test:**
1. Right panel shows current model card (name, ID, description) + "Change →" button
2. Click model card → popover opens to the left of the card
3. Popover shows Assistants tab active by default — Violet/Nova/Atlas listed with avatars
4. Click an assistant → popover closes, model card updates, AHK receives switchAssistant
5. Reopen popover, switch to Models tab → models grouped by provider
6. Click a model → popover closes, model card updates, AHK receives updateModelSettings
7. System prompt mini textarea shows current prompt
8. Click "Expand" → full modal opens with monospace textarea, edit, Save → mini textarea updates
9. Drag temperature slider → value display updates in real-time
10. Change thinking level dropdown → AHK receives update
11. Click "Advanced" → section expands with toggle switches
12. Toggle switches → AHK receives update
13. Run `tests\run_js_tests.bat` — all tests pass

**Smoke Test Classification:** Human

**Suggested Commit Message:** feat(webui): replace settings modal with inline config panel and model popover

---

### [x] Step 7: Final Integration — main.js, Resizers, Font Controls, Edge Cases

**Goal:** Update `main.js` event bindings. Wire panel resizers, font size controls. Handle all edge cases. Run full test suite. Dark mode fully removed — light mode only.

**Actions:**

**7a. Wire main.js + MockUI:**
- Rewrite `DOMContentLoaded` handler:
  - Call `MockUI.initFontControls()` — wire `#btn-font-dec`/`#btn-font-inc`
  - Call `MockUI.setupResize('seamLeft', 'notchLeft', railLeft, 'left', 64, 600, 340)`
  - Call `MockUI.setupResize('seamRight', 'notchRight', railRight, 'right', 260, 800, 400)`
  - Call `MockUI.setupVerticalResize('seamVertical', rrSession)`
  - Call `MockUI.initTreeZoom()` — wire zoom controls
  - Call `MockUI.initComposerResize()` — wire textarea auto-resize
  - Wire `#sidebar-toggle` → toggle left panel collapse
  - Wire `#treeBtn` → `toggleTreeModal()`. **Update `main.js` line 213**: change `document.getElementById('tree-view-btn')` to `document.getElementById('treeBtn')`.
  - Wire `#new-chat-btn` → `newChat()`
  - Wire `#usage-dashboard-btn` → `openUsageDashboard`
  - Wire `#copy-entire-chat-btn` → `copyEntireChat()`
  - Wire `#chat-send-btn` → `onChatSend`. **Update `setChatButtonsEnabled()`**: instead of `sendBtn.textContent = 'Send'/'Stop'`, toggle the Lucide icon: swap `data-lucide="send"` for `data-lucide="square"` (stop icon) and call `refreshIcons()`. Or use color change: `.send-btn { color: var(--accent-primary) }` vs `.send-btn.stopping { color: var(--danger) }`.
  - Wire `#chat-input` → keydown + auto-resize
  - Scroll tracking: attach to `#chat-messages`
  - SessionStorage restore: same logic, updated DOM IDs
  - Wire tools dropdown toggle: `.tools-toggle` click → toggle `.menu-open`
  - Wire document click → close tools menu + stat popovers
  - **Remove dead code**: `toggleNavBar()` function and `#nav-toggle` wiring (nav bar doesn't exist in new layout)
- Update `handleWebMessage()`:
  - Add `setTheme` target → `document.documentElement.setAttribute('data-theme', isDark ? 'dark' : 'light')`
  - Add `renderChatTree` target update: `window._treeData = data; var overlay = document.getElementById('treeOverlay'); if (overlay && overlay.classList.contains('open')) renderChatTree(data);`

**7b. Dark Mode:**
- Add `[data-theme="dark"]` CSS overrides to `webui/css/theme.css`:
  ```css
  [data-theme="dark"] {
    --bg-main: #111827; --bg-panel: #1F2937; --bg-hover: #374151; --bg-active: #1E1B4B;
    --text-primary: #F9FAFB; --text-secondary: #D1D5DB; --text-tertiary: #9CA3AF;
    --border-light: #1F2937; --border-main: #374151; --border-focus: #4338CA;
    --user-msg-bg: #374151; --user-msg-text: #F9FAFB;
    --shadow-sm: 0 1px 2px 0 rgba(0,0,0,0.3); --shadow-md: 0 4px 6px -1px rgba(0,0,0,0.4);
    --shadow-lg: 0 10px 15px -3px rgba(0,0,0,0.4); --shadow-modal: 0 25px 50px -12px rgba(0,0,0,0.5);
  }
  ```
- `setTheme(isDark)` in `main.js`: set `data-theme` attribute. AHK already sends `setTheme` message — no backend change.

**7c. Edge Cases:**
- Attachment bar: `#attachment-bar` (added above `.composer-inner` in Step 1c) works with existing `chat-attachments-setup.js` IDs
- Error banners: `showError()` already updated to new tokens in Step 2
- Loading dots: CSS (`.loading-indicator`, `.dot`, `@keyframes bounce`) added to `messages.css` in Step 3
- Undo notification: already updated in Step 2, fixed position bottom-right
- FIM mode: `#fim-notice` (added in Step 1c at top of `.thread`). Also add `id="content"` to a hidden `<div>` inside `.thread` for `renderMarkdown()` fallback. `initChatMode()` shows `#chat-messages`, hides `#content`. `renderMarkdown()` hides `#chat-messages`, shows `#content`.
- Empty states: "No chats yet" in `#thread-list`, "No messages yet" in `#chat-messages`
- Composer tools toggles: wire `.switch` clicks in tools dropdown
- **WebView2 panel resize fix**: In `MockUI.setupResize()` and `MockUI.setupVerticalResize()`, add `document.documentElement.addEventListener('mouseleave', cancelDrag)` to cancel drag state if cursor leaves WebView bounds. This prevents stuck `col-resize` cursor and frozen `userSelect: none` when mouse exits the WebView2 control during a fast drag.
- **Error banner positioning**: `showError()` appends to `#chat-messages` (`.thread`). Error banners render at the end of the thread, above the composer. The banner CSS uses new design tokens (`var(--danger)`, `var(--bg-panel)`) from Step 2.

**7d. Final Cleanup:**
- Grep all `webui/js/**/*.js` for `var(--bs-` — must return zero matches
- Verify `data-lucide` icons have `refreshIcons()` calls after creation
- Verify load order: mock-ui.js → vendor → chat-core → ... → main.js
- Remove `color-modes.js` reference if present

**Unit Tests to Write/Update:**
- Update `tests/unit/main.test.js` — verify all handler routes, add `setTheme` test
- Run `tests\run_all_tests.bat` — all 211 AHK + ~166 JS = ~377 tests pass

**Integration Tests to Write/Update:**
- Run `tests/integration/edit-send-flow.test.js` — verify cross-module flow

**Live Smoke Test (Model):**
1. Run `tests\run_all_tests.bat` — all tests pass
2. Run `tests\run_js_tests.bat` — all JS tests pass
3. Grep all `webui/js/**/*.js` for `var(--bs-` — zero matches

**Live Smoke Test (Human):**
1. Full feature walkthrough (a-w below):
   a. Open app → skeleton renders, all panels visible
   b. Trigger new chat → thread appears, messages render in new style
   c. Send message → streaming with thinking block
   d. Edit message → inline UI, save overwrite
   e. Branch nav → switch siblings
   f. Delete → confirm, removed
   g. Undo (Ctrl+Z) → restored
   h. Quote → text in composer
   i. Copy → checkmark feedback
   j. Fork → new thread
   k. Attach image/PDF → preview, send works
   l. Model popover → switch model/assistant
   m. Temperature slider → real-time update
   n. System prompt → expand modal, edit, save
   o. Tree modal → zoom/pan, node click → flash
   p. Font size +/- → chat text resizes
   q. Panel resize → drag seams, notch collapse
   r. Trash → trash/restore/delete forever
   s. Thread map → click to navigate
   t. Copy entire chat → topbar button
   u. Folder CRUD → create/rename/delete folders, move chats (localStorage)
   v. Tools dropdown → toggle switches
   w. Dark mode toggle → theme switches
2. No visual regressions vs mock (light mode)

**Smoke Test Classification:** Model (test suite) + Human (full walkthrough)

**Suggested Commit Message:** feat(webui): finalize chat UI overhaul with dark mode and all edge cases

---

## §5 Final Directory Tree

```
webui/
├── index.html                          (new — ~200 lines, skeleton structure)
├── api-logs.html                       (unchanged)
├── usage-dashboard.html                (unchanged)
├── fonts/
│   ├── fonts.css                       (new — imports inter.css + jetbrains-mono.css)
│   ├── inter.css                       (new — @font-face declarations)
│   ├── inter-latin-400.woff2           (new — downloaded)
│   ├── inter-latin-500.woff2           (new)
│   ├── inter-latin-600.woff2           (new)
│   ├── inter-latin-700.woff2           (new)
│   ├── jetbrains-mono.css              (new — @font-face declarations)
│   ├── jetbrains-mono-latin-400.woff2  (new)
│   ├── jetbrains-mono-latin-500.woff2  (new)
│   └── jetbrains-mono-latin-600.woff2  (new)
├── css/
│   ├── theme.css                       (new — variables, reset, font-face)
│   ├── layout.css                      (new — app, panels, seams, resizers)
│   ├── left-panel.css                  (new — folders, chat items, trash)
│   ├── center.css                      (new — topbar, thread, composer)
│   ├── messages.css                    (new — bubbles, thinking, edit UI)
│   ├── actions.css                     (new — action buttons, branch nav, stat popover)
│   ├── right-panel.css                 (new — config fields, model card, thread map)
│   ├── modals.css                      (new — tree modal, sysmsg modal)
│   ├── popover.css                     (new — model/assistant popover)
│   ├── components.css                  (new — buttons, inputs, switches, scrollbars)
│   └── vendor/                         (unchanged — katex, texmath, highlight)
│       ├── katex.min.css
│       ├── texmath.min.css
│       └── highlight/
│           └── atom-one-dark.min.css
├── js/
│   ├── main.js                         (modified — updated DOM bindings, setTheme, MockUI init)
│   ├── stream.js                       (modified — new bubble classes, refreshIcons calls)
│   ├── mock-ui.js                      (new — panel resize, font controls, tree zoom, composer resize ONLY)
│   ├── usage-dashboard.js              (unchanged)
│   ├── vendor/
│   │   ├── lucide.min.js               (new — downloaded from unpkg)
│   │   ├── markdown-it.min.js          (unchanged)
│   │   ├── katex.min.js                (unchanged)
│   │   ├── mhchem.min.js               (unchanged)
│   │   ├── texmath.min.js              (unchanged)
│   │   ├── highlight.min.js            (unchanged)
│   │   ├── pdf.min.js                  (unchanged)
│   │   ├── pdf.worker.min.js           (unchanged)
│   │   └── officeparser.iife.js        (unchanged)
│   └── chat/
│       ├── chat-core.js                (modified — layout references)
│       ├── chat-render.js              (modified — bubble structure)
│       ├── chat-actions.js             (modified — Lucide icons)
│       ├── chat-input.js               (modified — minimal)
│       ├── chat-format.js              (modified — token bar location)
│       ├── chat-branching.js           (modified — edit UI, tree modal)
│       ├── chat-sidebar.js             (modified — folders, trash, thread map)
│       ├── chat-quote.js               (modified — class name in closest() check)
│       ├── chat-undo.js                (unchanged)
│       ├── chat-token-tooltip.js       (modified — stat popover)
│       ├── attachments/
│       │   ├── chat-attachments.js     (unchanged)
│       │   ├── chat-attachments-extract.js (unchanged)
│       │   └── chat-attachments-setup.js   (unchanged)
│       └── settings/
│           ├── chat-settings.js        (modified — popover)
│           └── chat-settings-modal.js  (modified — inline panel)
├── Bootstrap/                          (🗑 REMOVED)
│   └── [all deleted]
└── [old css/chat/*.css]                (🗑 REMOVED — 6 old files)
```

```
tests/
├── unit/
│   ├── chat-render.test.js             (new — ~18 tests)
│   ├── chat-actions.test.js            (new — ~8 tests)
│   ├── chat-sidebar.test.js            (new — ~10 tests)
│   ├── chat-branching.test.js          (new — ~6 tests)
│   ├── stream.test.js                  (new — ~12 tests)
│   ├── chat-settings.test.js           (new — ~5 tests)
│   ├── main.test.js                    (new — ~10 tests)
│   ├── chat-format.test.js             (modified — +4 tests)
│   ├── chat-input.test.js              (modified — +4 tests)
│   └── [all existing tests unchanged]
└── [unchanged]
```
