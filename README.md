# AhkLLM

A Windows-native AI assistant that lives in your taskbar. Press `` ` `` (backtick) anywhere and it's there: a full chat window, a command menu, or a quick transform on the text you just selected.

Select a paragraph, hit backtick, and tell it to explain the diff, translate the text, or rewrite the email — without ever leaving the app you're in. AhkLLM is built on AutoHotkey v2 with a WebView2 chat UI, so it's small, fast, and keyboard-first: no Electron install, no browser tab, just a keystroke.

## What you get

- **A real chat window** — streaming responses, message branching, editing, and retry. Not a wrapper around a website.
- **Bring your own model** — DeepSeek, OpenAI, and Google Gemini out of the box, with per-conversation and per-command model selection.
- **Text commands** — summarize, translate, rephrase, refine, or run your own prompts on selected text in any app.
- **Inline code completions** — fill-in-the-middle (FIM) mode for DeepSeek's coding beta.
- **Drop in files** — images, PDFs, DOCX, and code files, dragged straight into the conversation.
- **Know what it costs** — a usage dashboard tracks tokens and spend across all your providers.
- **Chats that stay organized** — folders, real-time search across everything, and assistant profiles with custom system prompts.

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
5. Press `` ` `` — the command menu appears

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

GNU General Public License v3.0 — see [`LICENSE`](LICENSE).

AhkLLM is a derivative of [LLM-AutoHotkey-Assistant](https://github.com/kdalanon/LLM-AutoHotkey-Assistant) by [kdalanon](https://github.com/kdalanon), extended with a full WebView2 chat GUI, message branching, multi-provider streaming, file attachments, and a comprehensive test suite.
