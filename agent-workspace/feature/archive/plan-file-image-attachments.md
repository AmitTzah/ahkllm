# Implementation Plan: File & Image Attachment Support

## §1 Overall Project

The LLM AutoHotkey Assistant is an AutoHotkey v2 application providing an LLM chat interface via
WebView2 (Edge). It supports three AI providers (DeepSeek, OpenAI, Google Gemini) through
OpenAI-compatible chat completions endpoints, with SQLite persistence for chat history,
branching message trees, streaming responses, and a hotkey-activated command menu system.

The WebView2 frontend uses vanilla JavaScript with Bootstrap theming, markdown-it for rendering,
and communicates with the AHK backend via `chrome.webview.postMessage()` / `PostWebMessageAsJSON`.
The AHK backend builds cURL commands, writes request/response files to `%TEMP%`, and streams
responses via SSE polling.

## §2 This Feature

Add file and image attachment support throughout the application: drag-drop, paste-from-clipboard,
and browse-from-disk for images (PNG, JPEG, GIF, WebP, BMP), PDF documents, DOCX documents, and
plain text files. Attachments appear as thumbnail/file previews in the chat UI, are stored on
disk with DB references, and are included in LLM API calls using the appropriate format.

**In scope:**
- Drag-and-drop files onto the chat input area
- Clipboard paste detection (images from clipboard) in chat AND command input box
- "📎+" toolbar button to browse files from disk
- Thumbnail previews for images, filename badges for documents/text files
- Inline rendering of image thumbnails in chat message bubbles
- Provider vision-gating: non-vision models get graceful errors
- `includeImageContext` field for commands (screenshot auto-capture via PrintScreen clipboard)
- Client-side JS text extraction for PDF (pdf.js) and DOCX (mammoth.js)
- Attachment files stored on disk in `%APPDATA%\...\attachments\`, referenced by `message_attachments` table
- Per-attachment [×] delete button on sent messages
- Edit copies attachments to new branch message; fork copies attachments

**Out of scope:**
- Audio/video file support
- `.doc` (legacy Word) format — only `.docx`
- File backup/export features
- OCR of image-based PDFs
- File upload to provider file storage APIs

**Key Design Decisions:**
- **No GDI+ dependency**: Use `Send("{PrintScreen}")` + clipboard for screenshot capture. Works on all Windows systems, zero external deps.
- **Two size limits**: Files >50MB on disk rejected. Also, base64-encoded payload >10MB rejected (PostWebMessageAsJSON pipe limit). A ~7.5MB PNG exceeds 10MB after base64 — both limits checked independently.
- **Directory named `attachments/`**: Stores images, PDFs, DOCX, and text files uniformly.
- **Include via `lib/Config.ahk`**: Match existing include architecture pattern.
- **Uniform text extraction**: All PDF/DOCX use client-side text extraction (pdf.js/mammoth.js) and prepend text to message. No provider-specific `type: "file"` API format.
- **Retry preserves attachments**: `buildRequest()` loads attachments from active path's last user message.
- **Fork copies attachments**: `TreeRepo.ForkThread()` calls `AttachmentRepo.CopyForMessage()` for each copied message, physically duplicating disk files with new message IDs.
- **Edit copies attachments**: [`Edit.ahk`](chat/callbacks/Edit.ahk) in branch mode creates a new message row — `AttachmentRepo.CopyForMessage()` carries attachments forward. Overwrite mode preserves same message ID so no copy needed.
- **Per-attachment delete**: Each attachment in a sent message bubble has a [×] button. Clicking sends `deleteAttachment` → `AttachmentRepo.DeleteOne(id)` removes DB row + disk file.
- **Branch switching correct**: Different branches contain different message IDs. `buildStructuredMessagesFromPath()` loads attachments per message ID — switching branches automatically shows correct attachments.

## §3 End State Upon Feature Completion

### User Perspective

**Chat Window Input Area (new DOM elements in index.html):**
```
┌─────────────────────────────────────────────────────────┐
│ [📎+]  🖼️ screenshot.png [×]  📄 report.docx [×]        │  ← #attachment-bar
│ ┌─────────────────────────────────────────────────────┐ │
│ │ What's in this screenshot?                          │ │  ← #chat-input (existing)
│ └─────────────────────────────────────────────────────┘ │
│                                              [Send]     │
└─────────────────────────────────────────────────────────┘
```

- "📎+" button triggers `<input type="file">` with accept filter for images, PDF, DOCX, text files
- Drag-and-drop anywhere on `#chat-input-area` triggers `addAttachment(file)`
- Ctrl+V with image on clipboard captures and adds as attachment
- Each attachment: thumbnail icon + filename + [×] remove
- On send: attachments cleared, payload includes attachment data

