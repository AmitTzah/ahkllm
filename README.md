# AutoHotkey LLM Client

A Windows-native AI assistant that lives in your taskbar. Press `` ` `` (backtick) to summon a command menu — chat with any LLM, transform selected text, or get inline code completions. Built on AutoHotkey v2 with a modern WebView2 GUI.

## Features

- **Chat Interface** — Full conversation UI with message branching, editing, retry, and real-time streaming
- **Multi-Provider** — DeepSeek, OpenAI, and Google Gemini, with per-command model selection
- **Global Hotkey** — Press `` ` `` anywhere to open the command menu or chat window
- **Text Commands** — Summarize, translate, rephrase, refine, or run custom prompts on selected text
- **FIM Mode** — Fill-in-the-Middle inline code completion (DeepSeek FIM beta)
- **Attachments** — Drag & drop images, PDFs, DOCX, and code files into conversations
- **Usage Dashboard** — Track token usage and cost across all providers
- **Thread Management** — Organize conversations into folders, search across all chats in real time
- **Assistant Profiles** — Pre-configured AI personalities with custom system prompts

## Requirements

- Windows 10 or later
- [AutoHotkey v2.0.18+](https://www.autohotkey.com/)
- [WebView2 Runtime](https://developer.microsoft.com/en-us/microsoft-edge/webview2/) (pre-installed on Windows 11)
- API keys for the providers you want to use (set as environment variables):
  - `DEEPSEEK_API_KEY`
  - `OPENAI_API_KEY`
  - `GEMINI_API_KEY`

## Quick Start

1. Install [AutoHotkey v2](https://www.autohotkey.com/download/ahk-v2.exe)
2. Clone this repo
3. Set your API keys as environment variables:
   ```cmd
   setx DEEPSEEK_API_KEY "sk-your-key"
   ```
4. Double-click `Main.ahk` (or run `AutoHotkey64.exe Main.ahk`)
5. Press `` ` `` (backtick) — the command menu appears

## Configuration

Edit [`default-settings/DefaultSettings.ahk`](default-settings/DefaultSettings.ahk) to customize:
- API providers and models
- Commands (the `` ` `` menu)
- Assistants (chat profiles with custom system prompts)
- Hotkeys, UI theme, icons, and more

Save the file — the script auto-reloads on save (Ctrl+S).

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

The headless harness manual (targeted scenarios, sync check, cleanup) is
`tests/headless/README.md`; the live bug report is `tests/headless/BUG_HUNT_REPORT.md`.

## Architecture

See [`ARCHITECTURE.md`](ARCHITECTURE.md) for a detailed guide covering the data model, IPC, WebView communication, and module dependency graph.

## License

GNU General Public License v3.0 — see [`LICENSE`](LICENSE).

This project is a derivative of [LLM-AutoHotkey-Assistant](https://github.com/kdalanon/LLM-AutoHotkey-Assistant) by [kdalanon](https://github.com/kdalanon), with significant extensions including a full WebView2 chat GUI, message branching, multi-provider streaming, file attachments, and a comprehensive test suite.
