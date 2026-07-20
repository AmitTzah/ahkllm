# Implementation Plan: Fix Attachment Rendering, Cleanup, and Refactor

## 1 Overall Project

The LLM AutoHotkey Assistant is a Windows desktop application (AutoHotkey v2) with a WebView2 chat UI (vanilla HTML/CSS/JS) that communicates with an AHK backend via `chrome.webview.postMessage()`. The chat supports file and image attachments -- drag-drop, clipboard paste, browse-from-disk -- with SQLite persistence, base64 encoding, and Lucide-based iconography. The UI was recently migrated from Bootstrap to a custom 4-column SaaS design (commit `8bf0e1c`) using CSS variables and Lucide icons, Inter/JetBrains Mono fonts, and a modular CSS architecture.

## 2 This Feature

The UI overhaul deleted the old Bootstrap-dependent `webui/css/chat/chat-attachments.css` without replacing it. Combined with UTF-8 corruption in the attachment JS files, a synchronous base64 encoding bottleneck, and a gutted rendering function, the attachment system is effectively broken:

- **PDF/file thumbnails show "?" broken characters** -- mojibake from double-encoded UTF-8 emoji in `getAttachmentIcon()`
- **Pasting an image freezes the chat** -- synchronous byte-loop base64 encoding in `addAttachment()` blocks the UI thread on large clipboard images
- **Sent attachments render with no styles** -- zero CSS for `.attachment-item`, `.attachment-thumb`, `.msg-attachment-image`, `.msg-attachment-file`, the image overlay, or the delete button
- **Per-attachment [x] delete button is missing** -- `_buildAttachmentHtml()` was gutted to just an `<img>` or icon + name; no `.msg-attachment-delete` is rendered, making `setupMessageAttachmentDeleteDelegation()` dead code
- **XSS risk** -- `escHtml()` in `chat-core.js:87` is a no-op (replaces `&` with `&`, `<` with `<`, etc.) from the same entity-decode corruption

**In scope:**
- Create `webui/css/attachments.css` with full attachment styling for the new design system
- Fix all mojibake emoji -> Lucide icons in `chat-attachments.js` and `chat-attachments-extract.js`
- Fix `escHtml()` to actually escape HTML (with full call-site audit)
- Fix base64 encoding performance -- use chunked approach
- Restore full `_buildAttachmentHtml()`: thumbnails with max-size constraint, file badges with icon + name + size, per-attachment delete button, extracted-text preview, scanned-PDF banner, click-to-zoom image overlay
- Remove dead code: debug `console.log` throughout attachment files, officeParser double-quote debug block, unused `_editAttachments`/`_editExtractPromises`/`_editHashPromises` in `chat-branching.js`
- Add `--warning` / `--warning-light` CSS variables to `theme.css`

**Out of scope:**
- New attachment features (audio, video, OCR)
- AHK backend changes
- Dark mode-specific attachment styling (uses `:root` variables, inherits naturally)

**Design Decisions (from Architect review):**
- Use inline `if (typeof lucide !== 'undefined') lucide.createIcons();` for icon refresh -- no wrapper function needed (matches existing codebase pattern across 17 locations)
- `escHtml()` fix is safe: the 22 call sites across 10 files receive raw data from AHK (no `Format()` entity-encoding exists in the AHK codebase)
- Base64 chunked approach uses a loop within each chunk (avoids `Function.apply` stack overflow risk)
- `showErrorBanner()` delegates to `escHtml()` instead of maintaining parallel escaping logic
- `#attachment-bar` visibility is JS-controlled (already works); CSS `:empty` is supplementary only
- Image overlay is dynamically created in JS (not a static HTML element)

## 3 End State Upon Feature Completion

### Attachment Bar (composer, before send)

- `#attachment-bar` is above `.composer-inner`, hidden when empty (JS sets `display:none`)
- Each `.attachment-item`: thumbnail for images (48px, rounded, object-fit cover), or Lucide icon badge for files; filename (truncated); [x] remove button; spinner while extracting; scanned-PDF warning badge
- All icons are Lucide (`data-lucide` attribute), refreshed via `lucide.createIcons()`

### Sent Message Bubble (user role)

