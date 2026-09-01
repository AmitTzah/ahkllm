# Changelog

## [1.2.1] - 2026-09-01

### Fixed

- Removed the default `\n` stop sequence from FIM Continue so continuation output is not cut off at the first newline.

## [1.2.0] - 2026-09-01

### Added

- Support for adding and resolving user-supplied OpenRouter models, including model metadata, reasoning levels, pricing, and provider icons.
- Expanded regression coverage for settings, streaming, branching, attachments, locking, usage tracking, and concurrent requests.
- Isolated parallel WebView2 E2E workers for faster and safer full-application verification.

### Improved

- Refined settings labels, shortcut capture and feedback, usage-dashboard navigation, and input-window presentation.
- Clarified context-limit behavior and password-protection limitations in the documentation.

### Fixed

- Made Escape cancellation reliable and corrected several settings, FIM, and UI lifecycle edge cases.
- Refreshed the documentation screenshots and custom-paste demonstration assets.
