# Security

AhkLLM handles API keys, local chat history, attachments, clipboard text, screenshots, and data sent to external model providers, so security reports are taken seriously.

If you find a vulnerability, please do not post the details in a public issue before it has been looked at. If GitHub's private vulnerability reporting option is available on the repository, use that. If it is not available, open a short issue saying you need a private way to report a security problem, without including the vulnerability details or any sensitive data.

A useful report includes the affected version or commit, what you expected to happen, what actually happened, and the smallest safe reproduction you can provide. Logs can help, but please remove API keys, passwords, prompts, chat content, filesystem usernames, and other personal data before attaching anything.

I can't promise a particular response time, but reproducible security issues affecting the current version will be treated as a priority.

## What is and is not protected

Some parts of AhkLLM are security-sensitive by design: provider credential handling, WebView/IPC messages, attachment parsing, local SQLite persistence, API logging, locked chats, temporary request files, and the headless test harness.

Locked chats are an application-level access control feature. They hide locked content inside the app until the password is entered, remove it from normal search results, and redact locked-chat bodies in the API log viewer.

They are not encrypted storage. The SQLite database and attachment files are still stored on disk under the user's Windows profile. A process or user that can directly read those files can bypass the in-app lock. Chat passwords themselves are stored as PBKDF2-SHA-256 hashes rather than plaintext.

API logs and temporary request files can contain prompts, responses, selected text, or attachment-derived content. Logging can be disabled in Settings, but if it is enabled you should treat those files as potentially sensitive.

AhkLLM also sends data to whichever external providers you configure. Prompts, selected text, screenshots, uploaded files, and search queries may leave your machine as part of normal use. The security of those third-party services is outside this project's control.

## Supported versions

Security fixes target the current codebase and the latest release. Older builds are not maintained unless explicitly stated otherwise.

If you are reporting a problem against an older version, please check whether it still exists on the latest release or current default branch first.

## Out of scope

This project cannot protect data from a compromised Windows account, malware already running with access to your profile, a malicious model provider, or arbitrary third-party AutoHotkey code running with the same user permissions.

That does not mean reports involving those areas are useless, but the bug needs to be something AhkLLM can realistically prevent or mitigate.
