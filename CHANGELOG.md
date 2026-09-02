# Changelog

## [1.3.0] - 2026-09-02

### Added

- First-class user-added OpenAI-compatible Chat Completions providers with stable IDs and optional models.dev catalog mappings.
- Rich models.dev metadata refresh, including input/cache/output pricing, context, vision, reasoning, and compatibility details.

### Improved

- Redesigned the Edit Models workspace with stacked full-width tables, a draggable panel splitter, resizable columns, readable provider labels, and complete pricing visibility.
- Provider settings now clearly describe the OpenAI-compatible Chat Completions and Bearer-authentication requirements.

### Fixed

- Custom providers can add models during the same unsaved Settings session, and provider/model references survive Save and reload without mangling nested IDs.
- Legacy generated provider IDs can be renamed to stable IDs, while removing a provider cannot leave dangling model references.
- Custom-provider SSE parsing tolerates nullable OpenAI-compatible fields such as `tool_calls`, `choices`, and `delta`.
- OpenRouter remains lookup-only instead of bulk-importing its large catalog; the synthetic `openrouter/free` model remains available.
- Settings refreshes no longer rewrite committed defaults with user-specific provider mappings.
- Settings IPC acknowledgements are not lost when the host handles a save synchronously.

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