- Images: clickable thumbnail (max 300x300px via CSS), opens full-size overlay (dark backdrop, centered, click-to-dismiss). Info bar with Lucide `image` icon + filename + size + [x] delete button
- Files: Lucide icon + filename + file size + [x] delete button + expandable extracted-text preview (collapsed `<details>` by default)
- Scanned PDF banner: warning "No extractable text (scanned PDF) -- attached as image(s)" dismissible banner (only once per message)
- File sizes shown in human-readable format (KB/MB)

### Image Overlay

- Fixed full-screen dark overlay (`rgba(0,0,0,0.85)`, z-index 2000)
- Centered image, max 90vw x 90vh, border-radius, shadow
- Click overlay (outside image) to dismiss; also dismissed by global ESC handler
- Created dynamically in JS, removed on dismiss

### Edge Cases & Error States

1. Image >10MB base64 -> error banner (existing JS check)
2. Unsupported file type -> error banner (existing check)
3. File >50MB on disk -> error banner (existing check)
4. Empty PDF -> "no text content extracted"
5. Scanned PDF -> dismissible banner
6. Corrupted image -> error banner from FileReader error event
7. No attachments -> `#attachment-bar` hidden
8. Delete button while editing -> deferred (existing logic)
9. Click overlay outside image -> dismisses
10. ESC key -> dismisses overlay

## 4 Implementation Steps

---

### [ ] Step 1: Fix escHtml() + Audit Call Sites + Add CSS Variables

**Goal:** Fix the critical XSS-escaping no-op (with full call-site audit confirming safety), add missing `--warning` variables, fix `showErrorBanner()` to delegate to `escHtml()`, and update the test sandbox mock.

**Actions:**
- Audit all `escHtml()` call sites across 10 files -- verify AHK backend sends raw data without pre-encoding. Confirmed: no `Format()` or manual entity-encoding exists in AHK codebase. Thread titles, folder names, assistant names all arrive raw.
- Fix `escHtml()` in `chat-core.js:87`: `replace(/&/g,'&').replace(/</g,'<').replace(/>/g,'>').replace(/"/g,'"')`
- Fix `showErrorBanner()` in `chat-attachments.js:288`: replace manual `replace(/</g,'<')...` chain with `escHtml(message)`
- Add to `theme.css` `:root` block: `--warning: #F59E0B;` and `--warning-light: #FFFBEB;`
- Update `tests/unit/chat-render.test.js` sandbox `escHtml` mock (the entity-decoded no-op at line ~105): fix to use real entities matching new `escHtml()` behavior

**Unit Tests to Write/Update:**
- Update `tests/unit/chat-render.test.js`: fix `escHtml` sandbox mock

**Integration Tests to Write/Update:**
None.

**Live Smoke Test:**
1. Run `node --test "tests/unit/*.test.js" "tests/integration/*.test.js"` -- all pass
2. Grep `chat-core.js` for `replace(/&/g,'&')` -- must match

**Smoke Test Classification:** Model

**Suggested Commit Message:** fix(security): restore proper HTML escaping in escHtml; add --warning CSS variable

---

### [ ] Step 2: Create Attachment CSS for New Design System

**Goal:** Build `webui/css/attachments.css` from scratch using the new design tokens, covering the attachment bar, message-bubble attachments, image overlay, and text preview. Register in `index.html`.

