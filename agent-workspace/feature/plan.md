# Implementation Plan: Settings Tab — Full UserConfig UI

## §1 Overall Project

LLM AutoHotkey Assistant is a Windows desktop app (AutoHotkey v2 + WebView2) that provides an LLM-powered assistant accessible via a backtick hotkey menu. It features chat threads (SQLite-backed), command shortcuts, inline text manipulation (FIM), and provider/model management. The UI is a WebView2 app served from [`webui/index.html`](webui/index.html) with a three-panel layout: chat sidebar (left), center content (chat/dashboard), and configuration panel (right).

Currently, all user configuration lives in [`UserConfig.ahk`](UserConfig.ahk) — a 631-line AHK file that users edit manually. The Settings icon in the icon rail is unresponsive (no click handler). The right Configuration panel handles per-thread model/assistant settings only.

## §2 This Feature

Replace the file-based UserConfig.ahk configuration with a fully GUI-driven Settings panel accessible from the icon rail. ALL 13 UserConfig sections become editable through a tabbed settings interface. Settings are persisted to `settings.json` in `A_AppData\LLM-AutoHotkey-Assistant\`. UserConfig.ahk remains as the fallback defaults — if `settings.json` is missing or malformed, AHK uses hardcoded defaults from UserConfig.ahk.

**In scope:**
- 10 settings tabs covering all 13 UserConfig sections
- JSON persistence layer in AHK
- Full CRUD for providers, models, commands, assistants, and all simple settings
- Models pricing refresh workflow (PowerShell → popup → user imports)
- Unsaved changes detection + confirmation on tab switch
- System message edit popup with file selector (app defaults + user folder)
- Command Guide reference modal
- Live settings propagation from ChatWindow → Main process via IPC
- Reset to Defaults functionality

**Out of scope:**
- Dark theme CSS implementation (toggle is wired, styles not written)
- Multi-user support
- Protocol abstraction for non-OpenAI-compatible APIs
- Migration code (UserConfig.ahk is fallback, no migration needed)

**UserConfig section → Tab mapping:**
| UserConfig § | Tab |
|---|---|
| §1 Providers | Providers |
| §2 Models | Models |
| §3 Provider Map | Providers (Model Name Prefixes) |
| §4 Assistants | Assistants |
| §5 Commands | Commands |
| §6 Thread Titles | General |
| §7 Theme | UI & Theme |
| §8 UI | UI & Theme |
| §9 Icons | Icons |
| §10 Hotkeys | Hotkeys |
| §11 API Logs | General |
| §12 Trash Retention | General |
| §13 Menu Items | Menu Items |

## §3 End State Upon Feature Completion

### User Perspective

1. User clicks the Settings icon (gear) in the icon rail → chat sidebar is replaced by a settings navigation sidebar with 10 sections, center shows the active section's form, right Configuration panel remains visible.
2. User edits any setting → changes are tracked as "modified." Save button in the nav footer activates.
3. User clicks Save → all changes written to `settings.json` via AHK IPC, ChatWindow signals Main process to reload settings live. Settings requiring restart show a warning with [Restart Now] button.
4. User tries to switch to Chat/Dashboard with unsaved changes → confirmation popup: "You have unsaved changes. Discard them?" [Stay] [Discard].
5. User clicks "Refresh from PowerShell" on Models tab → PowerShell script runs, results appear in a modal popup with two panels: new models (left) and current models (right). User clicks "Add" to import individual models.
6. User clicks "Edit" on an assistant's system message → popup with radio buttons: "Load from file" (shows files from app defaults + user's AppData folder) or "Write inline" (textarea).
7. User hovers over `?` icons in Commands detail form → tooltip explains the field. User clicks "Command Guide" → full reference modal.
8. User clicks "Reset to Defaults" → all fields revert to UserConfig.ahk hardcoded values. Save button activates.
9. First launch (no settings.json): all settings populated from UserConfig.ahk defaults. User sees their current configuration, not empty forms.

### Technical Perspective

**Architecture (two AHK processes):**
```
Main.ahk                              ChatWindow.ahk
  ├─ #Include Config.ahk                ├─ #Include Config.ahk
  ├─ SettingsHandler.Load()             ├─ WebView2 UI
  ├─ populate globals                   ├─ SettingsHandler.Load()
  ├─ register hotkeys                   ├─ IPC: requestAllSettings
  ├─ listen for CustomMessages          ├─ IPC: saveSettings → write JSON
  │   └─ "settingsUpdated" → reload     │   └─ send "settingsUpdated" to Main
  └─ ...                                └─ ...
