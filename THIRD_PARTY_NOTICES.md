# Third-Party Notices

AhkLLM includes or redistributes the components below. This inventory covers
the tracked runtime libraries, JavaScript/CSS bundles, fonts, and attachment
icons found in the repository on 2026-08-25. Versions are taken from embedded
headers, binary metadata, or the upstream package metadata when identifiable;
an exact upstream commit is called out when it is not recorded locally.

This is an attribution and provenance record, not a legal opinion. The
project's own code is GPL-3.0-or-later only where the repository says so. A
component's permissive license or public-domain dedication appears suitable
for aggregation with GPL-3.0 code, subject to its own conditions. Microsoft
WebView2 terms, icon/trademark provenance, and any missing source/build
metadata require owner review before public redistribution.

## Inventory

| Component | Location | Upstream | License | Status | Notes |
|---|---|---|---|---|---|
| thqby AHK WebView2 bindings | `lib/WebView2.ahk`, `lib/ComVar.ahk`, `lib/Promise.ahk` | [thqby/ahk2_lib](https://github.com/thqby/ahk2_lib) | MIT | VERIFIED | Copyright notice and MIT text are embedded in the files. `WebView2.ahk` identifies version 2.0.4 and WebView2 SDK 1.0.2903.40 in its header; the bundled loader is a separate Microsoft component. Local integration edits exist. |
| WebViewToo | `lib/WebViewToo.ahk` | [The-CoDingman/WebViewToo](https://github.com/The-CoDingman/WebViewToo) | MIT | VERIFIED | Copyright and full MIT notice are embedded. The file is locally integrated/modified and retains the upstream notice. |
| UIA-v2 | `lib/UIA.ahk` | [Descolada/UIA-v2](https://github.com/Descolada/UIA-v2) | MIT | VERIFIED | Author/credits are embedded; the upstream MIT text is also preserved in [`lib/UIA_LICENSE.txt`](lib/UIA_LICENSE.txt). Exact upstream commit is not recorded; local modifications are present. |
| jsongo_AHKv2 | `lib/jsongo.v2.ahk` | [GroggyOtter/jsongo_AHKv2](https://github.com/GroggyOtter/jsongo_AHKv2) | GPL-3.0 | VERIFIED | The file identifies version 1.1 and the upstream URL. Its `@license GNU` tag is abbreviated; the upstream repository identifies GPL-3.0, and the repository's top-level [`LICENSE`](LICENSE) supplies the complete text. |
| AutoXYWH | Historical source replaced in `lib/AutoXYWH.ahk` | Historical source: [AutoHotkey forum topic](https://www.autohotkey.com/boards/viewtopic.php?f=6&t=1079); base-project attribution [LLM-AutoHotkey-Assistant](https://github.com/kdalanon/LLM-AutoHotkey-Assistant) | Not applicable to current file | VERIFIED | The historical source is attributed to tmplinshi, with toralf/Alguimist modifications and a Relayer v2 conversion, but no redistribution license was found. The unknown-license implementation was removed and replaced with a small original AhkLLM implementation supporting the app's `wh` and `x0.5 y` resize cases. |
| ToolTipEx | `lib/ToolTipEx.ahk` | [nperovic/ToolTipEx](https://github.com/nperovic/ToolTipEx) | MIT | VERIFIED | Upstream repository and MIT license are identifiable. The copied file does not retain a complete license header; the license text and attribution record are supplied in [`lib/ToolTipEx_LICENSE.txt`](lib/ToolTipEx_LICENSE.txt). Local integration changes are possible but not independently diffed. |
| RaptorX SQLite AHK wrapper | `lib/SQLite/SQLite.ahk`, `lib/SQLite/lib/interfaces/SQLite3.ahk`, `lib/SQLite/lib/headers/sqlite3.h.ahk` | [RaptorX/SQLite](https://github.com/RaptorX/SQLite) | MIT | VERIFIED | Wrapper version 0.4.3 and author are embedded. The upstream MIT notice is preserved in [`lib/SQLite/License.txt`](lib/SQLite/License.txt). The wrapper is locally modified for parameter binding and application behavior. |
| SQLite engine | `lib/SQLite/lib/bin/sqlite332.dll`, `lib/SQLite/lib/bin/sqlite364.dll` | [SQLite](https://www.sqlite.org/) | Public domain | VERIFIED | Both DLLs report SQLite 3.43.2 / source ID 2023-10-10 in binary metadata and the AHK header. SQLite describes its core source as public domain; the two filenames are legacy bitness names used by this application. |
| Microsoft WebView2 loader | `lib/32bit/WebView2Loader.dll`, `lib/64bit/WebView2Loader.dll` | [Microsoft.Web.WebView2 1.0.1072.54](https://www.nuget.org/packages/Microsoft.Web.WebView2/1.0.1072.54), [distribution guidance](https://learn.microsoft.com/microsoft-edge/webview2/concepts/distribution) | BSD-3-Clause-style Microsoft license | VERIFIED | SHA-256 matches the official NuGet package exactly: x86 `58ADEA8C6896ABF767EF1EE8C764A4C8734C486CFDB4E001529EA01E9D071FB2`; x64 `AD8BB426A8E438493DB4D703242F373D9CB36D8C13E88B6647CD083716E09BEF`. The package license permits source and binary redistribution with notice preservation; the exact notice is recorded in [`lib/WebView2Loader_LICENSE.md`](lib/WebView2Loader_LICENSE.md). |
| Chart.js | `webui/js/vendor/chart.umd.min.js` | [chartjs/Chart.js](https://github.com/chartjs/Chart.js) | MIT | VERIFIED | Bundle header identifies Chart.js 4.4.0 and retains the MIT notice; it also contains the `@kurkle/color` MIT notice. |
| highlight.js | `webui/js/vendor/highlight.min.js`, `webui/css/vendor/highlight/atom-one-dark.min.css` | [highlightjs/highlight.js](https://github.com/highlightjs/highlight.js) | BSD-3-Clause | VERIFIED | JS header identifies 11.10.0 / commit `366a8bd012` and retains the BSD notice. The CSS is the matching vendored theme; attribution is recorded here. |
| KaTeX | `webui/js/vendor/katex.min.js`, `webui/css/vendor/katex.min.css`, `webui/css/vendor/fonts/KaTeX_*` | [KaTeX/KaTeX](https://github.com/KaTeX/KaTeX) | MIT | VERIFIED | CSS identifies KaTeX 0.16.8. The matching WOFF/WOFF2/TTF font assets are pinned to the same upstream release and are included so the stylesheet is self-contained. The minified JS/CSS do not carry a complete license header, so this notice is the local attribution record. |
| KaTeX mhchem extension | `webui/js/vendor/mhchem.min.js` | [KaTeX contrib/mhchem](https://github.com/KaTeX/KaTeX/tree/main/contrib/mhchem) | MIT (as distributed with KaTeX) | VERIFIED | Version is not embedded in this minified file; it is paired with KaTeX 0.16.8. Preserve KaTeX's upstream license/attribution when updating it. |
| markdown-it | `webui/js/vendor/markdown-it.min.js` | [markdown-it/markdown-it](https://github.com/markdown-it/markdown-it) | MIT | VERIFIED | Bundle header identifies 13.0.1 and retains the MIT notice. |
| markdown-it-texmath | `webui/js/vendor/texmath.min.js`, `webui/css/vendor/texmath.min.css` | [goessner/markdown-it-texmath](https://github.com/goessner/markdown-it-texmath) | MIT | VERIFIED | jsDelivr headers identify package 1.0.0 and retain the source-package references. |
| PDF.js | `webui/js/vendor/pdf.min.js`, `webui/js/vendor/pdf.worker.min.js` | [mozilla/pdf.js](https://github.com/mozilla/pdf.js) | Apache-2.0 | VERIFIED | Both bundles identify PDF.js 3.11.174 and retain Mozilla's complete Apache license notice. |
| officeParser browser bundle | `webui/js/vendor/officeparser.iife.js` | [harshankur/officeParser](https://github.com/harshankur/officeParser) | MIT | VERIFIED | The bundle banner says `officeparser browser bundle`; embedded package data identifies Tesseract.js 7.0.0 and PDF.js 6.1.200, matching officeParser 7.0.0's dependency set. The bundle was locally changed during attachment work. |
| officeParser bundled dependencies | Inside `webui/js/vendor/officeparser.iife.js` | [naptha/tesseract.js](https://github.com/naptha/tesseract.js), [mozilla/pdf.js](https://github.com/mozilla/pdf.js), [zloirock/core-js](https://github.com/zloirock/core-js) | Apache-2.0 / Apache-2.0 / MIT | VERIFIED | Embedded metadata identifies Tesseract.js 7.0.0, PDF.js 6.1.200, and core-js 3.49.0. Preserve the upstream notices required by those licenses when updating the bundle. |
| Inter | `webui/fonts/inter-latin-*.ttf`, `webui/fonts/inter.css` | [rsms/inter](https://github.com/rsms/inter) | SIL OFL 1.1 | VERIFIED | Copyright and license are supplied in [`webui/fonts/OFL-1.1.txt`](webui/fonts/OFL-1.1.txt) and listed in [`webui/fonts/NOTICES.md`](webui/fonts/NOTICES.md). The CSS is a local subset of static web fonts; no local font modifications were identified. |
| JetBrains Mono | `webui/fonts/jetbrains-mono-latin-*.ttf`, `webui/fonts/jetbrains-mono.css` | [JetBrains/JetBrainsMono](https://github.com/JetBrains/JetBrainsMono) | SIL OFL 1.1 | VERIFIED | Copyright and license are supplied in [`webui/fonts/OFL-1.1.txt`](webui/fonts/OFL-1.1.txt) and listed in [`webui/fonts/NOTICES.md`](webui/fonts/NOTICES.md). The CSS is a local subset of static web fonts; no local font modifications were identified. |
| Filetype SVG icons | `webui/icons/filetypes/*.svg` | Original AhkLLM artwork | GPL-3.0 as project-authored assets | VERIFIED | The previously uncertain third-party SVGs were replaced with original AhkLLM paper/file glyphs carrying extension labels. They are not provider or product logos and have no third-party attribution requirement. |
| Provider/tray ICO assets | `icons/*.ico` | Original AhkLLM artwork | GPL-3.0 as project-authored assets | VERIFIED | The previously unprovenanced ICOs were replaced with original geometric tray/provider markers. Initials distinguish configured providers but do not reproduce or claim affiliation with provider logos. |

## Local project assets

The screenshots under `docs/screenshots/` were visually inspected during this
audit. They show synthetic example chats, placeholder API keys, localhost
endpoints, and aggregate example usage; no personal chat, real credential, or
developer filesystem path was found. They are project documentation assets,
not third-party dependencies.

## Preservation rules

Do not remove or replace a vendor file without updating this inventory and
retaining the upstream notice required by its license. When updating a bundle,
record its exact upstream version or commit and rerun the release-readiness
check.
