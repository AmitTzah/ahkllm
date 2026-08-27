# Contributing to AhkLLM

Contributions are welcome. That can mean a new feature you think AhkLLM should support, improving something that's already there, fixing a bug, or just opening an issue when something behaves strangely.

If you want to help out but don't have a particular feature in mind, take a look at `tests/headless/BUG_HUNT_REPORT.md`. It has a long list of bugs that have already been found, fixed, and turned into regression tests. It also gives you a pretty good idea of the kinds of edge cases this project tends to run into.

You can also point your LLM at the bug report and the headless harness and ask it to look for similar bugs that are not covered yet. A lot of the bug hunting on this project has been done that way.

## Before submitting a change

You'll need Windows 10 or later, AutoHotkey v2.0.18+, WebView2, and Node.js 22+ for the test tooling.

There is currently no `npm install` step. The JavaScript dependencies used by the app are vendored in the repository.

For normal code changes, run:

```cmd
npm run test:fast
```

If your change affects actual application behavior, please also run the full E2E suite:

```cmd
npm run test:e2e
```

Documentation-only changes obviously do not need the full GUI suite.

If AutoHotkey is not installed at the normal path, set `AHK_EXE` before running the tests.

## About the E2E suite

The E2E suite is a little unusual because it launches and interacts with the real AhkLLM application rather than testing a fake copy of the UI.

Before it does that, the harness temporarily isolates your real `%APPDATA%\AhkLLM` profile and runs the app against a separate test profile. When the run finishes, it restores the real profile.

I've put quite a bit of work into making that process recover safely, including recovery after interrupted runs, and it has worked reliably for me so far. That said, this is still a test harness that temporarily moves your real application profile around. I can't say for sure that every possible Windows/filesystem edge case has been covered.

Please back up any AhkLLM data you care about before running the full E2E suite.

If a run gets killed hard and the profile is not restored automatically, run:

```cmd
node tests\headless\e2e-suite.js --cleanup
```

The full harness documentation is in `tests/headless/README.md`.

## Bug fixes

If you're fixing a bug that can reasonably be reproduced through the UI, I strongly prefer turning the reproduction into an E2E regression scenario.

The workflow I've been using is:

1. Write a scenario that reproduces the bug.
2. Run it against the broken version and make sure it actually fails for the reason you think it does.
3. Fix the bug.
4. Run the same scenario again and make sure it passes.
5. Keep the scenario in the suite as a regression test.

This matters even more if you're using an LLM to make the fix. It is very easy for a model to read a bug description, make a plausible-looking code change, and declare victory without proving that it fixed the actual problem.

A failing reproduction before the change and a passing reproduction afterward makes that much harder.

If the bug is better covered by a unit or integration test, that's fine too. Use whatever level actually proves the behavior.

## Local setup and API keys

Run `Main.ahk` with AutoHotkey v2. User data is stored under `%APPDATA%\AhkLLM`.

Provider keys can be supplied through environment variables such as:

```text
DEEPSEEK_API_KEY
OPENAI_API_KEY
GOOGLE_API_KEY
TAVILY_API_KEY
```

Environment variables are preferable to storing keys directly in Settings.

Please do not commit API keys, passwords, settings files, chat databases, API/debug logs, user attachments, screenshots containing personal data, or local paths containing usernames.

If you add or replace a vendored dependency, make sure its license is compatible with the project and update `THIRD_PARTY_NOTICES.md` when needed.

## Pull requests

There isn't a complicated contribution process.

Explain what you changed and why, mention the tests you ran, and if something could not be tested locally just say so.

For anything non-trivial, please look over the complete diff before submitting it. AhkLLM has a lot of persistence, IPC, attachment, and background-process behavior, so a change that looks small in one file can occasionally affect something fairly far away from it.