**Actions:**
- Create `webui/css/attachments.css`:
  - `#attachment-bar` -- flex row, wrap, gap 8px, padding 8px 16px, border-top 1px solid var(--border-main), background var(--bg-panel)
  - `.attachment-item` -- flex row, align-items center, gap 6px, padding 4px 8px, border 1px solid var(--border-main), border-radius var(--radius-sm), background var(--bg-main), font-size 0.8rem, max-width 220px, overflow hidden
  - `.attachment-item .attachment-thumb` -- width 48px, height 48px, border-radius var(--radius-sm), object-fit cover, flex-shrink 0
  - `.attachment-item .attachment-icon` -- flex-shrink 0, width 20px, height 20px, color var(--text-tertiary)
  - `.attachment-item .attachment-name` -- overflow hidden, text-overflow ellipsis, white-space nowrap, flex 1, min-width 0
  - `.attachment-item .attachment-remove` -- background none, border none, color var(--text-tertiary), cursor pointer, font-size 1rem, padding 0 2px, line-height 1, flex-shrink 0
  - `.attachment-item .attachment-remove:hover` -- color var(--danger)
  - `.attachment-item .attachment-spinner` -- width 14px, height 14px, border 2px solid var(--border-main), border-top 2px solid var(--accent-primary), border-radius 50%, animation attach-spin 0.8s linear infinite, flex-shrink 0
  - `@keyframes attach-spin` -- `to { transform: rotate(360deg) }`
  - `.msg-attachment-image` -- margin 8px 0
  - `.msg-attachment-image img` -- max-width 300px, max-height 300px, border-radius var(--radius-md), border 1px solid var(--border-main), cursor pointer, transition transform 0.15s ease
  - `.msg-attachment-image img:hover` -- transform scale(1.02)
  - `.msg-attachment-image .msg-attachment-info` -- display flex, align-items center, gap 8px, font-size 0.75rem, margin-top 4px
  - `.msg-attachment-file` -- display flex, align-items center, gap 8px, padding 6px 10px, margin 4px 0, border 1px solid var(--border-main), border-radius var(--radius-sm), background var(--bg-hover), font-size 0.8rem
  - `.msg-attachment-file .file-icon` -- flex-shrink 0, width 18px, height 18px, color var(--text-tertiary)
  - `.msg-attachment-file .file-name` -- flex 1, overflow hidden, text-overflow ellipsis, white-space nowrap
  - `.msg-attachment-file .file-size` -- color var(--text-tertiary), font-size 0.7rem, flex-shrink 0
  - `.msg-attachment-delete` -- background none, border none, color var(--text-tertiary), cursor pointer, font-size 0.85rem, padding 0 4px, flex-shrink 0, opacity 0.5, transition opacity 0.15s
  - `.msg-attachment-delete:hover` -- opacity 1, color var(--danger)
  - `.msg-attachment-text-preview` -- margin 4px 0, padding 6px 10px, border 1px solid var(--border-main), border-radius var(--radius-sm), background var(--bg-hover), font-size 0.75rem, max-height 150px, overflow-y auto
  - `.msg-attachment-text-preview pre` -- margin 0, white-space pre-wrap, word-break break-all, font-family var(--font-mono), font-size 0.7rem
  - `.scan-banner` -- background var(--warning-light), color #92400E, padding 6px 12px, margin 4px 0, border-radius var(--radius-sm), font-size 0.8rem, border 1px solid #FDE68A, display flex, align-items center, justify-content space-between
  - `.image-overlay` -- display none (set to flex by JS), position fixed, top 0, left 0, width 100%, height 100%, background rgba(0,0,0,0.85), z-index 2000, cursor pointer, justify-content center, align-items center
  - `.image-overlay img` -- max-width 90vw, max-height 90vh, border-radius var(--radius-md), box-shadow 0 4px 30px rgba(0,0,0,0.5)
- Update `webui/index.html`: add `<link rel="stylesheet" href="css/attachments.css">` after `components.css` line (line 17)

**Unit Tests to Write/Update:**
None -- pure styling.

**Integration Tests to Write/Update:**
None.

**Live Smoke Test:**
1. Verify `webui/css/attachments.css` exists and is non-empty
2. Verify `webui/index.html` contains `href="css/attachments.css"` in `<head>`
3. Run `node --test "tests/unit/*.test.js" "tests/integration/*.test.js"` -- all pass

**Smoke Test Classification:** Model

**Suggested Commit Message:** feat(css): add attachment styling for new design system

---

### [ ] Step 3a: Fix Emoji -> Lucide Icons + Mozibake Warnings

**Goal:** Replace all mojibake emoji in attachment JS with Lucide icon names. Update `renderAttachmentBar()` to render Lucide `<i>` elements. Fix warning message mojibake.

**Actions:**
- Replace `getAttachmentIcon()` in `chat-attachments.js:35-48`: return Lucide icon name strings:
  - image mime -> `'image'`
  - application/pdf -> `'file-text'`
  - wordprocessing -> `'file-text'` (docx)
  - presentation -> `'presentation'` (pptx)
  - spreadsheet -> `'file-spreadsheet'` (xlsx)
  - code extensions (py,js,ahk,java,c,cpp,h,rs,go,ts,tsx,jsx,sql,bat,ps1,sh) -> `'file-code'`
  - data/config extensions (json,xml,csv,ini,cfg,yaml,yml,toml,xlsx,ods) -> `'file-type'`
  - web extensions (html,css) -> `'globe'`
  - odt,odp -> `'file-text'`
  - fallback -> `'paperclip'`
