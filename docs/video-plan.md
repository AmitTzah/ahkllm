# Video Production Plan

Goal: a README that works as a guided tour of AhkLLM. The landing page leads
with the Windows command integration (the real differentiator), every video is
a self-contained mini-guide with burned-in step captions, and the whole set is
produced automatically after two one-time approvals.

## Narrative

The app is a command layer for Windows, not a chat client. Select text in any
app, press the backtick key, pick a command, and the result comes back where
you are. The chat window is the escape hatch, so the hero video leads with
commands and ends by revealing chat.

Hero arc:

1. A real document with a selected paragraph.
2. Backtick opens the command menu over the selection.
3. Rephrase in Context rewrites the text in place.
4. Cursor mid-line, backtick, FIM Continue appends.
5. Another selection, backtick, Summarize. This is a chat-mode command, so the
   chat window opens and the reply streams in.
6. Short hold on the chat window.

Important accuracy note: the "1 - Open Chat" menu shortcut only opens the chat
window at the last active thread. It does not send anything. Streaming a reply
requires a chat-mode command (Summarize, Translate, Explain, Quick Ask, or a
model shortcut) or typing in the chat input. The hero uses Summarize for the
streaming beat; Open Chat is mentioned in the commands-chat guide and Quick
Start, never presented as something that streams.

## Verified app behaviors (refresh before scripting)

- `pasteMode` values: `chat`, `replace`, `append`.
- Default commands by output mode:
  - chat (stream into chat window): Summarize, Translate to English, Explain,
    Quick Ask, Screenshot, and the DeepSeek / GPT / Gemini shortcuts.
  - replace: FIM Fill, Rephrase in Context, Refine, Auto-paste custom command.
  - append: FIM Continue.
- A chat-mode command creates a new thread, inserts the captured selection as a
  user message, opens the chat window, and triggers the LLM (RequestProcessor).
  The response streams into that thread.
- Replace/append commands are non-stream: the app calls the API, parses the
  JSON response, and pastes the text into the foreground app via the clipboard.
- FIM uses the provider's FIM endpoint (`/beta/completions` for DeepSeek).
  Request shape: `{ model, prompt, suffix?, max_tokens }`. Response shape:
  `choices[0].text`. FIM Fill works with or without a selection (cursor is a
  zero-width gap). FIM Continue appends at the cursor.
- Text capture uses UIA (UI Automation) with full-document context
  (`{{fullText}}`) and a clipboard fallback.
- Menu structure: "1 - Open Chat" first (when `chatShortcut` is set), then
  commands (tagged submenus + direct accelerators), then Quick Access.
- Default hotkeys: backtick (menu), Ctrl+Alt+R (reload), Ctrl+W (close),
  CapsLock+backtick (suspend).
- Mock server must support three response modes:
  - SSE chat (`/v1/chat/completions` with `stream: true`).
  - JSON chat for replace/append (`choices[0].message.content`).
  - JSON FIM (`/beta/completions`, `choices[0].text`).

Spike result (2026-08-05): direct-spawned `curl.exe` receives responses from a
local Node mock in this session for JSON chat, SSE, and FIM. The old harness
warning about "0 bytes back" for non-stream requests does not reproduce here.
Still, the pipeline includes a full end-to-end re-verify of a replace command
before shooting those scenes.

## Toolchain

Decision: ffmpeg (static build) + Node CDP driver + AHK probes + local mock.

- Capture: ffmpeg `gdigrab` records the screen region at 30fps and includes the
  real OS cursor. No custom screen recorder is needed.
- Captions: a caption timeline JSON is compiled to an ASS subtitle file, and
  ffmpeg's `subtitles` filter burns it in during encoding. ASS gives
  professional styling (position, background box, font) and exact timing.
- Encode: H.264 MP4 (`libx264`, crf 18, `yuv420p`) for broad compatibility.
- WebView actions: the existing headless harness CDP client (click, type,
  scroll, waits) drives the chat, tree, dashboard, and settings.
- Native actions: AHK probes handle mouse movement, clicks, the backtick
  hotkey, Notepad setup and text selection, and native menu clicks.
- Mock LLM: per-scene response texts, deterministic for every take.

Rejected alternatives and why:

- OBS: interactive and not cleanly scriptable from a CLI.
- Windows.Graphics.Capture: shows a system picker, which needs user input.
- Browser MediaRecorder (VP9 WebM): works, but WebM-only, more fragile timing,
  and no gdigrab-style native capture.
- Custom C# BitBlt recorder: superseded by ffmpeg `gdigrab`.
- GIF: wrong frame rate for smooth cursor motion and no caption rendering.

## Approvals and environment

- Download a static ffmpeg build (~100MB) into `.tools/ffmpeg` (gitignored).
- Consent for on-screen recording: the app and Notepad are visible on the
  desktop while each scene records (roughly 1-2 minutes per video). The runs
  are scripted; the user does nothing.
- Requirements: interactive Windows session, AutoHotkey v2, Node 22+, WebView2.
- The app must not already be running (`#SingleInstance`).

## Video manifest

