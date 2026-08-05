<h1 align="center">AhkLLM</h1>

<p align="center">
  <a href="#requirements"><img src="https://img.shields.io/badge/Windows-10%2B-0078D6" alt="Windows"></a>
  <a href="https://www.autohotkey.com/"><img src="https://img.shields.io/badge/AutoHotkey-v2.0.18%2B-5e81ac" alt="AutoHotkey"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-GPL--3.0-blue" alt="License: GPL-3.0"></a>
</p>

<p align="center"><b>The AI assistant that's one keystroke away on Windows.</b></p>

Select text in any app, press `` ` ``, and pick from a menu of commands. Explain a diff, translate a paragraph, rewrite an email, or keep typing and let AhkLLM pick up where you left off. You can also just open the chat window and talk. You never leave the app you're in.

AhkLLM runs natively on Windows via AutoHotkey v2 with a WebView2 chat UI. It sits quietly in your system tray and preloads the chat window in the background, so it's ready the instant you hit the key.

| What it is | What it isn't |
|---|---|
| One keystroke away, in any app | A wrapper around a website |
| Direct API calls with your own keys | A relay that skims your tokens |
| Native Windows, light on resources | An Electron app that eats RAM |
| Local chat history in SQLite | A cloud service that owns your data |
| Keyboard-first by design | A tool that needs a mouse |

## What you get

- **A command menu you can shape.** Each command is a small config entry with its own model, prompt, thinking level, and output mode. The defaults cover summarize, translate, explain, refine, rephrase in context, FIM fill, and FIM continue. Add your own in `DefaultSettings.ahk` and it shows up in the menu, no code changes needed.
- **Rewrite or rephrase in place.** AhkLLM reads your selection through UI Automation, and when a command asks for it, the whole document around it. "Rephrase in Context" rewrites the highlighted text with the full page as context and drops the result back over the selection. You stay in the same app the whole time.
- **Keep typing, it takes over.** FIM Continue and FIM Fill use DeepSeek's coding endpoint, but they're not just for code. Put your cursor mid-line, trigger the command, and the model continues your sentence, your paragraph, or your function. No selection needed.
- **A real chat window.** Streaming responses, markdown with syntax highlighting and math rendering, edit, retry, quote, copy, and export.
- **Branching you can see.** Fork any message and explore alternate replies. Conversations render as an interactive tree, so you can hop between branches instead of scrolling a flat wall of text.
- **Drag in files.** Images, PDFs (scanned pages included), DOCX, and code, straight into the conversation.
- **Bring your own model.** DeepSeek, OpenAI, and Google Gemini out of the box, with per-conversation, per-command, and per-assistant model selection.
- **Everything stays organized.** Folders, trash with auto-retention, real-time search across all your chats, assistant profiles with custom system prompts, and per-thread model, reasoning, and temperature settings.
- **Know what it costs.** The usage dashboard charts tokens, spend, speed, and latency per model and provider, with filters and CSV export. A built-in API logs viewer lets you inspect requests and responses when something looks off.

## Requirements

- Windows 10 or later
- [AutoHotkey v2.0.18+](https://www.autohotkey.com/)
- [WebView2 Runtime](https://developer.microsoft.com/en-us/microsoft-edge/webview2/) (pre-installed on Windows 11)
- API keys for the providers you want to use, set as environment variables:
  - `DEEPSEEK_API_KEY`
  - `OPENAI_API_KEY`
  - `GEMINI_API_KEY`

## Quick Start

1. Install [AutoHotkey v2](https://www.autohotkey.com/download/ahk-v2.exe)
2. Clone this repo
3. Set your API keys:
   ```cmd
   setx DEEPSEEK_API_KEY "sk-your-key"
   ```
4. Double-click `Main.ahk` (or run `AutoHotkey64.exe Main.ahk`)
5. Press `` ` `` to open the command menu

## Configuration

Edit [`default-settings/DefaultSettings.ahk`](default-settings/DefaultSettings.ahk) to customize providers and models, the `` ` `` menu, assistant profiles, hotkeys, theme, and more. Save the file and the script auto-reloads (Ctrl+S).

## Running Tests

```cmd
# Unit + integration tests (AHK + JS)
tests\run_all_tests.bat

# Or individually:
tests\run_js_tests.bat    # Node.js unit tests (requires Node.js)
tests\run_ahk_tests.ahk   # AHK unit & integration tests

# Headless end-to-end GUI suite (launches the real app; needs an interactive session)
node tests\headless\e2e-suite.js --all
```

The headless harness manual is `tests/headless/README.md`; the live bug report is `tests/headless/BUG_HUNT_REPORT.md`.

## Architecture

See [`ARCHITECTURE.md`](ARCHITECTURE.md) for a deep dive into the data model, IPC, WebView communication, and module dependency graph.

## License

GNU General Public License v3.0. See [`LICENSE`](LICENSE).

AhkLLM is a derivative of [LLM-AutoHotkey-Assistant](https://github.com/kdalanon/LLM-AutoHotkey-Assistant) by [kdalanon](https://github.com/kdalanon), extended with a full WebView2 chat GUI, message branching, multi-provider streaming, file attachments, and a comprehensive test suite.
