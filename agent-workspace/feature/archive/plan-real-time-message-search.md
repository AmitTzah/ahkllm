# Implementation Plan: Real-Time Message Search with Dropdown

## §1 Overall Project

An AutoHotkey (AHK) chat application with a WebView2-based UI. Users interact with multiple AI assistants across chat threads. Messages are stored in a SQLite database with tree-based branching — each message can have sibling branches, and the active path is tracked per thread. The UI is a three-panel layout: left sidebar (chat list with search box), center (message view + composer), right panel (settings + thread map with search box).

Communication between AHK and the WebView uses `chrome.webview.postMessage` (JS→AHK) with action-based dispatch, and `postWebMessage` (AHK→JS) with target-based routing. The project has unit tests for both AHK (AutoHotkey test files) and JS (Node.js `node:test` with `vm` sandboxing), plus integration tests.

## §2 This Feature

Wire up the two existing (but non-functional) search inputs in the UI:

1. **"Search chats..."** (left panel, [`index.html:50`](webui/index.html:50)) — searches messages across ALL chat threads
2. **"Search in chat..."** (right panel thread map, [`index.html:257`](webui/index.html:257)) — searches messages only within the currently active thread

Both searches provide real-time dropdown results as the user types:
- Results update as the user types (debounced 250ms, minimum 2 characters)
- Each result shows a message preview with the search term highlighted (HTML-escaped, then `<mark>`-wrapped)
- Thread title shown for cross-chat results
- Role indicator (You/Assistant)
- Clicking a result navigates to that message with a flash highlight — reusing the existing [`scrollToMessage`](webui/js/chat/chat-sidebar.js:376) pattern
- Keyboard navigation: Arrow Up/Down to move through results, Enter to select, Escape to close
- Stale-response cancellation: each request carries a `queryId` counter; responses with non-matching IDs are discarded

**Out of scope:** Search in attachment text, search operators/filters.

**Search engine: SQLite FTS5** (Full-Text Search v5). FTS5 is built into SQLite — no external library. It tokenizes content on word boundaries, handles case-insensitive matching natively, supports prefix queries, and returns results ranked by relevance. A FTS5 virtual table (`messages_fts`) is kept in sync with the `messages` table via SQL triggers (INSERT/UPDATE/DELETE). The LIKE `'%term%'` query serves as a substring fallback for matches that FTS5 tokenization might miss (e.g., mid-word substrings).

**Title search:** The "Search chats" (global, un-scoped) search also matches against `chat_threads.title` via LIKE. Results from title-only matches show the thread title with no message preview and role=`"system"` (interpreted by the frontend as a thread-level result).

## §3 End State Upon Feature Completion

### User Perspective

```
[User types "error" in "Search chats..." box]

┌─────────────────────────────────┐
│ 🔍 error                        │  ← search input (left panel)
├─────────────────────────────────┤
│ 📁 Debug Session                │  ← thread title
│ 👤 You: "I'm getting an error   │  ← role icon + preview with "error" highlighted
│         when running the script"│
├─────────────────────────────────┤
│ 📁 API Troubleshooting          │
│ 🤖 Assistant: "The error code   │
│               indicates a       │
│               timeout"          │
├─────────────────────────────────┤
│ 📁 General Chat                 │
│ 👤 You: "Can you help fix this  │
│         error?"                 │
└─────────────────────────────────┘
         ↑ scrollable, max ~6 items visible (20 fetched, scrollable)

[User presses Arrow Down twice, then Enter on third result]
→ Switches to "General Chat" thread (via loadThread, not broken navigateToMessage)
→ Scrolls to the target message with flash highlight
→ Dropdown closes
```

```
[User types "config" in "Search in chat..." box (right panel)]

┌─────────────────────────────────┐
│ 🔍 config                       │  ← search input (right panel)
├─────────────────────────────────┤
│ 👤 You: "update the config file"│  ← no thread title (same chat)
├─────────────────────────────────┤
│ 🤖 Assistant: "The config has   │
│              been updated"      │
└─────────────────────────────────┘

[User presses Arrow Down, Enter]
→ Scrolls to assistant message within current thread
→ Message flashes with highlight animation
→ Dropdown closes
```

