# Locked Chats (password-protected conversations)

AhkLLM lets you protect individual chats with a password. A locked chat shows a
lock icon and a generic **"Locked chat"** title in the sidebar, refuses to load
until unlocked, is excluded from global search, and can't be edited, deleted, or
streamed into while locked.

## What this protects (and what it does not)

This is a **Tier-1 app-level lock**, not encryption at rest:

- **Protected:** another person opening the app on your Windows session, shoulder
  surfers, accidental navigation, global search, the API logs viewer (locked-chat
  request/response bodies are stored as `"<hidden: locked chat>"`), and every
  non-UI load path (`WM_LOAD_THREAD`, command-line argument, sidebar click).
- **Not protected:** anyone who copies `%APPDATA%\AhkLLM\chat_history.db` (or the
  `attachments\` folder) can still read the plaintext content. Malware running as
  your Windows user can also read process memory. Real confidentiality at rest
  (per-chat AES-GCM, Tier 2) is a separate follow-up and is intentionally not
  bundled into this change.

## How the password is handled

The raw password **never** touches AutoHotkey or the database:

1. You type the password into the WebView.
2. The page derives a PBKDF2-SHA-256 hash (600,000 iterations, 16-byte random
   salt, 256-bit output) using Web Crypto.
3. Only the derived hash crosses the IPC boundary; AutoHotkey compares it
   constant-time against the stored hash and keeps an in-memory "unlocked this
   session" set.
4. Five failed attempts trigger a 30-second cooldown per chat.

The unlock decision is enforced in AutoHotkey (never trusted to the WebView), so
an XSS or a direct IPC call cannot unlock a chat without the password.

## Usage

1. **Lock a chat:** hover a chat in the sidebar, open the lock menu, and pick
   **Lock Chat** → enter a password (minimum 4 characters) + confirmation.
2. **Open a locked chat:** click it (or lock menu → **Unlock Chat**) and enter the
   password. Unlock lasts for the lifetime of the chat window process (switch
   chats freely; it stays unlocked) and restores the real chat title, so
   renaming works again.
3. **Lock options menu:** the lock icon on any chat opens a menu with **Lock Chat**
   (relocks immediately once a password exists — the chat locks quietly, its
   content clears, and no prompt pops up; the password prompt only appears when
   you open the chat again), **Unlock Chat**, and **Change password / remove
   lock**. Options that do not apply to the chat's current state are greyed out.
4. **Leave the password prompt:** press **Escape**, click the **×**, or click
   **Cancel** — the app returns to the empty state without opening the chat.
5. **Change / remove the password:** lock menu → **Change password / remove lock**,
   enter the current password, then set a new one or press **Remove password**.

A forgotten password cannot be recovered from the UI. Because Tier 1 does not
encrypt content, an admin can remove a forgotten lock by deleting the row from
the `chat_locks` table and setting `chat_threads.is_locked = 0` in
`chat_history.db` (close the app first).

## Database

Migration v7 (automatic, versioned via `PRAGMA user_version`):

- `chat_threads.is_locked INTEGER DEFAULT 0`
- New table `chat_locks (thread_id PK REFERENCES chat_threads ON DELETE CASCADE,
  kdf, salt, hash, iterations, created_at, updated_at)`

Locked threads are excluded from FTS5, LIKE, and title search; their sidebar and
trash titles are redacted to "Locked chat"; deleting them requires the password.

## Headless verification

```powershell
node tests/headless/e2e-suite.js --scenarios=235,236,237,238,239,240,241,242,243,244,245
node tests/headless/e2e-suite.js --check-sync
npm run test:fast
```