**Chat Message Bubbles (User messages with attachments):**
```
┌──────────────────────────────────────────┐
│ You                                      │
│ ┌──────────────────────────────────────┐ │
│ │ 🖼️ [screenshot.png - 245KB]    [×]  │ │  ← clickable thumbnail + per-attachment delete
│ │ ┌──────────────────────────────────┐ │ │
│ │ │     [300px image thumbnail]      │ │ │
│ │ └──────────────────────────────────┘ │ │
│ │ 📄 report.pdf — 2.3KB extracted [×]  │ │  ← click to expand text
│ │ What's in this screenshot?           │ │
│ └──────────────────────────────────────┘ │
│ [✏️] [↩️] [🗑️] [👍👎]                   │
└──────────────────────────────────────────┘
```

**Error States:**
- Non-vision model + image: red banner "Model X does not support vision. Remove images or switch models."
- File >50MB on disk: "File exceeds 50MB limit"
- Base64 payload >10MB: "File too large to send (max ~7.5MB for images)"
- Unsupported type: "File type .exe is not supported"
- Empty PDF/DOCX: "[filename] — no text content extracted"
- Corrupted image: "Could not read image file"
- pdf.js/mammoth.js CDN failure: "Text extraction unavailable — attachment sent as reference only"
- Empty message with attachments only: allowed (implicit "describe this" prompt sent)

**Command System (`UserConfig.ahk`):**
```ahk
{
    commandName: "Analyze Screenshot",
    menuText: "&7 - Analyze Screenshot",
    APIModels: "openai/gpt-5.4",          ; must be vision-capable
    showInputBox: true,
    includeImageContext: true,             ; NEW: auto-capture screenshot
    userMessage: "{{input}}",
    pasteMode: "chat",
}
```

### Technical Perspective

**Data Flow (Chat):**
```
[User drops image on chat input]
  → JS: FileReader → ArrayBuffer → data URL + thumbnail
  → JS: Renders in #attachment-bar
  → [User clicks Send]
  → JS: Checks size limits (50MB file, 10MB base64)
  → JS: postMessage({ action: "chatSend", message: "...", attachments: [
       { type: "image", filename: "shot.png", mimeType: "image/png", base64: "...", size: 245000 }
     ]})
  → AHK (handleChatSend):
     → Save base64→file in attachments/ dir
     → ChatDB.Msg_Insert user message
     → ChatDB.Attachment_Insert for each attachment
     → _BuildAndFireRequest()
  → AHK (buildRequest):
     → Load attachments from last user message in active path (via AttachmentRepo.GetByMessage)
     → For images: add { type: "image_url", image_url: { url: "data:..." } } to content array
     → For docs: prepend extracted text to content
     → Build cURL, fire, stream response
```

**Data Flow (Command with includeImageContext):**
```
[User presses ` → selects command with includeImageContext:true]
  → processInitialRequest():
     → Send("{PrintScreen}") → Sleep 200 → clipboard has bitmap
     → Save clipboard bitmap as PNG to attachments/ dir
     → TextCapture.Capture() for text
     → Template expansion with {{input}}, {{selection}}
     → Create thread + user message with attachment
     → Fire LLM request with image_url in API call