```

**Data Flow:**
1. On startup (both processes): `Config.ahk` includes `UserConfig.ahk` → globals set to hardcoded defaults → `SettingsHandler.Load()` reads `settings.json` → overwrites globals with saved values → falls back to defaults for missing keys
2. WebView ready → AHK sends full settings JSON to UI via IPC
3. User edits → UI tracks dirty state → on Save, sends changed settings to AHK → ChatWindow validates → writes `settings.json` → sends `settingsUpdated` CustomMessage to Main → Main re-reads and repopulates → sends confirmation to UI
4. If no settings.json exists: UserConfig.ahk defaults are the active config. UI shows those values. First Save creates settings.json.

**Critical: RuntimeResolver startup check is DEFERRED.** Currently `RuntimeResolver.ahk` line 11-29 checks for API keys at compile time and exits if none found. After refactor: the check is wrapped in a function `RuntimeResolver.CheckApiKeys()` called AFTER `SettingsHandler.Load()` in both Main.ahk and ChatWindow.ahk. This allows direct-entry API keys from settings.json to satisfy the check.

**Assistants:** Dropped from SQLite DB. Stored in `settings.json` with stable IDs (auto-generated UUIDs on first save). Thread settings reference assistant by ID from settings.json. When resolving an assistant ID that no longer exists, fall back to the default assistant (first one with `isDefault: true`). Existing threads with old SQLite UUIDs automatically fall back — graceful degradation, no migration needed.

**Persistence (`settings.json`):**
```json
{
  "version": 1,
  "providers": {
    "deepseek": { "displayName": "DeepSeek", "endpoint": "...", "fimEndpoint": "...", "authMode": "env", "authEnvVar": "DEEPSEEK_API_KEY", "apiKey": "", "icon": "icons/deepseek.ico", "collapseThinking": false, "prefixes": ["deepseek"] },
    "openai": { ... }
  },
  "models": {
    "deepseek/deepseek-v4-pro": { "provider": "deepseek", "input": 0.435, "cachedInput": 0.003625, "output": 0.87, "context": 1000000, "reasoning": true, "vision": false }
  },
  "assistants": [
    { "id": "uuid-1", "name": "Natural Conversationalist", "baseModel": "deepseek/deepseek-v4-pro", "systemMessage": "...", "systemMessageFile": "system-messages/natural-conversationalist.txt", "description": "...", "reasoning": "none", "temperature": "", "isDefault": true }
  ],
  "commands": [ { "commandName": "...", "menuText": "...", ... } ],
  "submenuOrder": ["&Text manipulation", "&Digest", "&DeepSeek", "&OpenAI", "&Google"],
  "threadTitles": { "enabled": true, "model": "deepseek/deepseek-v4-flash", "prompt": "...", "maxTokens": 50 },
  "ui": { "chatDefaultModel": "deepseek/deepseek-v4-flash", "responseFont": "Arial, ...", "inputWindow": {...}, "suspendBanner": {...} },
  "theme": { "darkMode": false },
  "icons": { "iconOn": "icons\\IconOn.ico", "iconOff": "icons\\IconOff.ico" },
  "hotkeys": { "main": "``", "saveReload": "~^s", "closeWindows": "~^w", "suspend": "CapsLock & ``" },
  "apiLogs": { "maxEntries": 20 },
  "trash": { "retentionDays": 30 },
  "menuItems": { "quickAccess": [...], "tray": [...] }
}
```

### Edge Cases & Error States

- **settings.json missing on first launch**: AHK uses UserConfig.ahk defaults. UI shows those values. First Save creates settings.json.
- **settings.json malformed**: AHK logs error via `debugLog()`, falls back to UserConfig.ahk defaults. UI shows defaults.
- **User deletes all providers**: Must keep at least one provider. UI prevents deleting last provider.
- **User deletes a provider with models referencing it**: Models become orphaned. Provider dropdown shows "(unknown)" for those models.
- **Hotkey conflict**: UI validates AHK hotkey syntax. If user sets broken `saveReloadHotkey`, they must restart via tray menu → UserConfig.ahk is re-read as fallback.
- **PowerShell script fails**: Modal shows error message, user can try again or add models manually.
- **User switches tabs with unsaved changes**: Confirmation popup appears.
- **Concurrent saves**: Not applicable (single-user desktop app, one WebView).
- **Thread references deleted assistant**: Falls back to default assistant gracefully.
- **Direct API key + env var both present**: Env var takes priority at runtime. UI shows both fields.

## §4 Implementation Steps

### [ ] Step 0: Add Settings Icon ID + Create Directory Structure

**Goal:** Prepare the codebase with the minimal prerequisites for all subsequent steps.

**Actions:**
- Add `id="settings-icon"` to the Settings icon button in [`webui/index.html`](webui/index.html:35)
- Create `webui/js/settings/` directory
- Create `webui/js/settings/sections/` directory
- Create `app/SettingsHandler.ahk` as empty skeleton with class declaration

**Unit Tests to Write/Update:**
- None

**Integration Tests to Write/Update:**
- None

**Live Smoke Test:**
- Verify Settings icon button exists with id `settings-icon` in the DOM
- Verify directories exist on filesystem

**Smoke Test Classification:** Model

**Suggested Commit Message:** chore(settings): add settings icon ID and create directory structure

---

### [ ] Step 1: AHK Settings Persistence Layer

**Goal:** Create the JSON read/write infrastructure for settings with IPC handlers.

**Actions:**
- Implement `app/SettingsHandler.ahk`:
  - `SettingsHandler.Load()`: reads `A_AppData\LLM-AutoHotkey-Assistant\settings.json`, parses with `jsongo`, returns AHK Map. On failure, returns empty Map.
  - `SettingsHandler.Save(settingsMap)`: validates (at least one provider exists, model IDs have valid providers, hotkey syntax), writes JSON with pretty-print to `settings.json`
  - `SettingsHandler.GetDefaults()`: returns a Map of all settings populated from current UserConfig.ahk globals. This is the fallback assembly function — enumrates every global variable and builds the complete settings structure.
  - `SettingsHandler.Merge(existing, defaults)`: merges loaded settings with defaults for any missing keys
  - On first Save, create `A_AppData\LLM-AutoHotkey-Assistant\system-messages\` directory
- Add IPC handlers in [`chat/ChatIPC.ahk`](chat/ChatIPC.ahk) (in the IPC dispatch function that handles WebView messages):
  - `requestAllSettings`: calls `SettingsHandler.Load()`, merges with `GetDefaults()` for missing keys, returns full settings object to WebView as JSON via `postWebMessage()`
  - `saveSettings`: receives partial settings JSON from WebView, merges with existing, calls `SettingsHandler.Save()`, sends `settingsUpdated` CustomMessage to Main process, returns success/error
  - `refreshModelPricing`: runs `Refresh-ModelPricing.ps1`, reads `models_pricing.txt`, parses model entries using existing `ModelParser`, returns as structured array to WebView
- Wire `#Include ..\app\SettingsHandler.ahk` in [`lib/Config.ahk`](lib/Config.ahk) (note: `..\app\` path since Config.ahk is in `lib\`)
- Add `settingsUpdated` case to [`ipc/CustomMessages.ahk`](ipc/CustomMessages.ahk) message handling — when Main receives this, it calls `SettingsHandler.Load()` + `Merge()` + repopulates all globals