- Update `renderAttachmentBar()` in `chat-attachments.js:166-247`:
  - For file types (non-image): create `<i data-lucide="iconName" class="attachment-icon">` instead of `<span class="attachment-icon">` with emoji textContent
  - Call `if (typeof lucide !== 'undefined') lucide.createIcons();` at end of render
- Fix CDN unavailable warning mojibake at line 233: `'\u00E2\u0161\u00A0\u00EF\u00B8\u008F'` -> `'\u26A0\uFE0F'` (or Lucide `alert-triangle`)
- Fix em-dash mojibake in comments in `chat-attachments-extract.js` (lines 10, 33, 65, 70, 117): `\u00E2\u20AC\u201D` -> `--` (these are just comments, cosmetic)
- Update `tests/unit/chat-attachments.test.js`: change `getAttachmentIcon` test expectations from emoji strings to Lucide icon name strings

**Unit Tests to Write/Update:**
- Update `tests/unit/chat-attachments.test.js`: `getAttachmentIcon` tests -- all emoji expectations become Lucide icon names (e.g., `'\uD83D\uDCD5'` -> `'file-text'`)

**Integration Tests to Write/Update:**
None.

**Live Smoke Test:**
1. Run `node --test "tests/unit/*.test.js" "tests/integration/*.test.js"` -- all pass
2. Verify `getAttachmentIcon('application/pdf', 'test.pdf')` returns `'file-text'`
3. Verify `getAttachmentIcon('image/png', 'photo.png')` returns `'image'`

**Smoke Test Classification:** Model

**Suggested Commit Message:** fix(attachments): replace mojibake emoji with Lucide icon names; update renderer

---

### [ ] Step 3b: Fix Base64 Performance + Remove Debug Logging

**Goal:** Replace the synchronous byte-loop base64 conversion with a chunked approach. Remove all debug `console.log` statements and the officeParser double-quote debug block.

**Actions:**
- Optimize base64 conversion in `addAttachment()` at `chat-attachments.js:90-96`: replace byte-loop with chunked approach using a loop within each chunk:
  ```javascript
  var bytes = new Uint8Array(arrayBuffer);
  var chunks = [];
  var CHUNK = 8192;
  for (var i = 0; i < bytes.length; i += CHUNK) {
      var end = Math.min(i + CHUNK, bytes.length);
      var chunkStr = '';
      for (var j = i; j < end; j++) { chunkStr += String.fromCharCode(bytes[j]); }
      chunks.push(chunkStr);
  }
  att.base64 = btoa(chunks.join(''));
  ```
- Remove ALL `console.log` from `chat-attachments.js` (lines 155, 158, 161, 190) -- keep `console.error`
- Remove ALL `console.log` from `chat-attachments-extract.js` -- keep `console.error`
- Remove officeParser double-quote debug block from `chat-attachments-extract.js` (lines 164-169, the `dqCount` detection block)
- Remove ALL `console.log` from `chat-attachments-setup.js` (lines 96, 99, 104) -- keep `console.error`
- Remove `console.log` debug from `chat-input.js` lines 22, 42

**Unit Tests to Write/Update:**
None -- behavior unchanged, only performance and log removal.

**Integration Tests to Write/Update:**
None.

**Live Smoke Test:**
1. Run `node --test "tests/unit/*.test.js" "tests/integration/*.test.js"` -- all pass
2. Grep `chat-attachments.js` for `console.log` -- zero matches (except in comments)
3. Grep `chat-attachments-extract.js` for `console.log` -- zero matches
4. Grep `chat-input.js` for `console.log` -- zero matches
5. Verify base64 conversion uses chunked approach (grep for `CHUNK` or `chunkSize`)

**Smoke Test Classification:** Model

**Suggested Commit Message:** perf(attachments): optimize base64 encoding with chunked approach; remove debug logging

---

### [ ] Step 3c: Remove Dead Edit-Attachment State

**Goal:** Remove `_editAttachments`, `_editExtractPromises`, `_editHashPromises` from `chat-branching.js` -- these are never populated by the current edit UI and are dead code. Simplify `commitEdit()` to direct commit. Delete test cases that depended on them.