```

**Database Schema (additions):**
```sql
CREATE TABLE message_attachments (
    id TEXT PRIMARY KEY,
    message_id TEXT NOT NULL,
    attachment_type TEXT NOT NULL,   -- 'image', 'pdf', 'docx', 'text_file'
    file_path TEXT NOT NULL,         -- relative: 'attachments/msg_abc123_shot.png'
    mime_type TEXT,
    original_filename TEXT,
    file_size INTEGER,               -- bytes
    extracted_text TEXT,             -- for PDF/DOCX: text extracted client-side
    created_at TEXT DEFAULT (datetime('now')),
    FOREIGN KEY (message_id) REFERENCES messages(id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_attachments_message ON message_attachments(message_id);
```

**File Storage:**
```
%APPDATA%/LLM-AutoHotkey-Assistant/
├── chat_history.db
└── attachments/
    ├── msg_a1b2c3d4_screenshot.png
    ├── msg_e5f6g7h8_report.pdf
    └── msg_i9j0k1l2_document.docx
```

**JS Libraries (CDN, in index.html):**
- `pdf.js` v3.11.174 (Mozilla legacy browser build) — `pdfjsLib.getDocument({data})` + `getTextContent()`
- `mammoth.js` v1.8.0 (browser build) — `mammoth.extractRawText({arrayBuffer})`

**API Format (uniform across providers):**
| Attachment | API Format |
|-----------|-----------|
| Image (vision model) | `{ type: "image_url", image_url: { url: "data:image/png;base64,..." } }` |
| Image (non-vision) | ERROR — refuse to send |
| PDF | Prepended: `[Attached PDF: report.pdf]\n\n...extracted text...` |
| DOCX | Prepended: `[Attached DOCX: report.docx]\n\n...extracted text...` |
| Text file | Prepended: `[Attached: config.ini]\n\`\`\`ini\n...content...\n\`\`\`` |

### Edge Cases & Error States

1. Non-vision model + image → red banner (chat) / tooltip (command)
2. File >50MB on disk → "File exceeds 50MB limit"
3. Base64 payload >10MB → "File too large to send (max ~7.5MB for images)" — separately checked in JS
4. Unsupported type → "File type .exe is not supported"
5. Empty PDF/DOCX → "[filename] — no text content extracted"
6. Corrupted image → "Could not read image file"
7. Clipboard paste, no image → normal text paste
8. Multiple attachments → all processed (max 10)
9. Thread hard delete → cascade: AttachmentRepo.DeleteByThread before raw DELETE FROM messages
10. Thread soft delete/restore → attachments preserved
11. PurgeExpired → iterate threads, call AttachmentRepo.DeleteByThread before raw SQL DELETE
12. Thread fork → AttachmentRepo.CopyForMessage per copied message, physical file duplication
13. Edit branch mode → AttachmentRepo.CopyForMessage to new message ID
14. Edit overwrite mode → same message ID, attachments preserved automatically
15. Retry → attachments loaded from active path's last user message
16. Branch switch → different message IDs per branch, attachments load correctly per message
17. Per-attachment [×] delete → AttachmentRepo.DeleteOne removes DB row + disk file
18. Empty text message with attachments → allowed; implicit prompt sent
19. pdf.js/mammoth.js CDN failure → "Text extraction unavailable. Attachment sent as reference only."

## §4 Implementation Steps

### [ ] Step 1: Database Schema — message_attachments table and AttachmentRepo

**Goal:** Add the `message_attachments` table and full CRUD operations for attachment persistence, including copy, single-delete, and cascade cleanup.

**Actions:**
- Add `message_attachments` table to [`chat/db/ChatDB.ahk`](chat/db/ChatDB.ahk:49) `_CreateSchema()`:
  ```sql
  CREATE TABLE IF NOT EXISTS message_attachments (
      id TEXT PRIMARY KEY, message_id TEXT NOT NULL,
      attachment_type TEXT NOT NULL, file_path TEXT NOT NULL,
      mime_type TEXT, original_filename TEXT, file_size INTEGER,
      extracted_text TEXT, created_at TEXT DEFAULT (datetime('now')),
      FOREIGN KEY (message_id) REFERENCES messages(id) ON DELETE CASCADE
  );
  CREATE INDEX IF NOT EXISTS idx_attachments_message ON message_attachments(message_id);
  ```
- Create [`chat/db/AttachmentRepo.ahk`](chat/db/AttachmentRepo.ahk) with these methods:
  - `AttachmentRepo.Insert(msgId, attObj)` — insert attachment (type, filePath, mime, filename, size, extractedText)
  - `AttachmentRepo.GetByMessage(msgId)` — SELECT * WHERE message_id = msgId
  - `AttachmentRepo.GetByThread(threadId)` — SELECT a.* FROM message_attachments a JOIN messages m ON a.message_id = m.id WHERE m.thread_id = threadId
  - `AttachmentRepo.DeleteByMessage(msgId)` — delete DB rows + delete files from disk for one message. **Must be called BEFORE** the `DELETE FROM messages` that triggers ON DELETE CASCADE.
  - `AttachmentRepo.DeleteByThread(threadId)` — delete DB rows + delete files from disk for all messages in thread
  - `AttachmentRepo.DeleteOne(attachmentId)` — delete single DB row + file from disk (for per-attachment [×] button)
  - `AttachmentRepo.CopyForMessage(sourceMsgId, targetMsgId)` — copy all attachments from source message to target message, physically duplicating disk files with new message ID in filename
- Add facade methods to [`chat/db/ChatDB.ahk`](chat/db/ChatDB.ahk:92): `ChatDB.Attachment_Insert()`, `ChatDB.Attachment_GetByMessage()`, `ChatDB.Attachment_GetByThread()`, `ChatDB.Attachment_DeleteByMessage()`, `ChatDB.Attachment_DeleteByThread()`, `ChatDB.Attachment_DeleteOne()`, `ChatDB.Attachment_CopyForMessage()`
- Add `#Include AttachmentRepo.ahk` to [`chat/db/ChatDB.ahk`](chat/db/ChatDB.ahk:13)
- Update [`chat/db/MessageRepo.ahk`](chat/db/MessageRepo.ahk:46) `HardDelete()`: **before** `DELETE FROM messages` (line 70), call `AttachmentRepo.DeleteByMessage(msgId)` to clean up disk files before the CASCADE deletes DB rows
- Update [`chat/db/ThreadRepo.ahk`](chat/db/ThreadRepo.ahk:97) `Delete()`: call `AttachmentRepo.DeleteByThread(threadId)` **before** the raw `DELETE FROM messages`
- Update [`chat/db/ThreadRepo.ahk`](chat/db/ThreadRepo.ahk:90) `PurgeExpired()`: iterate purged thread IDs, call `AttachmentRepo.DeleteByThread(id)` for each **before** the raw SQL DELETEs (C1 fix)

**Unit Tests to Write/Update:**
- [`tests/unit/ChatDB.test.ahk`](tests/unit/ChatDB.test.ahk): table creation, INSERT, SELECT by message, SELECT by thread, DeleteOne (DB + disk), DeleteByMessage (before DELETE FROM messages ordering), CopyForMessage (physical file duplication with new message ID)

**Integration Tests to Write/Update:**
- None — pure DB layer, unit tests cover CRUD.

**Live Smoke Test:**
1. Run `tests/run_tests.ahk` — all existing + new tests pass
2. `ChatDB.Attachment_Insert()` returns a UUID
3. `ChatDB.Attachment_GetByMessage()` returns correct objects
4. `ChatDB.Attachment_DeleteOne("id")` removes DB row AND file from disk
5. `ChatDB.Attachment_CopyForMessage(srcId, dstId)` duplicates rows AND disk files with new filenames

**Smoke Test Classification:** Model

**Suggested Commit Message:** feat(db): add message_attachments table and AttachmentRepo with cascade cleanup

---

### [ ] Step 2: Attachment Utilities — Vision Gating, MIME Classification, Image File Operations

**Goal:** Create shared utility modules for attachment validation, vision gating, and image file I/O.

**Actions:**
- Create [`shared/ImageUtils.ahk`](shared/ImageUtils.ahk):
  - `ImageUtils.EnsureAttachmentDir()` — creates `%APPDATA%\...\attachments\` if not exists
  - `ImageUtils.SaveBase64ToFile(base64Data, messageId, filename)` — decode base64, write to attachments dir, return file path
  - `ImageUtils.SaveClipboardToFile(messageId)` — read clipboard bitmap, save as PNG to attachments dir, return file path
  - `ImageUtils.DeleteFile(filePath)` — delete file from disk
  - `ImageUtils.CopyFile(srcPath, destMsgId)` — copy file to new path with dest messageId in filename
- Create [`shared/AttachmentUtils.ahk`](shared/AttachmentUtils.ahk):
  - `AttachmentUtils.HasVision(modelName)` — check `models[modelName].vision`; default false
  - `AttachmentUtils.ValidateAttachments(attachments, modelName)` — check images only allowed if vision=true; return error array
  - `AttachmentUtils.IsImageMime(mime)` — image/* check
  - `AttachmentUtils.IsPDFMime(mime)` — application/pdf
  - `AttachmentUtils.IsDOCXMime(mime)` — application/vnd.openxmlformats-officedocument.wordprocessingml.document
  - `AttachmentUtils.GetAttachmentType(mime)` — map mime → 'image'|'pdf'|'docx'|'text_file'
  - `AttachmentUtils.IsAllowedTextFile(filename)` — check extension against allowed list
  - `AttachmentUtils.SanitizeFilename(name)` — remove path traversal chars, limit length
  - `AttachmentUtils.EstimateImageTokens(base64Length)` — rough token estimate for vision
- Add `#Include shared\ImageUtils.ahk` and `#Include shared\AttachmentUtils.ahk` to [`lib/Config.ahk`](lib/Config.ahk) (after existing shared includes)
- Update [`UserConfig.ahk`](UserConfig.ahk:157) §5: document `includeImageContext` field in the command field reference comments

**Unit Tests to Write/Update:**
- New [`tests/unit/AttachmentUtils.test.ahk`](tests/unit/AttachmentUtils.test.ahk): vision gating, mime classification, filename sanitization, token estimation
- [`tests/unit/UserConfig.test.ahk`](tests/unit/UserConfig.test.ahk): verify `includeImageContext` field documentation is parseable

**Integration Tests to Write/Update:**
- None — pure utility functions.

**Live Smoke Test:**
1. `tests/run_tests.ahk` — all pass
2. `ImageUtils.EnsureAttachmentDir()` creates `attachments/` directory
3. `AttachmentUtils.HasVision("openai/gpt-5.4")` → `true`
4. `AttachmentUtils.HasVision("deepseek/deepseek-v4-pro")` → `false` (current config)
5. `AttachmentUtils.ValidateAttachments([{type:"image"}], "deepseek/deepseek-v4-pro")` → error "model does not support vision"
6. `AttachmentUtils.SanitizeFilename("..\\..\\evil.png")` → `evil.png`

**Smoke Test Classification:** Model

**Suggested Commit Message:** feat(shared): add ImageUtils, AttachmentUtils with vision gating and file I/O

---

### [ ] Step 3: WebUI — Attachment Bar DOM, CSS, and JS Libraries

**Goal:** Add the attachment bar HTML elements, CSS styles, pdf.js/mammoth.js CDN scripts, and create the attachment processing JS module.

**Actions:**
- Update [`webui/index.html`](webui/index.html):
  - Add CDN scripts before chat modules (after line 168):
    ```html
    <script src="https://cdnjs.cloudflare.com/ajax/libs/pdf.js/3.11.174/pdf.min.js"></script>
    <script src="https://cdn.jsdelivr.net/npm/mammoth@1.8.0/mammoth.browser.min.js"></script>
    ```
  - Add attachment bar HTML inside `#chat-input-area` (after `#chat-input`, before `#chat-send-btn`, around line 93):
    ```html
    <div id="attachment-bar" style="display:none;"></div>
    <input type="file" id="attachment-file-input" accept="image/*,.pdf,.docx,.txt,.md,.py,.js,.json,.xml,.csv,.ini,.cfg,.yaml,.yml,.log,.html,.css,.sql,.bat,.ps1,.sh,.java,.c,.cpp,.h,.rs,.go,.ts,.tsx,.jsx,.toml" multiple style="display:none;">
    <button type="button" id="attachment-browse-btn" title="Attach files">📎+</button>
    ```
  - Add `<link rel="stylesheet" href="./css/chat/chat-attachments.css">` in the CSS section (after line 36)
  - Add `<script src="./js/chat/chat-attachments.js"></script>` in load order (before `chat-input.js`, around line 199)
- Create [`webui/css/chat/chat-attachments.css`](webui/css/chat/chat-attachments.css):
  - `#attachment-bar` — flex row, wraps, padding, border-top
  - `.attachment-item` — thumbnail/file badge with remove button
  - `.attachment-thumb` — image thumbnail (48px, border-radius)
  - `.attachment-file-badge` — document icon + filename
  - `.attachment-remove` — [×] button, absolute positioned
  - `.attachment-loading` — spinner for text extraction
  - Dark/light theme via CSS variables
- Create [`webui/js/chat/chat-attachments.js`](webui/js/chat/chat-attachments.js):
  - State: `attachmentState = []` — `{ type, filename, mimeType, base64, size, extractedText }`
  - `addAttachment(file)` — check 50MB file limit, FileReader → classify → render thumbnail/badge → extract text for PDF/DOCX
  - `addAttachmentFromClipboard(e)` — paste handler: detect image, get from clipboard as blob, add
  - `removeAttachment(index)` — splice state, re-render bar
  - `renderAttachmentBar()` — build DOM for `#attachment-bar` from state
  - `extractPDFText(arrayBuffer)` — pdf.js: `getDocument()` → iterate pages → `getTextContent()` → join. On failure: set `extractedText: null`, show "extraction unavailable" badge.
  - `extractDOCXText(arrayBuffer)` — mammoth.js: `extractRawText()` → resolve text. On failure: same as PDF.
  - `getAttachmentsForSend()` — check 10MB base64 limit, return serializable array for postMessage
  - `clearAttachments()` — reset state + hide bar
  - `setupAttachmentDropZone()` — dragenter/dragover/drop on `#chat-input-area`
  - `setupAttachmentPaste()` — paste listener on `#chat-input`
  - `setupAttachmentBrowse()` — click `#attachment-browse-btn` → click `#attachment-file-input` → onchange
  - Constants: `ALLOWED_EXTENSIONS`, `MAX_FILE_SIZE = 50 * 1024 * 1024`, `MAX_BASE64_SIZE = 10 * 1024 * 1024`

**Unit Tests to Write/Update:**
- None — JS module tested via smoke test.

**Integration Tests to Write/Update:**
- None — UI-only.

**Live Smoke Test:**
1. Open chat, drag image onto input area → thumbnail appears in attachment bar
2. Drag PDF → "📄 filename.pdf" badge with loading spinner → text extracted
3. Drag DOCX → badge with extracted text
4. Drag .txt → badge appears
5. Click "📎+" → browse → select file → appears in bar
6. Click [×] → attachment removed
7. Ctrl+V with image on clipboard → thumbnail appears
8. Drag .exe → error "File type not supported"
9. Drag >50MB file → error "File exceeds 50MB limit"

**Smoke Test Classification:** Human

**Suggested Commit Message:** feat(webui): add attachment bar, pdf.js/mammoth.js, drag-drop/paste/browse UI

---

### [ ] Step 4: Chat Send Pipeline — JS → AHK → DB → API

**Goal:** Wire attachments end-to-end: JS send → AHK processing → DB persistence → API request → response. Includes edit attachment copying and per-attachment delete.

**Actions:**
- Update [`webui/js/chat/chat-input.js`](webui/js/chat/chat-input.js:5) `onChatSend()`:
  - Get attachments from `getAttachmentsForSend()` (checks 10MB base64 limit)
  - Allow empty text when attachments present (send implicit prompt if needed)
  - Include `attachments` in the payload: `{ action: "chatSend", message: "...", attachments: [...] }`
  - After send: `clearAttachments()`
- Update [`chat/callbacks/Message.ahk`](chat/callbacks/Message.ahk:14) `handleChatSend()`:
  - Accept `attachments` array from parsed message
  - Allow empty `message` text if attachments present (M2 fix)
  - For each attachment: save base64 to disk via `ImageUtils.SaveBase64ToFile()`
  - After `ChatDB.Msg_Insert()`: call `ChatDB.Attachment_Insert()` for each attachment
  - When building structured messages: include attachment metadata (via updated `buildStructuredMessagesFromPath`)
- Update [`chat/ChatUtils.ahk`](chat/ChatUtils.ahk) `buildStructuredMessagesFromPath()`:
  - **Batch approach** (H1 fix): call `ChatDB.Attachment_GetByThread(threadId)` once at the top, index by `message_id`, then attach in the loop per message
  - Include in each message object: `attachments` array (metadata only — no base64 for rendering)
  - Thread ID extracted from first message's `thread_id` field
- Create handler in [`chat/callbacks/Message.ahk`](chat/callbacks/Message.ahk): `handleDeleteAttachment(params)`:
  - Call `ChatDB.Attachment_DeleteOne(params.id)` — removes DB row + disk file
  - Re-render the current thread via `postWebMessage("updateChatView", ...)`
- Update [`chat/callbacks/Dispatch.ahk`](chat/callbacks/Dispatch.ahk:15) `OnWebMessageReceived()`:
  - Add `deleteAttachment` case → routes to `handleDeleteAttachment(parsed)`
- Update [`chat/callbacks/Edit.ahk`](chat/callbacks/Edit.ahk) `handleEdit()` (H4 fix):
  - In **branch mode**: after `ChatDB.Msg_Insert()` for the new message, call `ChatDB.Attachment_CopyForMessage(oldMsgId, newMsgId)`
  - In **overwrite mode**: same message ID, attachments preserved automatically — no copy needed
- Update [`chat/ChatIPC.ahk`](chat/ChatIPC.ahk:38) `LoadThreadIntoUI()`:
  - Uses `buildStructuredMessagesFromPath()` which now includes attachments
- Update [`chat/ChatRequestBuilder.ahk`](chat/ChatRequestBuilder.ahk:15) `buildRequest()`:
  - After loading active path (line 38), get the last user message's attachments via `ChatDB.Attachment_GetByMessage()`
  - If image attachments and model lacks vision: return error
  - Convert the LAST user message's content:
    - Images present: replace `{ role: "user", content: "text" }` with `{ role: "user", content: [image parts..., { type: "text", text: "user text" }] }`
    - Docs/text files: prepend extracted text to the text content string
    - Messages earlier in path keep plain `{ role, content: "string" }` format
  - System override logic (lines 44-58): only applies text override to the system message — content arrays on user messages are untouched

**Unit Tests to Write/Update:**
- [`tests/unit/ChatRequestBuilder.test.ahk`](tests/unit/ChatRequestBuilder.test.ahk): image attachments produce correct content array, PDF attachments prepend text, non-vision model + image returns error, content array + text-only messages coexist
- [`tests/unit/ChatUtils.test.ahk`](tests/unit/ChatUtils.test.ahk): `buildStructuredMessagesFromPath` includes attachments via batch query

**Integration Tests to Write/Update:**
- [`tests/integration/ChatFlow.test.ahk`](tests/integration/ChatFlow.test.ahk): create thread with attachments, verify persistence, verify request built correctly, verify edit copies attachments in branch mode

**Live Smoke Test:**
1. Open chat, drag image, type message, click Send → loading → streaming response about image content
2. Verify: user bubble shows image thumbnail with [×] button
3. Click [×] on the attachment → attachment disappears from message bubble
4. Edit a message with attachments (branch mode) → new branch shows same attachments
5. Retry an assistant response to a message with attachments → image re-sent in API call
6. Switch to another thread, switch back → image still there
7. Delete the message → attachment file removed from disk
8. Send with attachments only (empty text) → message sent successfully
9. `tests/run_tests.ahk` — all pass

**Smoke Test Classification:** Human

**Suggested Commit Message:** feat(chat): wire end-to-end attachment pipeline with edit copy and per-attachment delete

---

### [ ] Step 5: Attachment Rendering in Chat Message Bubbles

**Goal:** Render image thumbnails and file badges in user message bubbles when viewing history, with per-attachment [×] delete buttons.

**Actions:**
- Update [`webui/js/chat/chat-render.js`](webui/js/chat/chat-render.js:93) `createMessageBubble()`:
  - After label, before content: if `msg.attachments` array exists, render attachment previews
  - For images: `<img>` thumbnail (max 300px, click to expand) with filename + size + [×] delete button
  - For PDF/DOCX: file icon + filename + collapsible extracted text + [×] delete button
  - For text files: file icon + filename + [×] delete button
  - [×] button sends `{ action: "deleteAttachment", id: attachmentId }` via `postMessage`
- Update [`webui/css/chat/chat-attachments.css`](webui/css/chat/chat-attachments.css) add message-bubble styles:
  - `.msg-attachment-image` — thumbnail wrapper, hover effect, click-to-expand cursor
  - `.msg-attachment-file` — document badge with icon
  - `.msg-attachment-text-preview` — collapsible pre block for extracted text
  - `.msg-attachment-delete` — [×] button on each attachment in message bubble

**Unit Tests to Write/Update:**
- None — rendering tested visually.

**Integration Tests to Write/Update:**
- None — rendering tested via smoke test.

**Live Smoke Test:**
1. Load existing thread with image attachment → thumbnail renders with [×] button
2. Load thread with PDF → file badge + click to see extracted text + [×] button
3. Load thread with text file → file badge visible + [×] button
4. Click image thumbnail → expands to full size
5. Verify dark mode: attachment styles match theme

**Smoke Test Classification:** Human

**Suggested Commit Message:** feat(webui): render attachment previews with per-attachment delete in chat bubbles

---

### [ ] Step 6: Command System — includeImageContext and Fork Support

**Goal:** Enable `includeImageContext` for commands (PrintScreen + clipboard), add fork attachment copying, and handle input box paste.

**Actions:**
- Update [`app/RequestProcessor.ahk`](app/RequestProcessor.ahk):
  - In `processInitialRequest()`: check `cmd.includeImageContext`
  - If true: `Send("{PrintScreen}")` → `Sleep 200` → `ImageUtils.SaveClipboardToFile(messageId)` → PNG saved to attachments/
  - Vision gate: if model lacks vision → tooltip error near cursor, abort
  - Create attachment via `ChatDB.Attachment_Insert()` after message insert
- Update [`chat/db/TreeRepo.ahk`](chat/db/TreeRepo.ahk) `ForkThread()` (H3 fix):
  - After copying messages (with new UUIDs): for each (oldId, newId) pair, call `ChatDB.Attachment_CopyForMessage(oldId, newId)`
  - This copies DB rows AND physically duplicates disk files with new message IDs in filenames
- Update [`app/InputWindow.ahk`](app/InputWindow.ahk):
  - Add paste handler: detect clipboard image → save to temp → show "📎 Image attached" indicator
  - Pass saved image path to `processInitialRequest()` via shared variable or temp file

**Unit Tests to Write/Update:**
- [`tests/unit/RequestProcessor.test.ahk`](tests/unit/RequestProcessor.test.ahk): `includeImageContext` triggers PrintScreen+clipboard save, vision gate blocks non-vision models

**Integration Tests to Write/Update:**
- [`tests/integration/BranchFlow.test.ahk`](tests/integration/BranchFlow.test.ahk): fork a thread with attachments → verify attachments copied to new thread with physical files

**Live Smoke Test:**
1. Configure command with `includeImageContext: true` + vision model → trigger → screenshot captured, chat opens, assistant responds about screenshot
2. Same command with non-vision model → tooltip error near cursor
3. Fork a thread with image attachments → forked thread shows same image thumbnails
4. `tests/run_tests.ahk` — all pass

**Smoke Test Classification:** Human

**Suggested Commit Message:** feat(commands): add includeImageContext screenshot capture and fork attachment copying

---

### [ ] Step 7: Polish — Error Handling, CSS, and Edge Cases

**Goal:** Comprehensive error handling, responsive CSS theming, edge case hardening.

**Actions:**
- Update [`webui/js/chat/chat-attachments.js`](webui/js/chat/chat-attachments.js):
  - Loading spinner during PDF/DOCX extraction
  - Graceful handling when pdf.js/mammoth.js fail to load (CDN error) → show "Text extraction unavailable" badge, still allow send
  - Clear error messages for each failure mode (size, type, corruption, base64 limit)
  - Both size limit checks: 50MB file before reading, 10MB base64 before sending
- Update [`webui/css/chat/chat-attachments.css`](webui/css/chat/chat-attachments.css):
  - Responsive wrap on narrow windows
  - Dark/light theme variable usage for all colors
  - Polish thumbnail hover effects, transition animations
- Update [`chat/callbacks/Message.ahk`](chat/callbacks/Message.ahk:14):
  - Sanitize filenames before saving (`AttachmentUtils.SanitizeFilename`)
  - Handle duplicate filenames (append counter before extension)
- Update [`chat/ChatRequestBuilder.ahk`](chat/ChatRequestBuilder.ahk:15):
  - Token estimation warning if context window near limit with images
  - Error message formatting for vision gate failures
- Limit attachments to 10 per message (enforce in JS and AHK)
- Update [`shared/AttachmentUtils.ahk`](shared/AttachmentUtils.ahk) edge case handling for missing models config

**Unit Tests to Write/Update:**
- [`tests/unit/AttachmentUtils.test.ahk`](tests/unit/AttachmentUtils.test.ahk): filename sanitization edge cases, token estimation

**Integration Tests to Write/Update:**
- None.

**Live Smoke Test:**
1. Dark mode toggle → attachment bar + thumbnails + file badges match theme
2. Corrupted image file → "Could not read image file"
3. >50MB file → "File exceeds 50MB limit"
4. Base64 >10MB → "File too large to send"
5. Unsupported file type → clear error
6. Filename with `../` → sanitized safely
7. 5 images in one message → all sent and rendered
8. Rapid send before extraction completes → loading state handled
9. CDN blocked (simulate) → "Text extraction unavailable" shown, send still works
10. `tests/run_tests.ahk` — all pass

**Smoke Test Classification:** Human

**Suggested Commit Message:** feat(attachments): polish error handling, CSS theming, and edge case hardening

---

## §5 Final Directory Tree

```
ai-automation/
├── Main.ahk                                (unchanged)
├── UserConfig.ahk                          (modified — includeImageContext field documentation)
├── lib/
│   └── Config.ahk                          (modified — #Include ImageUtils, AttachmentUtils)
├── shared/
│   ├── ImageUtils.ahk                      (new — base64 save, clipboard capture, file copy/delete)
│   ├── AttachmentUtils.ahk                 (new — vision gating, mime classification, validation)
│   ├── ModelParser.ahk                     (unchanged)
│   ├── TokenEstimation.ahk                 (unchanged)
│   └── DebugLog.ahk                        (unchanged)
├── app/
│   ├── RequestProcessor.ahk                (modified — includeImageContext via PrintScreen+clipboard)
│   └── InputWindow.ahk                     (modified — image paste indicator)
├── chat/
│   ├── ChatIPC.ahk                         (modified — attachments in LoadThreadIntoUI)
│   ├── ChatRequestBuilder.ahk              (modified — attachment integration in buildRequest)
│   ├── ChatUtils.ahk                       (modified — buildStructuredMessagesFromPath batch attachment loading)
│   ├── callbacks/
│   │   ├── Dispatch.ahk                    (modified — deleteAttachment action)
│   │   ├── Message.ahk                     (modified — attachment processing, deleteAttachment handler)
│   │   └── Edit.ahk                        (modified — branch-mode attachment CopyForMessage)
│   ├── streaming/
│   │   └── StreamHandler.ahk               (unchanged)
│   └── db/
│       ├── ChatDB.ahk                      (modified — AttachmentRepo include + all facade methods)
│       ├── AttachmentRepo.ahk              (new — Insert, GetByMessage, GetByThread, DeleteByMessage, DeleteByThread, DeleteOne, CopyForMessage)
│       ├── MessageRepo.ahk                 (modified — HardDelete calls AttachmentRepo.DeleteByMessage BEFORE raw DELETE)
│       ├── ThreadRepo.ahk                  (modified — Delete/PurgeExpired call AttachmentRepo.DeleteByThread BEFORE raw SQL)
│       ├── TreeRepo.ahk                    (modified — ForkThread copies attachments via CopyForMessage)
│       └── AssistantRepo.ahk               (unchanged)
├── webui/
│   ├── index.html                          (modified — pdf.js + mammoth.js CDN, attachment bar HTML, CSS link, JS include)
│   ├── css/
│   │   └── chat/
│   │       └── chat-attachments.css        (new — attachment bar, thumbnails, file badges, themes, delete buttons)
│   └── js/
│       └── chat/
│           ├── chat-attachments.js         (new — drag-drop, paste, browse, pdf.js/mammoth.js, size limits)
│           ├── chat-input.js               (modified — include attachments in chatSend, allow empty+attachments)
│           ├── chat-render.js              (modified — render attachment previews + [×] delete in bubbles)
│           └── chat-core.js                (unchanged)
├── tests/
│   ├── unit/
│   │   ├── AttachmentUtils.test.ahk        (new — vision gating, mime classification, sanitization)
│   │   ├── ChatRequestBuilder.test.ahk     (modified — attachment request building tests)
│   │   ├── ChatDB.test.ahk                 (modified — message_attachments CRUD, CopyForMessage, DeleteOne)
│   │   ├── ChatUtils.test.ahk              (modified — structured messages with batch attachment loading)
│   │   ├── RequestProcessor.test.ahk       (modified — includeImageContext tests)
│   │   └── UserConfig.test.ahk             (modified — includeImageContext field validation)
│   └── integration/
│       ├── ChatFlow.test.ahk               (modified — attachment flow + edit copy integration test)
│       └── BranchFlow.test.ahk             (modified — fork copies attachments integration test)
└── agent-workspace/
    └── feature/
        ├── plan.md                         (this file)
        ├── reference.md
        └── state.json
```