All videos: 1600x900 region, 30fps, H.264 MP4, under 50MB each, in
`docs/videos/`. Posters in `docs/screenshots/`.

| File | Context | Beats | Captions (steps) | Duration |
|---|---|---|---|---|
| hero.mp4 | Notepad + chat | select text, menu, in-place rewrite, FIM append, Summarize streams into chat, hold | "Select any text, in any app" / "One keystroke" / "Rewritten, right where you are" / "Or just keep typing" / "Commands can answer in the chat window too" | 30-40s |
| commands-replace.mp4 | Notepad | Rephrase in Context on a selection, full-document context | numbered steps: select, press backtick, pick command, text is replaced | ~30s |
| commands-append-fim.mp4 | Notepad (code-style text) | FIM Continue at cursor, FIM Fill in a gap | "No selection needed" / "Continues at the cursor" / "Fills the gap" | ~35s |
| commands-chat.mp4 | Chat | Summarize streams into chat; backtick then 1 reopens the last thread (no stream, shown accurately) | steps for chat-mode commands | ~30s |
| branch-navigation.mp4 | Chat | retry forks a branch, tree shows both, click a branch, chat snaps | "Retry creates a new branch" / "The tree shows every path" / "Click to jump back" | ~25s |
| screens.mp4 | App | chat, tree, dashboard, settings tour | per-screen label | ~35s |

README placement:

- hero.mp4 directly under the tagline, width 720.
- The other five in "Watch it in action", each under its own h3, width 640,
  with a one-line description and a poster frame.

## Production pipeline

Per-video scene runner (Node):

1. Start mock server in the scene's mode.
2. Launch the app with an isolated profile (existing harness machinery).
3. Position the app window on-screen at fixed coordinates (100, 60,
   1600x900) so gdigrab captures exactly that region.
4. Run the scene: a list of steps, each a wait, a CDP action, or an AHK probe.
   Every step records a caption timestamp.
5. Record with ffmpeg `gdigrab` at 30fps throughout.
6. Encode: compile the caption timeline to ASS, apply the `subtitles` filter,
   encode H.264 MP4.
7. Multi-clip scenes (hero) are recorded as separate takes and concatenated
   with the concat demuxer, then captioned.

Mouse driver (AHK probe):

- `SetCursorPos` in a loop at ~120Hz while the recorder samples at 30fps.
- Eased paths: ease-in-out quintic, a slight bezier curve, micro-jitter, and a
  200-400ms dwell before clicks.
- Real clicks via `SendInput`, so hover and pressed states appear in the video.
- Backtick hotkey sent with the cursor positioned over the target.

Mock modes:

- `sse-chat`: slow streamed reasoning + content chunks.
- `json-chat`: instant JSON response for replace/append commands.
- `json-fim`: instant FIM response for `/beta/completions`.
- Per-scene response text, so the pasted results are deterministic.

## Final README layout

Professional GitHub landing page rules:

- Centered header block: title, badges, tagline.
- Hero video immediately below the tagline, width 720, poster frame.
- Two short pitch paragraphs, commands-first.
- "What you get": bullets in command-first order (in-app commands, in-place
  rewrite, FIM, command menu, models, chat window, branching, files,
  organization, costs).
- "Watch it in action": one h3 per video, video (width 640) + poster + one
  sentence. Consistent sizing, centered, blank lines between blocks.
- Quick Start, Configuration, Where your data lives, Running Tests,
  Architecture, License.
- No em dashes anywhere. Consistent widths. Posters everywhere so VS Code's
  preview (which does not play `<video>` tags) still shows a still frame.

## Repo layout

```
docs/
  video-plan.md
  videos/
    hero.mp4
    commands-replace.mp4
    commands-append-fim.mp4
    commands-chat.mp4
    branch-navigation.mp4
    screens.mp4
  screenshots/            # posters + stills
scripts/videos/           # scene runner + captions + encode (thin layer over tests/headless)
.tools/ffmpeg/            # gitignored
```

## Milestones

1. Approvals: ffmpeg download, on-screen recording consent.
2. Spike: one replace command end-to-end against the mock, in the real app.
3. Infrastructure: gdigrab runner, ASS caption generator, mouse probe, mock
   modes.
4. First cuts: hero, commands-chat, branch-navigation.
5. Native scenes: commands-replace, commands-append-fim, screens.
6. Final README pass and review loop.

Acceptance: the user watches all six videos; no factual inaccuracies; README
looks professional; every video regenerable with one command.

## Risks and mitigations

- gdigrab throughput at 1600x900: if it cannot hold 30fps, drop to 24fps or a
  1280x720 region.
- Non-stream inline requests: direct cURL spike passed; re-verify in-app. If it
  fails, debug the app's cURL output-file path or fall back to a real API key
  for those scenes.
- Windows 11 Notepad window handle quirks (the earlier capture attempt could
  not get `MainWindowHandle`): mitigate by activating via title pattern and
  driving selection with SendInput rather than the process handle.
- Repo media footprint (~60-90MB): acceptable on GitHub; each file stays under
  50MB to avoid warnings.