**Actions:**
- Remove from `chat-branching.js`:
  - `var _editAttachments = [];` (line 44)
  - `var _editExtractPromises = [];` (line 45)
  - `var _editHashPromises = [];` (line 46)
  - Replace the `allPromises` wait logic in `commitEdit()` (lines 48-75) with a direct call: just execute the body of `doCommit()` directly (remove the Promise.all wrapper)
  - Remove `_editAttachments` mapping from payload construction (lines 56-62): delete the entire `if (_editAttachments.length > 0)` block
- Update `tests/unit/edit-removed-attachments.test.js`:
  - Remove `_editAttachments`, `_editExtractPromises`, `_editHashPromises` from sandbox initialization
  - DELETE the two test cases that create `_editAttachments` mock data: `'commitEdit includes contentHash in attachment payload'` and `'commitEdit handles empty contentHash'`
  - Keep the tests for `_removedAttachmentIds` tracking and `_editingMessageId` clearing

**Unit Tests to Write/Update:**
- Update `tests/unit/edit-removed-attachments.test.js` -- delete 2 test cases, remove dead vars from sandbox

**Integration Tests to Write/Update:**
None.

**Live Smoke Test:**
1. Run `node --test "tests/unit/*.test.js" "tests/integration/*.test.js"` -- all pass
2. Grep `chat-branching.js` for `_editAttachments`, `_editExtractPromises`, `_editHashPromises` -- zero matches

**Smoke Test Classification:** Model

**Suggested Commit Message:** refactor: remove dead edit-attachment state from chat-branching

---

### [ ] Step 4: Restore Full In-Message Attachment Rendering

**Goal:** Rewrite `_buildAttachmentHtml()` to produce full-featured attachment bubbles matching the pre-overhaul behavior but styled with Lucide icons and new design tokens. The function now renders HTML strings (matching existing `createMessageBubble()` pattern) with all the lost features restored. Add `_formatFileSize()` helper.

**Actions:**
- Rewrite `_buildAttachmentHtml()` in `chat-render.js:191-208`:
  - Pre-scan for scanned PDF: if any attachment has `extracted_text === '__SCANNED_PDF__'`, add a `.scan-banner` div (dismissible) once before the attachment loop
  - For each image attachment (`att.attachment_type === 'image'`, `att.base64` is the flag for DB-loaded image attachments -- use `att.id` since attachments from DB have `id` not `_id`):
    - Render `.msg-attachment-image` wrapper with `<img>` (CSS handles max 300px), click handler that dynamically creates and shows `.image-overlay`
    - Info bar (`.msg-attachment-info`): Lucide `image` icon + `escHtml(att.original_filename)` + `_formatFileSize(att.file_size)` + `.msg-attachment-delete` [x] button (only if `att.id` exists)
  - For each file attachment (non-image):
    - Render `.msg-attachment-file` wrapper with: `.file-icon` Lucide icon, `.file-name` (escaped), `.file-size` (formatted), `.msg-attachment-delete` [x] button (only if `att.id`)
    - If `extracted_text` exists and is not `'__SCANNED_PDF__'`, `'__LIBRARY_UNAVAILABLE__'`, or empty: add expandable `<details class="msg-attachment-text-preview">` with `<summary>` and `<pre>` block
  - All user-controlled values passed through `escHtml()` (filenames, extracted text)
  - Delete button: `data-attachment-id="` + `att.id` + `"` matches what `setupMessageAttachmentDeleteDelegation()` expects
- Add `_formatFileSize(bytes)` helper to `chat-render.js`: 0 -> "0B", < 1024 -> "N B", < 1048576 -> "N.N KB", >= 1048576 -> "N.N MB"
- After `createMessageBubble()` calls `addMessageActions()`, call `if (typeof lucide !== 'undefined') lucide.createIcons();` to render Lucide icons in attachment elements
- Add image overlay ESC dismiss: update the global ESC handler in `chat-core.js` (around line 142) to also check for and dismiss `.image-overlay` if visible

