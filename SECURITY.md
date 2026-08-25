# Security policy

## Private vulnerability reports

GitHub Security Advisories are the preferred private reporting mechanism, but
their availability for this repository has not been verified. The owner must
enable and verify that feature before launch. Do not open a public issue for an
undisclosed vulnerability, and do not send API keys, tokens, passwords, chat
exports, database files, or attachments in an issue or pull request.

Reports are most useful when they include the affected version/commit, the
smallest safe reproduction, impact, and any relevant logs with secrets and
personal data removed. The project does not promise a fixed response time.

## Supported versions

This is a small project with a rolling support policy: security fixes target
the latest tagged release and the default branch. Older releases are not
maintained unless the owner explicitly announces otherwise. Users should
upgrade before reporting issues against an old build.

## Scope notes

Security-sensitive areas include API-key handling, provider requests,
WebView/IPC messages, attachment parsing, local SQLite storage, locked-chat
gates, and the headless test harness. Locked chats are an application-level
access gate; chat content and attachments are not encrypted at rest. API logs
and temporary request files can contain user data. Never include their raw
contents in a report.

This policy does not promise security for a compromised Windows account,
malware with access to the user's profile, a malicious provider, or arbitrary
third-party AutoHotkey scripts loaded alongside AhkLLM.