**Unit Tests to Write/Update:**
- `tests/unit/SettingsHandler.test.ahk`: test Load with valid JSON, missing file, malformed JSON; test Save with valid data; test GetDefaults returns all sections; test Merge fills missing keys

**Integration Tests to Write/Update:**
- None — pure file I/O

**Live Smoke Test:**
1. Delete `settings.json` if it exists
2. Run the app → verify it starts with UserConfig defaults (no crash, chat works)
3. In test harness, call `SettingsHandler.GetDefaults()` → verify all 13 sections populated
4. Call `Save()` with test data → verify `settings.json` written at `%AppData%\LLM-AutoHotkey-Assistant\settings.json`
5. Call `Load()` → verify data matches what was saved
6. Delete `settings.json`, call `Load()` → verify returns empty Map, `Merge()` fills with defaults

**Smoke Test Classification:** Model

**Suggested Commit Message:** feat(settings): add JSON persistence layer with IPC handlers and live propagation

---

### [ ] Step 2: Settings Panel Shell — Icon Rail Wiring + Layout

**Goal:** Wire the Settings icon click, create the settings panel layout (nav sidebar + content area), and implement tab switching.

**Actions:**
- Add `showSettings()` and `hideSettings()` functions to [`webui/js/main.js`](webui/js/main.js):
  - `showSettings()`: hides `#chat-layout` and `#dashboard-panel`, shows settings-nav and settings-center, sets settings icon active, requests settings from AHK via `chrome.webview.postMessage({action:'requestAllSettings'})`
  - `hideSettings()`: checks dirty state → if dirty, shows confirmation popup → on Discard, hides settings, restores previous panel
- Wire settings icon click in main.js: `document.getElementById('settings-icon').addEventListener(...)`
- Add settings panel HTML to [`webui/index.html`](webui/index.html):
  - `.settings-nav` sidebar (replaces railLeft when visible): has nav-scroll (10 nav items) + nav-footer (Save + Reset buttons)
  - `.settings-center` (replaces center area): has `.settings-content` with 10 `.section-card` containers (initially empty/hidden)
  - All section cards have `id="sec-{name}"` attributes for tab switching
  - Settings nav replaces `.rail-left` — hide railLeft when settings is shown
- Create `webui/css/settings.css`: nav sidebar (280px, flex column with nav-scroll + nav-footer), content area (flush edge-to-edge cards separated by borders), section card headers, form fields matching mock
- Create `webui/js/settings/settings-panel.js`:
  - Tab switching: `showSection(sectionName)` hides all sections, shows target, updates nav active state, scrolls content to top
  - Dirty tracking: `_dirty = false` initially, any field change sets to true, Save button activates (removes `disabled`)
  - Save: calls `_collectAllSettings()` which iterates all section `save()` methods, sends `saveSettings` IPC
  - Reset: calls `_resetAllToDefaults()` which iterates all section `load()` methods with defaults data
  - On receiving `currentSettings` IPC response: stores as `_defaultSettings`, populates all sections via their `load()` methods
  - Active icon-rail management: `showSettings()` sets `nav-icon.active` on settings icon