**Edge Cases:**
- **Empty results:** Dropdown shows "No messages found"
- **Loading state:** Dropdown shows "Searching..." while query is in flight
- **Search timeout:** After 10 seconds, shows "Search timed out" and closes dropdown
- **< 2 characters:** No search triggered, no dropdown (existing search results cleared)
- **Escape key:** Closes dropdown, returns focus to input
- **Click outside:** Closes dropdown
- **Rapid typing:** Previous in-flight responses discarded via `queryId` matching; new query supersedes
- **No active thread (right panel):** If `activeThreadId` is empty, input is disabled with placeholder "Open a chat to search"
- **Active thread deleted while dropdown open:** Next search returns empty for that thread
- **Very long content:** Preview truncated to ~80 characters with ellipsis
- **Message edited/deleted after search:** Navigation falls back gracefully — `SetActiveLeaf` on a non-existent message is a no-op; the active leaf stays where it was
- **HTML in message content:** Content is HTML-escaped via `escHtml()` BEFORE `<mark>` wrapping to prevent XSS
- **Scroll while dropdown open:** Dropdown closes when the containing panel scrolls (event listener on `.rail-left-scroll` and `.rail-right`)

### Technical Perspective

**Data Flow:**
```
[User Types] → [250ms Debounce] → [JS: assign queryId, postMessage to AHK]
    → [AHK: Dispatch.searchMessages] → [Search.ahk: handleSearch]
    → [ChatDB.SearchMessages(query, threadId?)]
    → [SQLite: SELECT ... WHERE content LIKE '%term%' ESCAPE '\' LIMIT 20]
    → [AHK: postWebMessage("searchResults", {results, query, threadId, queryId})]
    → [JS: main.js routes to handleSearchResults(data)]
    → [JS: if data.queryId !== _activeQueryId → discard (stale response)]
    → [JS: render dropdown with highlighted terms]
```

**Cross-Chat Navigation (FIXED — uses loadThread, not broken navigateToMessage):**
```
[User Clicks Result (different thread)]
    → [JS: postMessage {action: "sidebarAction", subAction: "loadThread", threadId: result.threadId}]
    → [AHK: Sidebar._LoadThreadAndRefreshUI(newThreadId)]
    → [AHK: postWebMessage("initChatMode", path)]
    → [JS: initChatMode → renderChatMessages]
    → [JS: then sends {action: "sidebarAction", subAction: "navigateToMessage", messageId: result.messageId}]
    → [AHK: SetActiveLeaf, _LoadThreadAndRefreshUI]
    → [JS: setTimeout(find message index → scrollToMessage, 150ms)]
```

**Same-Chat Navigation:**
```
[User Clicks Result (same thread)]
    → [JS: find message index in chatMessages by result.messageId]
    → [JS: scrollToMessage(index)]
    → [Message flashes, dropdown closes]
```

**Search Engine DB Schema (FTS5 + LIKE fallback):**

*FTS5 virtual table (created in `_CreateSchema`, kept in sync via triggers):*
```sql
CREATE VIRTUAL TABLE IF NOT EXISTS messages_fts USING fts5(
    thread_id, role, content,
    tokenize='unicode61'
);

-- Triggers keep FTS in sync with messages table:
CREATE TRIGGER IF NOT EXISTS messages_fts_insert AFTER INSERT ON messages BEGIN
    INSERT INTO messages_fts(rowid, thread_id, role, content)
    VALUES (new.rowid, new.thread_id, new.role, new.content);
END;

CREATE TRIGGER IF NOT EXISTS messages_fts_delete AFTER DELETE ON messages BEGIN
    INSERT INTO messages_fts(messages_fts, rowid, thread_id, role, content)
    VALUES ('delete', old.rowid, old.thread_id, old.role, old.content);
END;

CREATE TRIGGER IF NOT EXISTS messages_fts_update AFTER UPDATE ON messages BEGIN
    INSERT INTO messages_fts(messages_fts, rowid, thread_id, role, content)
    VALUES ('delete', old.rowid, old.thread_id, old.role, old.content);
    INSERT INTO messages_fts(rowid, thread_id, role, content)
    VALUES (new.rowid, new.thread_id, new.role, new.content);
END;
```

