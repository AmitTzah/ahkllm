<h1 align="center">AhkLLM</h1>

<p align="center">
  <a href="#requirements"><img src="https://img.shields.io/badge/Windows-10%2B-0078D6" alt="Windows"></a>
  <a href="https://www.autohotkey.com/"><img src="https://img.shields.io/badge/AutoHotkey-v2.0.18%2B-5e81ac" alt="AutoHotkey"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-GPL--3.0-blue" alt="License: GPL-3.0"></a>
</p>

<p align="center"><b>The AI assistant that's one keystroke away on Windows.</b></p>

Select text in any app, press `` ` ``, and pick from a menu of commands. Explain a diff, translate a paragraph, rewrite an email, or keep typing and let FIM Continue pick up where you left off. You can also just open the chat window and talk. You never leave the app you're in.

AhkLLM runs natively on Windows via AutoHotkey v2 with a WebView2 chat UI. It sits quietly in your system tray and preloads the chat window in the background, so it's ready the instant you hit the key.

| What it is | What it isn't |
|---|---|
| One keystroke away, in any app | A wrapper around a website |
| Direct API calls with your own keys | A relay that skims your tokens |
| Native Windows, light on resources | An Electron app that eats RAM |
| Local chat history in SQLite | A cloud service that owns your data |
| Keyboard-first by design | A tool that needs a mouse |

## What you get

- **A real chat window.** Streaming responses, message branching, editing, and retry.
- **Bring your own model.** DeepSeek, OpenAI, and Google Gemini out of the box, with per-conversation and per-command model selection.
- **Text commands.** Summarize, translate, rephrase, refine, or run your own prompts on selected text in any app.
- **Inline code completions.** Fill-in-the-middle (FIM) mode for DeepSeek's coding beta.
- **Drop in files.** Images, PDFs, DOCX, and code files, dragged straight into the conversation.
- **Know what it costs.** A usage dashboard tracks tokens and spend across all your providers.
- **Chats that stay organized.** Folders, real-time search across everything, and assistant profiles with custom system prompts.

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
