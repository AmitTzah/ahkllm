# Contributing to AhkLLM

## Prerequisites

- Windows 10 or later
- AutoHotkey v2.0.18 or later
- Node.js 22 or later for JavaScript checks and test orchestration
- WebView2 Runtime for running the application and GUI tests

The repository vendors the browser runtime assets used by the app, so `npm
install` is not required for the current test suite. If AutoHotkey is not at
the default path, set `AHK_EXE` to the executable before running tests.

## Local setup

1. Clone the repository.
2. Set provider keys in environment variables such as `DEEPSEEK_API_KEY`,
   `OPENAI_API_KEY`, `GOOGLE_API_KEY`, or `TAVILY_API_KEY`. Environment
   variables are preferred over direct-entry keys.
3. Run `Main.ahk` with AutoHotkey v2. User data is created under
   `%APPDATA%\AhkLLM`; do not point tests at a profile containing personal
   data unless the harness is configured to isolate it.

## Tests

From the repository root:

```cmd
npm run check:release
npm run test:fast
npm run test:e2e
```

`test:fast` includes the release-tree check, IPC/lock/load/SQL checks, the AHK
suite, and Node unit/integration tests. The E2E suite requires an interactive
Windows session and WebView2; it is not required for every documentation-only
change.

## Contribution expectations

- Keep changes focused and explain behavior changes in the pull request.
- Add or update regression tests for bugs and features where practical.
- Do not commit API keys, tokens, passwords, `.env` files, settings, chat
  databases, API logs, debug logs, user attachments, screenshots of personal
  data, or local filesystem paths containing usernames.
- Preserve third-party copyright, license, and attribution notices. Update
  [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md) when adding, replacing,
  or modifying a vendored component.
- Treat provider responses and test fixtures as potentially sensitive; use
  synthetic data in committed tests.

## Pull requests

Before opening a PR, run the strongest applicable checks and report commands
that could not run locally. Keep generated output and local state out of the
PR. Review the complete diff, including binary additions, for provenance and
privacy. Maintainers may request a provenance record or license text before
accepting a new dependency.