- Include files in [`webui/index.html`](webui/index.html): `<link rel="stylesheet" href="css/settings.css">` and `<script src="js/settings/settings-panel.js"></script>`

**Unit Tests to Write/Update:**
- `tests/unit/settings-panel.test.js`: test tab switching (show/hide sections), dirty state tracking, save button activation, `_collectAllSettings()` aggregation

**Integration Tests to Write/Update:**
- None — pure frontend

**Live Smoke Test:**
1. Open app, click Settings icon (gear) → verify settings panel appears (nav sidebar + empty content)
2. Click each nav item → verify only one section visible at a time, active highlight follows
3. Click Chat icon → verify chat returns (no dirty state, no popup)
4. Verify right Configuration panel remains visible during settings
5. Click Dashboard icon → verify dashboard appears
6. Click Settings icon again → verify settings panel returns

**Smoke Test Classification:** Model

**Suggested Commit Message:** feat(settings): add settings panel shell with tab navigation and dirty tracking

---

### [ ] Step 3a: General + Icons Sections

**Goal:** Implement the two simplest sections.

**Actions:**
- Create `webui/js/settings/sections/general.js`:
  - Thread Title Generation: toggle switch (with grayed-out dependent fields when OFF), model dropdown, system prompt textarea, max tokens
  - Data Management: API Log Max Entries (number, 0=disable), Trash Retention Days (number, 0=never)
  - `load(data)`: populates form from `data.threadTitles`, `data.apiLogs`, `data.trash`
  - `save()`: returns `{ threadTitles: {...}, apiLogs: {...}, trash: {...} }`
- Create `webui/js/settings/sections/icons.js`:
  - iconOn/iconOff: text inputs with placeholder showing current values
  - `load(data)`: populates from `data.icons`
  - `save()`: returns `{ icons: { iconOn, iconOff } }`
- Add section HTML to the General and Icons `.section-card` containers in index.html

**Unit Tests to Write/Update:**
- `tests/unit/settings-general.test.js`: test title toggle enables/disables fields, data serialization
- `tests/unit/settings-icons.test.js`: test icon field serialization

**Integration Tests to Write/Update:**
- None

**Live Smoke Test:**
1. Open General tab → toggle Thread Titles OFF → verify dependent fields gray out (opacity 0.35, pointer-events none)
2. Toggle ON → verify fields are interactive
3. Open Icons tab → verify iconOn/iconOff fields show current values

**Smoke Test Classification:** Model

**Suggested Commit Message:** feat(settings): implement General and Icons sections

---

### [ ] Step 3b: UI & Theme Section

**Goal:** Implement the UI appearance section with color pickers and font dropdowns.

**Actions:**
- Create `webui/js/settings/sections/ui-theme.js`:
  - Dark Mode toggle (with note: not yet implemented)
  - Chat Defaults: default model dropdown, response font dropdown (Arial, Inter, Segoe UI, etc. — single names, not CSS stacks)
  - Command Input Window: font face dropdown, font size dropdown (s10–s18), font color dropdown (cWhite, cBlack, etc.), window background (native `<input type="color">` + hex display), width/height numbers
  - Suspend Banner: same pattern with dedicated subsection label
  - Color conversion: `#RRGGBB` ↔ `0xRRGGBB` on save/load (strip `0x` prefix for color picker, prepend on save)
  - Font face values: UI shows single names, backend appends fallback stacks on save (e.g., "Arial" → "Arial, Segoe UI, Helvetica, sans-serif")
  - `load(data)`: populates from `data.theme`, `data.ui`
  - `save()`: returns `{ theme: {...}, ui: {...} }`
- Add section HTML for UI & Theme `.section-card` container