*FTS5 primary query (word-level, ranked, case-insensitive):*
```sql
SELECT m.id AS messageId, m.thread_id AS threadId, m.role,
       SUBSTR(m.content, 1, 100) AS contentPreview,
       m.model, m.created_at AS createdAt,
       t.title AS threadTitle
FROM messages_fts f
JOIN messages m ON f.rowid = m.rowid
JOIN chat_threads t ON m.thread_id = t.id
WHERE t.is_deleted = 0
  AND messages_fts MATCH <escaped_fts_query>
  [AND m.thread_id = '<threadId>']
ORDER BY rank
LIMIT 20
```

*LIKE fallback (substring, only if FTS5 returns 0 results):*
```sql
-- Same SELECT from messages m JOIN chat_threads t
-- WHERE m.content LIKE '%' || <escaped> || '%' ESCAPE '\'
-- Covers mid-word substrings FTS5 tokenization misses
```

*Title search (global/un-scoped only):*
```sql
SELECT NULL AS messageId, t.id AS threadId, 'system' AS role,
       '' AS contentPreview, '' AS model, t.created_at AS createdAt,
       t.title AS threadTitle
FROM chat_threads t
WHERE t.is_deleted = 0
  AND t.title LIKE '%' || <escaped> || '%' ESCAPE '\'
ORDER BY t.updated_at DESC
LIMIT 10
```

### Component Architecture

```
chat/db/ChatDB.ahk                  (modified — add SearchMessages method)
chat/callbacks/Dispatch.ahk         (modified — add searchMessages case, include Search.ahk)
chat/callbacks/Search.ahk           (new — handleSearch callback)
chat/callbacks/Sidebar.ahk          (modified — navigateToMessage accepts optional threadId param)
webui/index.html                    (modified — add chat-search.js script tag, before main.js)
webui/js/main.js                    (modified — add searchResults handler, call initSearch in DOMContentLoaded)
webui/js/chat/chat-search.js        (new — search module: debounce, queryId, dropdown, keyboard nav, selection)
webui/css/components.css            (modified — add search dropdown styles at end of file)
tests/unit/ChatDB.test.ahk          (modified — add SearchMessages tests)
tests/unit/chat-search.test.js      (new — JS search module tests)
```

## §4 Implementation Steps

### [ ] Step 1: AHK Backend — DB Search Query, Dispatch, Callback, and Cross-Chat Navigation Fix

**Goal:** Create the server-side search infrastructure: database query method, IPC dispatch routing, callback that returns results, and fix the `navigateToMessage` handler to support cross-thread navigation.

**Actions:**
- Add `ChatDB.SearchMessages(query, threadId := "")` static method to [`chat/db/ChatDB.ahk`](chat/db/ChatDB.ahk:1):
  - Query `messages` joined with `chat_threads` (for thread title and is_deleted filter)
  - Filter: `content LIKE '%' || <escaped_query> || '%' ESCAPE '\'` AND `chat_threads.is_deleted = 0`
  - If `threadId` provided: add `AND messages.thread_id = '<threadId>'`
  - Select: `messages.id AS messageId, messages.thread_id AS threadId, messages.role, SUBSTR(messages.content, 1, 100) AS contentPreview, messages.model, messages.created_at AS createdAt, chat_threads.title AS threadTitle`
  - LIMIT 20, ORDER BY `messages.created_at DESC`
  - Return array of objects: `{threadId, threadTitle, messageId, contentPreview, role, model, createdAt}`
  - Use `SQLite.Escape()` on the query string to prevent SQL injection