**Unit Tests to Write/Update:**
- Update `tests/unit/chat-render.test.js`: add tests for `_buildAttachmentHtml()` output -- verify class names, delete button attributes, Lucide icon attributes, file size formatting, scan banner
- Add tests for `_formatFileSize()`: 0 -> "0B", 500 -> "500B", 1024 -> "1.0KB", 1536 -> "1.5KB", 1048576 -> "1.0MB", 1572864 -> "1.5MB"

**Integration Tests to Write/Update:**
None.

**Live Smoke Test:**
1. Run `node --test "tests/unit/*.test.js" "tests/integration/*.test.js"` -- all pass
2. Grep `chat-render.js` for `.msg-attachment-delete` with `data-attachment-id` -- must match

**Smoke Test Classification:** Model

**Suggested Commit Message:** fix(render): restore full in-message attachment rendering with delete buttons and text preview

---

### [ ] Step 5: Smoke Tests -- Human Visual Verification (Collected)

**Goal:** Steps 1-4 ensure code correctness. Step 5 is the accumulated Human smoke tests for hands-off mode. These tests require visual verification of the GUI.

**Note:** This step has no code changes. It collects the Human-classified smoke tests that must be verified at Phase 5. The step itself is marked complete after QA pre-flight passes and the tests are recorded in state.json for later presentation.

**Smoke Tests to Collect:**

**Test A: Attachment Bar Rendering**
1. Open the chat app
2. Click the paperclip button, browse and select an image file
3. Verify: attachment bar appears above the composer input with a 48x48px image thumbnail, filename, and [x] remove button
4. Verify: Lucide icon renders (not mojibake/emoji)
5. Click [x] -- verify attachment is removed and bar hides if empty
6. Drag a PDF file onto the composer -- verify file badge appears with Lucide `file-text` icon and filename
7. Verify: while PDF is loading, a spinner animation appears

**Test B: Image Paste (No Freeze)**
1. Copy an image to clipboard (PrintScreen or copy from image editor)
2. Click in the chat input and press Ctrl+V
3. Verify: attachment appears within 1-2 seconds (no multi-second freeze)
4. Verify: thumbnail renders at constrained size (not full-resolution)

**Test C: Sent Message Attachments**
1. Send a message with an image attachment
2. Verify: message bubble shows the image thumbnail (max 300px), with filename, file size, and [x] delete button below it
3. Click the image thumbnail -- verify overlay opens (dark backdrop, centered image)
4. Click outside the image -- verify overlay closes
5. Press ESC while overlay is open -- verify overlay closes
6. Send a message with a PDF that has extractable text
7. Verify: file badge shows in the message bubble with filename, size, and expandable "Extracted text" preview
8. Click the [x] delete button on the PDF attachment -- verify the attachment row is removed from the message

**Test D: Broken Characters Fixed**
1. Add a PDF attachment to the composer
2. Verify the file badge icon is a proper Lucide icon (not "?" or broken glyphs)
3. Send the message -- verify the file icon in the bubble is also a proper Lucide icon

**Smoke Test Classification:** Human

**Suggested Commit Message:** (no commit -- verification-only step)

---

## 5 Final Directory Tree

```
webui/
├── index.html                              (modified -- added attachments.css link)
├── css/
│   ├── theme.css                           (modified -- added --warning, --warning-light)
│   ├── attachments.css                     (NEW -- full attachment styling, ~160 lines)
│   └── ... (unchanged)
├── js/
│   └── chat/
│       ├── chat-core.js                    (modified -- fixed escHtml, overlay ESC dismiss)
│       ├── chat-render.js                  (modified -- full _buildAttachmentHtml rewrite, _formatFileSize)
│       ├── chat-branching.js               (modified -- dead code removal)
│       ├── chat-input.js                   (modified -- removed debug console.log)
│       └── attachments/
│           ├── chat-attachments.js         (modified -- Lucide icons, base64 perf, debug removal, escHtml delegation)
│           ├── chat-attachments-extract.js (modified -- debug removal, officeParser cleanup)
│           └── chat-attachments-setup.js   (modified -- debug removal)
└── ... (unchanged)

tests/
└── unit/
    ├── chat-attachments.test.js            (modified -- icon name assertions)
    ├── chat-render.test.js                 (modified -- escHtml mock fix, attachment DOM assertions, _formatFileSize tests)
    └── edit-removed-attachments.test.js    (modified -- delete 2 test cases, remove dead vars)
```