**Unit Tests to Write/Update:**
- `tests/unit/settings-ui-theme.test.js`: test color hex conversion (# ↔ 0x), font face mapping, data serialization

**Integration Tests to Write/Update:**
- None

**Live Smoke Test:**
1. Open UI tab → click color picker on Window Background → pick a color → verify hex field updates
2. Change font face dropdown → verify value changes
3. Verify Dark Mode toggle is present (switchable, note about future release)

**Smoke Test Classification:** Model

**Suggested Commit Message:** feat(settings): implement UI and Theme section with color pickers

---

### [ ] Step 3c: Hotkeys + Menu Items Sections

**Goal:** Implement key capture and table CRUD sections.

**Actions:**
- Create `webui/js/settings/sections/hotkeys.js`:
  - 4 key capture fields: Main Hotkey, Save & Reload, Close Windows, Suspend Toggle
  - Key capture flow: click field → "listening" state → press key/combo → display captured combo → validate AHK syntax
  - Validation: must be valid AHK hotkey syntax. Show red border on invalid.
  - Restart warning: yellow banner "⚠️ Hotkey changes require a script restart. [Restart Now]"
  - `saveReloadHotkey` special handling: must not be empty
  - `load(data)`: populates from `data.hotkeys`
  - `save()`: returns `{ hotkeys: {...} }`
- Create `webui/js/settings/sections/menu-items.js`:
  - Quick Access table: columns (Menu Text, Command), add/delete rows, inline editing
  - Tray Menu table: columns (Menu Text, Action dropdown with reload/exit options), add/delete rows
  - `load(data)`: populates from `data.menuItems`
  - `save()`: returns `{ menuItems: { quickAccess: [...], tray: [...] } }`
- Add section HTML for Hotkeys and Menu Items containers

**Unit Tests to Write/Update:**
- `tests/unit/settings-hotkeys.test.js`: test hotkey validation, capture flow, empty saveReload guard
- `tests/unit/settings-menu-items.test.js`: test add/remove rows, data serialization

**Integration Tests to Write/Update:**
- None

**Live Smoke Test:**
1. Open Hotkeys tab → click Main Hotkey field → verify "listening" state
2. Verify yellow restart banner is visible
3. Open Menu Items → add a row to Quick Access → fill menuText + command → delete a row
4. Verify data serialized correctly in `save()` output

**Smoke Test Classification:** Model

**Suggested Commit Message:** feat(settings): implement Hotkeys and Menu Items sections

---

### [ ] Step 4: Providers Section

**Goal:** Implement the Providers card editor with auth fields and model prefixes.

**Actions:**
- Create `webui/js/settings/sections/providers.js`:
  - Card grid: one card per provider, each card shows: display name, chat endpoint, FIM endpoint, API key (env var field + direct entry field), collapse thinking toggle, model name prefixes (tag-style with add/remove)
  - Auth: show both env var name field AND direct entry password field always. Env var takes priority at runtime.
  - Model prefixes: inline tag editor per provider card — click "+ add" to add a prefix, click × to remove
  - Prevent deleting last provider (disable Remove button when only one provider exists)
  - "+ Add Provider" button adds a new card with empty fields
  - Provider icon: auto-detected from provider key (first two letters as fallback)
  - Note below Add button: "Requires OpenAI-compatible API endpoint"
  - `load(data)`: populates cards from `data.providers`
  - `save()`: returns `{ providers: {...} }` — each provider object includes its prefixes array
- Add section HTML for Providers `.section-card` container

**Unit Tests to Write/Update:**
- `tests/unit/settings-providers.test.js`: test add/remove provider, last-provider guard, auth field serialization (both env and direct), prefix tag management

**Integration Tests to Write/Update:**
- None

**Live Smoke Test:**
1. Open Providers tab → verify 3 provider cards shown
2. Edit DeepSeek's display name → verify field updates
3. Add a prefix "test-prefix" to DeepSeek → verify tag appears with ×
4. Try to delete last provider → verify Remove button is disabled/hidden
5. Click "+ Add Provider" → verify new card appears with empty fields
6. Fill new provider, click Save → verify serialized with prefixes

**Smoke Test Classification:** Model

**Suggested Commit Message:** feat(settings): implement Providers section with auth and prefix management

---

### [ ] Step 5: Models Section with Refresh Popup

**Goal:** Implement the Models inline-editable table and the refresh-from-PowerShell modal popup.

**Actions:**
- Create `webui/js/settings/sections/models.js`:
  - Inline-editable table: columns (Model ID, Provider dropdown, Input $/1M, Cached $/1M, Output $/1M, Context, Vision checkbox, Reasoning checkbox, Delete button)
  - Model ID format: `provider/model-name` (e.g., `openai/gpt-4o`). Provider column reflects the provider portion of the ID.
  - "+ Add Model" button adds an empty row
  - "Refresh from PowerShell" button triggers `refreshModelPricing` IPC → opens modal popup (see HTML below)
  - Modal: left panel (new models with full pricing), right panel (current models for reference). "Add" button on each new model imports it to the table.
  - Inline editing: click cell to edit, Enter/blur to confirm, Escape to cancel
  - Cached input: shows hint "defaults to 10% of input if blank" — this is a backend-side default applied by CostCalculator, UI just shows the hint
  - `load(data)`: populates table from `data.models`
  - `save()`: returns `{ models: {...} }` with model IDs as keys
- Add Models section HTML and refresh modal HTML (matching mock's `#refreshModal`)

**Unit Tests to Write/Update:**
- `tests/unit/settings-models.test.js`: test table add/edit/delete, modal popup open/close (mocked IPC), model import from modal to table, data serialization

**Integration Tests to Write/Update:**
- None

**Live Smoke Test:**
1. Open Models tab → verify table shows current models
2. Click "+ Add Model" → verify new empty row appears
3. Edit a model's input price inline → verify value updates
4. Toggle Vision checkbox → verify state changes
5. Click "Refresh from PowerShell" → verify modal opens (may show loading/error if PowerShell unavailable in test)
6. Verify modal has two panels with tables

**Smoke Test Classification:** Model

**Suggested Commit Message:** feat(settings): implement Models section with refresh pricing modal

---

### [ ] Step 6: Assistants Section

**Goal:** Implement Assistants editable cards and system message edit popup.

**Actions:**
- Create `webui/js/settings/sections/assistants.js`:
  - Card list with add/remove, all fields per assistant
  - Each card: title (editable inline input), base model dropdown, reasoning dropdown, system message (shows source file name + Edit button), description text input, default toggle
  - Default toggle: radio behavior — only one assistant can be default. Toggling ON sets all others OFF via JS.
  - System Message Edit popup (matching mock's `#sysMsgEditModal`):
    - Radio buttons "Load from file" / "Write inline"
    - File mode: dropdown with `<optgroup>` for "App Defaults" (read-only) and "Your Files" (from AppData system-messages folder)
    - Inline mode: large textarea
  - "+ New Assistant": adds a blank card at top with auto-generated UUID
  - Delete: removes card. If deleted assistant was default, first remaining card becomes default.
  - Note about user system messages folder location
  - Assistant IDs: auto-generated UUIDs on creation, stored in settings.json
  - `load(data)`: populates cards from `data.assistants`
  - `save()`: returns `{ assistants: [...] }`
- Add Assistants section HTML and system message modal HTML

**Unit Tests to Write/Update:**
- `tests/unit/settings-assistants.test.js`: test card add/remove, default toggle mutual exclusion, system message popup file/inline modes, UUID generation

**Integration Tests to Write/Update:**
- None

**Live Smoke Test:**
1. Open Assistants tab → verify cards shown with current assistants
2. Click "Edit" on system message → verify popup with radio buttons
3. Switch to "Write inline" → verify textarea appears; switch to "Load from file" → verify dropdown
4. Toggle default on one → verify other's default turns off
5. Click "+ New Assistant" → verify blank card with generated UUID
6. Click Save → verify assistants serialized with IDs

**Smoke Test Classification:** Model

**Suggested Commit Message:** feat(settings): implement Assistants section with system message editor

---

### [ ] Step 7a: Commands Shell — Master-Detail + Basic Fields

**Goal:** Implement the Commands master-detail layout with all non-advanced fields.

**Actions:**
- Create `webui/js/settings/sections/commands.js`:
  - Left panel: command list with drag handles (⋮⋮) and ↑↓ arrow buttons for reordering, displayed in list order
  - Right panel: detail form with: title (editable inline input), Menu Label, Menu Shortcut dropdown (key 1 marked "reserved — Chat Window" and disabled), Direct Shortcut dropdown, API Model, Paste Mode dropdown, Temperature, User Message Template (textarea with natural newlines — backend converts `\n` → backtick-n on save), toggles (Show Input Box, Stream Response, FIM Mode), Thinking (type + level dropdowns), Tags (badge-style with add/remove), Max Tokens
  - Tooltip hints on every field label (hover `?` icon with `.tt` class)
  - Menu shortcut live preview: shows `&N - Label` format as user edits
  - "+ New" adds empty command to list with auto-generated `commandName`
  - Arrow reordering: JS moves items up/down in list, order preserved on save
  - `load(data)`: populates list and detail from `data.commands`
  - `save()`: returns `{ commands: [...], submenuOrder: [...] }`
- Add Commands section HTML (master-detail layout matching mock)
- Add tooltip CSS (`.tt` and `.tt::after` classes matching mock)

**Unit Tests to Write/Update:**
- `tests/unit/settings-commands.test.js`: test command add/remove, reorder arrows, menu shortcut validation (key 1 reserved), data serialization, template newline conversion

**Integration Tests to Write/Update:**
- None

**Live Smoke Test:**
1. Open Commands tab → verify list on left, detail form on right
2. Click a command → verify detail form populates
3. Click ↑↓ arrows → verify command moves in list
4. Edit menu label → verify live preview updates
5. Hover `?` icons → verify tooltips appear with correct content

**Smoke Test Classification:** Model

**Suggested Commit Message:** feat(settings): implement Commands master-detail with basic fields

---

### [ ] Step 7b: Commands Advanced Section + Command Guide Modal

**Goal:** Add the Advanced collapsible section and Command Guide reference modal.

**Actions:**
- Add Advanced collapsible section to command detail form (matching mock's `.advanced-wrap`):
  - Collapsible toggle: click "Advanced" to expand/collapse (CSS class toggle)
  - Fields: System Message, System Message File, Input Box Default, Stop Sequences, Max Context Words, Expand Newlines toggle
  - All fields have `?` tooltip hints
- Add Command Guide modal HTML (matching mock's `#cmdHelpModal`):
  - Intro section explaining what commands are and how the backtick menu works
  - 7 structured sections: Required Fields, Prompt Composition, Template Variables, Response Handling, Thinking, FIM, Menu Organization
  - All field names in `<code>` formatting
  - Self-contained — no external references
- Add Submenu Order section at bottom: tag badges with drag-to-reorder
- Update `commands.js` to serialize advanced fields and submenu order

**Unit Tests to Write/Update:**
- Update `tests/unit/settings-commands.test.js`: test advanced section toggle, advanced field serialization, submenu order serialization

**Integration Tests to Write/Update:**
- None

**Live Smoke Test:**
1. Click "Advanced" in command detail → verify 6 fields expand
2. Fill System Message → verify saved
3. Click "Command Guide" button → verify modal opens with documentation
4. Verify guide has intro + 7 sections, no UserConfig references
5. Verify submenu order badges visible at bottom of Commands section

**Smoke Test Classification:** Model

**Suggested Commit Message:** feat(settings): add Commands advanced section and Command Guide modal

---

### [ ] Step 8: AHK Backend — Refactor for Settings.json

**Goal:** Wire settings.json into the AHK runtime, refactor RuntimeResolver and assistant handling.

**Actions:**
- In `Main.ahk`, after `#Include` chain: call `SettingsHandler.Load()` → `SettingsHandler.Merge()` with defaults → assign to all globals (e.g., `global providers := settings["providers"]`, etc.). Then call `RuntimeResolver.CheckApiKeys()` (see below).
- In `ChatWindow.ahk`, before creating WebView: same Load/Merge/assign flow. No duplicate call needed since Main also loads.
- **Critical: Defer RuntimeResolver startup check.** Wrap current `RuntimeResolver.ahk` lines 11-29 in a function `RuntimeResolver.CheckApiKeys()`:
  - Iterates `providers`, checks BOTH `EnvGet(p.authEnvVar)` AND `p.apiKey` (direct entry)
  - If no keys found anywhere, shows `MsgBox` and calls `ExitApp()`
  - Called explicitly from Main.ahk and ChatWindow.ahk AFTER `SettingsHandler.Load()`
- Update `RuntimeResolver._getApiKey(p)`: check `authMode` — if "direct" and `p.apiKey` is non-empty, return `p.apiKey`. Otherwise fall back to `EnvGet(p.authEnvVar)`.
- Update `AssistantRepo.ahk`: remove `Seed()` method entirely. Add `AssistantRepo.GetFromSettings(assistantId)` that reads from the global `assistants` array by ID. Returns empty string if not found.
- Update `ChatSettings.ahk`:
  - `handleSwitchAssistant()`: replace `ChatDB.Assistant_Get()` with `AssistantRepo.GetFromSettings()`
  - `_restoreThreadSettings()`: same replacement for assistant resolution
  - `postAssistantsToWebView()`: replace `ChatDB.Assistant_List()` with reading the global `assistants` array directly (it's already in memory)
- Update `ChatDB.ahk`: in `_CreateSchema()`, wrap the `assistants` table creation in `IF NOT EXISTS` only (keep schema for now, just don't use it). Do NOT drop the table to avoid breakage.
- Handle `saveReloadHotkey` in `Main.ahk`: change the reload trigger from `WinActive("UserConfig.ahk")` to a generic reload. When Ctrl+S is pressed AND settings are loaded, just `Reload`. The script re-reads settings.json on reload.
- Update `test_config.ahk`: if it includes `UserConfig.ahk`, ensure it also calls `SettingsHandler.Load()` or sets test globals explicitly.
- **Live propagation**: After `saveSettings` in ChatWindow IPC, send `CustomMessages.Send("settingsUpdated")` to Main. Main's handler calls `SettingsHandler.Load()` → Merge → reassigns globals.

**Unit Tests to Write/Update:**
- Update `tests/unit/ChatSettings.test.ahk`: mock global `assistants` array, test resolution from settings
- Update `tests/unit/RuntimeResolver.test.ahk` (if exists): test `CheckApiKeys()` with direct and env keys
- `tests/unit/SettingsIntegration.test.ahk`: test full Load → Merge → assign cycle

**Integration Tests to Write/Update:**
- Update `tests/integration/ChatFlow.test.ahk`: verify chat works with settings-loaded config
- Update `tests/integration/UsageFlow.test.ahk`: verify usage tracking with settings config

**Live Smoke Test:**
1. Delete `settings.json` → start app → verify it uses UserConfig defaults (chat works, commands work)
2. Verify Ctrl+S reload still works (doesn't require WinActive check)
3. Verify backtick menu still shows commands
4. Verify chat model selection still works
5. Run full AHK test suite → verify existing tests pass (or identify which need updating)

**Smoke Test Classification:** Model

**Suggested Commit Message:** refactor(settings): wire settings.json into runtime, defer API key check, remove AssistantRepo.Seed

---

### [ ] Step 9: Integration — Wire Everything Together

**Goal:** Final integration: CSS polish, unsaved changes flow, restart warnings, mock-to-implementation verification.

**Actions:**
- Ensure `showSettings()`/`hideSettings()` properly manage the three-panel state:
  - Settings icon: `id="settings-icon"`, gets `.active` class when settings shown
  - When showing settings: hide `#railLeft` (chat sidebar), show `.settings-nav`, show `.settings-center`, hide `#chat-layout` and `#dashboard-panel`
  - When hiding settings: restore previous state based on which icon was active before settings
- Unsaved changes guard: `hideSettings()` checks `_dirty` flag. If dirty, shows a modal: "You have unsaved changes. Discard them?" [Stay] [Discard]. Discard calls `_resetAllToDefaults()` to revert UI to last saved state.
- Restart warning: after Save, if hotkeys/icons/tray menu were modified (tracked via dirty flags per section), show yellow banner in the affected section: "⚠️ Some changes require a script restart. [Restart Now]"
- "Restart Now": sends `{action: 'reloadScript'}` IPC to AHK
- "Reset to Defaults": wired to nav-footer button. Calls `_resetAllToDefaults()` then sets dirty=true (user must explicitly Save to persist defaults).
- CSS polish: ensure settings panel matches mock (flush cards, tooltip positioning z-index 9999, no overflow clipping, proper scroll behavior)
- Remove unused mock-specific CSS from settings.css (tab-bar styles no longer needed)
- Final verification: side-by-side comparison of mock vs real app for each tab

**Unit Tests to Write/Update:**
- `tests/unit/settings-integration.test.js`: test full flow (load → edit → save → reload), restart warning logic, unsaved changes guard, Reset to Defaults

**Integration Tests to Write/Update:**
- None — covered by smoke test

**Live Smoke Test:**
1. Walk through all 10 tabs — verify every field editable
2. Make changes across multiple tabs → Save → verify all persisted (check settings.json)
3. Switch to Chat with unsaved changes → verify confirmation popup → Discard → verify reverted
4. Switch to Chat with unsaved changes → verify confirmation popup → Stay → verify still in settings
5. Change a hotkey → Save → verify restart warning appears with "Restart Now" button
6. Click "Reset to Defaults" → verify all fields revert to UserConfig defaults → Save → verify settings.json written with defaults
7. Side-by-side comparison of mock (`settings-mock.html`) vs real app for visual fidelity

**Smoke Test Classification:** Human — requires visual comparison (step 7)

**Suggested Commit Message:** feat(settings): integrate all sections with unsaved changes guard, restart flow, and reset

---

## §5 Final Directory Tree

```
project/
├── app/
│   └── SettingsHandler.ahk              (new — JSON persistence + IPC + GetDefaults)
├── lib/
│   └── Config.ahk                       (modified — #Include ..\app\SettingsHandler.ahk)
├── Main.ahk                             (modified — SettingsHandler.Load + CheckApiKeys + settingsUpdated handler)
├── UserConfig.ahk                       (modified — remains as defaults, no longer primary config source)
├── chat/
│   ├── ChatIPC.ahk                      (modified — requestAllSettings, saveSettings, refreshModelPricing handlers)
│   ├── ChatSettings.ahk                 (modified — assistants from settings array, not DB)
│   ├── ChatWindow.ahk                   (modified — SettingsHandler.Load on startup)
│   ├── db/
│   │   ├── AssistantRepo.ahk           (modified — remove Seed(), add GetFromSettings())
│   │   └── ChatDB.ahk                  (modified — assistants table IF NOT EXISTS only)
│   └── ThreadTitleGen.ahk              (no changes — already reads globals dynamically)
├── shared/
│   └── RuntimeResolver.ahk             (modified — CheckApiKeys() function, direct key support)
├── ipc/
│   └── CustomMessages.ahk              (modified — settingsUpdated message type)
├── webui/
│   ├── index.html                       (modified — settings icon id, settings HTML, new includes)
│   ├── css/
│   │   └── settings.css                 (new — nav sidebar, content cards, tooltips, modals)
│   └── js/
│       ├── main.js                      (modified — showSettings/hideSettings, icon wiring, unsaved guard)
│       └── settings/
│           ├── settings-panel.js         (new — tab switching, IPC, dirty tracking, save/reset)
│           └── sections/
│               ├── general.js            (new)
│               ├── icons.js              (new)
│               ├── ui-theme.js           (new)
│               ├── hotkeys.js            (new)
│               ├── menu-items.js         (new)
│               ├── providers.js          (new)
│               ├── models.js             (new)
│               ├── assistants.js         (new)
│               └── commands.js           (new)
├── tests/
│   ├── test_config.ahk                  (modified — ensure settings loading in test mode)
│   ├── unit/
│   │   ├── SettingsHandler.test.ahk     (new)
│   │   ├── settings-panel.test.js       (new)
│   │   ├── settings-general.test.js     (new)
│   │   ├── settings-icons.test.js       (new)
│   │   ├── settings-ui-theme.test.js    (new)
│   │   ├── settings-hotkeys.test.js     (new)
│   │   ├── settings-menu-items.test.js  (new)
│   │   ├── settings-providers.test.js   (new)
│   │   ├── settings-models.test.js      (new)
│   │   ├── settings-assistants.test.js  (new)
│   │   ├── settings-commands.test.js    (new)
│   │   ├── settings-integration.test.js (new)
│   │   ├── SettingsIntegration.test.ahk (new)
│   │   ├── ChatSettings.test.ahk        (modified)
│   │   └── RuntimeResolver.test.ahk     (modified — if exists)
│   └── integration/
│       ├── ChatFlow.test.ahk            (modified)
│       └── UsageFlow.test.ahk           (modified)
└── agent-workspace/
    └── feature/
        ├── settings-mock.html            (reference — visual blueprint for implementation)
        ├── plan.md                       (this file)
        └── reference.md                  (to be written)
```