- Add `"searchMessages"` case to the switch in [`chat/callbacks/Dispatch.ahk`](chat/callbacks/Dispatch.ahk:25) that calls `handleSearch(parsed)`
- Create [`chat/callbacks/Search.ahk`](chat/callbacks/Search.ahk) with `handleSearch(params)`:
  - Extract `query`, optional `threadId`, and `queryId` from params
  - Validate: query must be ≥ 2 characters, else return `{results: [], query, threadId, queryId}`
  - Call `ChatDB.SearchMessages(query, threadId)`
  - Post results back via `postWebMessage("searchResults", {results, query, threadId, queryId})`
  - Wrap in try/catch — on error, post back with empty results (don't leave UI in "Searching..." state)
- Include `Search.ahk` at the bottom of [`chat/callbacks/Dispatch.ahk`](chat/callbacks/Dispatch.ahk:61)
- Modify `navigateToMessage` case in [`chat/callbacks/Sidebar.ahk`](chat/callbacks/Sidebar.ahk:21):
  - Accept optional `threadId` param
  - If `threadId` is provided AND differs from `activeThreadId`: set `activeThreadId := threadId`, call `_LoadThreadAndRefreshUI(threadId)` first, then `ChatDB.Msg_SetActiveLeaf(threadId, messageId)`, then `_LoadThreadAndRefreshUI(threadId, false)` to reload with the correct active path
  - If `threadId` matches `activeThreadId` or is not provided: existing behavior unchanged

**Unit Tests to Write/Update:**
- [`tests/unit/ChatDB.test.ahk`](tests/unit/ChatDB.test.ahk:1): test `SearchMessages` with matching term returns correct results with all expected fields
- [`tests/unit/ChatDB.test.ahk`](tests/unit/ChatDB.test.ahk:1): test `SearchMessages` with no matches returns empty array
- [`tests/unit/ChatDB.test.ahk`](tests/unit/ChatDB.test.ahk:1): test `SearchMessages` scoped to threadId only returns that thread's messages
- [`tests/unit/ChatDB.test.ahk`](tests/unit/ChatDB.test.ahk:1): test `SearchMessages` excludes deleted threads
- [`tests/unit/ChatDB.test.ahk`](tests/unit/ChatDB.test.ahk:1): test `SearchMessages` with special characters (SQL injection) is safe via `SQLite.Escape`
- [`tests/unit/ChatDB.test.ahk`](tests/unit/ChatDB.test.ahk:1): test `SearchMessages` LIMIT — returns at most 20 results even if more match

**Integration Tests to Write/Update:**
- None — the search is a read-only query with no external dependencies beyond the DB (which unit tests cover via test DB).

**Live Smoke Test:**
1. Run `AutoHotkey64.exe tests/run_ahk_tests.ahk` from project root
2. Verify all 6 ChatDB.SearchMessages tests pass
3. Verify no existing tests break

**Smoke Test Classification:** Model

**Suggested Commit Message:** feat(search): add DB search query, IPC handler, and cross-thread navigation support

---

### [ ] Step 2: JS Frontend — Search Module with Dropdown UI, Keyboard Navigation, and Styling

**Goal:** Wire the two existing search inputs with real-time debounced search, dropdown rendering with term highlighting, keyboard navigation (Arrow/Enter/Escape), click-to-navigate behavior, stale-response cancellation via queryId, and all visual styling.

**Actions:**
- Create [`webui/js/chat/chat-search.js`](webui/js/chat/chat-search.js):
  - Module-level state: `_activeQueryId` (counter, incremented per search), `_debounceTimer`, `_searchDropdownEl`, `_selectedIndex` (for keyboard nav), `_searchTimeout` (10s timeout handle)
  - `initSearch()`: finds both search inputs via `document.querySelector('.search-wrap:not(.in-panel) .search-input')` (left panel, global scope) and `document.querySelector('.search-wrap.in-panel .search-input')` (right panel, thread-scoped). Attaches `input` event listeners. Disables right-panel input when `activeThreadId` is empty.
  - `handleSearchInput(event)`: extracts query, determines scope (global if input has no `.in-panel` ancestor, thread-scoped otherwise). If query < 2 chars: close dropdown, return. Clears previous debounce timer. Sets 250ms debounce. On fire: increments `_activeQueryId`, sends `{action: "searchMessages", query, threadId: scopeThreadId || undefined, queryId: _activeQueryId}`, starts 10s timeout.
  - `handleSearchResults(data)`: called from main.js. FIRST checks `data.queryId === _activeQueryId` — if not, return (stale response). Clears timeout. If `data.results.length === 0`: shows "No messages found". Otherwise calls `renderSearchDropdown(wrapperEl, data.results, data.query)`.
  - `renderSearchDropdown(wrapperEl, results, query)`: finds or creates `.search-dropdown` div positioned below the `.search-wrap` parent. Populates with `.search-result-item` divs. Each item: optional `.search-result-thread` (cross-chat only), `.search-result-role` badge ("You" / model name), `.search-result-preview` with query term wrapped in `<mark>` AFTER `escHtml()`. Sets `_selectedIndex = -1`. Attaches click handlers, keyboard listeners.
  - Click handler for same-thread result: finds message index in `chatMessages` by `result.messageId`, calls `scrollToMessage(index)`, closes dropdown.
  - Click handler for cross-thread result: sends `{action: "sidebarAction", subAction: "loadThread", threadId: result.threadId}`. Then after `initChatMode` completes (listens for the message), sends `{action: "sidebarAction", subAction: "navigateToMessage", messageId: result.messageId}`. After 150ms `setTimeout`, finds message index and calls `scrollToMessage(index)`.
  - Keyboard handler on the search input: Arrow Down → `_selectedIndex++`, highlight item. Arrow Up → `_selectedIndex--`. Enter → trigger click on highlighted item. Escape → `closeSearchDropdown()`, input retains focus.
  - `closeSearchDropdown()`: removes dropdown element, clears `_selectedIndex`, clears debounce timer and timeout.
  - Click-outside: document-level click listener that closes dropdown if click target is outside `.search-wrap`.
  - Scroll listener: closes dropdown when the containing panel scrolls (attach to `.rail-left-scroll` and `.rail-right`).
- Add `<script src="js/chat/chat-search.js"></script>` to [`webui/index.html`](webui/index.html) — insert between `stream.js` (line 359) and `main.js` (line 361), approximately line 360.
- Add `case 'searchResults': handleSearchResults(data); break;` to the switch in [`webui/js/main.js`](webui/js/main.js) — add before the `default:` case (line 146).
- Add `if (typeof initSearch === 'function') initSearch();` call in the `DOMContentLoaded` handler in [`webui/js/main.js`](webui/js/main.js:164), near the other init calls.
- In [`chat-core.js`](webui/js/chat/chat-core.js) `initChatMode()`: after setting `activeThreadId`, re-enable the right-panel search input.
- Append search dropdown CSS rules to the end of [`webui/css/components.css`](webui/css/components.css):
  - `.search-dropdown`: `position: absolute; top: 100%; left: 0; right: 0; background: var(--bg-panel); border: 1px solid var(--border-main); border-radius: var(--radius-md); box-shadow: var(--shadow-lg); max-height: 320px; overflow-y: auto; z-index: 100; margin-top: 4px;`
  - `.search-result-item`: `padding: 10px 12px; cursor: pointer; border-bottom: 1px solid var(--border-light); transition: background 0.1s;`
  - `.search-result-item:hover, .search-result-item.active`: `background: var(--bg-hover);`
  - `.search-result-item:last-child`: `border-bottom: none;`
  - `.search-result-thread`: `font-size: 11px; color: var(--text-tertiary); margin-bottom: 2px; font-weight: 500;`
  - `.search-result-preview`: `font-size: 13px; color: var(--text-primary); white-space: nowrap; overflow: hidden; text-overflow: ellipsis; line-height: 1.4;`
  - `.search-result-preview mark`: `background: var(--accent-primary); color: #fff; border-radius: 2px; padding: 0 1px;`
  - `.search-result-role`: `font-size: 11px; color: var(--text-secondary); font-weight: 500; margin-bottom: 1px;`
  - `.search-empty, .search-loading`: `padding: 16px; text-align: center; color: var(--text-tertiary); font-size: 13px;`
  - `.search-dropdown .search-highlighted`: `background: var(--bg-active) !important;` (for keyboard-selected item)

**Unit Tests to Write/Update:**
- [`tests/unit/chat-search.test.js`](tests/unit/chat-search.test.js): test debounce — multiple rapid inputs only fire one search after 250ms, with the latest query
- [`tests/unit/chat-search.test.js`](tests/unit/chat-search.test.js): test minimum character threshold — < 2 chars does not send search, clears existing results
- [`tests/unit/chat-search.test.js`](tests/unit/chat-search.test.js): test queryId — stale responses (non-matching queryId) are discarded
- [`tests/unit/chat-search.test.js`](tests/unit/chat-search.test.js): test dropdown renders correct number of results
- [`tests/unit/chat-search.test.js`](tests/unit/chat-search.test.js): test term highlighting in preview — `<mark>` tags wrap matching text, HTML is escaped first
- [`tests/unit/chat-search.test.js`](tests/unit/chat-search.test.js): test cross-chat result shows thread title; same-chat result does not
- [`tests/unit/chat-search.test.js`](tests/unit/chat-search.test.js): test same-thread result click calls scrollToMessage with correct index
- [`tests/unit/chat-search.test.js`](tests/unit/chat-search.test.js): test cross-thread result click sends loadThread + navigateToMessage sequence
- [`tests/unit/chat-search.test.js`](tests/unit/chat-search.test.js): test Escape key closes dropdown
- [`tests/unit/chat-search.test.js`](tests/unit/chat-search.test.js): test click outside closes dropdown
- [`tests/unit/chat-search.test.js`](tests/unit/chat-search.test.js): test empty results shows "No messages found"
- [`tests/unit/chat-search.test.js`](tests/unit/chat-search.test.js): test loading state shows "Searching..."
- [`tests/unit/chat-search.test.js`](tests/unit/chat-search.test.js): test Arrow Down moves selection highlight, Enter triggers click on selected item
- [`tests/unit/chat-search.test.js`](tests/unit/chat-search.test.js): test search timeout — after 10s, shows "Search timed out" and closes dropdown
- [`tests/unit/chat-search.test.js`](tests/unit/chat-search.test.js): test right-panel input disabled when activeThreadId is empty

**Integration Tests to Write/Update:**
- None — the JS→AHK→JS round-trip is covered by unit tests on both sides.

**Live Smoke Test:**
1. Run `node --test tests/unit/chat-search.test.js` — verify all 15 tests pass
2. Run `tests/run_all_tests.bat` — verify no existing tests break
3. Verify `chat-search.js` script tag exists in `index.html` before `main.js`
4. Verify CSS file contains `.search-dropdown` rules

**Smoke Test Classification:** Model

**Suggested Commit Message:** feat(search): add real-time search dropdown with keyboard navigation

---

### [ ] Step 3: Human Verification — Interactive Search Behavior

**Goal:** Manually verify the complete search flow works end-to-end with real data in the live application.

**Live Smoke Test:**
1. Open the chat app. Verify the "Search chats..." input is enabled in the left panel.
2. Verify the "Search in chat..." input in the right panel shows "Open a chat to search" (disabled) when no chat is active.
3. Open a chat with messages. Verify the right-panel search input becomes enabled with placeholder "Search in chat...".
4. Type "the" in "Search chats..." — verify a dropdown appears below the input with matching messages from all chats, each showing thread title and role.
5. Verify the search term "the" is highlighted (visually distinct) in each result preview.
6. Press Arrow Down — verify the first result highlights. Press Arrow Down again — second result highlights. Press Enter — verify the app switches to that thread and scrolls to the target message with a flash highlight animation.
7. Type "xyzzy" (nonsense term) — verify dropdown shows "No messages found".
8. Type a single character "a" — verify no dropdown appears (minimum 2 chars).
9. Type "config" in "Search in chat..." (right panel) — verify results only show messages from the current thread (no thread titles shown).
10. Click a result — verify it scrolls to the message within the current thread with flash highlight.
11. Press Escape — verify dropdown closes, input retains focus.
12. Open the dropdown, click outside of it — verify it closes.
13. Type rapidly "he" → "hel" → "hello" — verify only the final "hello" results appear (stale responses discarded).

**Smoke Test Classification:** Human

**Suggested Commit Message:** (none — this step is verification only, no code changes)

## §5 Final Directory Tree

```
project/
├── chat/
│   ├── callbacks/
│   │   ├── Dispatch.ahk              (modified — add searchMessages case + #Include Search.ahk)
│   │   ├── Search.ahk                (new — handleSearch callback)
│   │   └── Sidebar.ahk               (modified — navigateToMessage accepts optional threadId)
│   └── db/
│       └── ChatDB.ahk                (modified — add SearchMessages method)
├── webui/
│   ├── index.html                    (modified — add chat-search.js script tag before main.js)
│   ├── css/
│   │   └── components.css            (modified — add search dropdown styles at end)
│   └── js/
│       ├── main.js                   (modified — add searchResults handler, initSearch() call)
│       ├── chat/
│       │   ├── chat-core.js          (modified — re-enable right search on thread load)
│       │   └── chat-search.js        (new — search module: debounce, queryId, dropdown, keyboard nav)
│       └── ...
└── tests/
    └── unit/
        ├── ChatDB.test.ahk           (modified — add 6 SearchMessages tests)
        └── chat-search.test.js       (new — 15 JS search module tests)
```
